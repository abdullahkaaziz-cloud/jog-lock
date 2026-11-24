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
    @State private var editingWebsites = false
    @State private var showingBuddies = false
    @ObservedObject private var buddies = LockBuddies.shared

    var body: some View {
        Group {
            if lock.isEnabled && lock.hasChosenApps {
                lockContent
            } else {
                setUpContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .familyActivityPicker(isPresented: $picking, selection: $draft)
        .sheet(isPresented: $editingWebsites) {
            WebsitesView()
                .environmentObject(lock)
        }
        .sheet(isPresented: $showingBuddies) {
            BuddiesView()
                .environmentObject(lock)
        }
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
            Text("Your apps open now, and every minute you use them counts. Tomorrow's run goes up by \(Format.shortDistance(lock.rules.borrowMeters)).")
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

    private var buddyLine: String {
        guard let buddy = buddies.buddy else { return "Lock buddy: waiting for them to join" }
        return "With \(buddy.name): \(BuddiesView.progress(buddy, today: lock.today).lowercased())"
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
            Text("Pick apps like TikTok or Instagram. Each day they stay locked until you've run \(Format.shortDistance(lock.rules.dailyMeters)). Once they're locked you can add apps, but removing them or turning the lock off waits until you've run.")
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

    private var lockContent: some View {
        let ledger = lock.ledger
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                status(ledger)
                Spacer()
                menu
            }
            if lock.accessOff {
                accessOff
            }
            LockedAppsRow(selection: lock.selection, websites: lock.websites)
            if buddies.membership != nil {
                Button {
                    showingBuddies = true
                } label: {
                    Label(buddyLine, systemImage: "person.2.fill")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if ledger.owedMeters > 0 && !ledger.isTargetMet {
                Text("Today's \(Format.shortDistance(ledger.targetMeters)) includes \(Format.shortDistance(ledger.owedMeters)) you borrowed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            minutes(ledger)
        }
    }

    @ViewBuilder
    private func status(_ ledger: LockLedger) -> some View {
        if ledger.isTargetMet {
            let end = lock.rules.dayEnd(after: ledger.unlockedAt ?? Date())
            Label("Unlocked until \(end.formatted(date: .omitted, time: .shortened))", systemImage: "lock.open.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else if ledger.spending {
            Label(ledger.isOpen ? "Open · \(ledger.spendableMinutes) min left" : "Opening…",
                  systemImage: ledger.isOpen ? "lock.open.fill" : "hourglass")
                .font(.headline)
                .foregroundStyle(.orange)
        } else {
            Label("Locked · \(Format.shortDistance(ledger.remainingMeters)) to go", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }
    }

    private var menu: some View {
        Menu {
            Button {
                chooseApps()
            } label: {
                Label(lock.isLocked ? "Add apps" : "Change apps", systemImage: "apps.iphone")
            }
            Button {
                editingWebsites = true
            } label: {
                Label(lock.isLocked ? "Add websites" : "Websites", systemImage: "globe")
            }
            Button {
                showingBuddies = true
            } label: {
                Label("Lock buddy", systemImage: "person.2.fill")
            }
            Button(role: .destructive) {
                if lock.isLocked {
                    lock.problem = "You can turn the lock off once today's run is done."
                } else {
                    confirmOff = true
                }
            } label: {
                Label("Turn off app lock", systemImage: "lock.open")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    private var accessOff: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Screen Time access is off", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("iOS can't lock your apps until it's back on.")
                .font(.footnote)
            Button("Turn it back on") {
                Task {
                    if await lock.authorize() {
                        lock.refresh(after: "access back")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func minutes(_ ledger: LockLedger) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(ledger.spendableMinutes) banked minutes", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
            Text("Each km past your target banks \(Int(lock.rules.minutesPerExtraKm)) minutes. Spent, they only count while you're using the locked apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if ledger.spending {
                Button("Lock again now") {
                    lock.stopSpending()
                }
                .buttonStyle(.bordered)
            } else if !ledger.isTargetMet {
                Button("Use banked minutes") {
                    lock.spend()
                }
                .buttonStyle(.bordered)
                .disabled(ledger.spendableMinutes < 1)
                borrow(ledger)
            }
        }
    }

    private func borrow(_ ledger: LockLedger) -> some View {
        let problem = ledger.borrowProblem(rules: lock.rules)
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

/// The chosen apps' icons, and the websites typed in. iOS draws the icons;
/// Jog Lock never learns which apps they are.
struct LockedAppsRow: View {
    let selection: FamilyActivitySelection
    var websites: [String] = []

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
                ForEach(websites, id: \.self) { site in
                    Label(site, systemImage: "globe")
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(.vertical, 4)
        }
    }
}
