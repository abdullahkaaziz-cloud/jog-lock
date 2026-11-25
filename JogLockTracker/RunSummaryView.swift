//
//  RunSummaryView.swift
//  JogLockTracker
//
//  Right after a run: the route, how far, how it was counted, the shoes it
//  went on, and the ways to share it. Opens once the run is saved, unless
//  the run unlocked the apps, when the unlock moment comes first.
//

import JogLockCore
import SwiftUI

struct RunSummaryView: View {
    let run: RunSummary
    let onClose: () -> Void

    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var shoes = ShoeStore.shared
    @State private var segments: [[Coordinate]] = []
    @State private var files: [URL] = []
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .frame(height: 340)
                    panel
                        .padding(.top, -40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .background(JL.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $sharing) {
                ShareRunView(run: run)
            }
            .task(id: run.id) {
                segments = await ShareCards.segments(for: run)
                let id = run.id
                files = await Task.detached(priority: .utility) {
                    RunStore.onDevice.shareableFiles(for: id)
                }.value
            }
        }
    }

    private var meters: Double {
        run.countedMeters ?? run.cleanMeters
    }

    private var seconds: TimeInterval {
        run.endedAt.timeIntervalSince(run.startedAt)
    }

    // MARK: - Map

    private var header: some View {
        ZStack(alignment: .top) {
            if run.mode == .treadmill {
                JL.infield
                TrackView(progress: 1, style: .done) {
                    Image(systemName: "figure.run.treadmill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(JL.paper)
                }
                .frame(width: 300, height: 190)
                .padding(.top, 90)
            } else {
                RouteMap(segments: segments, interactive: false)
            }
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                Spacer()
                Button {
                    sharing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(JLRoundButtonStyle(fill: JL.card))
            .shadow(color: JL.ink.opacity(0.15), radius: 8, y: 3)
            .padding(.horizontal, 20)
            .padding(.top, 62)
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(JL.line)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(run.startedAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(run.startedAt.formatted(date: .omitted, time: .shortened))")
                    .jlCaption()
                HStack {
                    Text(Format.runTitle(hour: Calendar.current.component(.hour, from: run.startedAt)))
                        .font(.jlHeading(26, relativeTo: .title))
                    Spacer()
                    if run.countedTargetAt != nil && lock.isEnabled {
                        Label("Unlocked", systemImage: "lock.open.fill")
                            .font(.caption.weight(.heavy))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(JL.card)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(JL.red, in: Capsule())
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.km(meters / 1_000))
                    .jlNumber(64)
                Text("KM")
                    .font(.jlHeading(22))
            }
            HStack(alignment: .top) {
                stat(Format.duration(seconds), "time")
                stat(pace, "pace /km")
                stat(run.steps.map { $0.formatted() } ?? "--", "steps")
            }
            counted
            if let shoe = shoes.rack.shoes.first(where: { $0.runs[run.id] != nil }) {
                NavigationLink {
                    ShoesView()
                } label: {
                    shoeCard(shoe)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button("Share card") {
                    sharing = true
                }
                .buttonStyle(.jlInk)
                ReelButton(run: run)
            }
            JLList {
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    JLListRow(title: "Add Strava's distance", detail: "Compare", chevron: true)
                }
                .buttonStyle(.plain)
                ShareLink(items: files) {
                    JLListRow(title: "Export run files", detail: "GPX, JSON", chevron: true, isLast: true)
                }
                .buttonStyle(.plain)
                .disabled(files.isEmpty)
            }
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JL.paper, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
    }

    private var pace: String {
        guard meters >= 50 else { return "--" }
        let moving = run.movingSeconds > 0 ? run.movingSeconds : seconds
        return Format.duration(moving / (meters / 1_000))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.jlHeading(22))
                .monospacedDigit()
            Text(label)
                .font(.footnote)
                .foregroundStyle(JL.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Counted on foot, thrown out, and the GPS distance next to it.
    private var counted: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How it was counted")
            row("Counted on foot", run.countedMeters ?? 0, strong: true)
            if run.mode == .treadmill {
                row("Not counted (car, bike or still)", run.rejectedMeters ?? 0)
            } else {
                row("Not counted (car, bike)", run.vehicleMeters ?? 0)
                if let noSteps = run.noStepsMeters, noSteps > 0 {
                    row("Not counted (too few steps)", noSteps)
                }
                row("GPS distance, cleaned", run.cleanMeters)
            }
            Text("Distance only counts when your steps match your speed.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ label: String, _ meters: Double, strong: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Format.km(meters / 1_000)) km")
                .monospacedDigit()
        }
        .font(.subheadline.weight(strong ? .bold : .regular))
        .foregroundStyle(strong ? JL.ink : JL.ink2)
    }

    private func shoeCard(_ shoe: Shoe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("**\(shoe.name)** +\(Format.tenths(shoe.runs[run.id] ?? 0)) km")
                Spacer()
                Text("\(Int(shoe.meters / 1_000)) of \(Int(shoe.limitMeters / 1_000)) km")
                    .monospacedDigit()
                    .foregroundStyle(JL.ink2)
            }
            .font(.subheadline)
            ProgressView(value: min(1, shoe.wear))
                .tint(shoe.wear >= 1 ? JL.red : JL.ink)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
