//
//  RunReel.swift
//  JogLockTracker
//
//  "Make a reel": a 10-second story video of a run (1080 × 1920, 30 fps,
//  H.264) to post on TikTok, Reels or Stories. The route draws itself in ink
//  on a paper map while the distance left to unlock counts down; if the run
//  met its target, the lock shakes and springs open and "UNLOCKED" comes up.
//  The timing is ReelTimeline (core); the frames are drawn here with Core
//  Graphics and written with AVAssetWriter, on the phone.
//

import AVFoundation
import AVKit
import JogLockCore
import SwiftUI
import UIKit

enum ReelMaker {
    struct Content: Sendable {
        let meters: Double
        let seconds: TimeInterval
        let app: String
        /// The distance the run set out to cover; 0 without one.
        let targetMeters: Double
        /// The run met its target, so the lock opens at the end.
        let unlocked: Bool
        /// The route, drawn into `routeBox`; empty for a treadmill run.
        let route: [[Point2D]]
    }

    enum Failure: Error {
        case writer
    }

    static let size = CGSize(width: 1080, height: 1920)
    static let routeBox = CGRect(x: 90, y: 330, width: 900, height: 900)

    /// Makes the reel for a run and returns the video file.
    static func make(_ run: RunSummary, app: String,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let segments = run.mode == .treadmill ? [] : Route.segments(from: RunStore.onDevice.readLines(id: run.id))
        let content = Content(meters: run.countedMeters ?? run.cleanMeters,
                              seconds: run.endedAt.timeIntervalSince(run.startedAt), app: app,
                              targetMeters: run.targetKm * 1_000, unlocked: run.countedTargetAt != nil,
                              route: Route.project(segments, width: routeBox.width, height: routeBox.height, padding: 30))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jog-lock-reel-\(run.id).mp4")
        try? FileManager.default.removeItem(at: url)
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try write(content, to: url, progress: progress)
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
        return url
    }

