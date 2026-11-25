//
//  LiveRunView.swift
//  JogLockTracker
//
//  A run in progress, full screen: the track standing up with what's left
//  to unlock, the 5K plan's runs and walks, tips for the treadmill, "Nice
//  try" when distance doesn't count, the map, the voice coach, and hold to
//  finish so a bump in a pocket can't end the run.
//

import FamilyControls
import JogLockCore
import SwiftUI

struct LiveRunView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingMap = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = tracker.startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            VStack(spacing: 14) {
                topRow(elapsed: elapsed)
                notices
                track(elapsed: elapsed)
                    .frame(minHeight: 300, maxHeight: 470)
                belowTrack(elapsed: elapsed)
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(JL.paper.ignoresSafeArea())
        .sheet(isPresented: $showingMap) {
            mapSheet
        }
        .sheet(isPresented: niceTryShown) {
            if let event = tracker.niceTry {
                NiceTrySheet(event: event, countedMeters: tracker.gateTotals.countedMeters,
                             remainingMeters: remainingMeters, unlocks: lockCounts ? settings.nemesis : nil) {
                    tracker.clearNiceTry()
                }
            }
        }
    }

    // MARK: - What's shown

    /// Distance so far: counted, and still being checked against the steps.
    private var liveMeters: Double {
        tracker.gateTotals.countedMeters + tracker.gateTotals.pendingMeters
    }

    private var remainingMeters: Double {
        max(0, tracker.runTargetKm * 1_000 - liveMeters)
    }

    /// This run unlocks the apps: the lock is on and they're locked.
    private var lockCounts: Bool {
        lock.isEnabled && lock.hasChosenApps && !lock.ledger.isRestDay
    }

    /// Today's week on the 5K plan, when it has runs and walks.
    private var fiveKWeek: FiveKWeek? {
        lock.fiveKWeekToday
    }

    /// The 5K plan's phase now, unless it's past the warm-up of a week run
    /// the whole way.
    private func intervalPhase(_ elapsed: TimeInterval) -> (week: FiveKWeek, index: Int, span: FiveKWeek.Span)? {
        guard let week = fiveKWeek, tracker.status != .waitingForGPS, tracker.status != .requestingPermission else {
            return nil
        }
        let index = week.spanIndex(at: elapsed)
        let span = week.span(index)
        return span.phase == .runAllTheWay ? nil : (week, index, span)
    }

    private var niceTryShown: Binding<Bool> {
        Binding(get: { tracker.niceTry != nil }, set: { if !$0 { tracker.clearNiceTry() } })
    }

    // MARK: - Top

    private func topRow(elapsed: TimeInterval) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .background(Circle().fill(statusColor.opacity(0.18)).frame(width: 17, height: 17))
                Text(statusText)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(JL.sand, in: Capsule())
            Spacer(minLength: 12)
            Text(Format.duration(elapsed))
                .font(.jlHeading(20))
                .monospacedDigit()
        }
        .foregroundStyle(JL.ink)
    }

    private var statusText: String {
        switch tracker.status {
        case .idle:
            return "Saving…"
        case .requestingPermission:
            return "Waiting for permission…"
        case .waitingForGPS:
            let need = Int(EngineSettings.standard.warmupAccuracy)
            if let accuracy = tracker.lastAccuracy {
                return "Getting GPS · ±\(Int(accuracy.rounded())) m, needs ±\(need)"
            }
            return "Getting GPS…"
        case .paused:
            return "Paused · standing still"
        case .tracking:
            if let week = fiveKWeek {
                return "5K plan · week \(week.number)"
            }
            if tracker.runMode == .treadmill {
                return "Treadmill · counting steps"
            }
            return tracker.lastAccuracy.map { "Outdoor · GPS ±\(Int($0.rounded())) m" } ?? "Outdoor"
        }
    }

    private var statusColor: Color {
        switch tracker.status {
        case .tracking: JL.red
        case .paused, .idle: Color(hex: 0x9A9284)
        case .requestingPermission, .waitingForGPS: .orange
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let warning = tracker.warning {
            Banner(text: warning, systemImage: "exclamationmark.triangle.fill", tint: .orange) {
                tracker.clearWarning()
            }
        }
        if let diagnostic = tracker.diagnostic {
            Banner(text: diagnostic, systemImage: "location.slash.fill", tint: JL.red, onClose: nil)
        }
    }

    // MARK: - The track

    @ViewBuilder
    private func track(elapsed: TimeInterval) -> some View {
        let target = tracker.runTargetKm * 1_000
        let progress = target > 0 ? liveMeters / target : 0
        if let interval = intervalPhase(elapsed) {
            TrackView(progress: progress, style: .intervals) {
                intervalCenter(interval, elapsed: elapsed)
            }
        } else {
            TrackView(progress: progress, style: tracker.countedTargetReached ? .done : .track) {
                distanceCenter
            }
            .overlay(alignment: .top) {
                if lockCounts && !tracker.countedTargetReached {
                    finishPill
                        .offset(y: -6)
                }
            }
        }
    }

    /// "TikTok +4 at the finish", on the start line.
    private var finishPill: some View {
        HStack(spacing: 6) {
            if lock.hasPickedApps {
                AppTiles(selection: lock.selection, size: 22, border: JL.ink, limit: 1)
            }
            HStack(spacing: 0) {
                AppNames(selection: lock.selection, websites: lock.websites, shown: 1)
                Text(" at the finish")
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(JL.paper)
        .padding(.leading, lock.hasPickedApps ? 4 : 12)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(JL.ink, in: Capsule())
    }

    @ViewBuilder
    private var distanceCenter: some View {
        let unlocked = tracker.countedTargetReached
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(unlocked ? "Unlocked" : lockCounts ? "To unlock" : "To go")
                    .font(.footnote.weight(.heavy))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(unlocked ? JL.redOnInk : JL.ink)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.km((unlocked ? liveMeters : remainingMeters) / 1_000))
                        .jlNumber(100)
                    Text("KM")
                        .font(.jlHeading(24))
                }
            }
            stats(unlocked: unlocked)
        }
        .foregroundStyle(unlocked ? JL.paper : JL.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private func stats(unlocked: Bool) -> some View {
        let first = unlocked
            ? stat("+" + Format.km(max(0, liveMeters - tracker.runTargetKm * 1_000) / 1_000), "km extra")
            : stat(Format.km(liveMeters / 1_000), "km run")
        if tracker.runMode == .treadmill {
            Grid(horizontalSpacing: 0) {
                GridRow {
                    stat(tracker.lastCadence.map { "\(Int(($0 * 60).rounded()))" } ?? "--", "steps/min")
                    first
                }
            }
            .frame(width: 210)
        } else {
            Grid(horizontalSpacing: 0, verticalSpacing: 14) {
                GridRow {
                    first
                    stat(paceText, "pace /km")
                }
                GridRow {
                    stat(tracker.gateTotals.steps.formatted(), "steps")
                    stat(tracker.lastKmSeconds.map(Format.duration) ?? "--", "last km")
                }
            }
            .frame(width: 210)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.jlHeading(24))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var paceText: String {
        let snapshot = tracker.snapshot
        guard snapshot.cleanMeters >= 50, snapshot.movingSeconds > 0 else { return "--" }
        return Format.duration(snapshot.movingSeconds / (snapshot.cleanMeters / 1_000))
    }

    private func intervalCenter(_ interval: (week: FiveKWeek, index: Int, span: FiveKWeek.Span),
                                elapsed: TimeInterval) -> some View {
        let span = interval.span
        let left = max(0, span.start + (span.length ?? 0) - elapsed)
        let next = interval.week.span(interval.index + 1)
        return VStack(spacing: 14) {
            Text(Self.title(span.phase))
                .font(.jlHeading(17))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .foregroundStyle(span.phase == .run ? JL.card : JL.ink)
                .background(span.phase == .run ? JL.red : JL.paper, in: Capsule())
            VStack(spacing: 2) {
                Text(Format.duration(left))
                    .jlNumber(104)
                Text(span.phase == .run ? "left in this run" : span.phase == .walk ? "left in this walk" : "left to warm up")
                    .font(.subheadline)
                    .opacity(0.75)
            }
            Text(Self.then(next))
                .font(.subheadline.weight(.semibold))
            Text(lockCounts
                 ? "\(Format.km(liveMeters / 1_000)) km · \(Format.km(remainingMeters / 1_000)) km to unlock"
                 : "\(Format.km(liveMeters / 1_000)) km run")
                .font(.footnote)
                .monospacedDigit()
                .opacity(0.75)
        }
        .foregroundStyle(JL.paper)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private static func title(_ phase: FiveKWeek.Phase) -> String {
        switch phase {
        case .warmUp: "WARM UP"
        case .run, .runAllTheWay: "RUN"
        case .walk: "WALK"
        }
    }

    private static func then(_ next: FiveKWeek.Span) -> String {
        guard let length = next.length else { return "Then run the rest of the way" }
        return "Then \(next.phase == .walk ? "walk" : "run") for \(Format.duration(length))"
    }

    // MARK: - Below the track

    @ViewBuilder
    private func belowTrack(elapsed: TimeInterval) -> some View {
        if let interval = intervalPhase(elapsed) {
            intervalStrip(interval, elapsed: elapsed)
        } else if tracker.runMode == .treadmill {
            treadmillCard
        } else {
            countedLine
        }
        if lock.hasRunOnly {
            HStack(spacing: 8) {
                AppTiles(selection: lock.runOnlySelection, size: 22, border: JL.paper)
                Text(lock.runOnlyOpen ? "Open while you run" : "Opening for your run…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JL.ink2)
            }
        }
    }

    private var countedLine: some View {
        let totals = tracker.gateTotals
        let thrownOut = totals.noStepsMeters + totals.vehicleMeters
        let text: String
        let symbol: String
        if tracker.status == .waitingForGPS || tracker.status == .requestingPermission {
            text = "Distance counts once the GPS is ready"
            symbol = "location"
        } else if thrownOut >= 10 {
            text = "\(Format.km(thrownOut / 1_000)) km didn't count · \(Format.km(totals.countedMeters / 1_000)) km on foot"
            symbol = "exclamationmark.triangle"
        } else {
            text = "All \(Format.km(liveMeters / 1_000)) km counted on foot · pauses when you stop"
            symbol = "checkmark"
        }
        return Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(JL.ink2)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    private var treadmillCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
            Text("**Keep the phone on you.** In a pocket or an armband. On the console it can't count your steps. \(strideText)")
                .font(.subheadline)
                .foregroundStyle(JL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var strideText: String {
        guard let model = tracker.strideModel else {
            return "Until you've done an outdoor run with Jog Lock, distance comes from the iPhone's own step count."
        }
        let typical = (model.minCadence + model.maxCadence) / 2
        return "Distance uses your stride from GPS runs: \(String(format: "%.2f", model.stepLength(cadence: typical))) m a step."
    }

    private func intervalStrip(_ interval: (week: FiveKWeek, index: Int, span: FiveKWeek.Span),
                               elapsed: TimeInterval) -> some View {
        let first = max(0, interval.index - 2)
        let spans = (first...(interval.index + 3)).map(interval.week.span)
        let span = interval.span
        let through = span.length.map { min(1, max(0, (elapsed - span.start) / $0)) } ?? 0
        return VStack(spacing: 8) {
            HStack {
                Text(span.phase == .warmUp ? "Warm-up walk" : "\(span.phase == .walk ? "Walk" : "Run") \(span.number)")
                    .fontWeight(.bold)
                Spacer()
                Text(interval.week.intervalsText)
                    .foregroundStyle(JL.ink2)
            }
            .font(.footnote)
            .foregroundStyle(JL.ink)
            PhaseStrip(spans: spans, current: interval.index - first, through: through)
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                settings.voiceOn.toggle()
            } label: {
                Image(systemName: settings.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .buttonStyle(JLRoundButtonStyle(size: 58))
            HoldToFinishButton {
                tracker.stop()
            }
            if tracker.runMode == .outdoor {
                Button {
                    showingMap = true
                } label: {
                    Image(systemName: "map")
                }
                .buttonStyle(JLRoundButtonStyle(size: 58))
            }
        }
    }

    private var mapSheet: some View {
        NavigationStack {
            RouteMap(segments: tracker.route, followsUser: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Your route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingMap = false }
                    }
                }
        }
    }
}

/// The ink "HOLD TO FINISH" pill. It fills with red while it's held and
/// finishes the run when full, so a bump in a pocket can't end it.
struct HoldToFinishButton: View {
    var seconds = 1.2
    let action: () -> Void
    @State private var filled = false

    var body: some View {
        Label("Hold to finish", systemImage: "stop.fill")
            .font(.jlHeading(18, relativeTo: .headline))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(JL.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    JL.red
                        .frame(width: filled ? proxy.size.width : 0)
                }
            }
            .background(JL.ink)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: seconds, maximumDistance: 40) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: seconds) : .easeOut(duration: 0.2)) {
                    filled = pressing
                }
            }
    }
}

