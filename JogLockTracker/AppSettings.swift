//
//  AppSettings.swift
//  JogLockTracker
//
//  Small preferences the runner sets once: which app they're running for
//  (used in voice lines, the lock-screen countdown and share cards), the
//  voice coach and its pep talks.
//

import Foundation
import JogLockCore

enum VoiceStyle: String, CaseIterable, Identifiable {
    case chipmunk
    case robot
    case deep
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chipmunk: "Chipmunk"
        case .robot: "Robot"
        case .deep: "Movie trailer"
        case .normal: "Normal"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let nemesisChoices = ["TikTok", "Instagram", "YouTube", "Snapchat", "X", "Reddit", VoiceLines.defaultApp]

    @Published var nemesis: String {
        didSet { UserDefaults.standard.set(nemesis, forKey: Keys.nemesis) }
    }
    @Published var voiceOn: Bool {
        didSet { UserDefaults.standard.set(voiceOn, forKey: Keys.voiceOn) }
    }
    @Published var voiceStyle: VoiceStyle {
        didSet { UserDefaults.standard.set(voiceStyle.rawValue, forKey: Keys.voiceStyle) }
    }
    /// Pep talks, each off until switched on: in the last 100 m, when the
    /// runner slows right down, when they stop.
    @Published var pepLastStretch: Bool {
        didSet { UserDefaults.standard.set(pepLastStretch, forKey: Keys.pepLastStretch) }
    }
    @Published var pepSlowing: Bool {
        didSet { UserDefaults.standard.set(pepSlowing, forKey: Keys.pepSlowing) }
    }
    @Published var pepStopped: Bool {
        didSet { UserDefaults.standard.set(pepStopped, forKey: Keys.pepStopped) }
    }

    var pepChoices: PepTalkChoices {
        PepTalkChoices(lastStretch: pepLastStretch, slowing: pepSlowing, stopped: pepStopped)
    }

    private enum Keys {
        static let nemesis = "nemesisApp"
        static let voiceOn = "voiceOn"
        static let voiceStyle = "voiceStyle"
        static let pepLastStretch = "pepLastStretch"
        static let pepSlowing = "pepSlowing"
        static let pepStopped = "pepStopped"
    }

    private init() {
        let defaults = UserDefaults.standard
        nemesis = defaults.string(forKey: Keys.nemesis) ?? VoiceLines.defaultApp
        voiceOn = defaults.object(forKey: Keys.voiceOn) as? Bool ?? true
        voiceStyle = VoiceStyle(rawValue: defaults.string(forKey: Keys.voiceStyle) ?? "") ?? .chipmunk
        pepLastStretch = defaults.bool(forKey: Keys.pepLastStretch)
        pepSlowing = defaults.bool(forKey: Keys.pepSlowing)
        pepStopped = defaults.bool(forKey: Keys.pepStopped)
    }
}
