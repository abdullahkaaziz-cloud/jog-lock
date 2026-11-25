//
//  RootView.swift
//  JogLockTracker
//
//  The four tabs: Today, Runs, Lock and Settings. Things that belong to the
//  whole app, like the unlock moment and waking up, live here so they work
//  whichever tab is open.
//

import SwiftUI

enum AppTab: Hashable {
    case today, runs, lock, settings
}

struct RootView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "capsule", value: AppTab.today) {
                LiveRunView()
            }
            Tab("Runs", systemImage: "chart.bar", value: AppTab.runs) {
                NavigationStack {
                    RunListView()
                }
            }
            Tab("Lock", systemImage: "lock", value: AppTab.lock) {
                LockTab()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(showsDone: false)
            }
        }
        .fullScreenCover(isPresented: $lock.celebrating) {
            UnlockCelebrationView(selection: lock.selection, app: AppSettings.shared.nemesis) {
                lock.celebrating = false
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            lock.setActive(phase == .active)
            if phase == .active {
                Task { await LockBuddies.shared.sync(reason: "open") }
            }
        }
    }
}

/// The Lock tab: what's locked and the rules around it.
/// Redesigned in step 7 of docs/design/BUILD-PLAN.md.
struct LockTab: View {
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppLockCard()
                    RunOnlyCard()
                    if lock.isAuthorized {
                        TimeOnAppsCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Lock")
            .jlScreen()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(RunTracker.shared)
        .environmentObject(AppLock.shared)
}
