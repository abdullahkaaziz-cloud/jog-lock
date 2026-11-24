//
//  ShareCards.swift
//  JogLockTracker
//
//  Story-sized images to post: a run card (route as line art, distance,
//  time) and a "nice try" card for when the step check catches a cheat.
//

import JogLockCore
import SwiftUI

private let storyGradient = LinearGradient(
    colors: [Color(red: 0.04, green: 0.06, blue: 0.09), Color(red: 0.02, green: 0.33, blue: 0.24)],
    startPoint: .top, endPoint: .bottom)

/// 9:16, rendered at 3x for a 1080 x 1920 image.
struct ShareCardView: View {
    let km: Double
    let duration: TimeInterval
    let app: String
    let segments: [[Coordinate]]

    var body: some View {
        ZStack {
            storyGradient
            VStack(alignment: .leading, spacing: 18) {
                Text("JOG LOCK")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.7))
                Group {
                    if segments.isEmpty {
                        Image(systemName: "figure.run.treadmill")
                            .font(.system(size: 120, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        RouteArt(segments: segments)
                    }
                }
                .frame(height: 300)
                Text(String(format: "%.2f km", km))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("ran to unlock \(app)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 28) {
                    stat("Time", Format.duration(duration))
                    stat("Pace", km > 0.05 ? Format.duration(duration / km) + " /km" : "--")
                }
                Spacer()
                Text("No run, no scroll.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(32)
        }
        .frame(width: 360, height: 640)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct NiceTryCardView: View {
    let kind: NiceTryKind
    let meters: Double

    var body: some View {
        ZStack {
            storyGradient
            VStack(spacing: 24) {
                Spacer()
                Text(kind == .vehicle ? "🚗" : "👟")
                    .font(.system(size: 110))
                Text("Nice try.")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(Self.message(kind: kind, meters: meters))
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("JOG LOCK · only real running counts")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(32)
        }
        .frame(width: 360, height: 640)
    }

    static func message(kind: NiceTryKind, meters: Double) -> String {
        let km = Format.km(meters / 1000)
        switch kind {
        case .vehicle:
            return "\(km) km by car or bike didn't count."
        case .noSteps:
            return "\(km) km without the steps to match didn't count."
        }
    }
}

/// The route drawn as a line, north up.
struct RouteArt: View {
    let segments: [[Coordinate]]

    var body: some View {
        GeometryReader { geo in
            let projected = Route.project(segments, width: geo.size.width, height: geo.size.height, padding: 8)
            Path { path in
                for segment in projected {
                    guard let first = segment.first else { continue }
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in segment.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                }
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }
}

@MainActor
enum ShareCards {
    static func runImage(for run: RunSummary, app: String) async -> Image? {
        let segments = await Task.detached(priority: .userInitiated) {
            Route.segments(from: RunStore.onDevice.readLines(id: run.id))
        }.value
        let card = ShareCardView(km: (run.countedMeters ?? run.cleanMeters) / 1000,
                                 duration: run.endedAt.timeIntervalSince(run.startedAt),
                                 app: app,
                                 segments: run.mode == .treadmill ? [] : segments)
        return render(card)
    }

    static func niceTryImage(kind: NiceTryKind, meters: Double) -> Image? {
        render(NiceTryCardView(kind: kind, meters: meters))
    }

    private static func render<V: View>(_ view: V) -> Image? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

/// "Share this run" for a finished run.
struct ShareRunButton: View {
    let run: RunSummary
    @ObservedObject private var settings = AppSettings.shared
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview("My Jog Lock run", image: image)) {
                    Label("Share this run", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .task(id: run.id + settings.nemesis) {
            image = await ShareCards.runImage(for: run, app: settings.nemesis)
        }
    }
}

/// The card shown when the step check throws out distance.
struct NiceTryBanner: View {
    let kind: NiceTryKind
    let meters: Double
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(kind == .vehicle ? "🚗" : "👟")
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nice try.")
                        .font(.headline)
                    Text(NiceTryCardView.message(kind: kind, meters: meters))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let image = ShareCards.niceTryImage(kind: kind, meters: meters) {
                ShareLink(item: image, preview: SharePreview("Nice try", image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
}
