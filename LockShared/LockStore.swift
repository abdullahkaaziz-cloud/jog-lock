//
//  LockStore.swift
//  Built into the app and its Screen Time extensions.
//
//  Where the lock keeps things in the App Group, so the extensions can read
//  them: the state (one JSON file, only ever replaced whole), the usage
//  events waiting to be counted, and short logs of what each part did, for
//  the diagnostics. The file lock that guards the state is in LockCycle.
//
//  The approach is Tilawah Key's, which settled on files over shared
//  UserDefaults after many iPhone tests.
//

import Foundation
import JogLockCore

enum LockStore {
    static let appGroup = "group.com.abdullahaziz.JogLockTracker"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func stateURL(in directory: URL) -> URL {
        directory.appendingPathComponent("lock-state-v1.json")
    }

    static func inbox(in directory: URL) -> UsageInbox {
        UsageInbox(directory: directory.appendingPathComponent("usage-events"))
    }

    /// The state as saved, read without the lock: for the shield and the
    /// monitor's warning, which never save it. Never half-written, as the
    /// file is only ever replaced whole. Nil if there's none or it can't be
    /// trusted.
    static func peek() -> LockState? {
        guard let directory = container,
              let data = try? Data(contentsOf: stateURL(in: directory)),
              let state = try? JSONDecoder().decode(LockState.self, from: data), state.valid
        else { return nil }
        return state
    }

    /// What the usage monitor did, newest last: iOS runs it where nothing else records it.
    static var monitorLog: DiagnosticLog? {
        container.map { DiagnosticLog(url: $0.appendingPathComponent("monitor-log.json"), limit: 60) }
    }

    /// What the shield's buttons did.
    static var shieldLog: DiagnosticLog? {
        container.map { DiagnosticLog(url: $0.appendingPathComponent("shield-log.json"), limit: 30) }
    }

    /// What the app asked of the lock, and how it went.
    static var appLog: DiagnosticLog? {
        container.map { DiagnosticLog(url: $0.appendingPathComponent("app-log.json"), limit: 100) }
    }
}

/// A short JSON list in a file, newest last, at most `limit` entries.
/// Diagnostics, not saved state: a list that can't be read starts again.
struct DiagnosticLog {
    let url: URL
    let limit: Int

    func entries() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list
    }

    func append(_ entry: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(entry) else { return }
        let list = Array((entries() + [entry]).suffix(limit))
        guard let data = try? JSONSerialization.data(withJSONObject: list) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The time for an entry.
    static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// Usage events wait here, one empty file each, named by monitor and event,
/// before the monitor asks for the lock. Every transaction counts what's
/// waiting first, so a busy lock never loses an event; counting is
/// idempotent, so one counted twice counts once.
struct UsageInbox {
    let directory: URL

    func keep(monitor: String, event: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(monitor + "~" + event),
                         options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func kept() -> [(file: URL, monitor: String, event: String)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            let parts = file.lastPathComponent.split(separator: "~", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].hasPrefix(".") else { return nil }
            return (file, parts[0], parts[1])
        }
    }

    func remove(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
