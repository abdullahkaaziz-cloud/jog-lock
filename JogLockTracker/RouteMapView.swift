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
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.location))
                    .stroke(.green, lineWidth: 4)
            }
            if followsUser {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
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
