//
//  AppLock.swift
//  JogLockTracker
//
//  The app's side of the lock: Screen Time permission, the chosen apps,
//  and runs, banked minutes and borrowing turned into unlocks. The lock
//  itself is LockCycle, shared with the extensions; here it runs on a
//  background actor, so file locks and iOS's DeviceActivity calls never
//  hold up the screen (as in Tilawah Key).
//

import FamilyControls
import Foundation
import JogLockCore
import UIKit
import UserNotifications

private actor LockRuntime {
    private let cycle = LockCycle()

    enum Command {
        case snapshot, refresh, turnOff, spend, stopSpending, borrow
        case choose(Data)
        case websites([String])
        case plan(RunPlan)
        case runOnly(Data?)
        case runStarted(String)
        case runEnded(String?)
        case credit(String, Double, Date)
        case dailyMeters(Double)

        var name: String {
            switch self {
            case .snapshot: "snapshot"
            case .refresh: "refresh"
            case .turnOff: "turn off"
            case .spend: "use minutes"
            case .stopSpending: "lock again"
            case .borrow: "borrow"
            case .choose: "choose apps"
            case .websites: "websites"
            case .plan: "plan"
            case .runOnly: "run-only apps"
            case .runStarted: "run started"
            case .runEnded: "run ended"
            case .credit: "credit run"
            case .dailyMeters: "daily target"
            }
        }

        /// Errors from what the runner asked for are shown; the rest (catching
        /// up, crediting runs) only go to the diagnostics.
        var showsErrors: Bool {
            switch self {
            case .turnOff, .spend, .stopSpending, .borrow, .choose, .websites, .plan, .runOnly: true
            case .snapshot, .refresh, .credit, .dailyMeters, .runStarted, .runEnded: false
            }
        }
    }

    struct Outcome {
        var state: LockState?
        var unlocked = false
        var note: String?
        var error: String?
    }

    func run(_ command: Command) -> Outcome {
        var outcome = Outcome()
        do {
            switch command {
            case .snapshot:
                break
            case .refresh:
                outcome.note = try cycle.refresh()
            case .turnOff:
                try cycle.turnOff()
            case .spend:
                try cycle.spend()
            case .stopSpending:
                try cycle.stopSpending()
            case .borrow:
                try cycle.borrow()
            case .choose(let selection):
                try cycle.choose(selection)
            case .websites(let websites):
                try cycle.setWebsites(websites)
            case .plan(let plan):
                try cycle.setPlan(plan)
            case .runOnly(let data):
                try cycle.chooseRunOnly(data)
            case .runStarted(let id):
                outcome.note = try cycle.runStarted(id)
            case .runEnded(let id):
                try cycle.runEnded(id)
            case .credit(let id, let meters, let time):
                outcome.unlocked = try cycle.credit(run: id, countedMeters: meters, at: time)
            case .dailyMeters(let meters):
                try cycle.setDailyMeters(meters)
            }
        } catch let error as LockError {
            outcome.error = AppLock.message(for: error)
        } catch {
            outcome.error = error.localizedDescription
        }
        outcome.state = try? cycle.snapshot()
        return outcome
    }
}

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    /// The lock as last read. The runtime's copy is the real one.
    @Published private(set) var state: LockState
    @Published private(set) var selection = FamilyActivitySelection()
    /// Apps that open only while a run is going.
    @Published private(set) var runOnlySelection = FamilyActivitySelection()
    @Published private(set) var authorization: AuthorizationStatus
    /// True when a run has just opened the apps: shows the unlock celebration.
    @Published var celebrating = false
    @Published var problem: String?

    private let runtime = LockRuntime()
    /// Run distance last saved to the lock, by run.
    private var savedMeters: [String: Double] = [:]
    private var undeterminedSince: Date?
    private var active = false
    private var nextCheck: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private init() {
        state = LockStore.peek() ?? LockState(now: Date())
        authorization = AuthorizationCenter.shared.authorizationStatus
        if let data = state.selection, let decoded = try? LockShield.decode(data) {
            selection = decoded
        }
        if let data = state.runOnly, let decoded = try? LockShield.decode(data) {
            runOnlySelection = decoded
        }
        LockSignal.listen()
        observer = NotificationCenter.default.addObserver(forName: LockSignal.received, object: nil,
                                                          queue: .main) { _ in
            Task { @MainActor in AppLock.shared.refresh(after: "monitor") }
        }
    }

    var isEnabled: Bool { state.enabled }
    var ledger: LockLedger { state.ledger }
    var rules: LockRules { state.rules }

    /// Apps, categories or websites chosen in Screen Time's picker.
    var hasPickedApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    /// Anything to lock: picked, or websites typed in.
    var hasChosenApps: Bool {
        hasPickedApps || !state.websites.isEmpty
    }

    /// Websites typed in by name, locked with the apps.
    var websites: [String] { state.websites }

    var isAuthorized: Bool {
        authorization == .approved
    }

    /// Screen Time access looks off: refused, or "not determined" for over
    /// 5 s with the lock on (iOS says that for a moment at launch).
    var accessOff: Bool {
        guard state.enabled else { return false }
        if authorization == .denied {
            return true
        }
        if authorization == .notDetermined, let since = undeterminedSince {
            return Date().timeIntervalSince(since) >= 5
        }
        return false
    }

    /// The apps are locked until today's run. Meanwhile apps can only be
    /// added, and the lock can't be turned off.
    var isLocked: Bool {
        state.enabled && !state.ledger.isTargetMet && !accessOff
    }

    // MARK: - Keeping up

    /// Catches up with the lock: at launch, when the app comes to the front,
    /// when the monitor signals, when an open monitor's time comes, and every
    /// minute while the app is open.
    func refresh(after trigger: String) {
        Task { await perform(.refresh, trigger: trigger) }
    }

    func setActive(_ isActive: Bool) {
        active = isActive
        if isActive {
            refresh(after: "app opened")
        } else {
            nextCheck?.cancel()
        }
    }

    private func perform(_ command: LockRuntime.Command, trigger: String) async {
        let status = AuthorizationCenter.shared.authorizationStatus
        authorization = status
        undeterminedSince = status == .notDetermined ? (undeterminedSince ?? Date()) : nil
        var command = command
        if case .refresh = command, state.enabled, status != .approved {
            command = .snapshot     // iOS won't take changes without access
        }
        let outcome = await runtime.run(command)
        if let new = outcome.state {
            state = new
            if let data = new.selection, let decoded = try? LockShield.decode(data) {
                selection = decoded
            }
            runOnlySelection = new.runOnly.flatMap { try? LockShield.decode($0) } ?? FamilyActivitySelection()
        }
        if let error = outcome.error, command.showsErrors {
            problem = error
        }
        if outcome.unlocked && state.enabled {
            celebrating = true
        }
        log(command, trigger: trigger, outcome: outcome)
        scheduleNextCheck()
    }

    private func scheduleNextCheck() {
        nextCheck?.cancel()
        guard active else { return }
        let now = Date()
        var wait: TimeInterval = 60
        if let end = state.ledger.monitor?.end, end > now {
            wait = min(wait, end.timeIntervalSince(now) + 0.5)
        }
        nextCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, wait) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh(after: "timer")
        }
    }

    /// Kept for the diagnostics: everything but plain refreshes that changed nothing.
    private func log(_ command: LockRuntime.Command, trigger: String, outcome: LockRuntime.Outcome) {
        if case .refresh = command, outcome.note == nil, outcome.error == nil {
            return
        }
        if case .snapshot = command, outcome.error == nil {
            return
        }
        var entry: [String: Any] = [
            "time": DiagnosticLog.now(), "command": command.name, "trigger": trigger,
            "authorization": "\(authorization)",
        ]
        if let note = outcome.note {
            entry["note"] = note
        }
        if let error = outcome.error {
            entry["error"] = error
        }
        if outcome.unlocked {
            entry["unlocked"] = true
        }
        if let state = outcome.state {
            entry.merge(LockCycle.summary(state)) { mine, _ in mine }
        }
        LockStore.appLog?.append(entry)
    }

    // MARK: - Turning it on and off

    /// Asks for Screen Time access (Face ID or passcode), and notifications
    /// for Run now and the 1-minute warning. True if Screen Time is allowed.
    func authorize() async -> Bool {
        if !isAuthorized {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            } catch {
                problem = "Jog Lock needs Screen Time access to lock apps. \(error.localizedDescription)"
            }
            authorization = AuthorizationCenter.shared.authorizationStatus
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return isAuthorized
    }

    /// The apps picked in Screen Time's picker: turns the lock on, or
    /// changes its apps. While they're locked, apps can only be added.
    func choose(_ newSelection: FamilyActivitySelection) {
        if let reason = LockShield.problem(with: newSelection, websites: state.websites) {
            if hasChosenApps {
                problem = reason
            }
            return
        }
        if isLocked && !Self.adds(newSelection, to: selection) {
            problem = "While your apps are locked you can only add to them. Run today's distance, then you can remove some."
            return
        }
        guard let data = try? LockShield.encode(newSelection) else {
            problem = "Couldn't save the apps you chose."
            return
        }
        selection = newSelection
        Task { await perform(.choose(data), trigger: "apps chosen") }
    }

    /// Whether `new` keeps everything in `old`.
    static func adds(_ new: FamilyActivitySelection, to old: FamilyActivitySelection) -> Bool {
        new.applicationTokens.isSuperset(of: old.applicationTokens)
            && new.categoryTokens.isSuperset(of: old.categoryTokens)
            && new.webDomainTokens.isSuperset(of: old.webDomainTokens)
    }

    /// Adds a website typed in by name. Returns why it couldn't be added, to
    /// show by the text field, or nil once it's added.
    func addWebsite(_ text: String) -> String? {
        switch TypedWebsite.adding(text, to: state.websites, picked: selection.webDomainTokens.count) {
        case .failure(.notAWebsite):
            return "Type a website's address, like instagram.com."
        case .failure(.alreadyBlocked(let domain)):
            return "\(domain) is already locked."
        case .failure(.tooMany):
            return "Up to \(LockShield.websiteLimit) websites in all, chosen and typed."
        case .success(let domain):
            saveWebsites(state.websites + [domain], trigger: "website added")
            return nil
        }
    }

    /// Removes websites typed in. While the apps are locked they can only be
    /// added to, like the apps.
    func removeWebsites(_ domains: [String]) {
        let kept = state.websites.filter { !domains.contains($0) }
        guard !isLocked || TypedWebsite.adds(kept, to: state.websites) else {
            problem = "While your apps are locked you can only add websites. Run today's distance, then you can remove some."
            return
        }
        saveWebsites(kept, trigger: "website removed")
    }

    private func saveWebsites(_ websites: [String], trigger: String) {
        state.websites = websites       // shown now, saved by the runtime
        Task { await perform(.websites(websites), trigger: trigger) }
    }

    func turnOff() {
        guard !isLocked else {
            problem = "You can turn the lock off once today's run is done."
            return
        }
        Task { await perform(.turnOff, trigger: "turned off") }
    }

    /// The daily distance setting. While the lock is on, today's target
    /// stays and the new one starts tomorrow.
    func setDailyKm(_ km: Double) {
        Task { await perform(.dailyMeters(km * 1_000), trigger: "daily target") }
    }

    // MARK: - Run-only apps

    var hasRunOnly: Bool {
        !runOnlySelection.applicationTokens.isEmpty || !runOnlySelection.categoryTokens.isEmpty
            || !runOnlySelection.webDomainTokens.isEmpty
    }

    /// The run-only apps are open for the run going now.
    var runOnlyOpen: Bool { state.runOnlyOpen(at: Date()) }

    /// Apps that open only while a run is going. Changing them is always
    /// allowed: they're a treat for running, not the lock.
    func chooseRunOnly(_ newSelection: FamilyActivitySelection) {
        if newSelection.applicationTokens.count > LockShield.appLimit {
            problem = "iOS can lock at most \(LockShield.appLimit) apps. Choose fewer, or a whole category."
            return
        }
        let empty = newSelection.applicationTokens.isEmpty && newSelection.categoryTokens.isEmpty
            && newSelection.webDomainTokens.isEmpty
        let data = empty ? nil : try? LockShield.encode(newSelection)
        runOnlySelection = empty ? FamilyActivitySelection() : newSelection
        Task { await perform(.runOnly(data), trigger: "run-only apps chosen") }
    }

    /// A run started: the run-only apps open until it ends.
    func runStarted(_ id: String) {
        Task { await perform(.runStarted(id), trigger: "run started") }
    }

    /// A run ended (`id` nil: none is going): the run-only apps lock.
    func runEnded(_ id: String?) {
        Task { await perform(.runEnded(id), trigger: "run ended") }
    }

    // MARK: - Plan

    /// Rest days, a weekly target or the 5K plan.
    var plan: RunPlan { state.rules.runPlan }

    /// Today, as the lock counts days (they start at 4:00).
    var today: LockDay { state.rules.day(of: Date()) }

    /// While the lock is on, a new plan starts tomorrow.
    func setPlan(_ plan: RunPlan) {
        state.rules.plan = plan       // shown now, saved by the runtime
        Task { await perform(.plan(plan), trigger: "plan") }
    }

    /// Starts the 5K plan at week 1: today, or tomorrow while the lock is on.
    func startFiveK(restDays: Set<Int>) {
        var plan = self.plan
        plan.kind = .fiveK
        plan.restDays = restDays
        plan.firstWeekday = Calendar.current.firstWeekday
        plan.fiveKStart = isEnabled ? today.adding(days: 1) : today
        setPlan(plan)
    }

    /// Does the current 5K plan week again: the plan moves a week later.
    func repeatFiveKWeek() {
        var plan = self.plan
        guard plan.kind == .fiveK, let start = plan.fiveKStart, plan.fiveKWeekNumber(on: today) > 1 else { return }
        plan.fiveKStart = start.adding(days: 7)
        setPlan(plan)
    }

    /// The 5K plan's week for a run today, when that's the plan.
    var fiveKWeekToday: FiveKWeek? {
        plan.kind == .fiveK ? plan.fiveKWeek(on: today) : nil
    }

    // MARK: - Runs

    /// What the next run has to cover: what's left of today's target while
    /// the apps are locked, otherwise the usual setting.
    func runTargetKm(default km: Double) -> Double {
        var ledger = state.ledger
        ledger.update(to: Date(), rules: state.rules)
        if state.enabled, !ledger.isTargetMet, ledger.remainingMeters > 0 {
            return ledger.remainingMeters / 1_000
        }
        // A weekly or 5K plan sets the distance; the setting is for daily ones.
        if plan.kind != .daily, ledger.targetMeters > 0 {
            return ledger.targetMeters / 1_000
        }
        return km
    }

    /// A run's counted distance so far. Saved to the lock every 25 m, at the
    /// unlock and at the end, so the shield's "1.8 km away" stays close.
    func credit(run id: String, countedMeters: Double, at now: Date = Date(), finished: Bool = false) {
        var preview = state.ledger
        preview.update(to: now, rules: state.rules)
        let unlocks = preview.credit(run: id, countedMeters: countedMeters, rules: state.rules, at: now)
        if unlocks || finished || countedMeters - (savedMeters[id] ?? 0) >= 25 {
            savedMeters[id] = finished ? nil : countedMeters
            Task { await perform(.credit(id, countedMeters, now), trigger: finished ? "run finished" : "run") }
        } else if preview != state.ledger {
            state.ledger = preview      // shown now, saved with the next credit
        }
    }

    // MARK: - Banked minutes and borrowing

    func spend() {
        Task { await perform(.spend, trigger: "use minutes") }
    }

    func stopSpending() {
        Task { await perform(.stopSpending, trigger: "lock again") }
    }

    func borrow() {
        Task { await perform(.borrow, trigger: "borrow") }
    }

    nonisolated static func message(for error: LockError) -> String {
        switch error {
        case .alreadyUnlocked:
            "Your apps are already open for today."
        case .noMinutes:
            "No banked minutes yet. Each km past your daily target banks 15."
        case .stillHaveMinutes(let minutes):
            "Use your \(minutes) banked minutes first."
        case .alreadyBorrowedToday:
            "You've already borrowed from tomorrow today."
        case .owedLimit(let owed):
            "You already owe \(Format.shortDistance(owed)). Run that off before borrowing more."
        }
    }

    // MARK: - Diagnostics

    /// A file to share when something goes wrong: the lock's state (counts
    /// only, never which apps) and what the app, the monitor and the shield
    /// did. Nothing about routes or places.
    func diagnosticsFile() -> URL? {
        let report: [String: Any] = [
            "made": DiagnosticLog.now(), "app": RunTracker.appVersion, "ios": UIDevice.current.systemVersion,
            "authorization": "\(authorization)", "state": LockCycle.summary(state),
            "app_log": LockStore.appLog?.entries() ?? [], "monitor_log": LockStore.monitorLog?.entries() ?? [],
            "shield_log": LockStore.shieldLog?.entries() ?? [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jog-lock-diagnostics.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
