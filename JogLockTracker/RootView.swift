//
//  RootView.swift
//  JogLockTracker
//
//  The four tabs: Today, Runs, Lock and Settings. Things that belong to the
//  whole app, like the unlock moment and waking up, live here so they work
//  whichever tab is open.
//

import JogLockCore
import SwiftUI

enum AppTab: Hashable {
    case today, runs, lock, settings
}

struct RootView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    /// The finished run whose summary or unlock moment has been closed.
    @State private var seenRunID: String?

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
        .fullScreenCover(item: cover) { cover in
            switch cover {
            case .run:
                LiveRunView()
                    .environmentObject(tracker)
                    .environmentObject(lock)
            case .unlocked:
                UnlockCelebrationView(selection: lock.selection, websites: lock.websites,
                                      app: AppSettings.shared.nemesis, run: finishedRun,
                                      until: dayEnd, onClose: closeFinishedRun)
            case .summary:
                if let run = finishedRun {
                    RunSummaryView(run: run, onClose: closeFinishedRun)
                        .environmentObject(lock)
                }
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

    /// What covers the tabs: a run in progress until it's saved, then the
    /// unlock moment if it unlocked the apps, or else its summary. The
    /// unlock moment also comes up on its own, when a lock buddy's running
    /// opens the apps.
    private enum Cover: String, Identifiable {
        case run, unlocked, summary
        var id: String { rawValue }
    }

    private var cover: Binding<Cover?> {
        Binding(get: {
            if tracker.isActive {
                return .run
            }
            if lock.celebrating {
                return .unlocked
            }
            return finishedRun == nil ? nil : .summary
        }, set: { cover in
            if cover == nil {
                closeFinishedRun()
            }
        })
    }

    /// The run just saved, until its summary or unlock moment is closed.
    private var finishedRun: RunSummary? {
        guard let run = tracker.lastFinishedRun, run.id != seenRunID else { return nil }
        return run
    }

    private func closeFinishedRun() {
        seenRunID = tracker.lastFinishedRun?.id
        lock.celebrating = false
    }

    /// When the apps lock again: "04:00", or "midnight".
    private var dayEnd: String {
        let end = lock.rules.dayEnd(after: lock.ledger.unlockedAt ?? Date())
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        return parts.hour == 0 && parts.minute == 0 ? "midnight" : end.formatted(date: .omitted, time: .shortened)
    }

    /// A lock action that failed, from any tab.
    private var problemShown: Binding<Bool> {
        Binding(get: { lock.problem != nil }, set: { if !$0 { lock.problem = nil } })
    }
}

#Preview {
    RootView()
        .environmentObject(RunTracker.shared)
        .environmentObject(AppLock.shared)
}
