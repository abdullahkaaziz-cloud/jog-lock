import Foundation
import Testing
@testable import JogLockCore

@Suite("Shoe mileage")
struct ShoeTests {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)

    @Test("Runs count once, to the pair being worn")
    func credit() {
        var rack = ShoeRack()
        let pegasus = rack.add(name: " Pegasus ", startMeters: 100_000, id: "p", at: Self.now)
        #expect(pegasus.name == "Pegasus")
        #expect(rack.active?.id == "p")
        _ = rack.credit(run: "a", meters: 5_000)
        _ = rack.credit(run: "a", meters: 4_000)    // a lower figure is ignored
        _ = rack.credit(run: "a", meters: 6_000)    // the run's final figure replaces it
        #expect(rack.active?.meters == 106_000)
    }

    @Test("A run started in one pair stays with it")
    func runStaysWithPair() {
        var rack = ShoeRack()
        rack.add(name: "Old", id: "old", at: Self.now)
        _ = rack.credit(run: "a", meters: 3_000)
        rack.add(name: "New", id: "new", at: Self.now)
        _ = rack.credit(run: "a", meters: 5_000)
        #expect(rack.shoes.first { $0.id == "new" }?.meters == 0)
        #expect(rack.shoes.first { $0.id == "old" }?.meters == 3_000)
    }

    @Test("A heads-up at 80% of the limit, and again at the limit")
    func alerts() {
        var rack = ShoeRack()
        // 80% of 650 km is 520 km.
        rack.add(name: "Pegasus", startMeters: 515_000, limitMeters: 650_000, id: "p", at: Self.now)
        let first = rack.credit(run: "a", meters: 10_000)
        let second = rack.credit(run: "b", meters: 10_000)
        let third = rack.credit(run: "c", meters: 200_000)
        let fourth = rack.credit(run: "d", meters: 1_000)
        #expect(first == .nearlyDone(name: "Pegasus", meters: 525_000))
        #expect(second == nil)
        #expect(third == .done(name: "Pegasus", meters: 735_000))
        #expect(fourth == nil)
        #expect(ShoeAlert.done(name: "Pegasus", meters: 735_000).title == "Time for new shoes")
        #expect(ShoeAlert.nearlyDone(name: "Pegasus", meters: 525_000).body.hasPrefix("Pegasus have done 525 km."))
    }

    @Test("Retired pairs aren't worn; no pair means nothing's credited")
    func retire() {
        var rack = ShoeRack()
        rack.add(name: "Pegasus", id: "p", at: Self.now)
        rack.retire("p", at: Self.now)
        #expect(rack.active == nil)
        let credited = rack.credit(run: "a", meters: 5_000)
        #expect(credited == nil)
        rack.wear("p")
        #expect(rack.active == nil)
        rack.add(name: "Clifton", id: "c", at: Self.now)
        rack.wear(nil)
        #expect(rack.active == nil)
        rack.wear("c")
        #expect(rack.active?.name == "Clifton")
    }

    @Test("Names and limits have sensible floors")
    func limits() {
        var rack = ShoeRack()
        let shoe = rack.add(name: "  ", limitMeters: 1_000, id: "x", at: Self.now)
        #expect(shoe.name == "My shoes")
        #expect(shoe.limitMeters == 50_000)
        rack.update("x", name: "Speedgoat", limitMeters: 800_000)
        #expect(rack.active?.name == "Speedgoat")
        #expect(rack.active?.limitMeters == 800_000)
        rack.remove("x")
        #expect(rack.shoes.isEmpty)
    }

    @Test("Saved and read back")
    func coding() throws {
        var rack = ShoeRack()
        rack.add(name: "Pegasus", id: "p", at: Self.now)
        _ = rack.credit(run: "a", meters: 5_000)
        let again = try JSONDecoder().decode(ShoeRack.self, from: JSONEncoder().encode(rack))
        #expect(again == rack)
    }
}
