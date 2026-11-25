//
//  RunOnlyCard.swift
//  JogLockTracker
//
//  Run-only apps: a podcast, music or audiobook app that opens only while
//  you're running. It's temptation bundling: people who could only hear
//  their audiobook at the gym went more often (Milkman et al., 2014).
//

import FamilyControls
import SwiftUI

struct RunOnlyCard: View {
    @EnvironmentObject private var lock: AppLock
    @State private var picking = false
    @State private var draft = FamilyActivitySelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Run-only apps", systemImage: "headphones")
                .font(.headline)
            if lock.hasRunOnly {
                LockedAppsRow(selection: lock.runOnlySelection)
                Text(lock.runOnlyOpen
                     ? "Open while you run. They lock again when you stop."
                     : "Locked. Start a run and they open until you stop.")
                    .font(.footnote)
                    .foregroundStyle(lock.runOnlyOpen ? .green : .secondary)
                Button("Change run-only apps", action: choose)
                    .font(.subheadline)
            } else {
                Text("Pick a podcast, music or audiobook app you can only open while you're running. Your favourite show becomes the reason to go.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: choose) {
                    Label("Choose run-only apps", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .familyActivityPicker(isPresented: $picking, selection: $draft)
        .onChange(of: picking) { _, isOpen in
            if !isOpen {
                lock.chooseRunOnly(draft)
            }
        }
    }

    private func choose() {
        Task {
            guard await lock.authorize() else { return }
            draft = lock.runOnlySelection
            picking = true
        }
    }
}
