//
//  BuddiesView.swift
//  JogLockTracker
//
//  Lock buddy: make a team and send the invite link, see how far your
//  buddy has run today, change the mode or leave. The rules are in core
//  (TeamMode); the syncing is LockBuddies.
//

import JogLockCore
import SwiftUI

struct BuddiesView: View {
    @ObservedObject private var buddies = LockBuddies.shared
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TeamMode = .together
    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            Form {
                if let membership = buddies.membership {
                    team(membership)
                } else {
                    newTeam
                }
                Section {
                    Text("Your buddy sees your first name and how far you've run today, through iCloud. Nothing else is shared, and there's no Jog Lock server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lock buddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Lock buddy", isPresented: problemShown) {
                Button("OK") { buddies.problem = nil }
            } message: {
                Text(buddies.problem ?? "")
            }
            .task {
                await buddies.sync(reason: "screen")
            }
        }
    }

    @ViewBuilder
    private var newTeam: some View {
        Section {
            TextField("Your first name", text: $buddies.name)
                .textContentType(.givenName)
        } footer: {
            Text("So your buddy knows it's you.")
        }
        Section {
            Picker("How it works", selection: $mode) {
                ForEach(TeamMode.allCases, id: \.self) { mode in
                    Text(Self.title(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(Self.explanation(mode))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Section {
            Button {
                Task { await buddies.create(mode: mode) }
            } label: {
                Label("Make a team and invite a buddy", systemImage: "person.2.fill")
            }
            .disabled(buddies.busy)
        } footer: {
            Text("You'll get a link to send them. They need Jog Lock and iCloud.")
        }
    }

    @ViewBuilder
    private func team(_ membership: LockBuddies.Membership) -> some View {
        Section("Your team") {
            if let buddy = buddies.buddy {
                LabeledContent(buddy.name, value: Self.progress(buddy, today: lock.today))
            } else {
                Text("Waiting for your buddy to join. Until they do, your lock works as usual.")
                    .foregroundStyle(.secondary)
            }
            if membership.role == .owner {
                Picker("Mode", selection: Binding(get: { membership.mode }, set: { new in
                    Task { await buddies.setMode(new) }
                })) {
                    ForEach(TeamMode.allCases, id: \.self) { mode in
                        Text(Self.title(mode)).tag(mode)
                    }
                }
            } else {
                LabeledContent("Mode", value: Self.title(membership.mode))
            }
            Text(Self.explanation(membership.mode))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if membership.role == .owner, let url = buddies.inviteURL {
            Section {
                ShareLink(item: url, subject: Text("Be my Jog Lock buddy"),
                          message: Text("Join my Jog Lock team: our apps unlock when we run.")) {
                    Label("Send the invite link", systemImage: "square.and.arrow.up")
                }
            }
        }
        Section {
            Button(membership.role == .owner ? "End the team" : "Leave the team", role: .destructive) {
                confirmLeave = true
            }
            .disabled(buddies.busy)
        } footer: {
            Text("Your lock goes back to your own running. Apps already open today stay open.")
        }
        .confirmationDialog(membership.role == .owner ? "End the team for both of you?" : "Leave the team?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(membership.role == .owner ? "End the team" : "Leave", role: .destructive) {
                Task { await buddies.leave() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { buddies.problem != nil }, set: { if !$0 { buddies.problem = nil } })
    }

    static func title(_ mode: TeamMode) -> String {
        switch mode {
        case .together: "Together"
        case .forEachOther: "For each other"
        }
    }

    static func explanation(_ mode: TeamMode) -> String {
        switch mode {
        case .together:
            "You both run your own distance. Your apps open once you've both done it, so you're each other's reason to go."
        case .forEachOther:
            "You run for each other. Your apps open when your buddy has run your distance, and your running opens theirs."
        }
    }

    static func progress(_ buddy: BuddyDay, today: LockDay) -> String {
        guard buddy.day == today else { return "Not run yet today" }
        if buddy.met && buddy.target <= 0 { return "Rest day" }
        let ran = buddy.meters < 10 ? "0 km" : Format.shortDistance(buddy.meters)
        return buddy.met ? "Done: \(ran)" : "\(ran) of \(Format.shortDistance(buddy.target))"
    }
}
