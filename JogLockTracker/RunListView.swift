//
//  RunListView.swift
//  JogLockTracker
//

import JogLockCore
import SwiftUI

struct RunListView: View {
    @State private var runs: [RunSummary] = []
    @State private var wrapping = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    wrapping = true
                } label: {
                    Label("Your month", systemImage: "sparkles")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AllRunsMapView()
                } label: {
                    Label("Map", systemImage: "map")
                }
            }
        }
        .sheet(isPresented: $wrapping) {
            WrappedView()
        }
        .onAppear { runs = RunStore.onDevice.allSummaries() }
    }
}

struct RunRow: View {
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text(ContentView.lastRunLine(run))
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
    @State private var segments: [[Coordinate]] = []

    init(run: RunSummary) {
        _run = State(initialValue: run)
        _stravaText = State(initialValue: run.stravaKm.map { String(format: "%.2f", $0) } ?? "")
        _trueText = State(initialValue: run.trueKm.map { String(format: "%.2f", $0) } ?? "")
        _noteText = State(initialValue: run.note ?? "")
    }

    private var rejectedMeters: (kind: NiceTryKind, meters: Double)? {
        let vehicle = run.vehicleMeters ?? run.rejectedMeters ?? 0
        let noSteps = run.noStepsMeters ?? 0
        if vehicle >= 100 && vehicle >= noSteps {
            return (.vehicle, vehicle)
        }
        return noSteps >= 100 ? (.noSteps, noSteps) : nil
    }

    var body: some View {
        Form {
            if !segments.isEmpty {
                Section {
                    RouteMap(segments: segments)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ShareRunButton(run: run)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                ReelButton(run: run)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let rejected = rejectedMeters {
                Section {
                    NiceTryBanner(kind: rejected.kind, meters: rejected.meters, onClose: nil)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("Distance") {
                if run.mode == .treadmill {
                    distanceRow("Counted (treadmill)", run.countedMeters ?? 0)
                    distanceRow("Not counted: car, bike or still", run.rejectedMeters ?? 0)
                } else {
                    if let counted = run.countedMeters {
                        distanceRow("Counted (steps checked)", counted)
                        distanceRow("Not counted: too few steps", run.noStepsMeters ?? 0)
                        distanceRow("Not counted: car or bike", run.vehicleMeters ?? 0)
                    }
                    distanceRow("GPS, cleaned", run.cleanMeters)
                    distanceRow("GPS, raw", run.rawMeters)
                }
                if let steps = run.steps {
                    LabeledContent("Steps", value: "\(steps)")
                }
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
                if let at = run.countedTargetAt {
                    LabeledContent("Target hit (counted)", value: "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
                }
                if let at = run.cleanTargetAt {
                    LabeledContent("Target hit (GPS)", value: "after " + Format.duration(at.timeIntervalSince(run.startedAt)))
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
        .task(id: run.id) {
            let id = run.id
            segments = await Task.detached(priority: .userInitiated) {
                Route.segments(from: RunStore.onDevice.readLines(id: id))
            }.value
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { shareURLs = RunStore.onDevice.shareableFiles(for: run.id) }
        .onChange(of: stravaText) { saved = false }
        .onChange(of: trueText) { saved = false }
        .onChange(of: noteText) { saved = false }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RunStore.onDevice.delete(id: run.id)
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
        try? RunStore.onDevice.save(run)
        shareURLs = RunStore.onDevice.shareableFiles(for: run.id)
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
