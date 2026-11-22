import Testing
@testable import JogLockCore

@Suite("Geo.distance")
struct GeoTests {
    // Expected values come from Tools/replay.py, so these also check that the
    // Swift engine and its Python mirror measure distance identically.

    @Test("A thousandth of a degree north at 51.5° N is 111.258 m")
    func northStep() {
        let d = Geo.distance(lat1: 51.5, lon1: -0.12, lat2: 51.501, lon2: -0.12)
        #expect(abs(d - 111.25784318332427) < 1e-6)
    }

    @Test("A thousandth of a degree east at 51.5° N is 69.441 m")
    func eastStep() {
        let d = Geo.distance(lat1: 51.5, lon1: -0.12, lat2: 51.5, lon2: -0.119)
        #expect(abs(d - 69.44051663973542) < 1e-6)
    }

    @Test("Crossing the 180° meridian takes the short way round")
    func dateLine() {
        let across = Geo.distance(lat1: 0, lon1: 179.9995, lat2: 0, lon2: -179.9995)
        let atGreenwich = Geo.distance(lat1: 0, lon1: -0.0005, lat2: 0, lon2: 0.0005)
        #expect(abs(across - atGreenwich) < 1e-3)
        #expect(abs(across - 111.3195) < 1e-3)
    }

    @Test("The same point is zero metres away")
    func samePoint() {
        #expect(Geo.distance(lat1: 10, lon1: 20, lat2: 10, lon2: 20) == 0)
    }
}
