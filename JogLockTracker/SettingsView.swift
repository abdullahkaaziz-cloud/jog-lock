//
//  SettingsView.swift
//  JogLockTracker
//
//  The Settings tab: you, the voice coach and its pep talks, running (shoes
//  and how runs start), the lock (making it unbreakable, notifications), and
//  help (diagnostics, privacy, testing against Strava).
//

import JogLockCore
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var tracker: RunTracker
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var buddies = LockBuddies.shared
    @ObservedObject private var shoes = ShoeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnostics: URL?
    @State private var speaker = VoiceSpeaker()
    @State private var sample = 0
    @State private var pepSample = Int.random(in: 0..<18)
    @State private var notificationsOn: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.jlHeading(34, relativeTo: .largeTitle))
                        .tracking(-0.7)
                        .padding(.top, 12)
                    group("You") {
                        line("First name", isLast: false) {
                            TextField("Your name", text: $buddies.name)
                                .textContentType(.givenName)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(JL.ink2)
                        }
                        line("I'm running for", note: "Used by the voice coach and share cards", isLast: true) {
                            Picker("I'm running for", selection: $settings.nemesis) {
                                ForEach(AppSettings.nemesisChoices, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                        }
                    }
                    group("Voice coach") {
                        line("Talk to me while I run", isLast: false) {
                            Toggle("Talk to me while I run", isOn: $settings.voiceOn)
                                .labelsHidden()
                                .tint(JL.red)
                        }
                        line("Voice", isLast: false) {
                            Picker("Voice", selection: $settings.voiceStyle) {
                                ForEach(VoiceStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                        }
                        sampleButton {
                            let line = VoiceLines.text(for: .progress(meters: 500), app: settings.nemesis,
                                                       remainingMeters: 1_800, variant: sample)
                            speaker.speak(line, style: settings.voiceStyle)
                            sample += 1
                        }
                    }
                    pepTalks
                    group("Running") {
                        NavigationLink {
                            ShoesView()
                        } label: {
                            JLListRow(title: "Shoes", detail: shoeText, chevron: true)
                        }
                        .buttonStyle(.plain)
                        line("Start runs as", isLast: true) {
                            Picker("Start runs as", selection: $tracker.mode) {
                                Text("Outdoor").tag(RunMode.outdoor)
                                Text("Treadmill").tag(RunMode.treadmill)
                            }
                        }
                    }
                    group("Lock") {
                        NavigationLink {
                            UnbreakableView()
                        } label: {
                            JLListRow(title: "Make it unbreakable", detail: "How to", chevron: true)
                        }
                        .buttonStyle(.plain)
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            JLListRow(title: "Notifications", detail: notificationsOn.map { $0 ? "On" : "Off" }, chevron: true,
                                      isLast: true)
                        }
                        .buttonStyle(.plain)
                    }
                    group("Help") {
                        if let diagnostics {
                            ShareLink(item: diagnostics) {
                                JLListRow(title: "Share lock diagnostics", chevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            JLListRow(title: "Privacy", detail: "Runs stay on this phone", chevron: true)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            StravaTestView()
                        } label: {
                            JLListRow(title: "Test a run against Strava", chevron: true, isLast: true)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Diagnostics show what the lock did and when, never which apps you chose or where you ran.")
                        .font(.footnote)
                        .foregroundStyle(JL.ink2)
                    Text("Jog Lock \(RunTracker.appVersion)")
                        .font(.footnote)
                        .foregroundStyle(JL.ink2)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(JL.ink)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .jlScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                diagnostics = lock.diagnosticsFile()
            }
            .task(id: scenePhase) {
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                notificationsOn = status == .authorized || status == .provisional || status == .ephemeral
            }
        }
    }

    /// A line from a battle, a speech or a fight film at the moments that
    /// count, each switched on here. They need the coach on.
    private var pepTalks: some View {
        VStack(alignment: .leading, spacing: 8) {
            group("Pep talks") {
                line("In the last 100 m", isLast: false) {
                    Toggle("In the last 100 m", isOn: $settings.pepLastStretch)
                        .labelsHidden()
                        .tint(JL.red)
                }
                line("When I slow down", note: "Not on 5K plan runs, where walking is part of the plan", isLast: false) {
                    Toggle("When I slow down", isOn: $settings.pepSlowing)
                        .labelsHidden()
                        .tint(JL.red)
                }
                line("When I stop", isLast: false) {
                    Toggle("When I stop", isOn: $settings.pepStopped)
                        .labelsHidden()
                        .tint(JL.red)
                }
                sampleButton {
                    speaker.speak(PepTalkLines.sample(index: pepSample), style: settings.voiceStyle)
                    pepSample += 1
                }
            }
            .disabled(!settings.voiceOn)
            .opacity(settings.voiceOn ? 1 : 0.5)
            Text(settings.voiceOn
                 ? "Lines from old battles, speeches and poems, and the big moments of fight and war films. They stop once you've run the day's distance."
                 : "Turn on Talk to me while I run to hear pep talks.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
        }
    }

    private func sampleButton(_ play: @escaping () -> Void) -> some View {
        Button(action: play) {
            Label("Play a sample", systemImage: "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(JL.redText)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shoeText: String {
        guard let shoe = shoes.rack.active else { return "Add a pair" }
        return "\(shoe.name) · \(Int(shoe.meters / 1_000)) km"
    }

    /// A labelled group of rows in one white card.
    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            JLList(content: content)
        }
    }

    /// A row with a title, an optional note under it, and a control on the right.
    private func line<Control: View>(_ title: String, note: String? = nil, isLast: Bool,
                                     @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(JL.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control()
                    .tint(JL.ink2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}

/// The steps that make the lock hard to switch off in a weak moment.
struct UnbreakableSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Ask someone you trust to set a Screen Time passcode: Settings → Screen Time → Lock Screen Time Settings. Only they should know it.")
            Text("2. Check it: Settings → Screen Time → Apps with Screen Time Access → turn off Jog Lock. It should ask for their code. Tap Cancel.")
            Text("If your own Face ID or passcode works instead, it isn't locked down.")
        }
    }
}

/// "Make it unbreakable", on its own screen.
struct UnbreakableView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Otherwise anyone with your Face ID can turn off Jog Lock's Screen Time access in Settings, and the lock with it.")
                    .font(.subheadline)
                    .foregroundStyle(JL.ink2)
                UnbreakableSteps()
                    .font(.body)
                    .padding(16)
                    .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .foregroundStyle(JL.ink)
            .padding(20)
        }
        .jlScreen()
        .navigationTitle("Make it unbreakable")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What stays on the phone, and what doesn't.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your runs, routes and steps stay on this iPhone. There's no Jog Lock server to send them to.")
                Text("Screen Time locks the apps you pick. iOS draws their names and icons; Jog Lock never learns which apps they are.")
                Text("A lock buddy sees your first name and today's distance, through your iCloud. Nothing else.")
                Text("Diagnostics, when you share them, say what the lock did and when, never which apps or where you ran.")
            }
            .font(.body)
            .foregroundStyle(JL.ink)
            .padding(20)
        }
        .jlScreen()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How to check Jog Lock's distance against Strava on the same run.
struct StravaTestView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("1. Tap Start run at your start point and wait for the GPS to be ready.")
                Text("2. Start Strava too, then run. Lock the phone as usual.")
                Text("3. Stop both at the same spot, then open the run in Runs and add Strava's distance.")
                Text("On a 400 m track, 2.5 laps of lane 1 is exactly 1 km.")
                    .foregroundStyle(JL.ink2)
            }
            .font(.body)
            .foregroundStyle(JL.ink)
            .padding(20)
        }
        .jlScreen()
        .navigationTitle("Test a run")
        .navigationBarTitleDisplayMode(.inline)
    }
}
