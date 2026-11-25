//
//  RunTracker.swift
//  JogLockTracker
//
//  Runs a jog: asks for location access, streams Core Location fitness
//  updates (also with the screen locked), feeds them to DistanceEngine,
//  logs every fix, and tells you when the target distance is reached.
//  Counted distance goes to the app lock as the run goes.
//
//  If iOS kills the app mid-run, it relaunches it in the background for the
//  next location update; the run resumes by replaying its own log.
//

import CoreLocation
import Foundation
import JogLockCore
import UIKit
import UserNotifications

@MainActor
final class RunTracker: NSObject, ObservableObject {
    static let shared = RunTracker()

    enum Status: Equatable {
        case idle
        case requestingPermission
        case waitingForGPS
        case tracking
        case paused
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var snapshot = EngineSnapshot()
    @Published private(set) var lastAccuracy: Double?
    @Published private(set) var startedAt: Date?
    @Published private(set) var runTargetKm: Double = 1
    @Published private(set) var gateTotals = GateTotals()
    @Published private(set) var countedTargetReached = false
    @Published private(set) var cleanTargetReached = false
    @Published private(set) var speedTargetReached = false
    @Published private(set) var warning: String?
    @Published private(set) var diagnostic: String?
    @Published private(set) var lastFinishedRun: RunSummary?
    @Published var targetKm: Double {
        didSet {
            UserDefaults.standard.set(targetKm, forKey: Keys.targetKm)
            AppLock.shared.setDailyKm(targetKm)
        }
    }
    /// The mode the next run starts in.
    @Published var mode: RunMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }
    /// The mode of the current run, or of the last one once it has ended.
    @Published private(set) var runMode: RunMode = .outdoor
    @Published private(set) var strideModel: StrideModel?
    @Published private(set) var lastCadence: Double?
    /// The counted route so far, for the live map.
    @Published private(set) var route: [[Coordinate]] = []
    /// Set when the step check has just thrown out distance ("nice try").
    @Published private(set) var niceTry: NiceTryEvent?

    /// True from tapping Start until the run is stopped.
    var isActive: Bool { status != .idle }

    private enum Keys {
        static let targetKm = "targetKm"
        static let activeRunID = "activeRunID"
        static let activeRunStart = "activeRunStart"
        static let activeRunTarget = "activeRunTarget"
        static let activeRunMode = "activeRunMode"
        static let mode = "runMode"
    }

