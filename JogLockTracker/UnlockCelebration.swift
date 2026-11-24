//
//  UnlockCelebration.swift
//  JogLockTracker
//
//  The unlock moment: the run that meets the day's target pops the lock,
//  the locked apps' icons spring out and confetti falls. Made to be
//  screen-recorded.
//

import FamilyControls
import SwiftUI

struct UnlockCelebrationView: View {
    let selection: FamilyActivitySelection
    let app: String
    let onClose: () -> Void
    @State private var opened = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.75, blue: 0.35), Color(red: 0.0, green: 0.3, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: opened ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: opened)
                Text("UNLOCKED")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(app) is all yours. You ran for it.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                HStack(spacing: 22) {
                    ForEach(Array(selection.applicationTokens.prefix(5)), id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(opened ? 2 : 0.2)
                            .opacity(opened ? 1 : 0)
                            .frame(width: 50, height: 50)
                    }
                }
                .padding(.top, 12)
                Spacer()
                Button(action: onClose) {
                    Text("Let me scroll")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.0, green: 0.45, blue: 0.25))
                .controlSize(.large)
            }
            .padding(32)
        }
        .sensoryFeedback(.success, trigger: opened)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.4)) {
                opened = true
            }
        }
    }
}

/// Confetti that keeps falling while the celebration is up.
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
    @State private var pieces = ConfettiView.makePieces(count: 90)

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
        let colors: [Color] = [.yellow, .pink, .orange, .white, .mint, .cyan, .purple]
        return (0..<count).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...1.5), speed: .random(in: 0.2...0.45),
                  size: .random(in: 7...13), spin: .random(in: 1...4), sway: .random(in: 10...40),
                  color: colors.randomElement() ?? .white)
        }
    }
}
