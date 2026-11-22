//
//  ContentView.swift
//  JogLockTracker
//

import JogLockCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var tracker: RunTracker
    @State private var confirmStop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusPill

                    if let warning = tracker.warning {
                        Banner(text: warning, systemImage: "exclamationmark.triangle.fill", tint: .orange) {
                            tracker.clearWarning()
                        }
                    }
                    if let diagnostic = tracker.diagnostic {
                        Banner(text: diagnostic, systemImage: "location.slash.fill", tint: .red, onClose: nil)
                    }

                    DistanceRing(meters: tracker.gateTotals.countedMeters + tracker.gateTotals.pendingMeters,
                                 targetKm: tracker.isActive ? tracker.runTargetKm : tracker.targetKm,
                                 reached: tracker.countedTargetReached && tracker.isActive)

                    statsRow
                    comparisonCard

                    if !tracker.isActive {
                        targetStepper
                    }

                    controlButton

                    if !tracker.isActive, let run = tracker.lastFinishedRun {
                        lastRunCard(run)
                    }

                    if !tracker.isActive {
                        howToCard
                    }
                }
                .padding()
            }
            .navigationTitle("Jog Tracker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RunListView()
                    } label: {
                        Label("Runs", systemImage: "list.bullet")
                    }
                }
            }
            .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop and save", role: .destructive) { tracker.stop() }
                Button("Keep going", role: .cancel) {}
            }
        }
    }

    // MARK: - Pieces

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.15), in: Capsule())
    }

    private var statusText: String {
        switch tracker.status {
        case .idle:
            return tracker.lastFinishedRun == nil ? "Ready" : "Run saved"
        case .requestingPermission:
            return "Waiting for permission…"
        case .waitingForGPS:
            let need = Int(EngineSettings.standard.warmupAccuracy)
            if let accuracy = tracker.lastAccuracy {
                return "Getting GPS… ±\(Int(accuracy.rounded())) m (need ±\(need) m)"
            }
            return "Getting GPS…"
        case .tracking:
            return "Tracking - go!"
        case .paused:
            return "Paused - standing still"
        }
    }

    private var statusColor: Color {
        switch tracker.status {
        case .idle: return .gray
        case .requestingPermission, .waitingForGPS: return .orange
        case .tracking: return .green
        case .paused: return .yellow
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatTile(title: "Time", value: elapsedText(at: context.date))
            }
            StatTile(title: "Pace /km", value: paceText)
            StatTile(title: "GPS accuracy", value: accuracyText)
        }
    }

    private var comparisonCard: some View {
        let s = tracker.snapshot
        let g = tracker.gateTotals
        return VStack(alignment: .leading, spacing: 10) {
            Text("Distance")
                .font(.headline)
            CompareRow(label: "Counted (steps checked)", meters: g.countedMeters, emphasised: true)
            if g.pendingMeters > 0 {
                CompareRow(label: "Checking steps", meters: g.pendingMeters, emphasised: false)
            }
            if g.noStepsMeters > 0 {
                CompareRow(label: "Not counted: too few steps", meters: g.noStepsMeters, emphasised: false)
            }
            if g.vehicleMeters > 0 {
                CompareRow(label: "Not counted: car or bike", meters: g.vehicleMeters, emphasised: false)
            }
            Divider()
            CompareRow(label: "GPS, cleaned", meters: s.cleanMeters, emphasised: false)
            CompareRow(label: "GPS, raw", meters: s.rawMeters, emphasised: false)
            Divider()
            HStack {
                Text("Steps")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(g.steps)")
                    .monospacedDigit()
            }
            .font(.footnote)
            HStack {
                Text("GPS fixes")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(s.fixCount) received · \(droppedCount(s)) dropped")
                    .monospacedDigit()
            }
            .font(.footnote)
            if !s.rejected.isEmpty {
                Text(droppedBreakdown(s))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var targetStepper: some View {
        Stepper(value: $tracker.targetKm, in: 0.25...20, step: 0.25) {
            HStack {
                Label("Unlock target", systemImage: "lock.fill")
                Spacer()
                Text("\(Format.km(tracker.targetKm)) km")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var controlButton: some View {
        if tracker.isActive {
            Button(role: .destructive) {
                confirmStop = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        } else {
            Button {
                tracker.start()
            } label: {
                Label("Start run", systemImage: "figure.run")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func lastRunCard(_ run: RunSummary) -> some View {
        NavigationLink {
            RunDetailView(run: run)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last run")
                        .font(.headline)
                    Text(Self.lastRunLine(run))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("Add Strava's distance and share the files")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    static func lastRunLine(_ run: RunSummary) -> String {
        guard let counted = run.countedMeters else {
            return "\(Format.km(run.cleanMeters / 1000)) km cleaned · \(Format.km(run.rawMeters / 1000)) raw"
        }
        return "\(Format.km(counted / 1000)) km counted · \(Format.km(run.cleanMeters / 1000)) km GPS"
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Test run")
                .font(.headline)
            Text("1. Tap Start at your start point and wait for \"GPS ready\".")
            Text("2. Start Strava too, then run. Lock the phone as usual.")
            Text("3. Stop both at the same spot, then add Strava's distance to the run.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Formatting

    private func elapsedText(at date: Date) -> String {
        Format.elapsed(now: date,
                       activeSince: tracker.isActive ? tracker.startedAt : nil,
                       lastRun: tracker.lastFinishedRun)
    }

    private var paceText: String {
        let s = tracker.snapshot
        guard s.cleanMeters >= 50, s.movingSeconds > 0 else { return "--" }
        return Format.duration(s.movingSeconds / (s.cleanMeters / 1000))
    }

    private var accuracyText: String {
        guard let accuracy = tracker.lastAccuracy else { return "--" }
        return "±\(Int(accuracy.rounded())) m"
    }

    private func droppedCount(_ s: EngineSnapshot) -> Int {
        s.rejected.values.reduce(0, +)
    }

    private func droppedBreakdown(_ s: EngineSnapshot) -> String {
        s.rejected
            .sorted { $0.value > $1.value }
            .map { "\(Format.reason($0.key)) \($0.value)" }
            .joined(separator: " · ")
    }
}

// MARK: - Small views

struct DistanceRing: View {
    let meters: Double
    let targetKm: Double
    let reached: Bool

    var body: some View {
        let progress = min(1, meters / max(1, targetKm * 1000))
        let title: String = reached ? "Unlocked" : "Unlock at \(Format.km(targetKm)) km"
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(reached ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            VStack(spacing: 2) {
                Text(String(format: "%.2f", meters / 1000))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("km")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Label(title, systemImage: reached ? "lock.open.fill" : "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(reached ? Color.green : Color.secondary)
                    .padding(.top, 6)
            }
        }
        .frame(width: 260, height: 260)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Distance")
        .accessibilityValue("\(Format.km(meters / 1000)) of \(Format.km(targetKm)) kilometres. \(reached ? "Apps unlocked" : "Apps locked")")
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

struct CompareRow: View {
    let label: String
    let meters: Double
    let emphasised: Bool

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(emphasised ? .semibold : .regular)
            Spacer()
            Text(String(format: "%.3f km", meters / 1000))
                .monospacedDigit()
                .fontWeight(emphasised ? .semibold : .regular)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.3f kilometres", meters / 1000))
    }
}

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    let onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .environmentObject(RunTracker.shared)
}
