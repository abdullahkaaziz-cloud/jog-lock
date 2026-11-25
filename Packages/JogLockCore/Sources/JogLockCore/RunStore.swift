//
//  RunStore.swift
//  JogLockCore
//
//  Files for each run, in <root>/<run id>/:
//    raw.jsonl     every GPS fix and event, one JSON object per line
//    summary.json  totals, settings and your notes (Strava / true distance)
//    track.gpx     made on demand for sharing
//
//  The app uses Documents/Runs as the root, which is also visible in the
//  Files app (On My iPhone > Jog Lock). Tests use a temporary folder.
//

import Foundation

/// Appends lines to raw.jsonl as the run goes, so nothing is lost if the app dies.
public final class RunLogWriter {
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private var unsynced = 0

    public init(url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil)
        }
        let fileHandle = try FileHandle(forWritingTo: url)
        _ = try fileHandle.seekToEnd()
        handle = fileHandle
        encoder = RunCoding.lineEncoder()
    }

    public func write(_ line: LogLine) {
        guard var data = try? encoder.encode(line) else { return }
        data.append(0x0A) // newline
        do {
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        unsynced += 1
        if unsynced >= 20 {
            try? handle.synchronize()
            unsynced = 0
        }
    }

    public func close() {
        try? handle.synchronize()
        try? handle.close()
    }
}

public struct RunStore: Sendable {
    /// The folder that holds one sub-folder per run.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    public func rawLogURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("raw.jsonl")
    }

    public func summaryURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("summary.json")
    }

    public func gpxURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("track.gpx")
    }

    public static func newRunID(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "run-" + formatter.string(from: date)
    }

    public func createDirectory(for id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
    }

    public func save(_ summary: RunSummary) throws {
        try createDirectory(for: summary.id)
        let data = try RunCoding.summaryEncoder().encode(summary)
        try data.write(to: summaryURL(for: summary.id), options: .atomic)
    }

    public func loadSummary(id: String) -> RunSummary? {
        guard let data = try? Data(contentsOf: summaryURL(for: id)) else { return nil }
        return try? RunCoding.decoder().decode(RunSummary.self, from: data)
    }

    /// Every saved run, newest first.
    public func allSummaries() -> [RunSummary] {
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return ids.compactMap { loadSummary(id: $0) }.sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: String) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    public func readLines(id: String) -> [LogLine] {
        guard let data = try? Data(contentsOf: rawLogURL(for: id)),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return RunCoding.decodeLines(text)
    }

    /// The files worth sending for analysis (only ones that exist).
    public func shareableFiles(for id: String) -> [URL] {
        var urls = [rawLogURL(for: id), summaryURL(for: id)]
        if let gpx = writeGPX(id: id) {
            urls.append(gpx)
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Writes track.gpx for a run and returns its URL, or nil if the run has no fixes.
    public func writeGPX(id: String) -> URL? {
        guard let gpx = GPX.make(name: id, lines: readLines(id: id)) else { return nil }
        let url = gpxURL(for: id)
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

public enum GPX {
    /// Two tracks: every fix as the phone reported it, and the points the
    /// engine actually counted. Open it next to Strava's GPX to compare.
    public static func make(name: String, lines: [LogLine]) -> String? {
        let fixes = lines.filter { $0.type == "fix" && $0.lat != nil && $0.lon != nil }
        guard !fixes.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeName = escape(name)

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"JogLockTracker\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        out += "  <trk><name>\(safeName) - all fixes</name><trkseg>\n"
        for line in fixes where (line.hAcc ?? -1) >= 0 {
            out += point(line, iso)
        }
        out += "  </trkseg></trk>\n"

        out += "  <trk><name>\(safeName) - counted points</name>\n"
        var segmentOpen = false
        for line in fixes {
            guard let decision = line.decision else { continue }
            switch decision {
            case FixDecision.warmupComplete.rawValue, FixDecision.gapReset.rawValue, FixDecision.jumpReset.rawValue:
                if segmentOpen { out += "  </trkseg>\n" }
                out += "  <trkseg>\n"
                segmentOpen = true
                out += point(line, iso)
            case FixDecision.accepted.rawValue:
                if !segmentOpen {
                    out += "  <trkseg>\n"
                    segmentOpen = true
                }
                out += point(line, iso)
            default:
                break
            }
        }
        if segmentOpen { out += "  </trkseg>\n" }
        out += "  </trk>\n</gpx>\n"
        return out
    }

    private static func point(_ line: LogLine, _ iso: ISO8601DateFormatter) -> String {
        let time = iso.string(from: Date(timeIntervalSince1970: line.t))
        var s = String(format: "    <trkpt lat=\"%.7f\" lon=\"%.7f\">", line.lat ?? 0, line.lon ?? 0)
        if let alt = line.alt, alt.isFinite {
            s += String(format: "<ele>%.1f</ele>", alt)
        }
        s += "<time>\(time)</time></trkpt>\n"
        return s
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
