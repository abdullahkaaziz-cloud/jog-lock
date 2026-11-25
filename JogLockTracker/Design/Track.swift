//
//  Track.swift
//  JogLockTracker
//
//  The running track: red lanes, a white start/finish line, and your progress
//  drawn in ink round the inner lane. Lying down on Today, standing up during
//  a run. The geometry is JogLockCore's `TrackGeometry` (tested on Linux).
//

import JogLockCore
import SwiftUI

/// The stadium line that fits its frame, starting at the start/finish line
/// and going clockwise, so `trim(from: 0, to: progress)` draws progress.
struct TrackLine: Shape {
    func path(in rect: CGRect) -> Path {
        let geometry = TrackGeometry(width: Double(rect.width), height: Double(rect.height))
        let segments = geometry.segments
        var path = Path()
        guard !segments.isEmpty else { return path }
        let start = geometry.start
        path.move(to: CGPoint(x: rect.minX + start.x, y: rect.minY + start.y))
        for segment in segments {
            switch segment {
            case let .line(_, _, toX, toY):
                path.addLine(to: CGPoint(x: rect.minX + toX, y: rect.minY + toY))
            case let .arc(centerX, centerY, radius, startAngle, sweep):
                path.addRelativeArc(center: CGPoint(x: rect.minX + centerX, y: rect.minY + centerY),
                                    radius: radius,
                                    startAngle: .radians(startAngle),
                                    delta: .radians(sweep))
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The track with something in the infield.
struct TrackView<Center: View>: View {
    enum Style: Equatable {
        /// Red lanes, ink progress.
        case track
        /// A full lap: the apps are open. Ink infield.
        case done
        /// A rest day: sand lanes, dashed lines, no progress.
        case rest
        /// The lock can't work (Screen Time access is off): grey progress.
        case paused
    }

    /// How far round, 0...1.
    var progress: Double
    var style: Style = .track
    var showsRunner = true
    @ViewBuilder var center: () -> Center

    /// From the outer edge: the two lane lines, the inner lane (where the
    /// progress runs) and the infield.
    private let outerLine: CGFloat = 10
    private let progressInset: CGFloat = 21
    private let infieldInset: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                TrackLine().fill(laneColor)
                laneLine.padding(outerLine)
                laneLine.padding(progressInset)
                TrackLine().fill(infieldColor).padding(infieldInset)
                if style != .rest {
                    TrackLine()
                        .trim(from: 0, to: drawnProgress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        .padding(progressInset)
                }
                startLine(in: size)
                if showsRunner && style != .rest && style != .paused {
                    runner(in: size)
                }
                center()
                    .padding(infieldInset + 10)
            }
            .animation(.easeOut(duration: 0.5), value: drawnProgress)
        }
    }

    private var drawnProgress: Double {
        style == .done ? 1 : min(max(progress, 0), 1)
    }

    private var laneLine: some View {
        TrackLine()
            .stroke(style == .rest || style == .paused ? JL.card : JL.card.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.2, dash: style == .rest ? [6, 6] : []))
    }

    private var laneColor: Color {
        switch style {
        case .track, .done: return JL.red
        case .rest, .paused: return JL.restLane
        }
    }

    private var infieldColor: Color {
        switch style {
        case .track: return JL.infield
        case .done: return JL.ink
        case .rest, .paused: return Color(hex: 0xEDE7DB)
        }
    }

    private var progressColor: Color {
        style == .paused ? Color(hex: 0x9A9284) : JL.ink
    }

    /// The white line across the lanes where every lap starts and ends.
    private func startLine(in size: CGSize) -> some View {
        let standing = size.height > size.width
        let x = standing ? size.width / 2 : size.height / 2
        return Rectangle()
            .fill(JL.card)
            .frame(width: 4, height: infieldInset)
            .position(x: x, y: infieldInset / 2)
    }

    /// The runner: a white dot with an ink ring at the head of the progress.
    private func runner(in size: CGSize) -> some View {
        let inner = TrackGeometry(width: Double(size.width - progressInset * 2),
                                  height: Double(size.height - progressInset * 2))
        let point = inner.point(at: drawnProgress)
        return Circle()
            .fill(JL.card)
            .overlay(Circle().stroke(JL.ink, lineWidth: 4))
            .frame(width: 22, height: 22)
            .position(x: progressInset + point.x, y: progressInset + point.y)
    }
}

#Preview("Today, locked") {
    TrackView(progress: 0.4) {
        Text("1.8 km").jlNumber(64)
    }
    .frame(width: 350, height: 230)
    .padding()
    .background(JL.paper)
}

#Preview("Running") {
    TrackView(progress: 0.81) {
        Text("0.57").jlNumber(96)
    }
    .frame(width: 350, height: 470)
    .padding()
    .background(JL.paper)
}
