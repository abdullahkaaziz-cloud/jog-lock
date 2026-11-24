//
//  AppSettings.swift
//  JogLockTracker
//
//  Small preferences the runner sets once: which app they're running for
//  (used in voice lines, the lock-screen countdown and share cards) and the
//  voice coach.
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

    private enum Keys {
        static let nemesis = "nemesisApp"
        static let voiceOn = "voiceOn"
        static let voiceStyle = "voiceStyle"
    }

    private init() {
        let defaults = UserDefaults.standard
        nemesis = defaults.string(forKey: Keys.nemesis) ?? VoiceLines.defaultApp
        voiceOn = defaults.object(forKey: Keys.voiceOn) as? Bool ?? true
        voiceStyle = VoiceStyle(rawValue: defaults.string(forKey: Keys.voiceStyle) ?? "") ?? .chipmunk
    }
}
