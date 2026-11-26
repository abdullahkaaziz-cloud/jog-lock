//
//  ShareCards.swift
//  JogLockTracker
//
//  Story-sized pictures to post (360 × 640 points, made at 1080 × 1920): a
//  run in three styles, Track, Route and Receipt, and "Nice try" for when
//  the step check catches a cheat. Plus the screen to pick a style and
//  share or save it.
//

import JogLockCore
import Photos
import SwiftUI

/// What a run card shows.
struct RunCardContent {
    var meters: Double
    var seconds: TimeInterval
    var steps: Int?
    var started: Date
    var app: String
    var segments: [[Coordinate]]

    init(run: RunSummary, app: String, segments: [[Coordinate]]) {
        meters = run.countedMeters ?? run.cleanMeters
        seconds = run.endedAt.timeIntervalSince(run.startedAt)
        steps = run.steps
        started = run.startedAt
        self.app = app
        self.segments = run.mode == .treadmill ? [] : segments
    }

    var pace: String {
        meters >= 50 ? Format.duration(seconds / (meters / 1_000)) : "--"
    }
}

/// A run card, 9:16. Track: the run as a full lap with the route inside.
/// Route: the route on a map-like square. Receipt: a till receipt, paid in km.
struct RunCardView: View {
    enum Style: String, CaseIterable, Identifiable {
        case track, route, receipt
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    let content: RunCardContent
    var style: Style = .track

    var body: some View {
        Group {
            switch style {
            case .track: trackCard
            case .route: routeCard
            case .receipt: receiptCard
            }
        }
        .frame(width: 360, height: 640)
    }

    // MARK: - Track

    private var trackCard: some View {
        VStack(spacing: 0) {
            brand
                .padding(.top, 30)
            TrackView(progress: 1, style: .track, showsRunner: false) {
                RouteLine(segments: content.segments, lineWidth: 3.5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .frame(width: 300, height: 196)
            .padding(.top, 26)
            bigDistance(76)
                .padding(.top, 30)
            ranToUnlock
                .padding(.top, 12)
            stats
                .padding(.top, 18)
            Spacer(minLength: 0)
            footer
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JL.paper)
    }

    // MARK: - Route

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 30)
                .frame(maxWidth: .infinity)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(JL.infield)
                MapLines()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                RouteLine(segments: content.segments, lineWidth: 5, casing: true)
                    .padding(28)
            }
            .frame(height: 300)
            .padding(.top, 22)
            bigDistance(64)
                .padding(.top, 24)
            ranToUnlock
                .multilineTextAlignment(.leading)
                .padding(.top, 8)
            stats
                .padding(.top, 14)
            Spacer(minLength: 0)
            footer
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(JL.paper)
    }

    // MARK: - Receipt

    private var receiptCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("JOG LOCK")
                Spacer()
                Text(content.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
            }
            .fontWeight(.heavy)
            dashes
            line("DISTANCE", "\(Format.km(content.meters / 1_000)) KM")
            line("TIME", Format.duration(content.seconds))
            line("PACE", "\(content.pace) /KM")
            if let steps = content.steps {
                line("STEPS", steps.formatted())
            }
            dashes
            line("UNLOCKED", content.app.uppercased())
                .fontWeight(.heavy)
            line("PAID WITH", "\(Format.km(content.meters / 1_000)) KM")
            dashes
            Text("PAID")
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(JL.redText)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(JL.red, lineWidth: 3))
                .rotationEffect(.degrees(-8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Text("ONLY REAL RUNNING COUNTS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(JL.ink2)
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 15, design: .monospaced))
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .background(JL.card)
        .mask(ZigzagEdges())
        .shadow(color: Color(hex: 0x3C2814, opacity: 0.14), radius: 14, y: 10)
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JL.red)
    }

    private var dashes: some View {
        Line()
            .stroke(Color(hex: 0x9A9284), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 1.5)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    // MARK: - Shared pieces

    private var brand: some View {
        Text("JOG LOCK")
            .font(.jlHeading(14))
            .tracking(4)
            .foregroundStyle(JL.ink)
    }

    private func bigDistance(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Format.km(content.meters / 1_000))
                .jlNumber(size)
            Text("KM")
                .font(.jlHeading(size * 0.3))
        }
        .foregroundStyle(JL.ink)
    }

    private var ranToUnlock: some View {
        VStack(spacing: 0) {
            Text("ran to unlock")
                .foregroundStyle(JL.ink)
            Text(content.app)
                .foregroundStyle(JL.redText)
        }
        .font(.jlHeading(26))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var stats: some View {
        HStack(spacing: 22) {
            Text("**\(Format.duration(content.seconds))** time")
            Text("**\(content.pace)** /km")
        }
        .font(.system(size: 18))
        .monospacedDigit()
        .foregroundStyle(JL.ink2)
    }

    private var footer: some View {
        Text("ONLY REAL RUNNING COUNTS")
            .font(.system(size: 12, weight: .heavy))
            .tracking(2.4)
            .foregroundStyle(JL.ink2)
    }
}

