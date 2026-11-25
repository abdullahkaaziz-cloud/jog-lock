//
//  Components.swift
//  JogLockTracker
//
//  Cards, list rows, section labels, the locked apps' icons and the week bars.
//

import FamilyControls
import JogLockCore
import ManagedSettings
import SwiftUI

extension View {
    /// A white card with rounded corners.
    func jlCard(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JL.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A sand card: quieter than white.
    func jlSandCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JL.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Paper behind the whole screen, under the bars too.
    func jlScreen() -> some View {
        self.background(JL.paper.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .toolbarBackground(JL.paper, for: .navigationBar)
    }
}

/// "LOCKED UNTIL YOU RUN": the small capitals over a group.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .jlLabel()
            .foregroundStyle(JL.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A white list: rows split by hairlines, in one rounded card.
struct JLList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One row of a `JLList`: a title, an optional value and a chevron.
struct JLListRow<Leading: View>: View {
    var title: String
    var detail: String?
    var chevron = false
    var isLast = false
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                leading()
                Text(title)
                    .foregroundStyle(JL.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .foregroundStyle(JL.ink2)
                        .multilineTextAlignment(.trailing)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x9A9284))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .contentShape(Rectangle())
    }
}

extension JLListRow where Leading == EmptyView {
    init(title: String, detail: String? = nil, chevron: Bool = false, isLast: Bool = false) {
        self.init(title: title, detail: detail, chevron: chevron, isLast: isLast) { EmptyView() }
    }
}

/// Something chosen in Screen Time's picker: an app, a category or a website.
enum ChosenToken {
    case app(ApplicationToken)
    case category(ActivityCategoryToken)
    case web(WebDomainToken)

    /// Apps first, then categories, then websites. Each kind in an order that
    /// stays the same between launches, which a set's order doesn't.
    static func all(_ selection: FamilyActivitySelection) -> [ChosenToken] {
        steady(selection.applicationTokens).map(ChosenToken.app)
            + steady(selection.categoryTokens).map(ChosenToken.category)
            + steady(selection.webDomainTokens).map(ChosenToken.web)
    }

    private static func steady<T: Encodable & Hashable>(_ tokens: Set<T>) -> [T] {
        let encoder = JSONEncoder()
        return tokens
            .map { (token: $0, key: (try? encoder.encode($0))?.base64EncodedString() ?? "") }
            .sorted { $0.key < $1.key }
            .map(\.token)
    }

    /// Its icon, drawn by iOS.
    @ViewBuilder var icon: some View {
        switch self {
        case let .app(token): Label(token).labelStyle(.iconOnly)
        case let .category(token): Label(token).labelStyle(.iconOnly)
        case let .web(token): Label(token).labelStyle(.iconOnly)
        }
    }

    /// Its name, drawn by iOS.
    @ViewBuilder var name: some View {
        switch self {
        case let .app(token): Label(token).labelStyle(.titleOnly)
        case let .category(token): Label(token).labelStyle(.titleOnly)
        case let .web(token): Label(token).labelStyle(.titleOnly)
        }
    }
}

/// The icons of up to three chosen apps, overlapping, from Screen Time.
/// Jog Lock never learns which apps they are: iOS draws them.
struct AppTiles: View {
    let selection: FamilyActivitySelection
    var size: CGFloat = 28
    var border: Color = JL.card

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(ChosenToken.all(selection).prefix(3).enumerated()), id: \.offset) { _, token in
                token.icon
                    .frame(width: size, height: size)
                    .background(JL.sand)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).stroke(border, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The chosen apps' names as iOS draws them, then how many more:
/// "TikTok, Instagram +3". Websites typed in count too.
struct AppNames: View {
    let selection: FamilyActivitySelection
    var websites: [String] = []
    var shown = 2

    private enum Name {
        case token(ChosenToken)
        case site(String)
    }

    var body: some View {
        let names = ChosenToken.all(selection).map(Name.token) + websites.map(Name.site)
        HStack(spacing: 0) {
            ForEach(Array(names.prefix(shown).enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Text(", ")
                }
                switch name {
                case let .token(token): token.name
                case let .site(site): Text(site)
                }
            }
            if names.count > shown {
                Text(" +\(names.count - shown)")
            }
        }
        .lineLimit(1)
    }
}

/// A run's route in a small square, north up, from the red dot. A treadmill
/// run gets a little track instead.
struct RouteThumbnail: View {
    let segments: [[Coordinate]]
    var isTreadmill = false
    var size: CGFloat = 64

    var body: some View {
        Canvas { context, box in
            var grid = Path()
            for share in [0.31, 0.69] {
                grid.move(to: CGPoint(x: box.width * share, y: 0))
                grid.addLine(to: CGPoint(x: box.width * share, y: box.height))
                grid.move(to: CGPoint(x: 0, y: box.height * share))
                grid.addLine(to: CGPoint(x: box.width, y: box.height * share))
            }
            context.stroke(grid, with: .color(JL.card), lineWidth: 3)
            let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            if isTreadmill {
                let lane = CGRect(origin: .zero, size: box).insetBy(dx: box.width * 0.16, dy: box.height * 0.3)
                context.stroke(Path(roundedRect: lane, cornerRadius: lane.height / 2), with: .color(JL.ink), style: line)
                return
            }
            let route = Route.project(segments, width: box.width, height: box.height, padding: box.width * 0.16)
            var path = Path()
            for segment in route where !segment.isEmpty {
                path.addLines(segment.map { CGPoint(x: $0.x, y: $0.y) })
            }
            context.stroke(path, with: .color(JL.ink), style: line)
            if let start = route.first?.first {
                context.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(JL.red))
            }
        }
        .frame(width: size, height: size)
        .background(JL.infield)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A lock buddy's first letter in a red circle.
struct BuddyAvatar: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.jlHeading(size * 0.44, relativeTo: .body))
            .foregroundStyle(JL.card)
            .frame(width: size, height: size)
            .background(JL.red, in: Circle())
            .accessibilityHidden(true)
    }
}

/// One day in the week bars.
struct WeekBarDay: Identifiable, Equatable {
    var id: Int { weekday }
    /// 1 = Sunday … 7 = Saturday, as Calendar counts.
    var weekday: Int
    /// Distance run as a share of the day's target, 0... (above 1 is fine).
    var fraction: Double
    var isToday: Bool
    var isRest: Bool
    var isFuture: Bool
}

/// Seven small bars, Monday first: ink for days run, red for today,
/// a dashed box for rest days.
struct WeekBars: View {
    let days: [WeekBarDay]
    var height: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    bar(day)
                        .frame(height: height)
                    Text(Self.letter(day.weekday))
                        .font(.caption2.weight(day.isToday ? .heavy : .semibold))
                        .foregroundStyle(day.isToday ? JL.redText : JL.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func bar(_ day: WeekBarDay) -> some View {
        if day.isRest {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(day.isToday ? JL.red : Color(hex: 0x9A9284),
                              style: StrokeStyle(lineWidth: 1.5, dash: day.isToday ? [] : [3, 3]))
                .overlay(Text("REST").font(.system(size: 9, weight: .bold)).foregroundStyle(day.isToday ? JL.redText : JL.ink2))
        } else {
            let filled = min(max(day.fraction, 0), 1)
            RoundedRectangle(cornerRadius: 6)
                .fill(JL.sand)
                .overlay(alignment: .bottom) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(day.isToday && filled < 1 ? JL.red : JL.ink)
                            .frame(height: proxy.size.height * filled)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    static func letter(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][(weekday - 1 + 7) % 7]
    }
}
