//
//  VoiceSpeaker.swift
//  JogLockTracker
//
//  Speaks the coach's lines. Music ducks while it talks and comes back
//  afterwards. Needs the "audio" background mode to talk while the phone
//  is locked.
//

import AVFoundation
import JogLockCore

// Only used from the main actor (RunTracker). The iOS 26 SDK makes the
// delegate protocol Sendable, and AVSpeechSynthesizer isn't marked Sendable.
final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, style: VoiceStyle) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        synthesizer.speak(Self.utterance(text, style: style))
    }

    static func utterance(_ text: String, style: VoiceStyle) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let standard = AVSpeechSynthesisVoice(language: "en-GB")
        switch style {
        case .normal:
            utterance.voice = standard
        case .chipmunk:
            utterance.voice = standard
            utterance.pitchMultiplier = 1.9
            utterance.rate = 0.56
        case .deep:
            utterance.voice = standard
            utterance.pitchMultiplier = 0.55
            utterance.rate = 0.44
        case .robot:
            if let robot = AVSpeechSynthesisVoice(identifier: "com.apple.speech.synthesis.voice.Zarvox") {
                utterance.voice = robot
            } else {
                utterance.voice = standard
                utterance.pitchMultiplier = 0.7
                utterance.rate = 0.42
            }
        }
        return utterance
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
