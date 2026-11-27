import Testing
@testable import JogLockCore

/// A runner sending the planner an update every second.
private struct Runner {
    var planner = PepTalkPlanner()
    var target: Double
    var choices = PepTalkChoices.all
    var slowingAllowed = true
    var pace = 3.0
    var t = 0.0
    var meters = 0.0
    var talks: [(t: Double, meters: Double, moment: PepMoment)] = []

    init(target: Double, choices: PepTalkChoices = .all, slowingAllowed: Bool = true) {
        self.target = target
        self.choices = choices
        self.slowingAllowed = slowingAllowed
    }

    var moments: [PepMoment] { talks.map(\.moment) }

    /// Moves at `speed` m/s for `seconds`.
    mutating func go(_ speed: Double, for seconds: Int) {
        for _ in 0..<seconds {
            t += 1
            meters += speed
            if let moment = planner.moment(at: t, meters: meters, pace: pace, target: target,
                                           choices: choices, slowingAllowed: slowingAllowed) {
                talks.append((t, meters, moment))
            }
        }
    }
}

@Suite("Pep talks")
struct PepTalkTests {
    @Test("The last 100 m gets one talk, with 100 m or less to go")
    func lastStretch() throws {
        var run = Runner(target: 1_000)
        run.go(3, for: 400)
        #expect(run.moments == [.lastStretch])
        let talk = try #require(run.talks.first)
        #expect(talk.meters >= 900 && talk.meters < 1_000)
    }

    @Test("Runs shorter than 300 m are all last stretch, so no talk")
    func shortTarget() {
        var run = Runner(target: 250)
        run.go(3, for: 120)
        #expect(run.talks.isEmpty)
    }

    @Test("With every switch off, nothing is said")
    func switchedOff() {
        var run = Runner(target: 2_000, choices: .none)
        run.go(3, for: 240)
        run.go(1.5, for: 120)
        run.go(0, for: 60)
        run.go(3, for: 300)
        #expect(run.talks.isEmpty)
    }

    @Test("Slowing gets one talk per slow patch, and another after speeding back up")
    func slowing() {
        var run = Runner(target: 5_000)
        run.go(3, for: 240)
        run.go(2, for: 200)
        #expect(run.moments == [.slowing])
        run.go(3, for: 60)
        run.go(2, for: 60)
        #expect(run.moments == [.slowing, .slowing])
    }

    @Test("Nothing about slowing in the first three minutes")
    func slowingWaits() {
        var run = Runner(target: 5_000)
        run.go(3, for: 60)
        run.go(1.5, for: 110)
        #expect(run.talks.isEmpty)
    }

    @Test("No slowing talks on a 5K plan run: walking is part of the plan")
    func fiveKPlan() {
        var run = Runner(target: 5_000, slowingAllowed: false)
        run.go(3, for: 240)
        run.go(2, for: 200)
        #expect(run.talks.isEmpty)
    }

    @Test("Stopping gets one talk after 15 s still, once per stop, 2 minutes apart")
    func stopped() throws {
        var run = Runner(target: 5_000)
        run.go(3, for: 60)
        run.go(0, for: 40)
        #expect(run.moments == [.stopped])
        #expect(try #require(run.talks.first).t == 75)
        run.go(3, for: 30)
        run.go(0, for: 70)
        #expect(run.moments == [.stopped, .stopped])
        #expect(try #require(run.talks.last).t == 195)
        run.go(0, for: 200)
        #expect(run.moments == [.stopped, .stopped])
    }

    @Test("A stop in the first 50 m doesn't count")
    func stopAtStart() {
        var run = Runner(target: 5_000)
        run.go(0, for: 60)
        run.go(3, for: 10)
        run.go(0, for: 30)
        #expect(run.talks.isEmpty)
    }

    @Test("Slowing into a stop is a stop, not slowing")
    func slowIntoStop() {
        var run = Runner(target: 5_000)
        run.go(3, for: 240)
        run.go(0, for: 30)
        #expect(run.moments == [.stopped])
    }

    @Test("Past the target there's no more pushing")
    func pastTarget() {
        var run = Runner(target: 600)
        run.go(3, for: 220)
        run.go(0, for: 60)
        run.go(1, for: 200)
        #expect(run.moments == [.lastStretch])
    }

    @Test("A gap while the app was asleep isn't read as a stop or a slowdown")
    func asleep() {
        var run = Runner(target: 5_000)
        run.go(3, for: 240)
        run.t += 300
        run.meters += 900
        run.go(3, for: 10)
        #expect(run.talks.isEmpty)
    }

    @Test("Six different lines for each moment, short enough to hear mid-stride")
    func lines() {
        for moment in PepMoment.allCases {
            let lines = PepTalkLines.lines(for: moment)
            #expect(lines.count == 6)
            #expect(Set(lines).count == lines.count)
            #expect(lines.allSatisfy { !$0.isEmpty && $0.count <= 140 })
        }
        #expect(PepTalkLines.line(.stopped, index: -1) == PepTalkLines.lines(for: .stopped).last)
        #expect(PepTalkLines.line(.slowing, index: 6) == PepTalkLines.lines(for: .slowing).first)
        #expect(Set((0..<18).map(PepTalkLines.sample(index:))).count == 18)
    }
}
