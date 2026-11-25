//
//  Components.swift
//  JogLockTracker
//
//  Cards, list rows, section labels, the locked apps' icons and the week bars.
//

import FamilyControls
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

/// The icons of up to three chosen apps, overlapping, from Screen Time.
/// Jog Lock never learns which apps they are: iOS draws them.
struct AppTiles: View {
    let selection: FamilyActivitySelection
    var size: CGFloat = 28
    var border: Color = JL.card

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                tile(token)
            }
        }
        .accessibilityHidden(true)
    }

    private enum Token {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)
        case web(WebDomainToken)
    }

    private var tokens: [Token] {
        let apps = selection.applicationTokens.map(Token.app)
        let categories = selection.categoryTokens.map(Token.category)
        let sites = selection.webDomainTokens.map(Token.web)
        return Array((apps + categories + sites).prefix(3))
    }

    @ViewBuilder
    private func tile(_ token: Token) -> some View {
        Group {
            switch token {
            case let .app(token): Label(token).labelStyle(.iconOnly)
            case let .category(token): Label(token).labelStyle(.iconOnly)
            case let .web(token): Label(token).labelStyle(.iconOnly)
            }
        }
        .frame(width: size, height: size)
        .background(JL.sand)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).stroke(border, lineWidth: 2))
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