    private let manager = CLLocationManager()   // only used for permission prompts
    private var counter = RunCounter(start: 0)
    private var routeBuilder = RouteBuilder()
    private var coach = VoiceCoachPlanner()
    private var coachVariant = 0
    private var intervalCoach: IntervalCoach?
    private var intervalVariant = 0
    private var intervalTask: Task<Void, Never>?
    private var niceTryDetector = NiceTryDetector()
    private let speaker = VoiceSpeaker()
    private let liveActivity = RunActivityController()
    private var treadmill: TreadmillCounter?
    private let motion = MotionTracker()
    private var isStopping = false
    private var countedTargetAt: Date?
    private var pedometerMeters: Double?
    private var writer: RunLogWriter?
    private var runID: String?
    private var cleanTargetAt: Date?
    private var speedTargetAt: Date?
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        let saved = UserDefaults.standard.double(forKey: Keys.targetKm)
        targetKm = saved > 0 ? saved : 1.0
        mode = RunMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .outdoor
        super.init()
        AppLock.shared.setDailyKm(targetKm)
        manager.delegate = self
        observeAppState()
        resumeIfNeeded()
        if runID == nil {
            AppLock.shared.runEnded(nil)    // run-only apps left open by a run that's gone
        }
        loadStrideModel()
    }

    // MARK: - Start / stop

    func start() {
        guard status == .idle else { return }
        warning = nil
        diagnostic = nil
        status = .requestingPermission
        Task { await startRun() }
    }

    func stop() {
        guard let id = runID else {
            status = .idle
            return
        }
        guard !isStopping else { return }
        isStopping = true
        stopIntervals()
        AppLock.shared.runEnded(id)
        updatesTask?.cancel()
        updatesTask = nil
        endSessions()
        Task { await finishRun(id: id) }
    }

    /// Takes the pedometer's final count (live updates lag a few seconds),
    /// settles the step check and saves the run.
    private func finishRun(id: String) async {
        let end = Date()
        if let start = startedAt, let totals = await motion.totals(from: start, to: end) {
            let sample = StepSample(t: end.timeIntervalSince1970, steps: totals.steps)
            if treadmill != nil {
                treadmill?.addSteps(sample, pedMeters: totals.meters)
            } else {
                counter.addSteps(sample)
            }
            pedometerMeters = totals.meters
            writeSteps(sample, meters: totals.meters, cadence: nil, detail: "final")
        }
        if treadmill != nil, let start = startedAt {
            // Live activity updates stop while the app is in the background,
            // so fill in the whole run from Core Motion's history.
            for sample in await motion.activities(from: start, to: end) where addMotion(sample) {
                writeMotion(sample)
            }
        }
        motion.stop()
        if treadmill != nil {
            treadmill?.finish()
            gateTotals = treadmill?.totals ?? GateTotals()
        } else {
            counter.finish()
            snapshot = counter.engine.snapshot
            gateTotals = counter.gate.totals
        }
        checkTargets(at: end, notifyUser: false)
        progressChanged(at: end)
        AppLock.shared.credit(run: id, countedMeters: gateTotals.countedMeters, at: end, finished: true)
        liveActivity.end(final: RunActivityAttributes.ContentState(
            meters: gateTotals.countedMeters, targetMeters: runTargetKm * 1000,
            unlocked: countedTargetReached, paused: false))
        logEvent("stop", totals: true)
        writer?.close()
        writer = nil

        let summary = makeSummary(id: id, endedAt: end)
        try? RunStore.onDevice.save(summary)
        lastFinishedRun = summary
        if let alert = ShoeStore.shared.credit(run: id, meters: gateTotals.countedMeters) {
            notify(title: alert.title, body: alert.body)
        }
        if runMode == .outdoor {
            learnStride(fromRun: id)
        }

        clearActiveRun()
        runID = nil
        isStopping = false
        diagnostic = nil
        status = .idle
    }

    func clearWarning() {
        warning = nil
    }

    func clearNiceTry() {
        niceTry = nil
    }

    private func startRun() async {
        let newMode = mode
        if newMode == .outdoor {
            guard await ensureLocationAuthorization() else {
                status = .idle
                warning = "Location access is off. Allow it in Settings > Privacy & Security > Location Services > Jog Lock."
                return
            }
            guard status == .requestingPermission else { return } // stopped while asking

            if manager.accuracyAuthorization == .reducedAccuracy {
                try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunDistance")
            }
            if manager.accuracyAuthorization == .reducedAccuracy {
                warning = "Precise Location is off, so distances will be wrong. Turn it on in Settings > Jog Lock > Location."
            }
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard status == .requestingPermission else { return }
        if !MotionTracker.canCountSteps {
            warning = "This iPhone can't count steps, so distance can't be checked and won't count."
        } else if MotionTracker.isDenied {
            warning = "Motion & Fitness is off, so your steps can't be checked and distance won't count. Turn it on in Settings > Privacy & Security > Motion & Fitness."
        }

        let id = RunStore.newRunID()
        do {
            try RunStore.onDevice.createDirectory(for: id)
            writer = try RunLogWriter(url: RunStore.onDevice.rawLogURL(for: id))
        } catch {
            status = .idle
            warning = "Couldn't create the run log: \(error.localizedDescription)"
            return
        }

        let now = Date()
        runID = id
        // With the app lock on, the run is what's left of today's target.
        runTargetKm = AppLock.shared.runTargetKm(default: targetKm)
        runMode = newMode
        counter = RunCounter(start: now.timeIntervalSince1970)
        snapshot = counter.engine.snapshot
        if newMode == .treadmill {
            let counting = TreadmillCounter(start: now.timeIntervalSince1970, model: strideModel)
            treadmill = counting
            gateTotals = counting.totals
        } else {
            treadmill = nil
            gateTotals = counter.gate.totals
        }
        lastCadence = nil
        routeBuilder = RouteBuilder()
        route = []
        coach = VoiceCoachPlanner()
        niceTryDetector = NiceTryDetector()
        niceTry = nil
        startedAt = now
        countedTargetReached = false
        countedTargetAt = nil
        pedometerMeters = nil
        cleanTargetReached = false
        speedTargetReached = false
        cleanTargetAt = nil
        speedTargetAt = nil
        lastAccuracy = nil
        lastFinishedRun = nil

        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Keys.activeRunID)
        defaults.set(now.timeIntervalSince1970, forKey: Keys.activeRunStart)
        defaults.set(runTargetKm, forKey: Keys.activeRunTarget)
        defaults.set(newMode.rawValue, forKey: Keys.activeRunMode)

        writeHeader(at: now)
        logEvent("start")
        if newMode == .outdoor {
            beginUpdates()
        } else {
            status = .tracking
        }
        startMotion(from: now)
        liveActivity.start(app: AppSettings.shared.nemesis, startedAt: now, targetMeters: runTargetKm * 1000)
        startIntervals(at: now)
        AppLock.shared.runStarted(id)
    }

    // MARK: - 5K plan intervals

    /// On a 5K plan run, the coach calls the warm-up, run and walk intervals,
    /// checked every second. They're spoken even with the funny lines off:
    /// they're the plan's instructions.
    private func startIntervals(at start: Date) {
        stopIntervals()
        intervalCoach = AppLock.shared.fiveKWeekToday.map { IntervalCoach(week: $0) }
        guard intervalCoach != nil else { return }
        intervalTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.checkInterval(since: start)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func checkInterval(since start: Date) {
        guard runID != nil, let cue = intervalCoach?.cue(at: Date().timeIntervalSince(start)) else { return }
        logEvent("interval", detail: "\(cue.phase)")
        let settings = AppSettings.shared
        let line = VoiceLines.interval(cue, app: settings.nemesis, variant: intervalVariant)
        intervalVariant += 1
        speaker.speak(line, style: settings.voiceStyle)
    }

    private func stopIntervals() {
        intervalTask?.cancel()
        intervalTask = nil
        intervalCoach = nil
    }

    private func startMotion(from start: Date) {
        motion.onSteps = { [weak self] sample, meters, cadence in
            self?.handleSteps(sample, meters: meters, cadence: cadence)
        }
        motion.onMotion = { [weak self] sample in
            self?.handleMotion(sample)
        }
        motion.start(from: start)
    }

    private func beginUpdates() {
        // Keeps location coming with the screen locked (blue pill in the status bar).
        backgroundSession = CLBackgroundActivitySession()
        serviceSession = CLServiceSession(authorization: .whenInUse)
        status = .waitingForGPS

        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, self.runID != nil else { break }
                    self.handle(update)
                }
            } catch {
                self?.logEvent("updatesError", detail: String(describing: error))
                self?.warning = "Location updates stopped: \(error.localizedDescription)"
            }
        }
    }

    private func endSessions() {
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    // MARK: - Updates

    private func handle(_ update: CLLocationUpdate) {
        guard !isStopping else { return }
        let stationary = update.stationary
        noteDiagnostics(update)
        guard let location = update.location else { return }

        let decision = counter.add(GPSFix(location: location, stationary: stationary))
        snapshot = counter.engine.snapshot
        gateTotals = counter.gate.totals
        let routeBefore = routeBuilder.segments.count
        routeBuilder.add(Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
                         decision: decision)
        if decision == .accepted || routeBuilder.segments.count != routeBefore {
            route = routeBuilder.segments
        }
        lastAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        writeFix(location, stationary: stationary, decision: decision)

        switch snapshot.phase {
        case .warmingUp:
            status = .waitingForGPS
        case .tracking:
            status = snapshot.isPaused ? .paused : .tracking
        }

        if decision == .warmupComplete {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            notify(title: "GPS ready", body: "Distance is counting now. Start running.")
            logEvent("gpsReady")
        }
        checkTargets(at: location.timestamp, notifyUser: true)
        progressChanged(at: location.timestamp)
    }

    private func handleSteps(_ sample: StepSample, meters: Double?, cadence: Double?) {
        guard runID != nil, !isStopping else { return }
        if treadmill != nil {
            treadmill?.addSteps(sample, pedMeters: meters)
            gateTotals = treadmill?.totals ?? GateTotals()
        } else {
            counter.addSteps(sample)
            gateTotals = counter.gate.totals
        }
        lastCadence = cadence
        writeSteps(sample, meters: meters, cadence: cadence, detail: nil)
        checkTargets(at: Date(timeIntervalSince1970: sample.t), notifyUser: true)
        progressChanged(at: Date(timeIntervalSince1970: sample.t))
    }

    private func handleMotion(_ sample: MotionSample) {
        guard runID != nil, !isStopping else { return }
        if addMotion(sample) {
            writeMotion(sample)
        }
    }

    private func addMotion(_ sample: MotionSample) -> Bool {
        if treadmill != nil {
            return treadmill?.addMotion(sample) ?? false
        }
        return counter.addMotion(sample)
    }

    private func noteDiagnostics(_ update: CLLocationUpdate) {
        var message: String?
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            message = "Location access is off for Jog Lock."
        } else if update.insufficientlyInUse {
            message = "iOS paused location for this app. Open it to carry on."
        } else if update.locationUnavailable {
            message = "No GPS signal right now."
        }
        if message != diagnostic {
            diagnostic = message
            if let message {
                logEvent("diagnostic", detail: message)
            }
        }
    }

    // MARK: - Voice coach and "nice try"

    /// After every change in distance: the app lock, the voice coach, "nice try" cards and the
    /// lock-screen countdown.
    private func progressChanged(at time: Date) {
        if let runID {
            AppLock.shared.credit(run: runID, countedMeters: gateTotals.countedMeters, at: time)
        }
        if let event = niceTryDetector.check(gateTotals, at: time.timeIntervalSince1970) {
            niceTry = event
            logEvent("niceTry", detail: event.kind.rawValue)
            say(.niceTry(event.kind))
        }
        let live = gateTotals.countedMeters + gateTotals.pendingMeters
        if let cue = coach.cue(meters: live, target: runTargetKm * 1000, unlocked: countedTargetReached) {
            say(cue)
        }
        liveActivity.update(meters: live, targetMeters: runTargetKm * 1000,
                            unlocked: countedTargetReached, paused: status == .paused)
    }

    private func say(_ cue: VoiceCue) {
        let settings = AppSettings.shared
        guard settings.voiceOn else { return }
        let live = gateTotals.countedMeters + gateTotals.pendingMeters
        let line = VoiceLines.text(for: cue, app: settings.nemesis,
                                   remainingMeters: max(0, runTargetKm * 1000 - live), variant: coachVariant)
        coachVariant += 1
        speaker.speak(line, style: settings.voiceStyle)
    }

    private func checkTargets(at time: Date, notifyUser: Bool) {
        let goal = runTargetKm * 1000
        if !countedTargetReached && gateTotals.countedMeters >= goal {
            countedTargetReached = true
            countedTargetAt = time
            logEvent("targetReached", detail: "counted")
            if notifyUser {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if AppLock.shared.isEnabled {
                    notify(title: "Unlocked! Today's run is done",
                           body: "\(AppSettings.shared.nemesis) is all yours. Keep going to bank minutes for another day.")
                } else {
                    notify(title: "\(Format.km(runTargetKm)) km reached - apps unlocked",
                           body: "Your steps check out. Note where you are.")
                }
            }
        }
        // GPS distance before the step check, logged for comparison.
        if !cleanTargetReached && snapshot.cleanMeters >= goal {
            cleanTargetReached = true
            cleanTargetAt = time
            logEvent("targetReached", detail: "clean")
        }
        // The speed-based estimate isn't shown any more (it ran 4.6% short on
        // the first real jog), but it is still logged for comparison.
        if !speedTargetReached && snapshot.speedMeters >= goal {
            speedTargetReached = true
            speedTargetAt = time
            logEvent("targetReached", detail: "speed")
        }
    }

    // MARK: - Permission

    private func ensureLocationAuthorization() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    fileprivate func authorizationChanged() {
        guard manager.authorizationStatus != .notDetermined, let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume()
    }

    // MARK: - Resume after iOS ends the app

    private func resumeIfNeeded() {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: Keys.activeRunID) else { return }
        let start = defaults.double(forKey: Keys.activeRunStart)
        let target = defaults.double(forKey: Keys.activeRunTarget)

        let lines = RunStore.onDevice.readLines(id: id)
        runTargetKm = target > 0 ? target : targetKm
        let runStart = Date(timeIntervalSince1970: start)
        startedAt = runStart
        runMode = RunMode(rawValue: defaults.string(forKey: Keys.activeRunMode) ?? "") ?? .outdoor
        counter = RunCounter.replaying(lines)
        treadmill = runMode == .treadmill ? TreadmillCounter.replaying(lines) : nil
        countedTargetAt = Self.targetTime(in: lines, kind: "counted")
        cleanTargetAt = Self.targetTime(in: lines, kind: "clean")
        speedTargetAt = Self.targetTime(in: lines, kind: "speed")
        countedTargetReached = countedTargetAt != nil
        cleanTargetReached = cleanTargetAt != nil
        speedTargetReached = speedTargetAt != nil
        snapshot = counter.engine.snapshot
        gateTotals = treadmill?.totals ?? counter.gate.totals
        runID = id
        writer = try? RunLogWriter(url: RunStore.onDevice.rawLogURL(for: id))

        if Date().timeIntervalSince1970 - start > 6 * 3600 {
            // Left over from hours ago: save it rather than carrying on.
            logEvent("abandoned")
            status = .paused
            stop()
            return
        }
        logEvent("resumed")
        warning = "Resumed a run that iOS interrupted."
        if runMode == .outdoor {
            beginUpdates()
        } else {
            status = .tracking
        }
        startMotion(from: runStart)
        liveActivity.reattach()
    }

    // MARK: - Stride model (treadmill mode)

    private func loadStrideModel() {
        Task { [weak self] in
            let model = await StrideStore.shared.loadOrBackfill(from: RunStore.onDevice)
            self?.strideModel = model
        }
    }

    private func learnStride(fromRun id: String) {
        Task { [weak self] in
            let model = await StrideStore.shared.learn(fromRun: id, in: RunStore.onDevice)
            self?.strideModel = model
        }
    }

    private static func targetTime(in lines: [LogLine], kind: String) -> Date? {
        lines.first(where: { $0.type == "event" && $0.name == "targetReached" && $0.detail == kind })
            .map { Date(timeIntervalSince1970: $0.t) }
    }

    private func clearActiveRun() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.activeRunID)
        defaults.removeObject(forKey: Keys.activeRunStart)
        defaults.removeObject(forKey: Keys.activeRunTarget)
        defaults.removeObject(forKey: Keys.activeRunMode)
    }

    // MARK: - Logging

    /// The header's time is the run start, which the step check also starts from.
    private func writeHeader(at start: Date) {
        var line = LogLine(type: "header", t: start.timeIntervalSince1970)
        line.name = runID
        line.device = Self.deviceModel
        line.os = UIDevice.current.systemVersion
        line.app = Self.appVersion
        line.mode = runMode
        if let treadmill {
            line.stride = treadmill.model
            line.treadmill = treadmill.settings
        } else {
            line.settings = counter.engine.settings
            line.gate = counter.gate.settings
        }
        line.targetKm = runTargetKm
        writer?.write(line)
    }

    private func writeFix(_ location: CLLocation, stationary: Bool, decision: FixDecision) {
        var line = LogLine(type: "fix", t: location.timestamp.timeIntervalSince1970)
        line.lat = location.coordinate.latitude
        line.lon = location.coordinate.longitude
        line.alt = location.altitude
        line.hAcc = location.horizontalAccuracy
        line.vAcc = location.verticalAccuracy
        line.speed = location.speed
        line.speedAcc = location.speedAccuracy
        line.course = location.course
        line.courseAcc = location.courseAccuracy
        line.stationary = stationary
        if let source = location.sourceInformation {
            line.simulated = source.isSimulatedBySoftware
            line.accessory = source.isProducedByAccessory
        }
        line.decision = decision.rawValue
        line.clean = snapshot.cleanMeters
        line.speedDist = snapshot.speedMeters
        line.raw = snapshot.rawMeters
        writer?.write(line)
    }

    private func writeSteps(_ sample: StepSample, meters: Double?, cadence: Double?, detail: String?) {
        var line = LogLine(type: "steps", t: sample.t)
        line.steps = sample.steps
        line.pedMeters = meters
        line.cadence = cadence
        line.detail = detail
        writer?.write(line)
    }

    private func writeMotion(_ sample: MotionSample) {
        var line = LogLine(type: "motion", t: sample.start)
        line.activity = sample.kind
        line.confidence = sample.confidence
        writer?.write(line)
    }

    private func logEvent(_ name: String, detail: String? = nil, totals: Bool = false) {
        var line = LogLine(type: "event", t: Date().timeIntervalSince1970)
        line.name = name
        line.detail = detail
        if totals {
            line.clean = snapshot.cleanMeters
            line.speedDist = snapshot.speedMeters
            line.raw = snapshot.rawMeters
            line.counted = gateTotals.countedMeters
            line.steps = gateTotals.steps
            if treadmill != nil {
                line.rejected = gateTotals.vehicleMeters
            } else {
                line.noSteps = gateTotals.noStepsMeters
                line.vehicle = gateTotals.vehicleMeters
            }
        }
        writer?.write(line)
    }

    private func observeAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.logEvent("background") }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.logEvent("foreground") }
        })
    }

    // MARK: - Helpers

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func makeSummary(id: String, endedAt: Date) -> RunSummary {
        RunSummary(id: id,
                   startedAt: startedAt ?? endedAt,
                   endedAt: endedAt,
                   targetKm: runTargetKm,
                   cleanMeters: snapshot.cleanMeters,
                   speedMeters: snapshot.speedMeters,
                   rawMeters: snapshot.rawMeters,
                   movingSeconds: snapshot.movingSeconds,
                   fixCount: snapshot.fixCount,
                   acceptedCount: snapshot.acceptedCount,
                   rejected: snapshot.rejected,
                   cleanTargetAt: cleanTargetAt,
                   speedTargetAt: speedTargetAt,
                   device: Self.deviceModel,
                   os: UIDevice.current.systemVersion,
                   appVersion: Self.appVersion,
                   settings: counter.engine.settings,
                   stravaKm: nil,
                   trueKm: nil,
                   note: nil,
                   countedMeters: gateTotals.countedMeters,
                   noStepsMeters: runMode == .outdoor ? gateTotals.noStepsMeters : nil,
                   vehicleMeters: runMode == .outdoor ? gateTotals.vehicleMeters : nil,
                   countedTargetAt: countedTargetAt,
                   steps: gateTotals.steps,
                   pedometerMeters: pedometerMeters,
                   mode: runMode,
                   rejectedMeters: runMode == .treadmill ? gateTotals.vehicleMeters : nil)
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

extension RunTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged()
        }
    }
}

extension GPSFix {
    init(location: CLLocation, stationary: Bool) {
        self.init(t: location.timestamp.timeIntervalSince1970,
                  lat: location.coordinate.latitude,
                  lon: location.coordinate.longitude,
                  hAcc: location.horizontalAccuracy,
                  speed: location.speed,
                  speedAcc: location.speedAccuracy,
                  stationary: stationary)
    }
}
