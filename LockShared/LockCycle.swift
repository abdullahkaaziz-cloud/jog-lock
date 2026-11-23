//
//  LockCycle.swift
//  Built into the app and its Screen Time extensions.
//
//  Runs the lock: the app and the usage monitor call it, and nothing else
//  changes the state. Ported from Tilawah Key's UsageCycle, which went
//  through dozens of iPhone tests:
//
//  - The state changes only inside `transaction`, under a file lock shared
//    with the extensions, and never waits long for it.
//  - iOS's DeviceActivity calls are made outside the lock, as iOS may call
//    the monitor while it registers one.
//  - Each monitor gets a new name, and the apps open only once iOS has
//    accepted it, so stale work never opens apps a newer state has locked.
//  - Usage events go to an inbox first, so a busy lock never loses one.
//

import Darwin
import DeviceActivity
import FamilyControls
import Foundation
import JogLockCore

final class LockCycle {
    static let prefix = "joglock-"
    /// Run-only apps' monitors: a different prefix, so the daily lock's
    /// clean-ups leave them alone.
    static let runPrefix = "joglockrun-"
    private let center = DeviceActivityCenter()
    private let calendar = Calendar.current

    // MARK: - The saved state

    private func container() throws -> URL {
        guard let directory = LockStore.container else { throw LockFailure.sharedContainer }
        return directory
    }

    /// Changes the state under the lock. Usage events waiting in the inbox
    /// are counted first, and a new day started, whoever holds the lock; if
    /// that changes anything, it's saved and the shield applied. The state is
    /// saved again if `body` changes it.
    @discardableResult
    func transaction<T>(_ body: (inout LockState) throws -> T) throws -> T {
        let directory = try container()
        let fd = open(directory.appendingPathComponent("lock.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LockFailure.sharedContainer }
        defer { close(fd) }
        // Never wait long, even in the monitor extension.
        let deadline = Date().addingTimeInterval(0.5)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else { throw LockFailure.busy }
            usleep(5_000)
        }
        defer { flock(fd, LOCK_UN) }

        let url = LockStore.stateURL(in: directory)
        var state: LockState
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(LockState.self, from: Data(contentsOf: url))
            // A state this build can't trust fails closed: kept as it is, never overwritten.
            guard state.valid else { throw LockFailure.state }
        } else {
            state = LockState(now: Date())
        }

        let saved = state
        let inbox = LockStore.inbox(in: directory)
        let waiting = inbox.kept()
        for item in waiting {
            state.ledger.count(monitor: item.monitor, event: item.event)
        }
        state.ledger.update(to: Date(), rules: state.rules, calendar: calendar)
        state.expireRunWindow(at: Date())
        if state != saved {
            try save(state, to: url)
            try LockShield.apply(state)
        }
        inbox.remove(waiting.map(\.file))

        let before = state
        let result = try body(&state)
        if state != before {
            try save(state, to: url)
        }
        return result
    }

