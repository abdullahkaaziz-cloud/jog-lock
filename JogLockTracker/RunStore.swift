//
//  RunStore.swift
//  JogLockTracker
//
//  Files for each run, in Documents/Runs/<run id>/:
//    raw.jsonl     every GPS fix and event, one JSON object per line
//    summary.json  totals, settings and your notes (Strava / true distance)
//    track.gpx     made on demand for sharing
//
//  The Documents folder is also visible in the Files app
//  (On My iPhone > Jog Tracker).
//

import Foundation

/// One line of raw.jsonl. Fields that are nil are left out of the JSON.
struct LogLine: Codable {
    var type: String            // "header", "fix" or "event"
    var t: Double               // seconds since 1970

    // Fix fields
    var lat: Double?
    var lon: Double?
    var alt: Double?
    var hAcc: Double?
    var vAcc: Double?
    var speed: Double?
    var speedAcc: Double?
    var course: Double?
    var courseAcc: Double?
    var stationary: Bool?
    var simulated: Bool?
    var accessory: Bool?
    var decision: String?
    var clean: Double?          // running totals after this fix (metres)
    var speedDist: Double?
    var raw: Double?

    // Header and event fields
    var name: String?
    var detail: String?
    var device: String?
    var os: String?
    var app: String?
    var settings: EngineSettings?
    var targetKm: Double?

    init(type: String, t: Double) {
        self.type = type
        self.t = t
    }
}

struct RunSummary: Codable, Identifiable {
    var id: String
    var startedAt: Date
    var endedAt: Date
    var targetKm: Double
    var cleanMeters: Double
    var speedMeters: Double
    var rawMeters: Double
    var movingSeconds: Double
    var fixCount: Int
    var acceptedCount: Int
    var rejected: [String: Int]
    var cleanTargetAt: Date?
    var speedTargetAt: Date?
    var device: String
    var os: String
    var appVersion: String
    var settings: EngineSettings
    var stravaKm: Double?
    var trueKm: Double?
    var note: String?
}

/// Appends lines to raw.jsonl as the run goes, so nothing is lost if the app dies.
final class RunLogWriter {
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private var unsynced = 0

    init(url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let fileHandle = try FileHandle(forWritingTo: url)
        _ = try fileHandle.seekToEnd()
        let jsonEncoder = JSONEncoder()
        jsonEncoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        handle = fileHandle
        encoder = jsonEncoder
    }

    func write(_ line: LogLine) {
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

    func close() {
        try? handle.synchronize()
        try? handle.close()
    }
}

enum RunStore {
    static var runsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Runs", isDirectory: true)
    }

    static func directory(for id: String) -> URL {
        runsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    static func rawLogURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("raw.jsonl")
    }

    static func summaryURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("summary.json")
    }

    static func gpxURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("track.gpx")
    }

    static func newRunID(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "run-" + formatter.string(from: date)
    }

    static func createDirectory(for id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    static func save(_ summary: RunSummary) {
        do {
            try createDirectory(for: summary.id)
            let data = try makeEncoder().encode(summary)
            try data.write(to: summaryURL(for: summary.id), options: .atomic)
        } catch {
            print("Saving summary failed: \(error)")
        }
    }

    static func loadSummary(id: String) -> RunSummary? {
        guard let data = try? Data(contentsOf: summaryURL(for: id)) else { return nil }
        return try? makeDecoder().decode(RunSummary.self, from: data)
    }

    static func allSummaries() -> [RunSummary] {
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: runsDirectory.path) else {
            return []
        }
        return ids.compactMap { loadSummary(id: $0) }.sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    static func readLines(id: String) -> [LogLine] {
        guard let data = try? Data(contentsOf: rawLogURL(for: id)),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = makeDecoder()
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(LogLine.self, from: Data(line.utf8))
        }
    }

    /// The files worth sending for analysis (only ones that exist).
    static func shareableFiles(for id: String) -> [URL] {
        var urls = [rawLogURL(for: id), summaryURL(for: id)]
        if let gpx = makeGPX(id: id) {
            urls.append(gpx)
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Two tracks: every fix as the phone reported it, and the points the
    /// engine actually counted. Open it next to Strava's GPX to compare.
    static func makeGPX(id: String) -> URL? {
        let fixes = readLines(id: id).filter { $0.type == "fix" && $0.lat != nil && $0.lon != nil }
        guard !fixes.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"JogLockTracker\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        out += "  <trk><name>\(id) - all fixes</name><trkseg>\n"
        for line in fixes where (line.hAcc ?? -1) >= 0 {
            out += gpxPoint(line, iso)
        }
        out += "  </trkseg></trk>\n"

        out += "  <trk><name>\(id) - counted points</name>\n"
        var segmentOpen = false
        for line in fixes {
            guard let decision = line.decision else { continue }
            switch decision {
            case FixDecision.warmupComplete.rawValue, FixDecision.gapReset.rawValue, FixDecision.jumpReset.rawValue:
                if segmentOpen { out += "  </trkseg>\n" }
                out += "  <trkseg>\n"
                segmentOpen = true
                out += gpxPoint(line, iso)
            case FixDecision.accepted.rawValue:
                if !segmentOpen {
                    out += "  <trkseg>\n"
                    segmentOpen = true
                }
                out += gpxPoint(line, iso)
            default:
                break
            }
        }
        if segmentOpen { out += "  </trkseg>\n" }
        out += "  </trk>\n</gpx>\n"

        let url = gpxURL(for: id)
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func gpxPoint(_ line: LogLine, _ iso: ISO8601DateFormatter) -> String {
        let time = iso.string(from: Date(timeIntervalSince1970: line.t))
        var s = String(format: "    <trkpt lat=\"%.7f\" lon=\"%.7f\">", line.lat ?? 0, line.lon ?? 0)
        if let alt = line.alt, alt.isFinite {
            s += String(format: "<ele>%.1f</ele>", alt)
        }
        s += "<time>\(time)</time></trkpt>\n"
        return s
    }
}
