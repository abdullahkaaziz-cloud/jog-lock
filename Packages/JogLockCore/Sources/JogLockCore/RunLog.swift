//
//  RunLog.swift
//  JogLockCore
//
//  The records a run leaves behind: one LogLine per line of raw.jsonl, and a
//  RunSummary in summary.json. New fields must be optional so older logs
//  still decode.
//

import Foundation

/// One line of raw.jsonl. Fields that are nil are left out of the JSON.
public struct LogLine: Codable, Equatable, Sendable {
    public var type: String            // "header", "fix" or "event"
    public var t: Double               // seconds since 1970

    // Fix fields
    public var lat: Double?
    public var lon: Double?
    public var alt: Double?
    public var hAcc: Double?
    public var vAcc: Double?
    public var speed: Double?
    public var speedAcc: Double?
    public var course: Double?
    public var courseAcc: Double?
    public var stationary: Bool?
    public var simulated: Bool?
    public var accessory: Bool?
    public var decision: String?
    public var clean: Double?          // running totals after this fix (metres)
    public var speedDist: Double?
    public var raw: Double?

    // Step and motion fields ("steps" and "motion" lines)
    public var steps: Int?             // pedometer count since the run started
    public var pedMeters: Double?      // the iPhone's own distance estimate from steps
    public var cadence: Double?        // steps per second
    public var activity: MotionKind?
    public var confidence: MotionConfidence?

    // Totals on the "stop" event (metres)
    public var counted: Double?
    public var noSteps: Double?
    public var vehicle: Double?

    // Header and event fields
    public var name: String?
    public var detail: String?
    public var device: String?
    public var os: String?
    public var app: String?
    public var settings: EngineSettings?
    public var gate: StepGateSettings?
    public var targetKm: Double?

    public init(type: String, t: Double) {
        self.type = type
        self.t = t
    }
}

public struct RunSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var endedAt: Date
    public var targetKm: Double
    public var cleanMeters: Double
    public var speedMeters: Double
    public var rawMeters: Double
    public var movingSeconds: Double
    public var fixCount: Int
    public var acceptedCount: Int
    public var rejected: [String: Int]
    public var cleanTargetAt: Date?
    public var speedTargetAt: Date?
    public var device: String
    public var os: String
    public var appVersion: String
    public var settings: EngineSettings
    public var stravaKm: Double?
    public var trueKm: Double?
    public var note: String?
    // Anti-cheat results; nil for runs recorded before the step check existed.
    public var countedMeters: Double?
    public var noStepsMeters: Double?
    public var vehicleMeters: Double?
    public var countedTargetAt: Date?
    public var steps: Int?
    public var pedometerMeters: Double?

    public init(id: String, startedAt: Date, endedAt: Date, targetKm: Double,
                cleanMeters: Double, speedMeters: Double, rawMeters: Double,
                movingSeconds: Double, fixCount: Int, acceptedCount: Int,
                rejected: [String: Int], cleanTargetAt: Date? = nil, speedTargetAt: Date? = nil,
                device: String, os: String, appVersion: String, settings: EngineSettings,
                stravaKm: Double? = nil, trueKm: Double? = nil, note: String? = nil,
                countedMeters: Double? = nil, noStepsMeters: Double? = nil, vehicleMeters: Double? = nil,
                countedTargetAt: Date? = nil, steps: Int? = nil, pedometerMeters: Double? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetKm = targetKm
        self.cleanMeters = cleanMeters
        self.speedMeters = speedMeters
        self.rawMeters = rawMeters
        self.movingSeconds = movingSeconds
        self.fixCount = fixCount
        self.acceptedCount = acceptedCount
        self.rejected = rejected
        self.cleanTargetAt = cleanTargetAt
        self.speedTargetAt = speedTargetAt
        self.device = device
        self.os = os
        self.appVersion = appVersion
        self.settings = settings
        self.stravaKm = stravaKm
        self.trueKm = trueKm
        self.note = note
        self.countedMeters = countedMeters
        self.noStepsMeters = noStepsMeters
        self.vehicleMeters = vehicleMeters
        self.countedTargetAt = countedTargetAt
        self.steps = steps
        self.pedometerMeters = pedometerMeters
    }
}

extension GPSFix {
    /// The fix recorded on a "fix" line, or nil for any other line.
    public init?(line: LogLine) {
        guard line.type == "fix", let lat = line.lat, let lon = line.lon else { return nil }
        self.init(t: line.t,
                  lat: lat,
                  lon: lon,
                  hAcc: line.hAcc ?? -1,
                  speed: line.speed ?? -1,
                  speedAcc: line.speedAcc ?? -1,
                  stationary: line.stationary ?? false)
    }
}

/// Encoders and decoders that read and write run files the same way everywhere.
public enum RunCoding {
    /// For raw.jsonl lines: compact, one object per line.
    public static func lineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    /// For summary.json: readable, stable key order.
    public static func summaryEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    /// Decodes raw.jsonl text, skipping lines that don't parse (for example a
    /// line cut short when the app was killed mid-write).
    public static func decodeLines(_ text: String) -> [LogLine] {
        let decoder = decoder()
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(LogLine.self, from: Data(line.utf8))
        }
    }
}
