//
//  LockBuddies.swift
//  JogLockTracker
//
//  Lock buddies over iCloud (CloudKit), with no server of our own.
//  - The person who invites makes a zone in their private iCloud database
//    and shares the whole zone by link; the buddy accepts it and sees the
//    same zone in their shared database.
//  - Each phone keeps one record there: its running today (BuddyDay), with
//    the first name it chose. The team record holds the mode.
//  - A silent push tells the other phone when something changes; it also
//    syncs when the app opens. The lock rules (core) decide what a buddy's
//    day means for this phone's lock, and a team only counts once a buddy
//    has joined.
//

import CloudKit
import JogLockCore
import SwiftUI

@MainActor
final class LockBuddies: ObservableObject {
    static let shared = LockBuddies()

    static let containerID = "iCloud.com.abdullahaziz.JogLockTracker"
    private static let zoneName = "LockBuddies"
    private static let teamType = "Team"
    private static let teamName = "team"
    private static let statusType = "Status"

    struct Membership: Codable, Equatable {
        enum Role: String, Codable {
            case owner, member
        }

        var role: Role
        var zoneName: String
        var ownerName: String
        var mode: TeamMode
    }

    @Published private(set) var membership: Membership?
    @Published private(set) var buddy: BuddyDay?
    @Published private(set) var inviteURL: URL?
    @Published private(set) var busy = false
    @Published var problem: String?
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Keys.name) }
    }

    private enum Keys {
        static let me = "buddies.me"
        static let name = "buddies.name"
        static let membership = "buddies.membership"
        static let invite = "buddies.invite"
    }

    /// This phone's own record in the team's zone.
    private let me: String
    private var lastShared: BuddyDay?
    private var lastShareTime = Date.distantPast
    private var pendingShare: Task<Void, Never>?

    private var container: CKContainer {
        CKContainer(identifier: Self.containerID)
    }

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Keys.me) {
            me = saved
        } else {
            me = UUID().uuidString
            defaults.set(me, forKey: Keys.me)
        }
        name = defaults.string(forKey: Keys.name) ?? ""
        if let data = defaults.data(forKey: Keys.membership) {
            membership = try? JSONDecoder().decode(Membership.self, from: data)
        }
        inviteURL = defaults.url(forKey: Keys.invite)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your buddy" : trimmed
    }

    private var zoneID: CKRecordZone.ID? {
        membership.map { CKRecordZone.ID(zoneName: $0.zoneName, ownerName: $0.ownerName) }
    }

    private var database: CKDatabase {
        membership?.role == .member ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private var myRecordName: String {
        "status-" + me
    }

    // MARK: - Making and joining a team

    /// Makes a team and its invite link; you own it.
    func create(mode: TeamMode) async {
        guard membership == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let zone = CKRecordZone(zoneName: Self.zoneName)
            let privateDatabase = container.privateCloudDatabase
            _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            let zoneShare = CKShare(recordZoneID: zone.zoneID)
            zoneShare[CKShare.SystemFieldKey.title] = "Jog Lock buddies" as CKRecordValue
            zoneShare.publicPermission = .readWrite
            let team = CKRecord(recordType: Self.teamType,
                                recordID: CKRecord.ID(recordName: Self.teamName, zoneID: zone.zoneID))
            team["mode"] = mode.rawValue as CKRecordValue
            let saved = try await privateDatabase.modifyRecords(saving: [zoneShare, team], deleting: [])
            guard case .success(let record)? = saved.saveResults[zoneShare.recordID],
                  let url = (record as? CKShare)?.url else {
                throw CKError(.internalError)
            }
            remember(Membership(role: .owner, zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName,
                                mode: mode))
            inviteURL = url
            UserDefaults.standard.set(url, forKey: Keys.invite)
            try await subscribe()
            await shareStatus()
        } catch {
            problem = Self.message(for: error)
        }
    }

    /// The buddy tapped an invite link.
    func accept(_ metadata: CKShare.Metadata) async {
        guard membership == nil else {
            problem = "You're already in a team. Leave it before joining another."
            return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await container.accept(metadata)
            let zone = metadata.share.recordID.zoneID
            remember(Membership(role: .member, zoneName: zone.zoneName, ownerName: zone.ownerName, mode: .together))
            try await subscribe()
            await shareStatus()
            await sync(reason: "joined")
        } catch {
            problem = Self.message(for: error)
        }
    }

    /// Leaves the team: the owner deletes it for both, a member leaves it.
    func leave() async {
        guard let membership, let zoneID else { return }
        busy = true
        defer { busy = false }
        do {
            if membership.role == .owner {
                _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            } else {
                let mine = CKRecord.ID(recordName: myRecordName, zoneID: zoneID)
                _ = try? await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [mine])
                _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            }
        } catch {
            // Already gone is fine; the team ends here either way.
        }
        forget()
    }

    // MARK: - Sharing and syncing

    /// Shares this phone's day if it changed: at once when a target's been
    /// met or the day's new, otherwise at most every 30 seconds.
    func shareIfChanged() {
        guard membership != nil else { return }
        let status = AppLock.shared.myStatus(name: displayName)
        guard let last = lastShared else {
            Task { await shareStatus() }
            return
        }
        guard status.meters != last.meters || status.target != last.target || status.met != last.met
            || status.day != last.day || status.name != last.name else { return }
        if status.met != last.met || status.day != last.day {
            Task { await shareStatus() }
            return
        }
        guard pendingShare == nil else { return }
        let wait = max(0, 30 - Date().timeIntervalSince(lastShareTime))
        pendingShare = Task {
            try? await Task.sleep(for: .seconds(wait))
            pendingShare = nil
            await shareStatus()
        }
    }

    private func shareStatus() async {
        guard let zoneID else { return }
        let status = AppLock.shared.myStatus(name: displayName)
        let record = CKRecord(recordType: Self.statusType, recordID: CKRecord.ID(recordName: myRecordName, zoneID: zoneID))
        record["name"] = status.name as CKRecordValue
        record["day"] = status.day.description as CKRecordValue
        record["meters"] = status.meters as CKRecordValue
        record["target"] = status.target as CKRecordValue
        record["met"] = (status.met ? 1 : 0) as CKRecordValue
        record["updated"] = status.updated as CKRecordValue
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            lastShared = status
            lastShareTime = Date()
        } catch {
            if isGone(error) {
                forget()
            }
        }
    }

    /// Reads the team's zone: the mode, and the buddy's day.
    func sync(reason: String) async {
        guard let membership, let zoneID else { return }
        do {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
            var mode = membership.mode
            var newest: BuddyDay?
            for (id, result) in changes.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                let record = modification.record
                if record.recordType == Self.teamType, let raw = record["mode"] as? String,
                   let saved = TeamMode(rawValue: raw) {
                    mode = saved
                }
                if record.recordType == Self.statusType, id.recordName != myRecordName,
                   let day = Self.buddyDay(record), day.updated > (newest?.updated ?? .distantPast) {
                    newest = day
                }
            }
            if mode != membership.mode {
                var changed = membership
                changed.mode = mode
                remember(changed)
            }
            buddy = newest
            // The team counts once a buddy has joined.
            AppLock.shared.teamSynced(mode: newest == nil ? nil : mode, buddy: newest)
        } catch {
            if isGone(error) {
                forget()
            }
        }
    }

    /// Changes the mode (the owner sets it for both).
    func setMode(_ mode: TeamMode) async {
        guard var membership, membership.role == .owner, let zoneID else { return }
        let team = CKRecord(recordType: Self.teamType, recordID: CKRecord.ID(recordName: Self.teamName, zoneID: zoneID))
        team["mode"] = mode.rawValue as CKRecordValue
        do {
            _ = try await container.privateCloudDatabase.modifyRecords(saving: [team], deleting: [], savePolicy: .allKeys)
            membership.mode = mode
            remember(membership)
            await sync(reason: "mode")
        } catch {
            problem = Self.message(for: error)
        }
    }

    private func subscribe() async throws {
        let id = membership?.role == .member ? "buddies-shared" : "buddies-private"
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    // MARK: - Saved state

    private func remember(_ membership: Membership) {
        self.membership = membership
        if let data = try? JSONEncoder().encode(membership) {
            UserDefaults.standard.set(data, forKey: Keys.membership)
        }
    }

    /// The team's over: the lock goes back to your own running.
    private func forget() {
        membership = nil
        buddy = nil
        inviteURL = nil
        lastShared = nil
        UserDefaults.standard.removeObject(forKey: Keys.membership)
        UserDefaults.standard.removeObject(forKey: Keys.invite)
        AppLock.shared.teamSynced(mode: nil, buddy: nil)
    }

    /// The team's zone no longer exists: the owner ended it, or this phone
    /// was taken out of it.
    private func isGone(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        return error.code == .zoneNotFound || error.code == .userDeletedZone
    }

    private static func buddyDay(_ record: CKRecord) -> BuddyDay? {
        guard let name = record["name"] as? String, let text = record["day"] as? String,
              let day = LockDay(text: text), let meters = record["meters"] as? Double,
              let target = record["target"] as? Double, let met = record["met"] as? Int,
              let updated = record["updated"] as? Date else { return nil }
        return BuddyDay(name: name, day: day, meters: meters, target: target, met: met != 0, updated: updated)
    }

    static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to use lock buddies."
        case .networkUnavailable, .networkFailure:
            return "No connection. Try again when you're online."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        default:
            return "iCloud said no: \(error.localizedDescription)"
        }
    }
}
