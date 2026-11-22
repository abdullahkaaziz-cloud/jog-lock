import Foundation
import Testing
@testable import JogLockCore

@Suite("RunStore")
final class RunStoreTests {
    let store = RunStore(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("JogLockCoreTests-\(UUID().uuidString)", isDirectory: true))

    deinit {
        try? FileManager.default.removeItem(at: store.root)
    }

    private func summary(id: String, startedAt: TimeInterval) -> RunSummary {
        RunSummary(id: id,
                   startedAt: Date(timeIntervalSince1970: startedAt),
                   endedAt: Date(timeIntervalSince1970: startedAt + 1260),
                   targetKm: 2.5,
                   cleanMeters: 3012.2,
                   speedMeters: 2863.4,
                   rawMeters: 3048.5,
                   movingSeconds: 1243,
                   fixCount: 1264,
                   acceptedCount: 512,
                   rejected: [FixDecision.rejectedJump.rawValue: 2],
                   device: "iPhone17,5",
                   os: "27.0",
                   appVersion: "0.1 (1)",
                   settings: .standard,
                   stravaKm: 3.0)
    }

    private func fixLine(t: Double, lat: Double, decision: FixDecision) -> LogLine {
        var line = LogLine(type: "fix", t: t)
        line.lat = lat
        line.lon = -0.12
        line.hAcc = 5
        line.decision = decision.rawValue
        return line
    }

    @Test("A saved summary loads back unchanged")
    func summaryRoundTrip() throws {
        let original = summary(id: "run-a", startedAt: 1_700_000_000)
        try store.save(original)
        #expect(store.loadSummary(id: "run-a") == original)
    }

    @Test("Runs are listed newest first")
    func newestFirst() throws {
        try store.save(summary(id: "run-old", startedAt: 1_700_000_000))
        try store.save(summary(id: "run-new", startedAt: 1_700_100_000))
        #expect(store.allSummaries().map(\.id) == ["run-new", "run-old"])
    }

    @Test("Deleting a run removes its folder")
    func delete() throws {
        try store.save(summary(id: "run-a", startedAt: 1_700_000_000))
        store.delete(id: "run-a")
        #expect(store.allSummaries().isEmpty)
    }

    @Test("Log lines written during a run read back in order, also after reopening")
    func writerAppends() throws {
        try store.createDirectory(for: "run-a")
        let url = store.rawLogURL(for: "run-a")

        let first = try RunLogWriter(url: url)
        first.write(LogLine(type: "header", t: 1))
        first.write(fixLine(t: 2, lat: 51.5, decision: .warmupComplete))
        first.close()

        // The app reopens the log when it resumes a run after being relaunched.
        let second = try RunLogWriter(url: url)
        second.write(fixLine(t: 3, lat: 51.5001, decision: .accepted))
        second.close()

        let lines = store.readLines(id: "run-a")
        #expect(lines.map(\.type) == ["header", "fix", "fix"])
        #expect(lines.map(\.t) == [1, 2, 3])
        #expect(lines[2].decision == FixDecision.accepted.rawValue)
    }

    @Test("A line cut short by the app being killed is skipped")
    func truncatedLine() throws {
        try store.createDirectory(for: "run-a")
        let text = "{\"type\":\"header\",\"t\":1}\n{\"type\":\"fix\",\"t\":2,\"lat\":51.5"
        try text.write(to: store.rawLogURL(for: "run-a"), atomically: true, encoding: .utf8)
        #expect(store.readLines(id: "run-a").map(\.type) == ["header"])
    }

    @Test("The GPX file has an all-fixes track and a counted-points track")
    func gpx() throws {
        let lines = [
            LogLine(type: "header", t: 1),
            fixLine(t: 2, lat: 51.5, decision: .warmupComplete),
            fixLine(t: 3, lat: 51.5001, decision: .pending),
            fixLine(t: 4, lat: 51.5002, decision: .accepted),
        ]
        let gpx = try #require(GPX.make(name: "run-a", lines: lines))
        #expect(gpx.components(separatedBy: "<trk>").count - 1 == 2)
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 3 + 2)
        #expect(GPX.make(name: "run-a", lines: [LogLine(type: "header", t: 1)]) == nil)
    }

    @Test("Run IDs are 'run-' plus the start date and time")
    func runID() {
        let id = RunStore.newRunID(date: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(id.hasPrefix("run-20"))
        #expect(id.count == "run-2023-11-14_22-13-20".count)
    }
}
