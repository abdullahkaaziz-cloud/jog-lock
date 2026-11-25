//
//  UnlockCelebration.swift
//  JogLockTracker
//
//  The unlock moment, in track red: the run that met the day's target, the
//  locked apps' icons spring out, UNLOCKED in italics, and paper confetti.
//  Made to be screen-recorded. After a run it shows once the run is saved.
//

import FamilyControls
import JogLockCore
import SwiftUI

struct UnlockCelebrationView: View {
    let selection: FamilyActivitySelection
    var websites: [String] = []
    /// The app the runner is running for.
    let app: String
    /// The run that did it, when there is one.
    var run: RunSummary?
    /// When the apps lock again: "midnight", "04:00".
    var until: String?
    let onClose: () -> Void
    @State private var opened = false
    @State private var sharing = false

    var body: some View {
        ZStack {
            JL.red
                .ignoresSafeArea()
            ZStack {
                TrackLine().stroke(JL.card.opacity(0.13), lineWidth: 1.5).padding(-40)
                TrackLine().stroke(JL.card.opacity(0.13), lineWidth: 1.5).padding(-10)
                TrackLine().stroke(JL.card.opacity(0.13), lineWidth: 1.5).padding(20)
            }
            .ignoresSafeArea()
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                if let run {
                    Text(caption(run))
                        .font(.jlHeading(14))
                        .tracking(2.2)
                        .opacity(0.85)
                        .padding(.top, 8)
                }
                Spacer()
                tiles
                Text("Unlocked")
                    .font(.jlDisplayItalic(60))
                    .tracking(-2.4)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 36)
                Text("\(app) is all yours.\nYou ran for it.")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 14)
                Text(othersText)
                    .font(.subheadline)
                    .opacity(0.85)
                    .padding(.top, 10)
                Spacer()
                VStack(spacing: 12) {
                    Button("Let me scroll", action: onClose)
                        .buttonStyle(JLPaperButtonStyle())
                    if run != nil {
                        Button("Share the run") {
                            sharing = true
                        }
                        .font(.body.weight(.bold))
                        .buttonStyle(JLOutlineButtonStyle(fullWidth: true, color: JL.card))
                    }
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(JL.card)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sensoryFeedback(.success, trigger: opened)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.3)) {
                opened = true
            }
        }
        .sheet(isPresented: $sharing) {
            if let run {
                ShareRunView(run: run)
            }
        }
    }

    /// The chosen apps' icons, tilted like cards thrown down.
    private var tiles: some View {
        let tokens = Array(ChosenToken.all(selection).prefix(3))
        return HStack(spacing: 10) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                token.icon
                    .scaleEffect(2.4)
                    .frame(width: 64, height: 64)
                    .background(JL.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: JL.ink.opacity(0.3), radius: 14, y: 14)
                    .rotationEffect(.degrees(tokens.count == 1 ? 0 : [-8, 0, 8][index]))
                    .offset(y: index == 1 ? -14 : 0)
                    .scaleEffect(opened ? 1 : 0.3)
                    .opacity(opened ? 1 : 0)
            }
        }
        .frame(height: 92)
    }

    /// "WEDNESDAY · 3.21 KM · 19:24"
    private func caption(_ run: RunSummary) -> String {
        let day = run.startedAt.formatted(.dateTime.weekday(.wide)).uppercased()
        let km = Format.km((run.countedMeters ?? run.cleanMeters) / 1_000)
        return "\(day) · \(km) KM · \(Format.duration(run.endedAt.timeIntervalSince(run.startedAt)))"
    }

    /// "3 more are open too, until midnight."
    private var othersText: String {
        let chosen = selection.applicationTokens.count + selection.categoryTokens.count
            + selection.webDomainTokens.count + websites.count
        let others = chosen - 1
        let end = until.map { ", until \($0)" } ?? ""
        if others <= 0 {
            return until.map { "Open until \($0)." } ?? "Open for the rest of the day."
        }
        return "\(others) more \(others == 1 ? "is" : "are") open too\(end)."
    }
}

/// Confetti that keeps falling while the celebration is up: paper, ink and sand.
struct ConfettiView: View {
    private struct Piece {
        var x: Double
        var delay: Double
        var speed: Double
        var size: Double
        var spin: Double
        var sway: Double
        var color: Color
    }

    @State private var start = Date()
    @State private var pieces = ConfettiView.makePieces(count: 70)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let age = t - piece.delay
                    guard age > 0 else { continue }
                    // Falls from just above the top, loops, and sways side to side.
                    let fall = (age * piece.speed).truncatingRemainder(dividingBy: 1.15)
                    var layer = context
                    layer.translateBy(x: piece.x * size.width + sin(age * piece.spin) * piece.sway,
                                      y: -20 + fall * (size.height + 40))
                    layer.rotate(by: .radians(age * piece.spin * 2))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    layer.fill(Path(rect), with: .color(piece.color))
                }
            }
        }
    }

    private static func makePieces(count: Int) -> [Piece] {
        let colors: [Color] = [JL.card, JL.card, JL.paper, JL.sand, JL.ink]
        return (0..<count).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...1.5), speed: .random(in: 0.2...0.45),
                  size: .random(in: 7...13), spin: .random(in: 1...4), sway: .random(in: 10...40),
                  color: colors.randomElement() ?? JL.card)
        }
    }
}
