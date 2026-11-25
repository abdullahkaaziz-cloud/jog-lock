//
//  WrappedView.swift
//  JogLockTracker
//
//  A month on Jog Lock as a short story to tap through: the distance in
//  laps of a running track, the runs that unlocked the apps, the longest
//  run and streak, the distance next to things people know, the "Nice
//  try"s caught (MonthWrap), and a story-sized card to share. Made from the
//  runs kept on the phone.
//

import JogLockCore
import SwiftUI

struct WrappedView: View {
    let month: Date
    let runs: [RunSummary]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var page = 0
    @State private var pageStarted = Date()
    @State private var image: Image?

    /// How long a page stays before the next one.
    private static let pageSeconds = 6.0

    private enum Page {
        case laps, longest, journey, niceTries
    }

    private var wrap: MonthWrap {
        MonthWrap(runs: runs.map { MonthWrap.Run($0) }, month: month)
    }

    private var pages: [Page] {
        wrap.niceTries > 0 ? [.laps, .longest, .journey, .niceTries] : [.laps, .longest, .journey]
    }

    /// Runs this month that met their target: unlocks, with the lock on.
    private var unlocks: Int {
        runs.filter { $0.countedTargetAt != nil && Calendar.current.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
            .count
    }

    var body: some View {
        let wrap = self.wrap
        let pages = self.pages
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation) { context in
                let through = min(1, context.date.timeIntervalSince(pageStarted) / Self.pageSeconds)
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color(hex: 0xD6CEBF))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(JL.ink)
                                        .frame(width: proxy.size.width * (index < page ? 1 : index == page ? through : 0))
                                }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(.top, 12)
            HStack {
                Text("\(wrap.title.components(separatedBy: " ").first ?? wrap.title), wrapped")
                    .font(.jlHeading(15))
                    .tracking(3)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.jlRound)
            }
            .padding(.top, 18)
            Group {
                switch pages[min(page, pages.count - 1)] {
                case .laps: laps(wrap)
                case .longest: longest(wrap)
                case .journey: journey(wrap)
                case .niceTries: niceTries(wrap)
                }
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                if location.x < 110 {
                    show(page - 1)
                } else {
                    show(page + 1)
                }
            }
            if let image {
                ShareLink(item: image, preview: SharePreview("My month on Jog Lock", image: image)) {
                    Label("Share my month", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.jlPrimary)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .background(JL.paper.ignoresSafeArea())
        .task(id: page) {
            try? await Task.sleep(for: .seconds(Self.pageSeconds))
            if !Task.isCancelled && page < pages.count - 1 {
                show(page + 1)
            }
        }
        .task {
            image = ShareCards.render(WrappedCardView(wrap: wrap, app: settings.nemesis))
        }
    }

    private func show(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        page = index
        pageStarted = Date()
    }

    // MARK: - Pages

    private func laps(_ wrap: MonthWrap) -> some View {
        let laps = Int(wrap.meters / 400)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("You ran")
                    .font(.jlHeading(26))
                bigKm(wrap.meters)
            }
            Text("That's \(Text("\(laps) \(laps == 1 ? "lap" : "laps")").foregroundStyle(JL.redText)) of a running track.")
                .font(.jlHeading(28))
            LapGrid(laps: laps)
            HStack(spacing: 12) {
                fact("\(unlocks)", "\(unlocks == 1 ? "time" : "times") you ran to unlock \(settings.nemesis)")
                if let time = wrap.timeOfDay {
                    fact("\(wrap.runs)", "\(wrap.runs == 1 ? "run" : "runs"). You're \(time.runner).")
                } else {
                    fact("\(wrap.runs)", wrap.runs == 1 ? "run" : "runs")
                }
            }
        }
    }

    private func longest(_ wrap: MonthWrap) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your longest run")
                    .font(.jlHeading(26))
                bigKm(wrap.longest)
            }
            TrackView(progress: min(1, wrap.longest / 5_000), style: wrap.longest >= 5_000 ? .done : .track) {
                Text(wrap.longest >= 5_000 ? "5K+" : "\(Int(wrap.longest / 50) * 5)% of a 5K")
                    .font(.jlHeading(22))
                    .foregroundStyle(wrap.longest >= 5_000 ? JL.paper : JL.ink)
            }
            .frame(height: 200)
            HStack(spacing: 12) {
                fact("\(wrap.streak)", wrap.streak == 1 ? "day in a row, your best streak" : "days in a row, your best streak")
                fact(ScreenTimeWeek.text(Int(wrap.seconds)), "on your feet")
            }
        }
    }

    private func journey(_ wrap: MonthWrap) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(wrap.journey)
                .font(.jlDisplay(46))
                .tracking(-1.8)
                .minimumScaleFactor(0.6)
            if let scrolling = wrap.scrolling(minutesPerKm: LockRules().minutesPerExtraKm) {
                Text(scrolling)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(JL.ink2)
            }
            Spacer(minLength: 0)
            Text("Only real running counts. Every kilometre was checked against your steps.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
        }
    }

    private func niceTries(_ wrap: MonthWrap) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(wrap.niceTries)")
                .jlNumber(140)
            Text(wrap.niceTries == 1 ? "Nice try." : "Nice tries.")
                .font(.jlDisplay(56))
                .tracking(-2.2)
                .textCase(.uppercase)
                .foregroundStyle(JL.redText)
            Text("Distance by car or bike, or without the steps to match, was caught and didn't count.")
                .font(.title3.weight(.semibold))
        }
    }

    private func bigKm(_ meters: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Format.tenths(meters))
                .jlNumber(110)
            Text("KM")
                .font(.jlHeading(30))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.jlDisplay(34))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: 110, alignment: .topLeading)
        .background(JL.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A pill for each lap of a 400 m track, ten to a row; a pill is more than
/// one lap past a hundred.
struct LapGrid: View {
    let laps: Int

    var body: some View {
        let per = max(1, Int((Double(laps) / 100).rounded(.up)))
        let filled = Int((Double(laps) / Double(per)).rounded(.up))
        let cells = max(10, Int((Double(filled) / 10).rounded(.up)) * 10)
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10), spacing: 8) {
                ForEach(0..<cells, id: \.self) { index in
                    if index < filled {
                        Capsule().fill(JL.ink).frame(height: 12)
                    } else {
                        Capsule().strokeBorder(Color(hex: 0x9A9284), lineWidth: 1.5).frame(height: 12)
                    }
                }
            }
            if per > 1 {
                Text("Each is \(per) laps.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The month's card to share, 360 × 640 points, made at 1080 × 1920.
struct WrappedCardView: View {
    let wrap: MonthWrap
    let app: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("JOG LOCK")
                .font(.jlHeading(14))
                .tracking(4)
            Text("\(wrap.title.uppercased()), WRAPPED")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2)
                .foregroundStyle(JL.redText)
            Spacer(minLength: 8)
            Text("You ran")
                .font(.jlHeading(22))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.tenths(wrap.meters))
                    .jlNumber(84)
                Text("KM")
                    .font(.jlHeading(24))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text("to unlock \(app)")
                .font(.jlHeading(22))
                .foregroundStyle(JL.redText)
            LapGrid(laps: Int(wrap.meters / 400))
                .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(wrap.runs) \(wrap.runs == 1 ? "run" : "runs") · \(ScreenTimeWeek.text(Int(wrap.seconds)))")
                if wrap.longest > 0 {
                    Text("Longest run \(Format.shortDistance(wrap.longest))")
                }
                if wrap.streak > 1 {
                    Text("\(wrap.streak) days in a row")
                }
                if wrap.niceTries > 0 {
                    Text("\(wrap.niceTries) Nice \(wrap.niceTries == 1 ? "try" : "tries") caught")
                }
            }
            .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 8)
            Text(wrap.journey)
                .font(.jlHeading(18))
            Text("ONLY REAL RUNNING COUNTS")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.2)
                .foregroundStyle(JL.ink2)
        }
        .foregroundStyle(JL.ink)
        .padding(28)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(JL.paper)
    }
}
