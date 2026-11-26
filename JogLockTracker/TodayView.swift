//
//  TodayView.swift
//  JogLockTracker
//
//  Today: the track with today's running on it, what's waiting at the
//  finish, the week, and the button to start. Five looks: locked,
//  unlocked, rest day, lock paused (Screen Time access off), and no lock
//  yet.
//

import FamilyControls
import JogLockCore
import SwiftUI

struct TodayView: View {
    /// Opens the Lock tab.
    var openLock: () -> Void = {}

    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var buddies = LockBuddies.shared
    @State private var runs: [RunSummary] = []
    @State private var editingPlan = false
    @State private var showingBuddies = false
    @State private var borrowing = false

    private enum Look {
        case locked, unlocked, rest, accessOff, noLock
    }

    var body: some View {
        let week = self.week
        let today = week.days.first(where: \.isToday)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    banners
                    switch look {
                    case .locked:
                        lockedDay(week, ran: today?.meters ?? 0, target: today?.target ?? 0)
                    case .unlocked:
                        unlockedDay
                    case .rest:
                        restDay(week)
                    case .accessOff:
                        pausedDay(ran: today?.meters ?? 0, target: today?.target ?? 0)
                    case .noLock:
                        noLockDay(week, today: today)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .jlScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $editingPlan) {
                PlanView(targetKm: $tracker.targetKm)
                    .environmentObject(lock)
                    .environmentObject(tracker)
            }
            .sheet(isPresented: $showingBuddies) {
                BuddiesView()
                    .environmentObject(lock)
            }
            .sheet(isPresented: $borrowing) {
                BorrowSheet()
                    .environmentObject(lock)
                    .environmentObject(tracker)
            }
            .task(id: tracker.lastFinishedRun?.id) {
                runs = RunStore.onDevice.allSummaries()
            }
        }
    }

    private var look: Look {
        guard lock.isEnabled && lock.hasChosenApps else { return .noLock }
        if lock.accessOff {
            return .accessOff
        }
        if lock.ledger.isRestDay {
            return .rest
        }
        return lock.ledger.isTargetMet ? .unlocked : .locked
    }

    /// The week from the saved runs. With the lock on, today's figures are
    /// the lock's: they include distance owed and a run that began before
    /// the day started.
    private var week: TodayWeek {
        let ledger = lock.ledger
        let current = lock.isEnabled && ledger.day == lock.today
        return TodayWeek(runs: runs.map { MonthWrap.Run($0) }, today: lock.today, plan: lock.plan,
                         dailyMeters: lock.rules.dailyMeters, startHour: lock.rules.dayStartHour,
                         todayMeters: current ? ledger.ranMeters : nil,
                         todayTarget: current ? ledger.targetMeters : nil)
    }

    /// Today's latest finished run.
    private var lastRunToday: RunSummary? {
        runs.filter { lock.rules.day(of: $0.startedAt) == lock.today }.max { $0.startedAt < $1.startedAt }
    }

    // MARK: - The five looks

    @ViewBuilder
    private func lockedDay(_ week: TodayWeek, ran: Double, target: Double) -> some View {
        let ledger = lock.ledger
        toGo(ran: ran, target: target, label: "To unlock")
        appsCard("wait at the finish", chevron: true)
        weekBars(week)
        startRow
        chips(ledger)
        if ledger.owedMeters > 0 {
            Text("Today's \(Format.shortDistance(ledger.targetMeters)) includes \(Format.shortDistance(ledger.owedMeters)) you borrowed.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        buddyRow(unlocked: false)
        if let run = lastRunToday {
            TodayRunCard(run: run)
        }
    }

    @ViewBuilder
    private var unlockedDay: some View {
        let ledger = lock.ledger
        TrackView(progress: 1, style: .done) {
            VStack(spacing: 6) {
                Image(systemName: "lock.open.fill")
                    .font(.title2.weight(.bold))
                Text("Unlocked")
                    .font(.jlDisplay(44))
                    .tracking(-1.7)
                    .textCase(.uppercase)
                Text("\(Format.tenths(ledger.ranMeters)) km run · open until \(dayEnd(after: ledger.unlockedAt))")
                    .font(.footnote)
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .foregroundStyle(JL.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(height: 230)
        appsCard("are yours. You ran for them.", chevron: false)
        if let run = lastRunToday {
            TodayRunCard(run: run)
        }
        VStack(spacing: 8) {
            runButton("Run more")
            Text("Every km past \(Format.shortDistance(ledger.targetMeters)) banks \(Int(lock.rules.minutesPerExtraKm)) minutes for a locked day.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
                .multilineTextAlignment(.center)
        }
        buddyRow(unlocked: true)
    }

    @ViewBuilder
    private func restDay(_ week: TodayWeek) -> some View {
        TrackView(progress: 0, style: .rest, showsRunner: false) {
            VStack(spacing: 6) {
                Text("Rest day")
                    .font(.jlDisplay(44))
                    .tracking(-1.7)
                    .textCase(.uppercase)
                Text("Your apps are open all day.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(height: 230)
        appsCard(lockAgainText(week), chevron: false)
        weekBars(week)
        HStack(spacing: 12) {
            Text("\(week.runs)")
                .jlNumber(30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(week.runs == 1 ? "run" : "runs") this week, \(Format.tenths(week.meters)) km.")
                    .fontWeight(.bold)
                Text(nextRunText(week))
                    .foregroundStyle(JL.ink2)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(JL.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        VStack(spacing: 8) {
            runButton("Run anyway")
            Text("Nothing's locked today. A run still goes in your history.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
                .multilineTextAlignment(.center)
        }
        buddyRow(unlocked: true)
    }

    @ViewBuilder
    private func pausedDay(ran: Double, target: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(JL.redOnInk)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Time access is off")
                        .font(.headline)
                    Text("iOS can't lock your apps until it's back on. Your runs still count.")
                        .font(.subheadline)
                        .opacity(0.78)
                }
            }
            Button("Turn it back on") {
                Task {
                    if await lock.authorize() {
                        lock.refresh(after: "access back")
                    }
                }
            }
            .buttonStyle(JLSmallButtonStyle(fill: JL.red, text: JL.card))
            .padding(.leading, 36)
        }
        .foregroundStyle(JL.paper)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JL.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        TrackView(progress: target > 0 ? ran / target : 0, style: .paused) {
            VStack(spacing: 6) {
                Text("Lock paused")
                    .font(.jlDisplay(38))
                    .tracking(-1.5)
                    .textCase(.uppercase)
                Text("\(Format.tenths(ran)) of \(Format.tenths(target)) km run today")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(height: 230)
        startRow
        Text("This happens if Jog Lock's access is turned off in Settings → Screen Time. Ask someone you trust to lock it with a Screen Time passcode so it can't happen in a weak moment.")
            .font(.footnote)
            .foregroundStyle(JL.ink2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func noLockDay(_ week: TodayWeek, today: WeekDayProgress?) -> some View {
        if today?.isRest == true {
            TrackView(progress: 0, style: .rest, showsRunner: false) {
                Text("Rest day")
                    .font(.jlDisplay(44))
                    .tracking(-1.7)
                    .textCase(.uppercase)
                    .foregroundStyle(JL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(height: 230)
        } else {
            toGo(ran: today?.meters ?? 0, target: today?.target ?? 0, label: "To run today")
        }
        Button(action: openLock) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(JL.card)
                    .frame(width: 34, height: 34)
                    .background(JL.red, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lock your apps")
                        .font(.subheadline.weight(.bold))
                    Text("Pick the apps that wait until you've run.")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        weekBars(week)
        startRow
        if let run = lastRunToday {
            TodayRunCard(run: run)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .jlCaption()
                Text("Today")
                    .font(.jlHeading(34, relativeTo: .largeTitle))
                    .tracking(-0.7)
                    .foregroundStyle(JL.ink)
            }
            Spacer(minLength: 12)
            Button {
                editingPlan = true
            } label: {
                Label(planText, systemImage: "calendar")
            }
            .buttonStyle(.jlSmall)
        }
        .padding(.top, 12)
    }

    private var planText: String {
        PlanText.summary(lock.plan, dailyMeters: lock.rules.dailyMeters, today: lock.today)
    }

    @ViewBuilder
    private var banners: some View {
        if let warning = tracker.warning {
            Banner(text: warning, systemImage: "exclamationmark.triangle.fill", tint: .orange) {
                tracker.clearWarning()
            }
        }
        if let diagnostic = tracker.diagnostic {
            Banner(text: diagnostic, systemImage: "location.slash.fill", tint: .red, onClose: nil)
        }
        if let niceTry = tracker.niceTry {
            NiceTryBanner(kind: niceTry.kind, meters: niceTry.meters) {
                tracker.clearNiceTry()
            }
        }
    }

    /// The track with the distance still to run in the middle.
    private func toGo(ran: Double, target: Double, label: String) -> some View {
        let big = Format.bigDistance(target - ran)
        return TrackView(progress: target > 0 ? ran / target : 0) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(big.value)
                        .jlNumber(76)
                    Text(big.unit)
                        .font(.jlHeading(22))
                        .textCase(.uppercase)
                }
                Text(label)
                    .font(.footnote.weight(.heavy))
                    .tracking(1.3)
                    .textCase(.uppercase)
                Text("\(Format.tenths(ran)) of \(Format.tenths(target)) km run today")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(height: 230)
    }

    /// The chosen apps, and what's become of them today.
    private func appsCard(_ text: String, chevron showsChevron: Bool) -> some View {
        Button(action: openLock) {
            HStack(spacing: 10) {
                if lock.hasPickedApps {
                    AppTiles(selection: lock.selection)
                } else {
                    Image(systemName: "globe")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(JL.ink)
                        .frame(width: 28, height: 28)
                        .background(JL.sand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    AppNames(selection: lock.selection, websites: lock.websites)
                        .font(.subheadline.weight(.bold))
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    chevron
                }
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(hex: 0x9A9284))
    }

    private func weekBars(_ week: TodayWeek) -> some View {
        WeekBars(days: week.days.map { day in
            WeekBarDay(weekday: day.day.weekday, fraction: day.fraction, isToday: day.isToday,
                       isRest: day.isRest, isFuture: day.isFuture)
        })
    }

    /// Outdoor or treadmill, and Start.
    @ViewBuilder
    private var startRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Where", selection: $tracker.mode) {
                    Label("Outdoor", systemImage: "location.fill").tag(RunMode.outdoor)
                    Label("Treadmill", systemImage: "figure.run.treadmill").tag(RunMode.treadmill)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(tracker.mode == .treadmill ? "Treadmill" : "Outdoor")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
            }
            .menuStyle(.button)
            .buttonStyle(.jlOutline)
            .fixedSize(horizontal: true, vertical: false)
            Button {
                tracker.start()
            } label: {
                Label("Start run", systemImage: "play.fill")
            }
            .buttonStyle(.jlPrimary)
        }
        if tracker.mode == .treadmill {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep the phone on you")
                    .font(.subheadline.weight(.bold))
                Text("In a pocket or an armband. On the treadmill's console it can't count your steps. \(strideText)")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .jlSandCard(padding: 14)
        }
    }

    private var strideText: String {
        guard let model = tracker.strideModel else {
            return "Distance comes from the iPhone's own step estimate until you've done an outdoor run with Jog Lock. Then it uses your own stride."
        }
        let typical = (model.minCadence + model.maxCadence) / 2
        let length = model.stepLength(cadence: typical)
        return "Your stride, learned on GPS runs: \(String(format: "%.2f", length)) m a step at \(Int((typical * 60).rounded())) steps a minute."
    }

    /// "Run more" and "Run anyway": a run on a day with nothing locked.
    private func runButton(_ title: String) -> some View {
        Button {
            tracker.start()
        } label: {
            Label(title, systemImage: "play.fill")
                .font(.body.weight(.bold))
        }
        .buttonStyle(.jlOutlineWide)
    }

    /// Banked minutes and borrowing from tomorrow.
    private func chips(_ ledger: LockLedger) -> some View {
        let problem = ledger.borrowProblem(rules: lock.rules)
        return HStack(spacing: 10) {
            Button {
                borrowing = true
            } label: {
                if ledger.spending {
                    chip(ledger.isOpen ? "Open · \(ledger.spendableMinutes) min left" : "Opening…", "Tap to lock again")
                } else {
                    chip("\(ledger.spendableMinutes) min banked", "from extra km")
                }
            }
            Button {
                borrowing = true
            } label: {
                chip("Borrow \(Int(lock.rules.borrowMinutes)) min",
                     problem.map(Self.whyNoBorrowing) ?? "+\(Format.shortDistance(lock.rules.borrowMeters)) tomorrow")
            }
        }
        .buttonStyle(.jlChip)
    }

    private func chip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(JL.ink2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private static func whyNoBorrowing(_ problem: LockError) -> String {
        switch problem {
        case .alreadyBorrowedToday: "Borrowed today"
        case .stillHaveMinutes: "Use banked first"
        case .owedLimit: "Run off what you owe"
        case .alreadyUnlocked, .noMinutes: "Not now"
        }
    }

    /// A lock buddy's running today. Opens the buddy screen.
    @ViewBuilder
    private func buddyRow(unlocked: Bool) -> some View {
        if buddies.membership != nil {
            let buddy = buddies.buddy
            let today = buddy.flatMap { $0.day == lock.today ? $0 : nil }
            Button {
                showingBuddies = true
            } label: {
                HStack(spacing: 12) {
                    BuddyAvatar(name: buddy?.name ?? "")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(buddyText(buddy, today: today, unlocked: unlocked))
                            .font(.subheadline)
                            .foregroundStyle(JL.ink)
                        if let today, !today.met, today.target > 0 {
                            ProgressView(value: min(1, today.meters / today.target))
                                .tint(JL.ink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 56)
                .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func buddyText(_ buddy: BuddyDay?, today: BuddyDay?, unlocked: Bool) -> AttributedString {
        guard let buddy else { return AttributedString("Waiting for your lock buddy to join.") }
        var name = AttributedString(buddy.name)
        name.font = Font.subheadline.weight(.bold)
        let rest: String
        if let today {
            if today.met && today.target <= 0 {
                rest = " has a rest day."
            } else if today.met {
                rest = unlocked ? " ran \(Format.shortDistance(today.meters)) too. You're both done."
                    : " ran \(Format.shortDistance(today.meters)). Done for today."
            } else {
                rest = " ran \(Format.shortDistance(today.meters)) of \(Format.shortDistance(today.target))"
            }
        } else {
            rest = " hasn't run yet today."
        }
        var text = AttributedString(rest)
        text.foregroundColor = JL.ink2
        return name + text
    }

    /// When the apps lock again after a rest day.
    private func lockAgainText(_ week: TodayWeek) -> String {
        guard let next = week.next, next.meters > 0 else { return "open. Nothing to run for a while." }
        if next.day == lock.today.adding(days: 1) {
            return "open. They lock again tomorrow."
        }
        return "open. They lock again on \(weekdayName(next.day))."
    }

    private func nextRunText(_ week: TodayWeek) -> String {
        guard let next = week.next else { return "" }
        if next.meters <= 0 {
            return "The rest of this week is covered."
        }
        return "Next run \(weekdayName(next.day)): \(Format.shortDistance(next.meters)) to unlock."
    }

    private func weekdayName(_ day: LockDay) -> String {
        Calendar.current.weekdaySymbols[(day.weekday - 1 + 7) % 7]
    }

    /// "4:00", or "midnight" when days start at midnight.
    private func dayEnd(after unlockedAt: Date?) -> String {
        let end = lock.rules.dayEnd(after: unlockedAt ?? Date())
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        if parts.hour == 0 && parts.minute == 0 {
            return "midnight"
        }
        return end.formatted(date: .omitted, time: .shortened)
    }
}

/// Today's latest run: when, how far, how fast. Opens the run.
struct TodayRunCard: View {
    let run: RunSummary
    @State private var segments: [[Coordinate]] = []

    var body: some View {
        NavigationLink {
            RunDetailView(run: run)
        } label: {
            HStack(spacing: 12) {
                RouteThumbnail(segments: segments, isTreadmill: run.mode == .treadmill)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Format.partOfDay(hour: Calendar.current.component(.hour, from: run.startedAt))) · \(run.startedAt.formatted(date: .omitted, time: .shortened))")
                        .jlLabel()
                        .foregroundStyle(JL.ink2)
                    Text("\(Format.tenths(meters)) km")
                        .font(.jlHeading(20))
                        .monospacedDigit()
                    Text(detail)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(JL.ink2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x9A9284))
            }
            .foregroundStyle(JL.ink)
            .padding(10)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: run.id) {
            guard run.mode != .treadmill else { return }
            let id = run.id
            segments = await Task.detached {
                Route.segments(from: RunStore.onDevice.readLines(id: id))
            }.value
        }
    }

    private var meters: Double {
        run.countedMeters ?? run.cleanMeters
    }

    /// "19:24 · 6:04 /km · counted on foot"
    private var detail: String {
        let elapsed = run.endedAt.timeIntervalSince(run.startedAt)
        var parts = [Format.duration(elapsed)]
        if meters >= 50 {
            let seconds = run.movingSeconds > 0 ? run.movingSeconds : elapsed
            parts.append("\(Format.duration(seconds / (meters / 1_000))) /km")
        }
        parts.append(run.mode == .treadmill ? "treadmill" : "counted on foot")
        return parts.joined(separator: " · ")
    }
}

#Preview {
    TodayView()
        .environmentObject(RunTracker.shared)
        .environmentObject(AppLock.shared)
}