    private func save(_ state: LockState, to url: URL) throws {
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func snapshot() throws -> LockState {
        try transaction { $0 }
    }

    // MARK: - Monitors

    /// Plans the monitor the apps need now, registers it with iOS outside
    /// the lock, then lifts the shield only if it's still the current one.
    /// Until then the apps stay shielded.
    func registerMonitor() throws {
        let name = Self.prefix + UUID().uuidString
        let plan: (monitor: LockMonitor?, replaced: String?, selection: Data?) = try transaction { state in
            guard state.enabled else { return (nil, nil, nil) }
            let planned = state.ledger.planMonitor(name: name, at: Date(), rules: state.rules, calendar: calendar)
            try LockShield.apply(state)
            return (planned.monitor, planned.replaced, state.selection)
        }
        if let replaced = plan.replaced {
            center.stopMonitoring([DeviceActivityName(replaced)])
        }
        guard let monitor = plan.monitor, let data = plan.selection else { return }
        let selection = try LockShield.decode(data)
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(fields, from: Date()),
                                              intervalEnd: calendar.dateComponents(fields, from: monitor.end),
                                              repeats: false)
        // One event per banked minute: iOS reports each minute the chosen apps are used.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if monitor.purpose == .minutes {
            for minute in stride(from: 1, through: monitor.base, by: 1) {
                events[DeviceActivityEvent.Name(LockMonitor.event(minute))] = DeviceActivityEvent(
                    applications: selection.applicationTokens, categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minute),
                    includesPastActivity: false)
            }
        }
        try center.startMonitoring(DeviceActivityName(monitor.name), during: schedule, events: events)
        let current: Bool = try transaction { state in
            guard state.enabled, state.ledger.monitorStarted(monitor.name) else { return false }
            try LockShield.apply(state)
            return true
        }
        if !current {
            center.stopMonitoring([DeviceActivityName(monitor.name)])
        }
    }

    /// Stops every Jog Lock monitor. Only when the lock is off: nothing then
    /// registers a new one.
    private func stopMonitors() {
        let ours = center.activities.filter { $0.rawValue.hasPrefix(Self.prefix) }
        if !ours.isEmpty {
            center.stopMonitoring(ours)
        }
    }

    /// Brings iOS in line with the state: the right monitor running while
    /// the apps are open, the shield on while they're locked. Returns why it
    /// registered a monitor, for the log.
    @discardableResult
    func refresh() throws -> String? {
        let state = try snapshot()
        guard state.enabled else {
            try transaction { current in
                if !current.enabled {
                    LockShield.open()
                    LockShield.applyRunOnly(current)
                }
            }
            stopMonitors()
            return nil
        }
        let listed = state.ledger.monitor.map { center.activities.contains(DeviceActivityName($0.name)) } ?? false
        if let problem = state.ledger.monitorProblem(at: Date(), listed: listed) {
            try registerMonitor()
            return "monitor registered: " + problem
        }
        let stale: String? = try transaction { current in
            let stale = current.openFor == nil ? current.ledger.dropMonitor() : nil
            try LockShield.apply(current)
            return stale
        }
        if let stale {
            center.stopMonitoring([DeviceActivityName(stale)])
        }
        return nil
    }

    // MARK: - The monitor's callbacks

    /// A usage event. It's kept in the inbox before the lock is asked for,
    /// and the transaction counts it. While the lock stays busy, an event
    /// that uses the minutes up shields the apps at once. Returns a note for
    /// the log when the lock was busy.
    @discardableResult
    func threshold(monitor name: String, event: String) throws -> String? {
        try LockStore.inbox(in: try container()).keep(monitor: name, event: event)
        let settle = { (state: inout LockState) throws -> String? in
            try LockShield.apply(state)
            return state.openFor == nil ? state.ledger.dropMonitor() : nil
        }
        var note = ""
        var stale: String?
        do {
            stale = try transaction(settle)
        } catch LockFailure.busy {
            note = "lock busy: event kept"
            if let saved = LockStore.peek(), saved.enabled, saved.ledger.usesUp(monitor: name, event: event),
               let data = saved.selection, let selection = try? LockShield.decode(data) {
                LockShield.shield(selection, websites: saved.websites)
                note += ", minutes used up, apps shielded"
            }
            do {
                stale = try transaction(settle)
                note += "; counted on the second try"
            } catch LockFailure.busy {
                note += "; counted by the next update"
            }
        }
        if let stale {
            center.stopMonitoring([DeviceActivityName(stale)])
        }
        return note.isEmpty ? nil : note
    }

    /// A monitor's interval ended: an open day is over, or a day of counting
    /// minutes is, and minutes left are counted by a new monitor. While the
    /// lock is busy the apps are shielded rather than left open with nothing
    /// timing them; the app renews when it next refreshes.
    @discardableResult
    func intervalEnded(monitor name: String) throws -> String {
        if name.hasPrefix(Self.runPrefix) {
            return try runMonitorEnded(name)
        }
        let end: LockLedger.MonitorEnd
        do {
            end = try transaction { state in
                guard state.enabled else { return LockLedger.MonitorEnd.ignored }
                let outcome = state.ledger.intervalEnded(monitor: name, at: Date(), rules: state.rules,
                                                         calendar: calendar)
                if outcome != .ignored {
                    try LockShield.apply(state)
                }
                return outcome
            }
        } catch LockFailure.busy {
            if let saved = LockStore.peek(), saved.enabled, saved.ledger.monitor?.name == name,
               let data = saved.selection, let selection = try? LockShield.decode(data) {
                LockShield.shield(selection, websites: saved.websites)
                return "lock busy: apps shielded until the app refreshes"
            }
            return "lock busy"
        }
        switch end {
        case .ignored:
            return "old monitor"
        case .locked:
            return "locked"
        case .renew:
            try registerMonitor()
            return "renewed"
        }
    }

    // MARK: - The app's changes

    /// Turns the lock on, or changes the chosen apps. Today's runs so far
    /// count when it's turned on. The apps lock unless today's run is done.
    func choose(_ selection: Data) throws {
        let needsMonitor: Bool = try transaction { state in
            if !state.enabled {
                state.ledger.resetTarget(rules: state.rules, at: Date())
            }
            state.enabled = true
            state.selection = selection
            try LockShield.apply(state)
            return state.openFor != nil
        }
        // Open apps need a monitor that counts the new choice.
        if needsMonitor {
            try registerMonitor()
        } else {
            try refresh()
        }
    }

    func turnOff() throws {
        try transaction { state in
            state.enabled = false
            state.ledger.stopSpending()
            state.ledger.dropMonitor()
            LockShield.open()
        }
        stopMonitors()
    }

    /// Credits a run's counted distance. When it meets today's target, the
    /// apps open for the rest of the day, once iOS has the monitor that locks
    /// them again. True if it did.
    @discardableResult
    func credit(run id: String, countedMeters: Double, at now: Date) throws -> Bool {
        let unlocked: Bool = try transaction { state in
            state.ledger.credit(run: id, countedMeters: countedMeters, rules: state.rules, at: now)
        }
        if unlocked {
            try refresh()
        }
        return unlocked
    }

    func spend() throws {
        try transaction { state in
            guard state.enabled else { throw LockFailure.state }
            try state.ledger.startSpending()
        }
        try registerMonitor()
    }

    func stopSpending() throws {
        let stale: String? = try transaction { state in
            state.ledger.stopSpending()
            let stale = state.openFor == nil ? state.ledger.dropMonitor() : nil
            try LockShield.apply(state)
            return stale
        }
        if let stale {
            center.stopMonitoring([DeviceActivityName(stale)])
        }
    }

    func borrow() throws {
        try transaction { state in
            guard state.enabled else { throw LockFailure.state }
            try state.ledger.borrow(rules: state.rules)
        }
        try registerMonitor()
    }

    /// The websites typed in. The app checks that, while the apps are
    /// locked, they're only added to.
    func setWebsites(_ websites: [String]) throws {
        try transaction { state in
            state.websites = TypedWebsite.cleaned(websites)
            if state.enabled {
                try LockShield.apply(state)
            }
        }
    }

    /// The daily distance. While the lock is on, today's target stays and
    /// the new one starts tomorrow.
    func setDailyMeters(_ meters: Double) throws {
        try transaction { state in
            guard state.rules.dailyMeters != meters else { return }
            state.rules.dailyMeters = meters
            if !state.enabled {
                state.ledger.resetTarget(rules: state.rules, at: Date())
            }
        }
    }

    /// Rest days, a weekly target or the 5K plan. While the lock is on,
    /// today stays as it is and the plan starts tomorrow, so a rest day
    /// can't be made today to open the apps.
    func setPlan(_ plan: RunPlan?) throws {
        try transaction { state in
            guard state.rules.plan != plan else { return }
            state.rules.plan = plan
            if !state.enabled {
                state.ledger.resetTarget(rules: state.rules, at: Date())
            }
        }
    }

    // MARK: - Run-only apps

    /// Run-only apps chosen (nil: none).
    func chooseRunOnly(_ selection: Data?) throws {
        try transaction { state in
            state.runOnly = selection
            try LockShield.apply(state)
        }
    }

    /// A run started: the run-only apps open until it ends. A monitor locks
    /// them again four hours on, in case the app isn't running by then.
    func runStarted(_ run: String) throws -> String {
        let now = Date()
        let name = Self.runPrefix + UUID().uuidString
        let opened: (open: Bool, replaced: String?) = try transaction { state in
            guard state.runOnly != nil else { return (false, nil) }
            let replaced = state.openRunOnly(run: run, monitor: name, at: now)
            try LockShield.apply(state)
            return (true, replaced?.monitor)
        }
        if let replaced = opened.replaced {
            center.stopMonitoring([DeviceActivityName(replaced)])
        }
        guard opened.open else { return "no run-only apps" }
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: now),
            intervalEnd: calendar.dateComponents(fields, from: now.addingTimeInterval(LockState.longestRun)),
            repeats: false)
        do {
            try center.startMonitoring(DeviceActivityName(name), during: schedule)
            return "run-only apps open"
        } catch {
            return "run-only apps open; their monitor failed: \(error.localizedDescription)"
        }
    }

    /// A run ended (`run` nil: no run is going): the run-only apps lock.
    func runEnded(_ run: String?) throws {
        let closed: String? = try transaction { state in
            guard let window = state.closeRunOnly(run: run) else { return nil }
            try LockShield.apply(state)
            return window.monitor
        }
        if let closed {
            center.stopMonitoring([DeviceActivityName(closed)])
        }
    }

    /// A run-only monitor ended: its run has had four hours.
    private func runMonitorEnded(_ name: String) throws -> String {
        try transaction { state in
            guard state.runMonitorEnded(name) else { return "old run monitor" }
            try LockShield.apply(state)
            return "run-only apps locked"
        }
    }

    // MARK: - Diagnostics

    /// The state for the logs: counts only, never which apps.
    static func summary(_ state: LockState) -> [String: Any] {
        let ledger = state.ledger
        var entry: [String: Any] = [
            "enabled": state.enabled, "day": ledger.day.description,
            "target_m": Int(ledger.targetMeters), "ran_m": Int(ledger.ranMeters), "owed_m": Int(ledger.owedMeters),
            "bank_min": ledger.bankMinutes, "spending": ledger.spending, "target_met": ledger.isTargetMet,
            "open": ledger.isOpen, "plan": state.rules.runPlan.kind.rawValue, "rest_day": ledger.isRestDay,
            "week_m": Int(ledger.weekMeters), "run_only": state.runOnly != nil, "run_open": state.runOpen != nil,
        ]
        if let monitor = ledger.monitor {
            entry["monitor"] = String(monitor.name.suffix(8))
            entry["monitor_purpose"] = monitor.purpose.rawValue
            entry["monitor_ready"] = monitor.ready
            entry["monitor_end"] = ISO8601DateFormatter().string(from: monitor.end)
            if monitor.purpose == .minutes {
                entry["monitor_counted"] = "\(monitor.counted) of \(monitor.base)"
            }
        }
        if let counts = LockShield.counts(state) {
            entry["chosen"] = counts
        }
        return entry
    }
}
