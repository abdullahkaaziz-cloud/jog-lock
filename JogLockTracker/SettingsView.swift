//
//  SettingsView.swift
//  JogLockTracker
//

import JogLockCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var lock = AppLock.shared
    @State private var diagnostics: URL?
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
                Section {
                    NavigationLink {
                        ShoesView()
                    } label: {
                        Label("Shoes", systemImage: "shoe.2.fill")
                    }
                } footer: {
                    Text("Kilometres on each pair, with a heads-up when they're getting tired.")
                }
                Section {
                    DisclosureGroup("Make the lock harder to switch off") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Otherwise anyone with your Face ID can turn off Jog Lock's Screen Time access in Settings.")
                            Text("1. Ask someone you trust to set a Screen Time passcode: Settings → Screen Time → Lock Screen Time Settings. Only they should know it.")
                            Text("2. Check it: Settings → Screen Time → Apps with Screen Time Access → turn off Jog Lock. It should ask for their code. Tap Cancel.")
                            Text("If your own Face ID or passcode works instead, it isn't locked down.")
                        }
                        .font(.footnote)
                    }
                    if let diagnostics {
                        ShareLink(item: diagnostics) {
                            Label("Share lock diagnostics", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("App lock")
                } footer: {
                    Text("Diagnostics show what the lock did and when, never which apps you chose or where you ran.")
                }
            }
            .navigationTitle("Settings")
            .task {
                diagnostics = lock.diagnosticsFile()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
