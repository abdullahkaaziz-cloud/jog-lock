//
//  RunTracker.swift
//  JogLockTracker
//
//  Runs a jog: asks for location access, streams Core Location fitness
//  updates (also with the screen locked), feeds them to DistanceEngine,
//  logs every fix, and tells you when the target distance is reached.
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
    @Published private(set) var cleanTargetReached = false
    @Published private(set) var speedTargetReached = false
    @Published private(set) var warning: String?
    @Published private(set) var diagnostic: String?
    @Published private(set) var lastFinishedRun: RunSummary?
    @Published var targetKm: Double {
        didSet { UserDefaults.standard.set(targetKm, forKey: Keys.targetKm) }
    }

    /// True from tapping Start until the run is stopped.
    var isActive: Bool { status != .idle }

    private enum Keys {
        static let targetKm = "targetKm"
        static let activeRunID = "activeRunID"
        static let activeRunStart = "activeRunStart"
        static let activeRunTarget = "activeRunTarget"
    }

    private let manager = CLLocationManager()   // only used for permission prompts
    private var engine = DistanceEngine()
    private var writer: RunLogWriter?
    private var runID: String?
    private var cleanTargetAt: Date?
    private var speedTargetAt: Date?
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: AnyObject?       // CLServiceSession on iOS 18+
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        let saved = UserDefaults.standard.double(forKey: Keys.targetKm)
        targetKm = saved > 0 ? saved : 1.0
        super.init()
        manager.delegate = self
        observeAppState()
        resumeIfNeeded()
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
        updatesTask?.cancel()
        updatesTask = nil
        endSessions()

        snapshot = engine.finalize()
        checkTargets(at: Date(), notifyUser: false)
        logEvent("stop", totals: true)
        writer?.close()
        writer = nil

        let summary = makeSummary(id: id, endedAt: Date())
        try? RunStore.onDevice.save(summary)
        lastFinishedRun = summary

        clearActiveRun()
        runID = nil
        diagnostic = nil
        status = .idle
    }

    func clearWarning() {
        warning = nil
    }

    private func startRun() async {
        guard await ensureLocationAuthorization() else {
            status = .idle
            warning = "Location access is off. Allow it in Settings > Privacy & Security > Location Services > Jog Tracker."
            return
        }
        guard status == .requestingPermission else { return } // stopped while asking

        if manager.accuracyAuthorization == .reducedAccuracy {
            try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunDistance")
        }
        if manager.accuracyAuthorization == .reducedAccuracy {
            warning = "Precise Location is off, so distances will be wrong. Turn it on in Settings > Jog Tracker > Location."
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard status == .requestingPermission else { return }

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
        runTargetKm = targetKm
        engine = DistanceEngine(settings: .standard)
        snapshot = engine.snapshot
        startedAt = now
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

        writeHeader()
        logEvent("start")
        beginUpdates()
    }

    private func beginUpdates() {
        // Keeps location coming with the screen locked (blue pill in the status bar).
        backgroundSession = CLBackgroundActivitySession()
        if #available(iOS 18.0, *) {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
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
        if #available(iOS 18.0, *) {
            (serviceSession as? CLServiceSession)?.invalidate()
        }
        serviceSession = nil
    }

    // MARK: - Updates

    private func handle(_ update: CLLocationUpdate) {
        let stationary: Bool
        if #available(iOS 18.0, *) {
            stationary = update.stationary
            noteDiagnostics(update)
        } else {
            stationary = update.isStationary
        }
        guard let location = update.location else { return }

        let decision = engine.process(GPSFix(location: location, stationary: stationary))
        snapshot = engine.snapshot
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
    }

    @available(iOS 18.0, *)
    private func noteDiagnostics(_ update: CLLocationUpdate) {
        var message: String?
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            message = "Location access is off for Jog Tracker."
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

    private func checkTargets(at time: Date, notifyUser: Bool) {
        let goal = runTargetKm * 1000
        if !cleanTargetReached && snapshot.cleanMeters >= goal {
            cleanTargetReached = true
            cleanTargetAt = time
            logEvent("targetReached", detail: "clean")
            if notifyUser {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                notify(title: "\(Format.km(runTargetKm)) km reached - apps unlocked",
                       body: "Jog Lock's distance hit your target. Note where you are.")
            }
        }
        if !speedTargetReached && snapshot.speedMeters >= goal {
            speedTargetReached = true
            speedTargetAt = time
            logEvent("targetReached", detail: "speed")
            if notifyUser {
                notify(title: "Speed-based: \(Format.km(runTargetKm)) km",
                       body: "The speed-based estimate hit your target too.")
            }
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
        let settings = lines.first(where: { $0.type == "header" })?.settings ?? .standard
        runTargetKm = target > 0 ? target : targetKm
        startedAt = Date(timeIntervalSince1970: start)
        engine = DistanceEngine(settings: settings)
        let goal = runTargetKm * 1000
        for line in lines {
            guard let fix = GPSFix(line: line) else { continue }
            engine.process(fix)
            if cleanTargetAt == nil && engine.snapshot.cleanMeters >= goal {
                cleanTargetAt = Date(timeIntervalSince1970: fix.t)
            }
            if speedTargetAt == nil && engine.snapshot.speedMeters >= goal {
                speedTargetAt = Date(timeIntervalSince1970: fix.t)
            }
        }
        cleanTargetReached = cleanTargetAt != nil
        speedTargetReached = speedTargetAt != nil
        snapshot = engine.snapshot
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
        beginUpdates()
    }

    private func clearActiveRun() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.activeRunID)
        defaults.removeObject(forKey: Keys.activeRunStart)
        defaults.removeObject(forKey: Keys.activeRunTarget)
    }

    // MARK: - Logging

    private func writeHeader() {
        var line = LogLine(type: "header", t: Date().timeIntervalSince1970)
        line.name = runID
        line.device = Self.deviceModel
        line.os = UIDevice.current.systemVersion
        line.app = Self.appVersion
        line.settings = engine.settings
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

    private func logEvent(_ name: String, detail: String? = nil, totals: Bool = false) {
        var line = LogLine(type: "event", t: Date().timeIntervalSince1970)
        line.name = name
        line.detail = detail
        if totals {
            line.clean = snapshot.cleanMeters
            line.speedDist = snapshot.speedMeters
            line.raw = snapshot.rawMeters
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
                   settings: engine.settings,
                   stravaKm: nil,
                   trueKm: nil,
                   note: nil)
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
