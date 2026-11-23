//
//  JogLockTrackerApp.swift
//  JogLockTracker
//
//  Jog Lock: run today's distance to unlock the apps you chose. Distance
//  comes from Core Location with Strava-style clean-up, checked against
//  your steps; the locking is Screen Time (see AppLock).
//

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
        return true
    }

    // Show "GPS ready" and "target reached" banners while the app is open too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
