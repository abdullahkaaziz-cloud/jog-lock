//
//  BuddiesView.swift
//  JogLockTracker
//
//  A lock buddy: a friend whose running and yours open each other's apps,
//  Together (you both run) or For each other (their run opens your apps).
//  Shared through iCloud: a first name and today's distance, nothing else.
//

import JogLockCore
import SwiftUI

/// The buddy screen in a sheet, for Today.
struct BuddiesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BuddiesScreen()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The buddy screen: you and your buddy today, how it works, the invite,
/// and leaving. Before a team, making one.
struct BuddiesScreen: View {
    @ObservedObject private var buddies = LockBuddies.shared
    @EnvironmentObject private var lock: AppLock
    @State private var mode: TeamMode = .together
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let membership = buddies.membership {
                    team(membership)
                } else {
                    newTeam
                }
                Text("Shared through iCloud: your first name and today's distance. Nothing else, and there's no Jog Lock server.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .jlScreen()
        .navigationTitle("Lock buddy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Lock buddy", isPresented: problemShown) {
            Button("OK") { buddies.problem = nil }
        } message: {
            Text(buddies.problem ?? "")
        }
        .task {
            await buddies.sync(reason: "screen")
        }
    }

    // MARK: - No team yet

    @ViewBuilder
    private var newTeam: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Your first name")
            TextField("So your buddy knows it's you", text: $buddies.name)
                .textContentType(.givenName)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        howItWorks(selection: $mode, canChange: true)
        Button {
            Task { await buddies.create(mode: mode) }
        } label: {
            Label("Make a team", systemImage: "person.2.fill")
        }
        .buttonStyle(.jlInk)
        .disabled(buddies.busy)
        Text("You'll get a link to send them. They need Jog Lock and iCloud.")
            .font(.footnote)
            .foregroundStyle(JL.ink2)
    }

    // MARK: - In a team

    @ViewBuilder
    private func team(_ membership: LockBuddies.Membership) -> some View {
        let ledger = lock.ledger
        let buddy = buddies.buddy
        let theirs = buddy.flatMap { $0.day == lock.today ? $0 : nil }
        VStack(spacing: 14) {
            person(name: "You", initial: buddies.displayName,
                   meters: ledger.ranMeters, target: ledger.targetMeters)
            if let buddy {
                person(name: buddy.name, initial: buddy.name, meters: theirs?.meters ?? 0,
                       target: theirs?.target ?? ledger.targetMeters)
            } else {
                Text("Waiting for your buddy to join. Until they do, your lock works as usual.")
                    .font(.subheadline)
                    .foregroundStyle(JL.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        if let buddy {
            Text(standing(membership.mode, buddy: buddy, theirs: theirs, ledger: ledger))
                .font(.subheadline)
        }
        howItWorks(selection: Binding(get: { membership.mode }, set: { new in
            Task { await buddies.setMode(new) }
        }), canChange: membership.role == .owner)
        JLList {
            if membership.role == .owner, let url = buddies.inviteURL {
                ShareLink(item: url, subject: Text("Be my Jog Lock buddy"),
                          message: Text("Join my Jog Lock team: our apps unlock when we run.")) {
                    JLListRow(title: "Invite link", detail: "Share", chevron: true)
                }
                .buttonStyle(.plain)
            }
            Button {
                confirmLeave = true
            } label: {
                Text(membership.role == .owner ? "End the team" : "Leave \(membership.ownerName)'s lock")
                    .foregroundStyle(JL.redText)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(buddies.busy)
        }
        .confirmationDialog(membership.role == .owner ? "End the team for both of you?" : "Leave the team?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(membership.role == .owner ? "End the team" : "Leave", role: .destructive) {
                Task { await buddies.leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your lock goes back to your own running. Apps already open today stay open.")
        }
    }

    /// One of the two of you: initial, name, a bar and "1.2/3".
    private func person(name: String, initial: String, meters: Double, target: Double) -> some View {
        HStack(spacing: 12) {
            BuddyAvatar(name: initial.isEmpty ? name : initial, size: 36)
            Text(name)
                .font(.headline)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: target > 0 ? min(1, meters / target) : 1)
                .tint(JL.ink)
            Text("\(Format.tenths(meters))/\(Format.shortDistance(target).replacingOccurrences(of: " km", with: ""))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    /// "You both run to unlock. Sam is 0.9 km away. You're 1.8 km away."
    private func standing(_ mode: TeamMode, buddy: BuddyDay, theirs: BuddyDay?, ledger: LockLedger) -> AttributedString {
        var lead = AttributedString(mode == .together ? "You both run to unlock. " : "You run for each other. ")
        lead.font = Font.subheadline.weight(.bold)
        let theirLeft = theirs.map { max(0, $0.target - $0.meters) }
        var parts: [String] = []
        if let theirLeft {
            parts.append(theirLeft > 0 ? "\(buddy.name) is \(Format.shortDistance(theirLeft)) away." : "\(buddy.name) has run today.")
        } else {
            parts.append("\(buddy.name) hasn't run yet today.")
        }
        parts.append(ledger.isTargetMet ? "You've run today." : "You're \(Format.shortDistance(ledger.remainingMeters)) away.")
        var rest = AttributedString(parts.joined(separator: " "))
        rest.foregroundColor = JL.ink2
        return lead + rest
    }

    private func howItWorks(selection: Binding<TeamMode>, canChange: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How it works")
            HStack(spacing: 4) {
                ForEach(TeamMode.allCases, id: \.self) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(Self.title(option))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(selection.wrappedValue == option ? JL.card : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChange)
                }
            }
            .padding(4)
            .background(JL.sand, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(Self.explanation(selection.wrappedValue) + (canChange ? "" : " Your buddy chooses how it works."))
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
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