/// The 5K plan's phases round now: up to two done, the one under way
/// filling up, and three to come. Each as wide as it is long.
struct PhaseStrip: View {
    let spans: [FiveKWeek.Span]
    /// Which of `spans` is under way.
    let current: Int
    /// How far through it, 0 to 1.
    let through: Double

    var body: some View {
        GeometryReader { proxy in
            let lengths = spans.map { $0.length ?? 600 }
            let total = max(1, lengths.reduce(0, +))
            let free = proxy.size.width - CGFloat(max(0, spans.count - 1)) * 3
            HStack(spacing: 3) {
                ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                    segment(index, span)
                        .frame(width: max(4, free * CGFloat(lengths[index] / total)))
                }
            }
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private func segment(_ index: Int, _ span: FiveKWeek.Span) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if index < current {
            shape.fill(span.phase == .run ? JL.ink : JL.line)
        } else if index == current {
            shape.fill(Color(hex: 0xE7D2C9))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        JL.red.frame(width: proxy.size.width * through)
                    }
                }
                .clipShape(shape)
        } else {
            shape.fill(JL.sand)
        }
    }
}

/// "NICE TRY." Distance that went by at car speed, or without the steps to
/// match, doesn't count. A sheet over the run, with a card to share.
struct NiceTrySheet: View {
    let event: NiceTryEvent
    let countedMeters: Double
    let remainingMeters: Double
    /// The app the runner is running for, when the run unlocks something.
    let unlocks: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nice try.")
                    .font(.jlDisplay(64))
                    .tracking(-2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(JL.redText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(message)
                    .font(.body)
                    .foregroundStyle(JL.ink)
            }
            VStack(spacing: 10) {
                GeometryReader { proxy in
                    let parts = [countedMeters, event.meters, remainingMeters].map { max(0, $0) }
                    let total = max(1, parts.reduce(0, +))
                    let free = proxy.size.width - 6
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4).fill(JL.ink)
                            .frame(width: free * parts[0] / total)
                        Hatching()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(width: free * parts[1] / total)
                        RoundedRectangle(cornerRadius: 4).fill(JL.line)
                            .frame(width: free * parts[2] / total)
                    }
                }
                .frame(height: 12)
                HStack {
                    Text("**\(Format.km(countedMeters / 1_000)) km** counted")
                    Spacer()
                    Text("**\(Format.km(event.meters / 1_000)) km** \(event.kind == .vehicle ? "by car" : "without steps")")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(JL.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(JL.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(unlocks.map { "Keep going on foot and it all counts again. Still \(Format.km(remainingMeters / 1_000)) km to unlock \($0)." }
                 ?? "Keep going on foot and it all counts again.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            HStack(spacing: 10) {
                if let image = ShareCards.niceTryImage(kind: event.kind, meters: event.meters) {
                    ShareLink(item: image, preview: SharePreview("Nice try", image: image)) {
                        Text("Share it")
                            .font(.body.weight(.bold))
                    }
                    .buttonStyle(.jlOutline)
                }
                Button("Back to running", action: onClose)
                    .buttonStyle(.jlInk)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .presentationDetents([.medium, .large])
        .presentationBackground(JL.card)
    }

    private var message: LocalizedStringKey {
        let km = Format.km(event.meters / 1_000)
        switch event.kind {
        case .vehicle:
            return "That last **\(km) km** went by at car speed, with almost no steps. It doesn't count."
        case .noSteps:
            return "That last **\(km) km** of GPS came without the steps to match. It doesn't count."
        }
    }
}

/// Red stripes on pink: distance that didn't count.
private struct Hatching: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF0D5CC)))
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 10
            }
            context.stroke(stripes, with: .color(JL.red), lineWidth: 5)
        }
    }
}

/// A short message at the top of a screen: a GPS problem, a resumed run.
struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    let onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(JL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JL.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    LiveRunView()
        .environmentObject(RunTracker.shared)
        .environmentObject(AppLock.shared)
}