    private static func write(_ content: Content, to url: URL, progress: (Double) -> Void) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let artwork = Artwork(content: content)
        for frame in 0..<ReelTimeline.frames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer
            else {
                throw Failure.writer
            }
            artwork.draw(at: ReelTimeline.time(ofFrame: frame), into: buffer)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(ReelTimeline.fps))
            guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? Failure.writer }
            if frame % 15 == 0 || frame == ReelTimeline.frames - 1 {
                progress(Double(frame + 1) / Double(ReelTimeline.frames))
            }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else { throw writer.error ?? Failure.writer }
    }

    /// Everything a frame draws, made once. The Race Day look: a paper map,
    /// the route in ink, the distance left to unlock counting down, and the
    /// lock opening if the run met its target.
    private struct Artwork {
        let content: Content
        let timeline: ReelTimeline
        let brand: NSAttributedString
        let numberFont: UIFont
        let unitFont: UIFont
        let labelFont: UIFont
        let italicFont: UIFont
        let shut: UIImage?
        let open: UIImage?
        let treadmill: UIImage?

        static let ink = color(0x17140F)
        static let red = color(0xC8321A)
        static let redText = color(0xA82A14)
        static let card = color(0xFFFDF8)
        static let ground = color(0xE6DFD1)
        static let street = color(0xF7F3EB)
        static let water = color(0xD2D9D5)
        static let park = color(0xD9DCC7)
        /// Design units (a 280-wide frame) to pixels.
        static let unit = size.width / 280
        static let margin: CGFloat = 62

        static func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }

        static func font(_ name: String, _ size: CGFloat, fallback weight: UIFont.Weight) -> UIFont {
            UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }

        init(content: Content) {
            self.content = content
            timeline = ReelTimeline(meters: content.meters)
            brand = NSAttributedString(string: "JOG LOCK", attributes: [
                .font: Self.font("ArchivoTrack-Heading", 46, fallback: .heavy), .kern: 8.3,
                .foregroundColor: Self.ink,
            ])
            numberFont = Self.font("ArchivoTrack-Display", 216, fallback: .black)
            unitFont = Self.font("ArchivoTrack-Heading", 69, fallback: .heavy)
            labelFont = .systemFont(ofSize: 42, weight: .heavy)
            italicFont = Self.font("ArchivoTrack-DisplayItalic", 150, fallback: .black)
            let symbol = UIImage.SymbolConfiguration(pointSize: 72, weight: .bold)
            shut = UIImage(systemName: "lock.fill", withConfiguration: symbol)
            open = UIImage(systemName: "lock.open.fill", withConfiguration: symbol)
            treadmill = UIImage(systemName: "figure.run.treadmill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 420))
        }

        func draw(at t: Double, into buffer: CVPixelBuffer) {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else {
                return
            }
            // UIKit's way up: the origin at the top left.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }

            drawMap(context)
            drawRoute(context, at: t)
            brand.draw(at: CGPoint(x: Self.margin, y: Self.margin))
            drawLock(context, at: t)
            drawCount(at: t)
            drawProgress(context, at: t)
        }

        /// A made-up neighbourhood: ground, water, a park and streets.
        private func drawMap(_ context: CGContext) {
            let u = Self.unit
            Self.ground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let water = UIBezierPath()
            water.move(to: CGPoint(x: 0, y: 380 * u))
            water.addCurve(to: CGPoint(x: 180 * u, y: 388 * u),
                           controlPoint1: CGPoint(x: 60 * u, y: 360 * u), controlPoint2: CGPoint(x: 110 * u, y: 410 * u))
            water.addCurve(to: CGPoint(x: 280 * u, y: 360 * u),
                           controlPoint1: CGPoint(x: 250 * u, y: 366 * u), controlPoint2: CGPoint(x: 260 * u, y: 350 * u))
            water.addLine(to: CGPoint(x: size.width, y: size.height))
            water.addLine(to: CGPoint(x: 0, y: size.height))
            water.close()
            Self.water.setFill()
            water.fill()
            Self.park.setFill()
            UIBezierPath(roundedRect: CGRect(x: 22 * u, y: 170 * u, width: 90 * u, height: 80 * u), cornerRadius: 9 * u).fill()

            Self.street.setStroke()
            let wide = UIBezierPath()
            for y in [140.0, 300.0] {
                wide.move(to: CGPoint(x: 0, y: y * u))
                wide.addLine(to: CGPoint(x: size.width, y: y * u))
            }
            for x in [70.0, 170.0, 240.0] {
                wide.move(to: CGPoint(x: x * u, y: 0))
                wide.addLine(to: CGPoint(x: x * u, y: size.height))
            }
            wide.lineWidth = 10 * u
            wide.stroke()
            let narrow = UIBezierPath()
            narrow.move(to: CGPoint(x: 0, y: 220 * u))
            narrow.addLine(to: CGPoint(x: size.width, y: 220 * u))
            narrow.move(to: CGPoint(x: 120 * u, y: 0))
            narrow.addLine(to: CGPoint(x: 120 * u, y: size.height))
            narrow.move(to: CGPoint(x: 0, y: 70 * u))
            narrow.addLine(to: CGPoint(x: size.width, y: 190 * u))
            narrow.lineWidth = 4 * u
            narrow.stroke()
        }

        private func drawRoute(_ context: CGContext, at t: Double) {
            guard !content.route.isEmpty else {
                treadmill?.withTintColor(Self.ink.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
                    .draw(in: fitted(treadmill?.size ?? .zero, in: routeBox.insetBy(dx: 120, dy: 120)))
                return
            }
            stroke(content.route, color: Self.ink.withAlphaComponent(0.12), width: 12, in: context)
            let drawn = ReelRoute.partial(content.route, share: ReelTimeline.drawn(at: t))
            stroke(drawn, color: Self.card, width: 38, in: context)
            stroke(drawn, color: Self.ink, width: 19, in: context)
            if let head = drawn.last(where: { !$0.isEmpty })?.last {
                let dot = UIBezierPath(ovalIn: CGRect(x: point(head).x - 35, y: point(head).y - 35, width: 70, height: 70))
                Self.red.setFill()
                dot.fill()
                Self.card.setStroke()
                dot.lineWidth = 12
                dot.stroke()
            }
        }

        private func stroke(_ segments: [[Point2D]], color: UIColor, width: CGFloat, in context: CGContext) {
            let path = UIBezierPath()
            for segment in segments {
                guard let first = segment.first else { continue }
                path.move(to: point(first))
                for next in segment.dropFirst() {
                    path.addLine(to: point(next))
                }
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }

        private func point(_ point: Point2D) -> CGPoint {
            CGPoint(x: routeBox.minX + point.x, y: routeBox.minY + point.y)
        }

        /// The lock in the top corner: it shakes, then springs open in red,
        /// if the run met its target.
        private func drawLock(_ context: CGContext, at t: Double) {
            let opened = content.unlocked ? ReelTimeline.open(at: t) : 0
            let shake = content.unlocked ? ReelTimeline.shake(at: t) : 0
            let bounce = opened > 0.5 ? 1 + 0.18 * sin(min(1, (t - ReelTimeline.shakeEnds) / 0.5) * .pi) : 1
            let radius: CGFloat = 75
            context.saveGState()
            context.translateBy(x: size.width - Self.margin - radius, y: Self.margin + radius - 14)
            context.rotate(by: CGFloat(shake * .pi / 180))
            context.scaleBy(x: bounce, y: bounce)
            (opened > 0.5 ? Self.red : Self.ink).setFill()
            UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).fill()
            if let image = (opened > 0.5 ? open : shut)?.withTintColor(Self.card, renderingMode: .alwaysOriginal) {
                image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                      width: image.size.width, height: image.size.height))
            }
            context.restoreGState()
        }

        /// Bottom left: "TIKTOK IN 1.11 KM" counting down, then "UNLOCKED".
        private func drawCount(at t: Double) {
            let shown = timeline.shownMeters(at: t)
            let app = content.app.uppercased()
            let label: String
            if content.targetMeters <= 0 {
                label = "KM RUN"
            } else if content.unlocked && ReelTimeline.titleOpacity(at: t) > 0 {
                label = app
            } else {
                label = "\(app) IN"
            }
            NSAttributedString(string: label, attributes: [
                .font: labelFont, .kern: 5, .foregroundColor: Self.ink,
            ]).draw(at: CGPoint(x: Self.margin, y: 1450))

            let titled = ReelTimeline.titleOpacity(at: t)
            if content.unlocked && titled > 0 {
                NSAttributedString(string: "UNLOCKED", attributes: [
                    .font: italicFont, .kern: -6, .foregroundColor: Self.redText.withAlphaComponent(titled),
                ]).draw(at: CGPoint(x: Self.margin - 8, y: 1530))
                return
            }
            let meters = content.targetMeters > 0 ? max(0, content.targetMeters - shown) : shown
            let number = NSAttributedString(string: String(format: "%.2f", meters / 1_000), attributes: [
                .font: numberFont, .kern: -8.6, .foregroundColor: Self.ink,
            ])
            number.draw(at: CGPoint(x: Self.margin - 10, y: 1500))
            let unit = NSAttributedString(string: "KM", attributes: [.font: unitFont, .foregroundColor: Self.ink])
            let width = number.size().width
            unit.draw(at: CGPoint(x: Self.margin + width, y: 1500 + numberFont.ascender - unitFont.ascender))
        }

        private func drawProgress(_ context: CGContext, at t: Double) {
            let track = CGRect(x: Self.margin, y: size.height - 54 - 15, width: size.width - Self.margin * 2, height: 15)
            Self.ink.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 7.5).fill()
            var done = track
            done.size.width *= CGFloat(min(1, max(0, t / ReelTimeline.seconds)))
            Self.ink.setFill()
            UIBezierPath(roundedRect: done, cornerRadius: 7.5).fill()
        }

        private func fitted(_ size: CGSize, in box: CGRect) -> CGRect {
            guard size.width > 0, size.height > 0 else { return box }
            let scale = min(box.width / size.width, box.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            return CGRect(x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        }
    }
}

