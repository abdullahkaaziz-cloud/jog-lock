//
//  RunReel.swift
//  JogLockTracker
//
//  "Make a reel": a 10-second story video of a run (1080 × 1920, 30 fps,
//  H.264) to post on TikTok, Reels or Stories. The route draws itself while
//  the kilometres tick up, the lock shakes and springs open, then "TikTok
//  unlocked". The timing is ReelTimeline (core); the frames are drawn here
//  with Core Graphics and written with AVAssetWriter, on the phone.
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

    /// Everything a frame draws, made once.
    private struct Artwork {
        let content: Content
        let timeline: ReelTimeline
        let header: NSAttributedString
        let counterFont: UIFont
        let titleFont: UIFont
        let smallFont: UIFont
        let shut: UIImage?
        let open: UIImage?
        let treadmill: UIImage?
        let green = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)

        init(content: Content) {
            self.content = content
            timeline = ReelTimeline(meters: content.meters)
            header = NSAttributedString(string: "JOG LOCK", attributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .heavy), .kern: 14,
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
            ])
            let rounded = UIFont.systemFont(ofSize: 170, weight: .black).fontDescriptor.withDesign(.rounded)
            counterFont = rounded.map { UIFont(descriptor: $0, size: 170) } ?? .systemFont(ofSize: 170, weight: .black)
            titleFont = .systemFont(ofSize: 76, weight: .heavy)
            smallFont = .systemFont(ofSize: 38, weight: .semibold)
            let symbol = UIImage.SymbolConfiguration(pointSize: 170, weight: .bold)
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

            drawBackground(context)
            header.draw(at: CGPoint(x: (size.width - header.size().width) / 2, y: 150))
            drawRoute(context, at: t)
            drawCounter(at: t)
            drawLock(context, at: t)
            drawTitle(at: t)
        }

        private func drawBackground(_ context: CGContext) {
            let colors = [UIColor(red: 0.04, green: 0.14, blue: 0.08, alpha: 1).cgColor, UIColor.black.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }

        private func drawRoute(_ context: CGContext, at t: Double) {
            guard !content.route.isEmpty else {
                treadmill?.withTintColor(green.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
                    .draw(in: fitted(treadmill?.size ?? .zero, in: routeBox.insetBy(dx: 120, dy: 120)))
                return
            }
            stroke(content.route, color: UIColor.white.withAlphaComponent(0.13), width: 12, in: context)
            stroke(ReelRoute.partial(content.route, share: ReelTimeline.drawn(at: t)), color: green, width: 18, in: context)
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

        private func drawCounter(at t: Double) {
            let km = timeline.shownMeters(at: t) / 1_000
            let text = NSAttributedString(string: String(format: "%.2f km", km), attributes: [
                .font: counterFont, .foregroundColor: UIColor.white,
            ])
            text.draw(at: CGPoint(x: (size.width - text.size().width) / 2, y: 1270))
        }

        private func drawLock(_ context: CGContext, at t: Double) {
            let opened = ReelTimeline.open(at: t)
            guard let image = (opened > 0.5 ? open : shut)?
                .withTintColor(opened > 0.5 ? green : .white, renderingMode: .alwaysOriginal) else { return }
            let bounce = opened > 0.5 ? 1 + 0.18 * sin(min(1, (t - ReelTimeline.shakeEnds) / 0.5) * .pi) : 1
            context.saveGState()
            context.translateBy(x: size.width / 2, y: 1590)
            context.rotate(by: CGFloat(ReelTimeline.shake(at: t) * .pi / 180))
            context.scaleBy(x: bounce, y: bounce)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
            context.restoreGState()
        }

        private func drawTitle(at t: Double) {
            let alpha = ReelTimeline.titleOpacity(at: t)
            guard alpha > 0 else { return }
            let title = NSAttributedString(string: "\(content.app) unlocked", attributes: [
                .font: titleFont, .foregroundColor: UIColor.white.withAlphaComponent(alpha),
            ])
            title.draw(at: CGPoint(x: (size.width - title.size().width) / 2, y: 1730))
            let minutes = Int((content.seconds / 60).rounded())
            let detail = NSAttributedString(string: "Ran \(Format.shortDistance(content.meters)) for it · \(minutes) min", attributes: [
                .font: smallFont, .foregroundColor: green.withAlphaComponent(alpha),
            ])
            detail.draw(at: CGPoint(x: (size.width - detail.size().width) / 2, y: 1830))
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
        Group {
            if making {
                ProgressView(value: progress) {
                    Text("Making your reel…")
                        .font(.footnote)
                }
            } else {
                Button {
                    Task { await make() }
                } label: {
                    Label("Make a reel", systemImage: "film.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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

/// The finished reel, playing on a loop, with Share.
struct ReelPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                ShareLink(item: url, preview: SharePreview("My Jog Lock run")) {
                    Label("Share the reel", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Text("Save it to Photos from the share sheet to post it on TikTok or Instagram.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Your reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
}
