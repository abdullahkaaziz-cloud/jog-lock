//
//  AppLockCard.swift
//  JogLockTracker
//
//  The lock on the home screen: which apps are locked, how far there is
//  to run, banked minutes and borrowing from tomorrow.
//

import FamilyControls
import JogLockCore
import SwiftUI

struct AppLockCard: View {
    @EnvironmentObject private var lock: AppLock
    @State private var picking = false
    @State private var draft = FamilyActivitySelection()
    @State private var confirmBorrow = false
    @State private var confirmOff = false

    var body: some View {
        Group {
            if lock.isEnabled && lock.hasChosenApps {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    lockContent(now: context.date)
                }
            } else {
                setUpContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .familyActivityPicker(isPresented: $picking, selection: $draft)
        .onChange(of: picking) { _, isOpen in
            if !isOpen {
                lock.choose(draft)
            }
        }
        .confirmationDialog("Borrow \(Int(lock.rules.borrowMinutes)) minutes from tomorrow?",
                            isPresented: $confirmBorrow, titleVisibility: .visible) {
            Button("Borrow") { lock.borrow() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your apps open now. Tomorrow's run goes up by \(Format.shortDistance(lock.rules.borrowMeters)).")
        }
        .confirmationDialog("Turn off the app lock?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { lock.turnOff() }
            Button("Keep it on", role: .cancel) {}
        } message: {
            Text("Your apps open straight away. Banked minutes and borrowed distance are kept.")
        }
        .alert("App lock", isPresented: problemShown) {
            Button("OK") { lock.problem = nil }
        } message: {
            Text(lock.problem ?? "")
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { lock.problem != nil }, set: { if !$0 { lock.problem = nil } })
    }

    private func chooseApps() {
        Task {
            guard await lock.authorize() else { return }
            draft = lock.selection
            picking = true
        }
    }

    // MARK: - Lock off

    private var setUpContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lock your apps", systemImage: "lock.fill")
                .font(.headline)
            Text("Pick apps like TikTok or Instagram. Each day they stay locked until you've run \(Format.shortDistance(lock.rules.dailyMeters)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                chooseApps()
            } label: {
                Label("Choose apps to lock", systemImage: "apps.iphone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Lock on

    private func lockContent(now: Date) -> some View {
        let ledger = lock.ledger
        let unlocked = ledger.isUnlocked(at: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                status(ledger: ledger, now: now)
                Spacer()
                Menu {
                    Button {
                        chooseApps()
                    } label: {
                        Label("Change apps", systemImage: "apps.iphone")
                    }
                    Button(role: .destructive) {
                        confirmOff = true
                    } label: {
                        Label("Turn off app lock", systemImage: "lock.open")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            LockedAppsRow(selection: lock.selection)
            if ledger.owedMeters > 0 && !ledger.isTargetMet {
                Text("Today's \(Format.shortDistance(ledger.targetMeters)) includes \(Format.shortDistance(ledger.owedMeters)) you borrowed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            bank(ledger: ledger, unlocked: unlocked)
            if !unlocked {
                borrow(ledger: ledger, now: now)
            }
        }
    }

    @ViewBuilder
    private func status(ledger: LockLedger, now: Date) -> some View {
        if ledger.isTargetMet {
            Label("Unlocked for today", systemImage: "lock.open.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else if let session = ledger.activeSession(at: now) {
            let kind = session.source == .borrow ? "borrowed" : "banked"
            Label("Open for \(Format.duration(session.end.timeIntervalSince(now))) (\(kind))", systemImage: "lock.open.fill")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.orange)
        } else {
            Label("Locked · \(Format.shortDistance(ledger.remainingMeters)) to go", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }
    }

    private func bank(ledger: LockLedger, unlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(Int(ledger.bankMinutes)) banked minutes", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
            Text("Every km past your target banks \(Int(lock.rules.minutesPerExtraKm)) minutes for another day.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !unlocked {
                HStack {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("Use \(minutes) min") {
                            lock.spend(minutes: Double(minutes))
                        }
                        .buttonStyle(.bordered)
                        .disabled(ledger.bankMinutes + 1e-9 < Double(minutes))
                    }
                }
                .font(.footnote)
            }
        }
    }

    private func borrow(ledger: LockLedger, now: Date) -> some View {
        let problem = ledger.borrowProblem(rules: lock.rules, at: now)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                confirmBorrow = true
            } label: {
                Label("Borrow \(Int(lock.rules.borrowMinutes)) min from tomorrow", systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(problem != nil)
            Text(problem.map { AppLock.message(for: $0) }
                 ?? "Tomorrow's run goes up by \(Format.shortDistance(lock.rules.borrowMeters)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The chosen apps' icons. iOS draws them; Jog Lock never learns which apps they are.
struct LockedAppsRow: View {
    let selection: FamilyActivitySelection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.5)
                        .frame(width: 40, height: 40)
                }
                ForEach(Array(selection.categoryTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.5)
                        .frame(width: 40, height: 40)
                }
                ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.5)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