/// "NICE TRY." for distance the step check threw out.
struct NiceTryCardView: View {
    let kind: NiceTryKind
    let meters: Double

    var body: some View {
        VStack(spacing: 22) {
            Text("JOG LOCK")
                .font(.jlHeading(14))
                .tracking(4)
                .padding(.top, 30)
            Spacer()
            Image(systemName: kind == .vehicle ? "car.side.fill" : "shoeprints.fill")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(JL.ink)
            Text("Nice try.")
                .font(.jlDisplay(64))
                .tracking(-2.5)
                .textCase(.uppercase)
                .foregroundStyle(JL.redText)
            Text(Self.message(kind: kind, meters: meters))
                .font(.jlHeading(22))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            Text("ONLY REAL RUNNING COUNTS")
                .font(.system(size: 12, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(JL.ink2)
                .padding(.bottom, 30)
        }
        .foregroundStyle(JL.ink)
        .frame(width: 360, height: 640)
        .background(JL.paper)
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

/// A route as an ink line from a red start dot, north up, fitted to the space.
struct RouteLine: View {
    let segments: [[Coordinate]]
    var lineWidth: CGFloat = 4
    /// A paper edge round the line, for drawing over map lines.
    var casing = false

    var body: some View {
        Canvas { context, size in
            let route = Route.project(segments, width: size.width, height: size.height)
            var path = Path()
            for segment in route where !segment.isEmpty {
                path.addLines(segment.map { CGPoint(x: $0.x, y: $0.y) })
            }
            if casing {
                context.stroke(path, with: .color(JL.card),
                               style: StrokeStyle(lineWidth: lineWidth * 2.2, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(JL.ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if let start = route.first?.first {
                let dot = lineWidth * 2.2
                context.fill(Path(ellipseIn: CGRect(x: start.x - dot, y: start.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(JL.red))
            }
        }
    }
}

/// Streets on a map, drawn loosely.
private struct MapLines: View {
    var body: some View {
        Canvas { context, size in
            var wide = Path()
            for x in [0.22, 0.58, 0.86] {
                wide.move(to: CGPoint(x: size.width * x, y: 0))
                wide.addLine(to: CGPoint(x: size.width * x, y: size.height))
            }
            for y in [0.3, 0.64] {
                wide.move(to: CGPoint(x: 0, y: size.height * y))
                wide.addLine(to: CGPoint(x: size.width, y: size.height * y))
            }
            context.stroke(wide, with: .color(JL.card.opacity(0.9)), lineWidth: 8)
            var narrow = Path()
            narrow.move(to: CGPoint(x: 0, y: size.height * 0.12))
            narrow.addLine(to: CGPoint(x: size.width, y: size.height * 0.4))
            narrow.move(to: CGPoint(x: size.width * 0.4, y: 0))
            narrow.addLine(to: CGPoint(x: size.width * 0.4, y: size.height))
            narrow.move(to: CGPoint(x: 0, y: size.height * 0.84))
            narrow.addLine(to: CGPoint(x: size.width, y: size.height * 0.84))
            context.stroke(narrow, with: .color(JL.card.opacity(0.9)), lineWidth: 3)
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// A receipt's torn top and bottom.
private struct ZigzagEdges: Shape {
    func path(in rect: CGRect) -> Path {
        let tooth: CGFloat = 7
        let width: CGFloat = 14
        var path = Path()
        path.move(to: CGPoint(x: 0, y: tooth))
        var x: CGFloat = 0
        while x < rect.width {
            path.addLine(to: CGPoint(x: min(x + width / 2, rect.width), y: 0))
            path.addLine(to: CGPoint(x: min(x + width, rect.width), y: tooth))
            x += width
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - tooth))
        x = rect.width
        while x > 0 {
            path.addLine(to: CGPoint(x: max(x - width / 2, 0), y: rect.height))
            path.addLine(to: CGPoint(x: max(x - width, 0), y: rect.height - tooth))
            x -= width
        }
        path.closeSubpath()
        return path
    }
}

@MainActor
enum ShareCards {
    static func segments(for run: RunSummary) async -> [[Coordinate]] {
        guard run.mode != .treadmill else { return [] }
        let id = run.id
        return await Task.detached(priority: .userInitiated) {
            Route.segments(from: RunStore.onDevice.readLines(id: id))
        }.value
    }

    static func niceTryImage(kind: NiceTryKind, meters: Double) -> Image? {
        render(NiceTryCardView(kind: kind, meters: meters))
    }

    static func render<V: View>(_ view: V) -> Image? {
        renderUIImage(view).map(Image.init(uiImage:))
    }

    static func renderUIImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// "Share your run": the card in the style picked, to share or save.
struct ShareRunView: View {
    let run: RunSummary
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var style: RunCardView.Style = .track
    @State private var segments: [[Coordinate]] = []
    @State private var image: Image?
    @State private var saved: String?

    private var styles: [RunCardView.Style] {
        run.mode == .treadmill ? [.track, .receipt] : RunCardView.Style.allCases
    }

    private var card: RunCardView {
        RunCardView(content: RunCardContent(run: run, app: settings.nemesis, segments: segments), style: style)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Text("Share your run")
                    .font(.jlHeading(18))
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(JLRoundButtonStyle(fill: JL.card))
                    Spacer()
                }
            }
            .padding(.top, 12)
            card
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(0.72)
                .frame(width: 360 * 0.72, height: 640 * 0.72)
                .shadow(color: Color(hex: 0x3C2814, opacity: 0.18), radius: 22, y: 14)
            HStack(spacing: 4) {
                ForEach(styles) { option in
                    Button {
                        style = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(style == option ? JL.card : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(hex: 0xDDD5C6), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Spacer(minLength: 0)
            if let saved {
                Text(saved)
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            HStack(spacing: 10) {
                Button("Save to Photos", action: save)
                    .buttonStyle(.jlOutline)
                    .fixedSize(horizontal: true, vertical: false)
                if let image {
                    ShareLink(item: image, preview: SharePreview("My Jog Lock run", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.jlPrimary)
                }
            }
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(JL.sand.ignoresSafeArea())
        .task(id: run.id) {
            segments = await ShareCards.segments(for: run)
            image = ShareCards.render(card)
        }
        .onChange(of: style) {
            image = ShareCards.render(card)
        }
    }

    private func save() {
        guard let image = ShareCards.renderUIImage(card) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in saved = "Jog Lock can't add to Photos. Allow it in Settings → Jog Lock → Photos." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { done, _ in
                Task { @MainActor in saved = done ? "Saved to Photos." : "Couldn't save it. Try Share instead." }
            }
        }
    }
}

/// "Share card" for a finished run: opens the share screen.
struct ShareRunButton: View {
    let run: RunSummary
    @State private var sharing = false

    var body: some View {
        Button("Share card") {
            sharing = true
        }
        .buttonStyle(.jlInk)
        .sheet(isPresented: $sharing) {
            ShareRunView(run: run)
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
                Image(systemName: kind == .vehicle ? "car.side.fill" : "shoeprints.fill")
                    .font(.title2)
                    .foregroundStyle(JL.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nice try.")
                        .font(.jlHeading(17))
                    Text(NiceTryCardView.message(kind: kind, meters: meters))
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(JL.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let image = ShareCards.niceTryImage(kind: kind, meters: meters) {
                ShareLink(item: image, preview: SharePreview("Nice try", image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .font(.subheadline.weight(.semibold))
                .tint(JL.redText)
            }
        }
        .foregroundStyle(JL.ink)
        .padding()
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
