//
//  RouteMapView.swift
//  JogLockTracker
//
//  Maps of where you ran: one run, the run in progress, or every run.
//

import JogLockCore
import MapKit
import SwiftUI

extension Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct RouteMap: View {
    let segments: [[Coordinate]]
    var followsUser = false
    /// False for a map that's only there to look at, like the top of a run's summary.
    var interactive = true
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.location))
                    .stroke(JL.card, lineWidth: 9)
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.location))
                    .stroke(JL.ink, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            if let start = segments.first?.first {
                Annotation("Start", coordinate: start.location, anchor: .center) {
                    Circle()
                        .fill(JL.red)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(JL.card, lineWidth: 3))
                }
                .annotationTitles(.hidden)
            }
            if followsUser {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onAppear {
            if followsUser {
                position = .userLocation(fallback: .automatic)
            }
        }
    }
}

/// Every outdoor run's route on one map.
struct AllRunsMapView: View {
    @State private var segments: [[Coordinate]]?

    var body: some View {
        Group {
            if let segments {
                if segments.isEmpty {
                    ContentUnavailableView("No routes yet", systemImage: "map",
                                           description: Text("Your outdoor runs show up here."))
                } else {
                    RouteMap(segments: segments)
                        .ignoresSafeArea(edges: .bottom)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Where you've run")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            segments = await Task.detached(priority: .userInitiated) {
                let store = RunStore.onDevice
                return store.allSummaries()
                    .filter { $0.mode != .treadmill }
                    .flatMap { Route.segments(from: store.readLines(id: $0.id)) }
            }.value
        }
    }
}
