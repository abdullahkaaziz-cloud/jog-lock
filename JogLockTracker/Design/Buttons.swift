//
//  Buttons.swift
//  JogLockTracker
//
//  The design's buttons: red and ink pills, outline pills, sand chips.
//

import SwiftUI

/// The main action: a red pill with the label in capitals. "START RUN".
struct JLPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        JLPill(configuration: configuration, height: height, fill: JL.red, text: JL.card, capitals: true)
    }
}

/// A strong second action: an ink pill with the label in capitals.
/// "HOLD TO FINISH", "SHARE CARD".
struct JLInkButtonStyle: ButtonStyle {
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        JLPill(configuration: configuration, height: height, fill: JL.ink, text: JL.paper, capitals: true)
    }
}

/// The way out of the red unlock screen: a paper pill, ink capitals.
/// "LET ME SCROLL".
struct JLPaperButtonStyle: ButtonStyle {
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        JLPill(configuration: configuration, height: height, fill: JL.card, text: JL.ink, capitals: true)
    }
}

/// A quiet action: an outline, normal text. "Outdoor", "Run anyway". Ink on
/// paper; paper on red for "Share the run".
struct JLOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 58
    var fullWidth = false
    var color: Color = JL.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .overlay(Capsule().strokeBorder(color.opacity(0.9), lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A sand chip with two lines: "24 min banked / from extra km".
/// The label's first line is the headline, the rest is secondary.
struct JLChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        JLChip(configuration: configuration)
    }
}

/// A sand chip, dimmed when the button is disabled.
private struct JLChip: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 14)
            .foregroundStyle(JL.ink)
            .background(JL.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

/// A small sand capsule, 44 high: "3 km a day", "Allow".
struct JLSmallButtonStyle: ButtonStyle {
    var fill: Color = JL.sand
    var text: Color = JL.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A round button: back, close, more (44 points), and the run screen's
/// voice and map buttons (58).
struct JLRoundButtonStyle: ButtonStyle {
    var fill: Color = JL.sand
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size > 50 ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(JL.ink)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A filled pill, dimmed when the button is disabled.
private struct JLPill: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let fill: Color
    let text: Color
    let capitals: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.jlHeading(18, relativeTo: .headline))
            .tracking(capitals ? 0.4 : 0)
            .textCase(capitals ? .uppercase : nil)
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == JLPrimaryButtonStyle {
    static var jlPrimary: JLPrimaryButtonStyle { JLPrimaryButtonStyle() }
}

extension ButtonStyle where Self == JLInkButtonStyle {
    static var jlInk: JLInkButtonStyle { JLInkButtonStyle() }
}

extension ButtonStyle where Self == JLOutlineButtonStyle {
    static var jlOutline: JLOutlineButtonStyle { JLOutlineButtonStyle() }
    static var jlOutlineWide: JLOutlineButtonStyle { JLOutlineButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == JLChipButtonStyle {
    static var jlChip: JLChipButtonStyle { JLChipButtonStyle() }
}

extension ButtonStyle where Self == JLSmallButtonStyle {
    static var jlSmall: JLSmallButtonStyle { JLSmallButtonStyle() }
}

extension ButtonStyle where Self == JLRoundButtonStyle {
    static var jlRound: JLRoundButtonStyle { JLRoundButtonStyle() }
}
