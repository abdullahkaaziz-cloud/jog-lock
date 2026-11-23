//
//  SettingsView.swift
//  JogLockTracker
//

import JogLockCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var speaker = VoiceSpeaker()
    @State private var sample = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("I'm running for", selection: $settings.nemesis) {
                        ForEach(AppSettings.nemesisChoices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                } footer: {
                    Text("Used in the voice lines and on your share cards.")
                }
                Section("Voice coach") {
                    Toggle("Talk to me while I run", isOn: $settings.voiceOn)
                    Picker("Voice", selection: $settings.voiceStyle) {
                        ForEach(VoiceStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Button("Play a sample") {
                        let line = VoiceLines.text(for: .progress(meters: 500), app: settings.nemesis,
                                                   remainingMeters: 1_800, variant: sample)
                        speaker.speak(line, style: settings.voiceStyle)
                        sample += 1
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
