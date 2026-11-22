//
//  ContentView.swift
//  JogLockTracker
//

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

                    DistanceRing(meters: tracker.snapshot.cleanMeters,
                                 targetKm: tracker.isActive ? tracker.runTargetKm : tracker.targetKm,
                                 reached: tracker.cleanTargetReached && tracker.isActive)

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
        return VStack(alignment: .leading, spacing: 10) {
            Text("Same run, three ways")
                .font(.headline)
            CompareRow(label: "Jog Lock (cleaned)", meters: s.cleanMeters, emphasised: true)
            CompareRow(label: "Speed-based", meters: s.speedMeters, emphasised: false)
            CompareRow(label: "Raw, no clean-up", meters: s.rawMeters, emphasised: false)
            Divider()
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
                    Text("\(Format.km(run.cleanMeters / 1000)) km cleaned · \(Format.km(run.speedMeters / 1000)) speed · \(Format.km(run.rawMeters / 1000)) raw")
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
        guard tracker.isActive, let start = tracker.startedAt else { return "0:00" }
        return Format.duration(date.timeIntervalSince(start))
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
            }
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

enum Format {
    static func km(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func reason(_ key: String) -> String {
        switch key {
        case FixDecision.rejectedLowAccuracy.rawValue: return "weak signal"
        case FixDecision.rejectedJump.rawValue: return "jumps"
        case FixDecision.rejectedOutOfOrder.rawValue: return "duplicates"
        case FixDecision.rejectedInvalid.rawValue: return "invalid"
        default: return key
        }
    }

    static func percent(_ value: Double, versus reference: Double) -> String {
        guard reference > 0 else { return "" }
        return String(format: "%+.1f%%", (value - reference) / reference * 100)
    }
}

#Preview {
    ContentView()
        .environmentObject(RunTracker.shared)
}