/// "Make a reel" for a finished run, then watch it and share it.
struct ReelButton: View {
    let run: RunSummary
    @ObservedObject private var settings = AppSettings.shared
    @State private var making = false
    @State private var progress = 0.0
    @State private var reel: Reel?
    @State private var failed = false

    struct Reel: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        Button {
            Task { await make() }
        } label: {
            if making {
                ProgressView(value: progress)
                    .tint(JL.ink)
                    .padding(.horizontal, 8)
            } else {
                Text("Make a reel")
                    .font(.body.weight(.bold))
            }
        }
        .buttonStyle(.jlOutlineWide)
        .disabled(making)
        .sheet(item: $reel) { reel in
            ReelPreview(url: reel.url)
        }
        .alert("Couldn't make the reel", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again, or share the run as a picture.")
        }
    }

    private func make() async {
        making = true
        progress = 0
        defer { making = false }
        do {
            let url = try await ReelMaker.make(run, app: settings.nemesis) { value in
                Task { @MainActor in progress = value }
            }
            reel = Reel(url: url)
        } catch {
            failed = true
        }
    }
}

/// "Your reel": the finished video playing on a loop, with Share.
struct ReelPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("Your reel")
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
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: JL.ink.opacity(0.22), radius: 22, y: 20)
            }
            Text("\(Int(ReelTimeline.seconds)) seconds · 1080 × 1920")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(JL.ink2)
            Spacer(minLength: 0)
            ShareLink(item: url, preview: SharePreview("My Jog Lock run")) {
                Label("Share the reel", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.jlPrimary)
            Text("Save it to Photos from the share sheet to post it on TikTok or Instagram.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(JL.paper.ignoresSafeArea())
        .onAppear {
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.play()
            self.player = player
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}
