//
//  RunListView.swift
//  JogLockTracker
//
//  The Runs tab: this week, month or year added up with a bar for each
//  day, last month wrapped, and every run under This week, Last week and
//  the months before. A run opens with its route, splits, how it was
//  counted, the distance other apps gave, and its files.
//

import JogLockCore
import SwiftUI

struct RunListView: View {
    @EnvironmentObject private var lock: AppLock
    @State private var runs: [RunSummary] = []
    @State private var period: RunPeriod = .month
    @State private var wrapping: WrapMonth?

    var body: some View {
        let now = Date()
        let totals = PeriodTotals(runs: runs.map { MonthWrap.Run($0) }, period: period, now: now,
                                  firstWeekday: lock.plan.firstWeekday)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Runs")
                        .font(.jlHeading(34, relativeTo: .largeTitle))
                        .tracking(-0.7)
                    Spacer()
                    NavigationLink {
                        AllRunsMapView()
                    } label: {
                        Image(systemName: "map")
                    }
                    .buttonStyle(.jlRound)
                }
                .padding(.top, 12)
                periodPicker
                summary(totals)
                Bars(values: totals.bars, current: totals.current)
                    .frame(height: 150)
                if let banner = lastMonth(now: now) {
                    banner
                }
                if runs.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "figure.run",
                                           description: Text("Finished runs show up here."))
                        .padding(.top, 20)
                }
                ForEach(RunSection.group(runs.map(\.startedAt), now: now, firstWeekday: lock.plan.firstWeekday),
                        id: \.title) { section in
                    SectionLabel(section.title)
                        .padding(.top, 4)
                    JLList {
                        ForEach(Array(section.indices.enumerated()), id: \.element) { position, index in
                            NavigationLink {
                                RunDetailView(run: runs[index])
                            } label: {
                                RunListRow(run: runs[index], unlocks: lock.isEnabled,
                                           isLast: position == section.indices.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .jlScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $wrapping) { wrap in
            WrappedView(month: wrap.month, runs: runs)
        }
        .onAppear { runs = RunStore.onDevice.allSummaries() }
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(RunPeriod.allCases, id: \.self) { option in
                Button {
                    period = option
                } label: {
                    Text(option.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(period == option ? JL.card : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(JL.sand, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func summary(_ totals: PeriodTotals) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.tenths(totals.meters))
                    .jlNumber(76)
                Text("KM")
                    .font(.jlHeading(22))
            }
            Text(Self.line(totals))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(JL.ink2)
        }
    }

    /// "in November · 14 runs · 4:21:08 · 6:08 /km"
    private static func line(_ totals: PeriodTotals) -> String {
        var parts = [totals.title, "\(totals.runs) \(totals.runs == 1 ? "run" : "runs")"]
        if totals.seconds > 0 {
            parts.append(Format.duration(totals.seconds))
        }
        if let pace = totals.pace {
            parts.append("\(Format.duration(pace)) /km")
        }
        return parts.joined(separator: " · ")
    }

    /// "October, wrapped": last month's runs as a story, once there are some.
    private func lastMonth(now: Date) -> AnyView? {
        guard let month = Calendar.current.date(byAdding: .month, value: -1, to: now) else { return nil }
        let wrap = MonthWrap(runs: runs.map { MonthWrap.Run($0) }, month: month)
        guard wrap.runs > 0 else { return nil }
        let unlocks = runs.filter { run in
            run.countedTargetAt != nil && Calendar.current.isDate(run.startedAt, equalTo: month, toGranularity: .month)
        }.count
        let name = wrap.title.components(separatedBy: " ").first ?? wrap.title
        return AnyView(
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name), wrapped")
                        .font(.jlHeading(20))
                    Text("\(Format.tenths(wrap.meters)) km and \(unlocks > 0 ? "\(unlocks) unlocks" : "\(wrap.runs) runs")")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                Spacer()
                Button("Watch") {
                    wrapping = WrapMonth(month: month)
                }
                .buttonStyle(JLSmallButtonStyle(fill: JL.card, text: JL.ink))
            }
            .foregroundStyle(JL.card)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(JL.red, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
    }
}

/// The month a wrap is for, to open it as a sheet.
struct WrapMonth: Identifiable {
    let month: Date
    var id: Date { month }
}

/// A bar for each day (or month), standing on a line, the current one red.
struct Bars: View {
    let values: [Double]
    let current: Int

    var body: some View {
        GeometryReader { proxy in
            let highest = max(values.max() ?? 0, 1)
            let gap: CGFloat = values.count > 20 ? 3 : 8
            let width = max(2, (proxy.size.width - gap * CGFloat(values.count - 1)) / CGFloat(max(values.count, 1)))
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index == current ? JL.red : JL.ink)
                            .frame(width: width, height: value > 0 ? max(6, (proxy.size.height - 2) * value / highest) : 0)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle()
                    .fill(JL.ink)
                    .frame(height: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One run in the list: its route, name, day, distance and time, and a
/// red lock if it unlocked the apps.
struct RunListRow: View {
    let run: RunSummary
    var unlocks = true
    var isLast = false
    @State private var segments: [[Coordinate]] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                RouteThumbnail(segments: segments, isTreadmill: run.mode == .treadmill)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.jlHeading(18))
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if unlocks && run.countedTargetAt != nil {
                    Image(systemName: "lock.open")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(JL.redText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
            }
        }
        .foregroundStyle(JL.ink)
        .contentShape(Rectangle())
        .task(id: run.id) {
            segments = await RouteCache.shared.segments(for: run)
        }
    }

    private var meters: Double {
        run.countedMeters ?? run.cleanMeters
    }

    private var thrownOut: Double {
        (run.noStepsMeters ?? 0) + (run.vehicleMeters ?? 0) + (run.rejectedMeters ?? 0)
    }

    private var name: String {
        Format.runName(hour: Calendar.current.component(.hour, from: run.startedAt), mode: run.mode,
                       meters: meters, thrownOut: thrownOut)
    }

    /// "Wed 25 Nov · 3.21 km · 19:24", or for a Nice try what counted and what didn't.
    private var detail: String {
        let day = run.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if thrownOut >= MonthWrap.niceTryMeters {
            let how = (run.vehicleMeters ?? run.rejectedMeters ?? 0) >= (run.noStepsMeters ?? 0) ? "by car" : "without steps"
            return "\(day) · \(Format.km(meters / 1_000)) km counted · \(Format.km(thrownOut / 1_000)) km \(how)"
        }
        return "\(day) · \(Format.km(meters / 1_000)) km · \(Format.duration(run.endedAt.timeIntervalSince(run.startedAt)))"
    }
}

/// Routes read from the runs' logs, kept while the app is open so the list
/// doesn't read them again on every scroll.
@MainActor
final class RouteCache {
    static let shared = RouteCache()
    private var routes: [String: [[Coordinate]]] = [:]

    func segments(for run: RunSummary) async -> [[Coordinate]] {
        guard run.mode != .treadmill else { return [] }
        if let cached = routes[run.id] {
            return cached
        }
        let segments = await ShareCards.segments(for: run)
        routes[run.id] = segments
        return segments
    }
}

/// One run: the route, splits, how it was counted, the distance other apps
/// gave, the shoes it went on, and its files.
struct RunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shoes = ShoeStore.shared
    @State private var run: RunSummary
    @State private var segments: [[Coordinate]] = []
    @State private var splits: RunSplits?
    @State private var files: [URL] = []
    @State private var comparing = false
    @State private var sharing = false
    @State private var confirmDelete = false

    init(run: RunSummary) {
        _run = State(initialValue: run)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .frame(height: 360)
                panel
                    .padding(.top, -40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .background(JL.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $comparing) {
            CompareSheet(run: $run)
        }
        .sheet(isPresented: $sharing) {
            ShareRunView(run: run)
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RunStore.onDevice.delete(id: run.id)
                dismiss()
            }
        } message: {
            Text("Its route and files go too. What it unlocked stays unlocked.")
        }
        .task(id: run.id) {
            segments = await RouteCache.shared.segments(for: run)
            let id = run.id
            let loaded = await Task.detached(priority: .userInitiated) {
                (RunSplits(lines: RunStore.onDevice.readLines(id: id)), RunStore.onDevice.shareableFiles(for: id))
            }.value
            splits = loaded.0
            files = loaded.1
        }
    }

    private var meters: Double {
        run.countedMeters ?? run.cleanMeters
    }

    private var seconds: TimeInterval {
        run.endedAt.timeIntervalSince(run.startedAt)
    }

    private var pace: String {
        guard meters >= 50 else { return "--" }
        return Format.duration((run.movingSeconds > 0 ? run.movingSeconds : seconds) / (meters / 1_000))
    }

    // MARK: - Map

    private var header: some View {
        ZStack(alignment: .top) {
            if run.mode == .treadmill {
                JL.infield
                TrackView(progress: 1, style: .done) {
                    Image(systemName: "figure.run.treadmill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(JL.paper)
                }
                .frame(width: 300, height: 190)
                .padding(.top, 100)
            } else {
                RouteMap(segments: segments, interactive: false)
            }
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Menu {
                    Button {
                        comparing = true
                    } label: {
                        Label("Compare and notes", systemImage: "ruler")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete run", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .buttonStyle(JLRoundButtonStyle(fill: JL.card))
            .menuStyle(.button)
            .shadow(color: JL.ink.opacity(0.15), radius: 8, y: 3)
            .padding(.horizontal, 20)
            .padding(.top, 62)
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(JL.line)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(run.startedAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(run.startedAt.formatted(date: .omitted, time: .shortened))")
                    .jlCaption()
                Text(Format.runTitle(hour: Calendar.current.component(.hour, from: run.startedAt)))
                    .font(.jlHeading(26, relativeTo: .title))
            }
            HStack(alignment: .top) {
                stat(Format.km(meters / 1_000), "km")
                stat(Format.duration(seconds), "time")
                stat(pace, "pace /km")
                stat(run.steps.map { $0.formatted() } ?? "--", "steps")
            }
            if let rejected = rejectedMeters {
                NiceTryBanner(kind: rejected.kind, meters: rejected.meters, onClose: nil)
            }
            if let splits, !splits.kilometres.isEmpty {
                splitsCard(splits)
            }
            counted
            JLList {
                Button {
                    comparing = true
                } label: {
                    JLListRow(title: "Strava said", detail: stravaText, chevron: true)
                }
                .buttonStyle(.plain)
                if let shoe = shoes.rack.shoes.first(where: { $0.runs[run.id] != nil }) {
                    NavigationLink {
                        ShoesView()
                    } label: {
                        JLListRow(title: "Shoes", detail: shoe.name, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    comparing = true
                } label: {
                    Text(run.note ?? "Notes: route, where the phone was…")
                        .font(.subheadline)
                        .foregroundStyle(run.note == nil ? JL.ink2 : JL.ink)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button("Share card") {
                    sharing = true
                }
                .buttonStyle(.jlInk)
                ReelButton(run: run)
            }
            details
            HStack(spacing: 10) {
                ShareLink(items: files) {
                    Text("Export run files")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JLSmallButtonStyle())
                .disabled(files.isEmpty)
                Button("Delete run") {
                    confirmDelete = true
                }
                .buttonStyle(JLSmallButtonStyle(fill: JL.sand, text: JL.redText))
            }
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JL.paper, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.jlHeading(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(JL.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rejectedMeters: (kind: NiceTryKind, meters: Double)? {
        let vehicle = run.vehicleMeters ?? run.rejectedMeters ?? 0
        let noSteps = run.noStepsMeters ?? 0
        if vehicle >= 100 && vehicle >= noSteps {
            return (.vehicle, vehicle)
        }
        return noSteps >= 100 ? (.noSteps, noSteps) : nil
    }

    /// Each kilometre's time, with a bar as long as it was fast.
    private func splitsCard(_ splits: RunSplits) -> some View {
        var rows: [(label: String, meters: Double, seconds: Double)] = splits.kilometres.enumerated().map {
            (label: "\($0.offset + 1)", meters: 1_000, seconds: $0.element)
        }
        if splits.restMeters >= 50 {
            rows.append((label: Format.km(splits.restMeters / 1_000), meters: splits.restMeters, seconds: splits.restSeconds))
        }
        let fastest = rows.map { $0.meters / max($0.seconds, 1) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Splits")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.label)
                        .foregroundStyle(JL.ink2)
                        .frame(width: 38, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(JL.ink)
                            .frame(width: proxy.size.width * (row.meters / max(row.seconds, 1)) / fastest)
                    }
                    .frame(height: 8)
                    Text(Format.duration(row.seconds / (row.meters / 1_000)))
                        .frame(width: 48, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
            }
            Text("From the GPS distance, stops included.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var counted: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How it was counted")
            row("Counted on foot", "\(Format.km((run.countedMeters ?? 0) / 1_000)) km", strong: true)
            if run.mode == .treadmill {
                row("Not counted (car, bike or still)", "\(Format.km((run.rejectedMeters ?? 0) / 1_000)) km")
            } else {
                if let noSteps = run.noStepsMeters, noSteps > 0 {
                    row("Not counted (too few steps)", "\(Format.km(noSteps / 1_000)) km")
                }
                if let vehicle = run.vehicleMeters, vehicle > 0 {
                    row("Not counted (car, bike)", "\(Format.km(vehicle / 1_000)) km")
                }
                row("GPS, cleaned · raw", "\(Format.km(run.cleanMeters / 1_000)) · \(Format.km(run.rawMeters / 1_000)) km")
                row("GPS fixes", "\(run.fixCount.formatted()) · \(run.rejected.values.reduce(0, +)) dropped")
            }
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline.weight(strong ? .bold : .regular))
        .foregroundStyle(strong ? JL.ink : JL.ink2)
    }

    private var stravaText: String {
        guard let strava = run.stravaKm, strava > 0 else { return "Add" }
        return "\(Format.km(strava)) km · \(Int((meters / (strava * 1_000) * 100).rounded()))%"
    }

    /// What testing needs: times, the target, the phone and the app.
    private var details: some View {
        DisclosureGroup {
            VStack(spacing: 8) {
                row("Moving time", Format.duration(run.movingSeconds))
                row("Target", "\(Format.km(run.targetKm)) km")
                if let at = run.countedTargetAt {
                    row("Target hit (counted)", "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
                }
                if let at = run.cleanTargetAt {
                    row("Target hit (GPS)", "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
                }
                if let trueKm = run.trueKm {
                    row("True distance", "\(Format.km(trueKm)) km · \(Format.percent(meters, versus: trueKm * 1_000))")
                }
                row("Dropped fixes", droppedText)
                row("Phone", "\(run.device), iOS \(run.os)")
                row("App", run.appVersion)
            }
            .padding(.top, 8)
        } label: {
            Text("Run details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JL.ink)
        }
        .tint(JL.ink2)
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var droppedText: String {
        let total = run.rejected.values.reduce(0, +)
        guard total > 0 else { return "0" }
        let parts = run.rejected
            .sorted { $0.value > $1.value }
            .map { "\(Format.reason($0.key)) \($0.value)" }
        return "\(total) (" + parts.joined(separator: ", ") + ")"
    }
}

/// Strava's distance, the true distance and notes for a run, saved with it.
struct CompareSheet: View {
    @Binding var run: RunSummary
    @Environment(\.dismiss) private var dismiss
    @State private var stravaText = ""
    @State private var trueText = ""
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Strava's distance in km, e.g. 1.02", text: $stravaText)
                        .keyboardType(.decimalPad)
                    TextField("True distance in km, e.g. 1.00", text: $trueText)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("On a 400 m track, 2.5 laps of lane 1 is exactly 1 km.")
                }
                Section("Notes") {
                    TextField("Route, where the phone was…", text: $noteText, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JL.paper)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                stravaText = run.stravaKm.map { String(format: "%.2f", $0) } ?? ""
                trueText = run.trueKm.map { String(format: "%.2f", $0) } ?? ""
                noteText = run.note ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        run.stravaKm = Self.parseKm(stravaText)
        run.trueKm = Self.parseKm(trueText)
        run.note = noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText
        try? RunStore.onDevice.save(run)
    }

    private static func parseKm(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
