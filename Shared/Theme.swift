//
//  Theme.swift
//  JogLockTracker
//
//  Race Day · Track: the colours and type every screen uses
//  (docs/design/DESIGN.md).
//

import SwiftUI

/// Jog Lock's colours. Light look only: the app sets `UIUserInterfaceStyle`.
enum JL {
    /// Screen background.
    static let paper = Color(hex: 0xF3EFE6)
    /// Cards, lists and sheets.
    static let card = Color(hex: 0xFFFDF8)
    /// Chips and quiet buttons.
    static let sand = Color(hex: 0xE7E1D5)
    /// Inside the track.
    static let infield = Color(hex: 0xE9E2D3)
    /// Hairlines and dashed rules.
    static let line = Color(hex: 0xCFC6B6)
    /// A darker sand for lanes on a rest day.
    static let restLane = Color(hex: 0xDCD4C5)
    /// Text, progress and ink buttons.
    static let ink = Color(hex: 0x17140F)
    /// Secondary text. Passes 4.5:1 on paper and on cards.
    static let ink2 = Color(hex: 0x5E584F)
    /// The track and primary buttons.
    static let red = Color(hex: 0xC8321A)
    /// Red words on paper.
    static let redText = Color(hex: 0xA82A14)
    /// Red marks on ink.
    static let redOnInk = Color(hex: 0xE0482C)
}

extension Color {
    /// A colour from a 0xRRGGBB number, in sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Big numbers: Archivo, black, 122% wide. Scales with Dynamic Type.
    static func jlDisplay(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("ArchivoTrack-Display", size: size, relativeTo: style)
    }

    /// The unlock moment: the display cut in italic.
    static func jlDisplayItalic(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("ArchivoTrack-DisplayItalic", size: size, relativeTo: style)
    }

    /// Headings and button labels: Archivo, extra bold, 112% wide.
    static func jlHeading(_ size: CGFloat, relativeTo style: TextStyle = .headline) -> Font {
        .custom("ArchivoTrack-Heading", size: size, relativeTo: style)
    }
}

extension View {
    /// A big display number, with the tight letter spacing the design uses.
    func jlNumber(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        font(.jlDisplay(size, relativeTo: style))
            .tracking(-size * 0.04)
            .monospacedDigit()
    }

    /// Small capitals above a section: "LOCKED UNTIL YOU RUN".
    func jlLabel() -> some View {
        font(.caption2.weight(.heavy))
            .tracking(1.3)
            .textCase(.uppercase)
    }

    /// The date line over a big title: "WEDNESDAY 25 NOV".
    func jlCaption() -> some View {
        font(.footnote.weight(.semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(JL.ink2)
    }
}
