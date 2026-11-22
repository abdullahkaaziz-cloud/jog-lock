//
//  Format.swift
//  JogLockCore
//
//  How distances, times and reasons are shown to the runner.
//

import Foundation

public enum Format {
    public static func km(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func reason(_ key: String) -> String {
        switch key {
        case FixDecision.rejectedLowAccuracy.rawValue: return "weak signal"
        case FixDecision.rejectedJump.rawValue: return "jumps"
        case FixDecision.rejectedOutOfOrder.rawValue: return "duplicates"
        case FixDecision.rejectedInvalid.rawValue: return "invalid"
        default: return key
        }
    }

    public static func percent(_ value: Double, versus reference: Double) -> String {
        guard reference > 0 else { return "" }
        return String(format: "%+.1f%%", (value - reference) / reference * 100)
    }
}
