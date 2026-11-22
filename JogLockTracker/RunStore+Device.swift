//
//  RunStore+Device.swift
//  JogLockTracker
//

import Foundation
import JogLockCore

extension RunStore {
    /// Runs saved on this iPhone, in Documents/Runs. The Files app shows
    /// them under On My iPhone > Jog Tracker.
    static let onDevice: RunStore = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return RunStore(root: docs.appendingPathComponent("Runs", isDirectory: true))
    }()
}
