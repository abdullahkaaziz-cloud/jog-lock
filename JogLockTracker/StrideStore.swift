//
//  StrideStore.swift
//  JogLockTracker
//
//  The stride samples learned from outdoor runs, kept in UserDefaults. An
//  actor, so learning after a run and the first-launch backfill can't
//  overwrite each other.
//

import Foundation
import JogLockCore

actor StrideStore {
    static let shared = StrideStore()

    private let key = "strideSamples"
    private let maxSamples = 300      // 30-second windows: about 2.5 hours of running
    private let backfillRuns = 10

    func model() -> StrideModel? {
        StrideModel.fit(samples())
    }

    /// Adds what an outdoor run teaches, and returns the updated model.
    func learn(fromRun id: String, in store: RunStore) -> StrideModel? {
        let new = StrideCalibration.samples(from: store.readLines(id: id))
        if !new.isEmpty {
            save(Array((samples() + new).suffix(maxSamples)))
        }
        return model()
    }

    /// The current model. If nothing has been learned yet, learns from the
    /// most recent outdoor runs already on the phone first.
    func loadOrBackfill(from store: RunStore) -> StrideModel? {
        guard samples().isEmpty else { return model() }
        let runs = store.allSummaries()
            .filter { $0.mode != .treadmill && $0.countedMeters != nil }
            .prefix(backfillRuns)
        var learned: [StrideSample] = []
        for run in runs.reversed() {   // oldest first, so the newest samples are kept
            learned += StrideCalibration.samples(from: store.readLines(id: run.id))
        }
        if !learned.isEmpty {
            save(Array(learned.suffix(maxSamples)))
        }
        return model()
    }

    private func samples() -> [StrideSample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let samples = try? JSONDecoder().decode([StrideSample].self, from: data) else {
            return []
        }
        return samples
    }

    private func save(_ samples: [StrideSample]) {
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
