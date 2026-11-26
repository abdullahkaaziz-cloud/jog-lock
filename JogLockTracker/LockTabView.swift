//
//  LockTabView.swift
//  JogLockTracker
//
//  The Lock tab: where the lock stands, what stays locked until you run,
//  today's ways in (the plan, banked time, borrowing), run-only apps, the
//  lock buddy, time on apps, how to make the lock harder to switch off,
//  and switching it off.
//

import FamilyControls
import JogLockCore
import SwiftUI

struct LockTab: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var tracker: RunTracker
    @ObservedObject private var buddies = LockBuddies.shared
    @State private var picking = false
    @State private var draft = FamilyActivitySelection()
    @State private var pickingRunOnly = false
    @State private var runOnlyDraft = FamilyActivitySelection()
    @State private var borrowing = false
    @State private var editingPlan = false
    @State private var confirmOff = false
    @State private var showsHowTo = false
    @State private var paidMeters: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Lock")
                        .font(.jlHeading(34, relativeTo: .largeTitle))
                        .tracking(-0.7)
                        .padding(.top, 12)
                    status
                    if lock.isEnabled && lock.hasChosenApps {
                        lockedApps
                        today
                    } else {
                        setUp
                    }
                    runOnly
                    buddyCard
                    if lock.isAuthorized {
                        timeOnApps
                    }
                    unbreakable
                    if lock.isEnabled {
                        turnOff
                    }
                }
                .foregroundStyle(JL.ink)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .jlScreen()
            .toolbar(.hidden, for: .navigationBar)
            .familyActivityPicker(isPresented: $picking, selection: $draft)
            .familyActivityPicker(isPresented: $pickingRunOnly, selection: $runOnlyDraft)
            .onChange(of: picking) { _, isOpen in
                if !isOpen {
                    lock.choose(draft)
                }
            }
            .onChange(of: pickingRunOnly) { _, isOpen in
                if !isOpen {
                    lock.chooseRunOnly(runOnlyDraft)
                }
            }
            .sheet(isPresented: $borrowing) {
                BorrowSheet()
                    .environmentObject(lock)
                    .environmentObject(tracker)
            }
            .sheet(isPresented: $editingPlan) {
                PlanView(targetKm: $tracker.targetKm)
                    .environmentObject(lock)
                    .environmentObject(tracker)
            }
            .confirmationDialog("Turn off the app lock?", isPresented: $confirmOff, titleVisibility: .visible) {
                Button("Turn off", role: .destructive) { lock.turnOff() }
                Button("Keep it on", role: .cancel) {}
            } message: {
                Text("Your apps open straight away. Banked minutes and borrowed distance are kept.")
            }
            .task {
                paidMeters = TimeOnAppsCard.paidThisWeek(since: ScreenTimeWeek.thisWeek(from: ScreenTimeWeek.fortnight(of: Date())))
            }
        }
    }

    // MARK: - Where the lock stands

    private var status: some View {
        let ledger = lock.ledger
        let look = statusLook(ledger)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: look.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(look.red ? JL.redOnInk : JL.paper)
                Text(look.title)
                    .font(.jlHeading(26))
                Spacer(minLength: 8)
                Text(look.detail)
                    .font(.subheadline)
                    .monospacedDigit()
                    .opacity(0.7)
                    .multilineTextAlignment(.trailing)
            }
            if let progress = look.progress {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(hex: 0x3A352E))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(JL.redOnInk)
                                .frame(width: proxy.size.width * min(1, max(0, progress)))
                        }
                }
                .frame(height: 8)
            }
            if lock.accessOff {
                Button("Turn it back on") {
                    Task {
                        if await lock.authorize() {
                            lock.refresh(after: "access back")
                        }
                    }
                }
                .buttonStyle(JLSmallButtonStyle(fill: JL.red, text: JL.card))
            }
        }
        .foregroundStyle(JL.paper)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(JL.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statusLook(_ ledger: LockLedger) -> (icon: String, title: String, detail: String, progress: Double?, red: Bool) {
        guard lock.isEnabled && lock.hasChosenApps else {
            return ("lock.open", "Not set up", "", nil, false)
        }
        if lock.accessOff {
            return ("exclamationmark.triangle", "Paused", "Screen Time access is off", nil, true)
        }
        if ledger.isRestDay {
            return ("lock.open", "Rest day", "open all day", nil, false)
        }
        if ledger.isTargetMet {
            return ("lock.open.fill", "Unlocked", "until \(dayEnd)", 1, false)
        }
        if ledger.spending {
            return ("lock.open", "Open", ledger.isOpen ? "\(ledger.spendableMinutes) min left" : "opening…", nil, false)
        }
        let progress = ledger.targetMeters > 0 ? ledger.ranMeters / ledger.targetMeters : 0
        return ("lock.fill", "Locked", "\(Format.shortDistance(ledger.remainingMeters)) to go", progress, true)
    }

    private var dayEnd: String {
        let end = lock.rules.dayEnd(after: lock.ledger.unlockedAt ?? Date())
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        return parts.hour == 0 && parts.minute == 0 ? "midnight" : end.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Locked until you run

    private var lockedApps: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Locked until you run")
            JLList {
                Button(action: chooseApps) {
                    row(isLast: false) {
                        if lock.hasPickedApps {
                            AppTiles(selection: lock.selection)
                            AppNames(selection: lock.selection)
                        } else {
                            Text("Apps")
                        }
                        Spacer(minLength: 8)
                        Text(lock.isLocked ? "Add" : "Change")
                            .foregroundStyle(JL.ink2)
                    }
                }
                .buttonStyle(.plain)
                NavigationLink {
                    WebsitesView()
                } label: {
                    row(isLast: true) {
                        Image(systemName: "globe")
                            .frame(width: 28, height: 28)
                            .background(JL.sand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("Websites")
                        Spacer(minLength: 8)
                        Text("\(lock.websites.count)")
                            .foregroundStyle(JL.ink2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A list row with any content, a chevron and a hairline under it.
    private func row<Content: View>(isLast: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                content()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x9A9284))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .foregroundStyle(JL.ink)
        .contentShape(Rectangle())
    }

    // MARK: - Today

    private var today: some View {
        let ledger = lock.ledger
        let banked = ledger.spending
            ? (ledger.isOpen ? "Open · \(ledger.spendableMinutes) min left" : "Opening…")
            : "\(ledger.spendableMinutes) min · Use"
        let borrow = ledger.isTargetMet ? "Not needed today" : "+\(Format.shortDistance(lock.rules.borrowMeters)) tomorrow"
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Today")
            JLList {
                Button {
                    editingPlan = true
                } label: {
                    JLListRow(title: "Run to unlock",
                              detail: PlanText.summary(lock.plan, dailyMeters: lock.rules.dailyMeters, today: lock.today),
                              chevron: true)
                }
                .buttonStyle(.plain)
                Button {
                    borrowing = true
                } label: {
                    JLListRow(title: "Banked time", detail: banked, chevron: true)
                }
                .buttonStyle(.plain)
                Button {
                    borrowing = true
                } label: {
                    JLListRow(title: "Borrow \(Int(lock.rules.borrowMinutes)) min", detail: borrow, chevron: true, isLast: true)
                }
                .buttonStyle(.plain)
                .disabled(ledger.isTargetMet)
            }
            if ledger.owedMeters > 0 && !ledger.isTargetMet {
                Text("Today's \(Format.shortDistance(ledger.targetMeters)) includes \(Format.shortDistance(ledger.owedMeters)) you borrowed.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
        }
    }

    // MARK: - No lock yet

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick apps like TikTok or Instagram. Each day they stay locked until you've run \(Format.shortDistance(lock.rules.dailyMeters)). Once they're locked you can add apps, but removing them or turning the lock off waits until you've run.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            Button(action: chooseApps) {
                Label("Choose apps to lock", systemImage: "apps.iphone")
            }
            .buttonStyle(.jlPrimary)
            JLList {
                NavigationLink {
                    WebsitesView()
                } label: {
                    JLListRow(title: "Websites", detail: lock.websites.isEmpty ? "Add" : "\(lock.websites.count)",
                              chevron: true, isLast: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Run-only apps

    private var runOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Run-only apps")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if lock.hasRunOnly {
                        AppTiles(selection: lock.runOnlySelection)
                        AppNames(selection: lock.runOnlySelection)
                    } else {
                        Text("A podcast, music or audiobook app")
                    }
                    Spacer(minLength: 8)
                    Toggle("Run-only apps", isOn: runOnlyOn)
                        .labelsHidden()
                        .tint(JL.red)
                }
                .font(.body)
                Text(lock.hasRunOnly
                     ? (lock.runOnlyOpen ? "Open now, while you run. They shut again when you stop."
                        : "They open only while you're running, and stay shut the rest of the day.")
                     : "Pick an app you can only open while you're running. Your favourite show becomes the reason to go.")
                    .font(.subheadline)
                    .foregroundStyle(JL.ink2)
                if lock.hasRunOnly {
                    Button("Change run-only apps", action: chooseRunOnly)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JL.redText)
                }
            }
            .padding(16)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// On picks run-only apps; off lets them be opened any time again.
    private var runOnlyOn: Binding<Bool> {
        Binding(get: { lock.hasRunOnly }, set: { on in
            if on {
                chooseRunOnly()
            } else {
                lock.chooseRunOnly(FamilyActivitySelection())
            }
        })
    }

    // MARK: - Buddy, time on apps, and making it stick

    private var buddyCard: some View {
        NavigationLink {
            BuddiesScreen()
        } label: {
            HStack(spacing: 12) {
                if let buddy = buddies.buddy, buddies.membership != nil {
                    BuddyAvatar(name: buddy.name, size: 44)
                } else {
                    Image(systemName: "person.2.fill")
                        .frame(width: 44, height: 44)
                        .background(JL.sand, in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(buddyTitle)
                        .font(.headline)
                    Text(buddyDetail)
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x9A9284))
            }
            .foregroundStyle(JL.ink)
            .padding(16)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var buddyTitle: String {
        guard let membership = buddies.membership else { return "Lock buddy" }
        return "Lock buddy: \(buddies.buddy?.name ?? (membership.role == .owner ? "invite sent" : membership.ownerName))"
    }

    private var buddyDetail: String {
        guard let membership = buddies.membership else { return "Run with a friend. Your apps open when you've both run." }
        switch membership.mode {
        case .together: return "Together · you both run to unlock"
        case .forEachOther: return "For each other · your runs unlock each other"
        }
    }

    private var timeOnApps: some View {
        NavigationLink {
            TimeOnAppsScreen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "receipt")
                    .frame(width: 44, height: 44)
                    .background(JL.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time on apps")
                        .font(.headline)
                    Text("This week's receipt, paid with \(PlanText.distance(paidMeters))")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x9A9284))
            }
            .foregroundStyle(JL.ink)
            .padding(16)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var unbreakable: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                showsHowTo.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make it unbreakable")
                            .font(.headline)
                        Text("Ask someone you trust to set a Screen Time passcode, so the lock can't be switched off in a weak moment.")
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x9A9284))
                        .rotationEffect(.degrees(showsHowTo ? 90 : 0))
                }
                if showsHowTo {
                    UnbreakableSteps()
                        .font(.footnote)
                        .foregroundStyle(JL.ink)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(JL.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JL.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var turnOff: some View {
        Button {
            confirmOff = true
        } label: {
            HStack {
                Text("Turn off the lock")
                Spacer()
                if lock.isLocked {
                    Text("after today's run")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(lock.isLocked ? JL.ink2 : JL.redText)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(lock.isLocked)
    }

    // MARK: - Pickers

    private func chooseApps() {
        Task {
            guard await lock.authorize() else { return }
            draft = lock.selection
            picking = true
        }
    }

    private func chooseRunOnly() {
        Task {
            guard await lock.authorize() else { return }
            runOnlyDraft = lock.runOnlySelection
            pickingRunOnly = true
        }
    }
}
