import Foundation
import Testing
@testable import JogLockCore

@Suite("Run-only apps")
struct RunOnlyTests {
    static let start = Date(timeIntervalSince1970: 1_795_000_000)

    static func state() -> LockState {
        var state = LockState(now: start)
        state.runOnly = Data([1, 2, 3])
        return state
    }

    @Test("A run opens them until it ends")
    func openAndClose() {
        var state = Self.state()
        #expect(!state.runOnlyOpen(at: Self.start))
        #expect(state.openRunOnly(run: "a", monitor: "m1", at: Self.start) == nil)
        #expect(state.runOnlyOpen(at: Self.start.addingTimeInterval(60)))
        // Another run's end leaves them open; this run's end locks them.
        #expect(state.closeRunOnly(run: "b") == nil)
        #expect(state.runOnlyOpen(at: Self.start.addingTimeInterval(60)))
        #expect(state.closeRunOnly(run: "a")?.monitor == "m1")
        #expect(!state.runOnlyOpen(at: Self.start.addingTimeInterval(60)))
    }

    @Test("With no run going, whichever run left them open is closed")
    func closeAny() {
        var state = Self.state()
        _ = state.openRunOnly(run: "a", monitor: "m1", at: Self.start)
        #expect(state.closeRunOnly(run: nil)?.run == "a")
        #expect(state.runOpen == nil)
    }

    @Test("They lock again after four hours, even if the app never sees the run end")
    func longestRun() {
        var state = Self.state()
        _ = state.openRunOnly(run: "a", monitor: "m1", at: Self.start)
        let later = Self.start.addingTimeInterval(LockState.longestRun)
        #expect(!state.expireRunWindow(at: later.addingTimeInterval(-1)))
        #expect(!state.runOnlyOpen(at: later))
        #expect(state.expireRunWindow(at: later))
        #expect(state.runOpen == nil)
    }

    @Test("Only the current window's monitor closes it; a new run replaces the old window")
    func monitors() {
        var state = Self.state()
        _ = state.openRunOnly(run: "a", monitor: "m1", at: Self.start)
        #expect(state.openRunOnly(run: "b", monitor: "m2", at: Self.start)?.monitor == "m1")
        #expect(!state.runMonitorEnded("m1"))
        #expect(state.runOnlyOpen(at: Self.start))
        #expect(state.runMonitorEnded("m2"))
        #expect(!state.runOnlyOpen(at: Self.start))
    }

    @Test("Without run-only apps nothing is open")
    func noneChosen() {
        var state = LockState(now: Self.start)
        _ = state.openRunOnly(run: "a", monitor: "m1", at: Self.start)
        #expect(!state.runOnlyOpen(at: Self.start))
    }

    @Test("Saved and read back; a state from before reads with none")
    func coding() throws {
        var state = Self.state()
        _ = state.openRunOnly(run: "a", monitor: "m1", at: Self.start)
        let again = try JSONDecoder().decode(LockState.self, from: JSONEncoder().encode(state))
        #expect(again == state)
        let old = try JSONDecoder().decode(LockState.self, from: JSONEncoder().encode(LockState(now: Self.start)))
        #expect(old.runOnly == nil)
        #expect(old.runOpen == nil)
    }

    @Test("A run-only app's shield says it's for runs")
    func shieldText() {
        #expect(ShieldText.runOnlyTitle(app: "Spotify") == "Spotify is for runs")
        #expect(ShieldText.runOnlyTitle(app: nil) == "This app is for runs")
    }
}
