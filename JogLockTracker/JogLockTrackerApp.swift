//
//  JogLockTrackerApp.swift
//  JogLockTracker
//
//  Jog Lock: run today's distance to unlock the apps you chose. Distance
//  comes from Core Location with Strava-style clean-up, checked against
//  your steps; the locking is Screen Time (see AppLock).
//

import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct JogLockTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tracker = RunTracker.shared
    @StateObject private var lock = AppLock.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(lock)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Create the tracker at launch so a run that iOS interrupted resumes,
        // even when iOS relaunches the app in the background.
        _ = RunTracker.shared
        // Silent pushes say a lock buddy's running changed.
        application.registerForRemoteNotifications()
        return true
    }

    /// A lock buddy's day changed in iCloud: sync it, even in the background.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task {
            await LockBuddies.shared.sync(reason: "push")
            completionHandler(.newData)
        }
    }

    /// A scene delegate of our own, for invite links to a lock buddies team.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Show "GPS ready" and "target reached" banners while the app is open too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Receives a lock buddy's invite link, whether it opened the app or
/// arrived while it was open. SwiftUI still makes the window.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await LockBuddies.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await LockBuddies.shared.accept(cloudKitShareMetadata) }
    }
}
