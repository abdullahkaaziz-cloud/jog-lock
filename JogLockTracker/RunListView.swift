//
//  RunListView.swift
//  JogLockTracker
//

import SwiftUI

struct RunListView: View {
    @State private var runs: [RunSummary] = []

    var body: some View {
        List {
            ForEach(runs) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunRow(run: run)
                }
            }
        }
        .overlay {
            if runs.isEmpty {
                ContentUnavailableView("No runs yet",
                                       systemImage: "figure.run",
                                       description: Text("Finished runs show up here."))
            }
        }
        .navigationTitle("Runs")
        .onAppear { runs = RunStore.allSummaries() }
    }
}

struct RunRow: View {
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text("\(Format.km(run.cleanMeters / 1000)) km · speed \(Format.km(run.speedMeters / 1000)) · raw \(Format.km(run.rawMeters / 1000))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let strava = run.stravaKm {
                Text("Strava \(Format.km(strava)) km")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var run: RunSummary
    @State private var stravaText: String
    @State private var trueText: String
    @State private var noteText: String
    @State private var shareURLs: [URL] = []
    @State private var saved = false
    @State private var confirmDelete = false

    init(run: RunSummary) {
        _run = State(initialValue: run)
        _stravaText = State(initialValue: run.stravaKm.map { String(format: "%.2f", $0) } ?? "")
        _trueText = State(initialValue: run.trueKm.map { String(format: "%.2f", $0) } ?? "")
        _noteText = State(initialValue: run.note ?? "")
    }

    var body: some View {
        Form {
            Section("Distance") {
                distanceRow("Jog Lock (cleaned)", run.cleanMeters)
                distanceRow("Speed-based", run.speedMeters)
                distanceRow("Raw, no clean-up", run.rawMeters)
            }

            Section {
                TextField("Strava's distance in km, e.g. 1.02", text: $stravaText)
                    .keyboardType(.decimalPad)
                TextField("True distance in km, e.g. 1.00", text: $trueText)
                    .keyboardType(.decimalPad)
                TextField("Notes: route, where the phone was…", text: $noteText, axis: .vertical)
                Button {
                    saveNotes()
                } label: {
                    Text(saved ? "Saved" : "Save")
                }
                .disabled(saved)
            } header: {
                Text("Compare")
            } footer: {
                Text("On a 400 m track, 2.5 laps of lane 1 is exactly 1 km.")
            }

            Section("Run") {
                LabeledContent("Started", value: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Format.duration(run.endedAt.timeIntervalSince(run.startedAt)))
                LabeledContent("Moving time", value: Format.duration(run.movingSeconds))
                LabeledContent("Target", value: "\(Format.km(run.targetKm)) km")
                if let at = run.cleanTargetAt {
                    LabeledContent("Target hit (cleaned)", value: "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
                }
                if let at = run.speedTargetAt {
                    LabeledContent("Target hit (speed)", value: "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
                }
                LabeledContent("GPS fixes", value: "\(run.fixCount)")
                LabeledContent("Dropped", value: droppedText)
                LabeledContent("Phone", value: "\(run.device), iOS \(run.os)")
                LabeledContent("App", value: run.appVersion)
            }

            Section {
                if shareURLs.isEmpty {
                    Text("Preparing files…")
                        .foregroundStyle(.secondary)
                } else {
                    ShareLink(items: shareURLs) {
                        Label("Share run files", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Share")
            } footer: {
                Text("raw.jsonl has every GPS fix, summary.json has the totals and your notes, track.gpx opens in any map tool.")
            }

            Section {
                Button("Delete run", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(run.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { shareURLs = RunStore.shareableFiles(for: run.id) }
        .onChange(of: stravaText) { saved = false }
        .onChange(of: trueText) { saved = false }
        .onChange(of: noteText) { saved = false }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RunStore.delete(id: run.id)
                dismiss()
            }
        }
    }

    private func distanceRow(_ label: String, _ meters: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3f km", meters / 1000))
                    .monospacedDigit()
                if let trueKm = run.trueKm {
                    Text(Format.percent(meters, versus: trueKm * 1000) + " vs true")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let stravaKm = run.stravaKm {
                    Text(Format.percent(meters, versus: stravaKm * 1000) + " vs Strava")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var droppedText: String {
        let total = run.rejected.values.reduce(0, +)
        guard total > 0 else { return "0" }
        let parts = run.rejected
            .sorted { $0.value > $1.value }
            .map { "\(Format.reason($0.key)) \($0.value)" }
        return "\(total) (" + parts.joined(separator: ", ") + ")"
    }

    private func saveNotes() {
        run.stravaKm = Self.parseKm(stravaText)
        run.trueKm = Self.parseKm(trueText)
        run.note = noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText
        RunStore.save(run)
        shareURLs = RunStore.shareableFiles(for: run.id)
        saved = true
    }

    private static func parseKm(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
