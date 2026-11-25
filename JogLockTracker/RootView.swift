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
                TodayView { tab = .lock }
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
        .fullScreenCover(isPresented: running) {
            LiveRunView()
                .environmentObject(tracker)
                .environmentObject(lock)
        }
        .fullScreenCover(isPresented: celebrating) {
            UnlockCelebrationView(selection: lock.selection, app: AppSettings.shared.nemesis) {
                lock.celebrating = false
            }
        }
        .alert("App lock", isPresented: problemShown) {
            Button("OK") { lock.problem = nil }
        } message: {
            Text(lock.problem ?? "")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            lock.setActive(phase == .active)
            if phase == .active {
                Task { await LockBuddies.shared.sync(reason: "open") }
            }
        }
    }

    /// A run in progress covers the tabs until it's saved.
    private var running: Binding<Bool> {
        Binding(get: { tracker.isActive }, set: { _ in })
    }

    /// The unlock moment. During a run the run screen shows it.
    private var celebrating: Binding<Bool> {
        Binding(get: { lock.celebrating && !tracker.isActive }, set: { lock.celebrating = $0 })
    }

    /// A lock action that failed, from any tab.
    private var problemShown: Binding<Bool> {
        Binding(get: { lock.problem != nil }, set: { if !$0 { lock.problem = nil } })
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
