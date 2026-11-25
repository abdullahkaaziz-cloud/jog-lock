import Foundation
import Testing
@testable import JogLockCore

@Suite("Typed websites")
struct TypedWebsiteTests {
    @Test("A typed address becomes the domain iOS's web filter takes")
    func domains() {
        let cases: [(String, String?)] = [
            ("instagram.com", "instagram.com"), ("  Instagram.COM ", "instagram.com"),
            ("https://www.instagram.com/explore?x=1#top", "instagram.com"), ("http://instagram.com", "instagram.com"),
            ("www.instagram.com/", "instagram.com"), ("instagram.com.", "instagram.com"),
            ("m.youtube.com", "m.youtube.com"), ("bbc.co.uk", "bbc.co.uk"), ("user@x.com:8080/a", "x.com"),
            ("xn--mgbh0fb.xn--kgbechtv", "xn--mgbh0fb.xn--kgbechtv"), ("my-site.io", "my-site.io"),
            ("", nil), ("instagram", nil), ("insta gram.com", nil), ("192.168.1.1", nil), ("-bad.com", nil),
            ("bad-.com", nil), ("a..com", nil), ("*.instagram.com", nil), ("instagram.c", nil), ("www.", nil),
            (String(repeating: "a", count: 64) + ".com", nil),
        ]
        for (typed, expected) in cases {
            #expect(TypedWebsite.domain(from: typed) == expected, "\(typed)")
        }
    }

    @Test("A name in another script becomes its ASCII form")
    func otherScripts() {
        #expect(TypedWebsite.domain(from: "مثال.com") == "xn--mgbh0fb.com")
    }

    @Test("Websites stay under iOS's web filter limit")
    func limit() {
        #expect(TypedWebsite.limit < 50)
    }

    @Test("Adding one: the domain, or why not")
    func adding() {
        #expect(TypedWebsite.adding("https://www.TikTok.com/foryou", to: []) == .success("tiktok.com"))
        #expect(TypedWebsite.adding("tiktok", to: []) == .failure(.notAWebsite))
        #expect(TypedWebsite.adding("www.tiktok.com", to: ["tiktok.com"]) == .failure(.alreadyBlocked("tiktok.com")))
        let full = (1...TypedWebsite.limit).map { "site\($0).com" }
        #expect(TypedWebsite.adding("new.com", to: Array(full.dropLast())) == .success("new.com"))
        #expect(TypedWebsite.adding("new.com", to: full) == .failure(.tooMany))
        // Websites chosen in the picker count towards the same limit.
        #expect(TypedWebsite.adding("new.com", to: Array(full.prefix(30)), picked: 10) == .failure(.tooMany))
    }

    @Test("While locked, websites can only be added")
    func addOnly() {
        #expect(TypedWebsite.adds(["a.com", "b.com"], to: ["a.com"]))
        #expect(TypedWebsite.adds(["a.com"], to: []))
        #expect(!TypedWebsite.adds(["b.com"], to: ["a.com", "b.com"]))
    }

    @Test("Saved websites reach iOS cleaned: once each, valid, at most the limit")
    func cleaned() {
        #expect(TypedWebsite.cleaned(["a.com", "WWW.A.com", "not a site", "b.com"]) == ["a.com", "b.com"])
        let many = (1...60).map { "site\($0).com" }
        #expect(TypedWebsite.cleaned(many).count == TypedWebsite.limit)
        #expect(TypedWebsite.cleaned(many).first == "site1.com")
    }

    @Test("A lock saved before typed websites reads with none, and they're kept from then on")
    func savedState() throws {
        var state = LockState(now: Date(timeIntervalSince1970: 1_795_000_000))
        state.enabled = true
        state.selection = Data([1, 2, 3])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try #require(String(data: try encoder.encode(state), encoding: .utf8))
        #expect(json.contains(",\"websites\":[]"))
        let oldJSON = json.replacingOccurrences(of: ",\"websites\":[]", with: "")
        let old = try JSONDecoder().decode(LockState.self, from: Data(oldJSON.utf8))
        #expect(old.websites.isEmpty)
        #expect(old == state)
        #expect(old.valid)

        state.websites = ["instagram.com", "x.com"]
        let again = try JSONDecoder().decode(LockState.self, from: JSONEncoder().encode(state))
        #expect(again.websites == ["instagram.com", "x.com"])
        #expect(again == state)
    }
}

@Suite("Time on apps")
struct ScreenTimeWeekTests {
    typealias Usage = ScreenTimeWeek.Usage

    static func app(_ key: String, _ name: String? = nil, thisWeek: Bool = true, minutes: Double) -> Usage {
        Usage(key: key, name: name ?? key, thisWeek: thisWeek, seconds: minutes * 60)
    }

    static func site(_ domain: String, thisWeek: Bool = true, minutes: Double) -> Usage {
        Usage(key: domain, name: domain, website: true, thisWeek: thisWeek, seconds: minutes * 60)
    }

    @Test("A day on average: this week's days so far, and last week's seven")
    func averages() {
        let week = ScreenTimeWeek(usage: [
            Self.app("tiktok", minutes: 60), Self.app("tiktok", minutes: 30),
            Self.app("tiktok", thisWeek: false, minutes: 140),
            Self.site("x.com", minutes: 30), Self.site("x.com", thisWeek: false, minutes: 70),
        ], daysThisWeek: 3)
        #expect(week.total == ScreenTimeWeek.Time(thisWeek: 7_200, lastWeek: 12_600, perDay: 2_400, lastWeekPerDay: 1_800))
        #expect(week.apps.map(\.id) == ["tiktok"])
        #expect(week.apps.first?.time.perDay == 1_800)
        #expect(week.apps.first?.time.lastWeekPerDay == 1_200)
        #expect(week.lastWeekRecorded)
        #expect(week.change(week.total) == "10 min more than last week")
        #expect(week.change(week.apps[0].time) == "10 min more than last week")
    }

    @Test("The five apps used most this week, websites aside")
    func mostUsed() {
        let week = ScreenTimeWeek(usage: [
            Self.app("a", minutes: 10), Self.app("b", minutes: 50), Self.app("c", minutes: 30),
            Self.app("d", "Zed", minutes: 20), Self.app("e", "Alpha", minutes: 20), Self.app("f", minutes: 5),
            Self.app("g", minutes: 0), Self.app("h", thisWeek: false, minutes: 90), Self.site("big.com", minutes: 500),
        ], daysThisWeek: 7)
        #expect(week.apps.map(\.id) == ["b", "c", "e", "d", "a"])
        #expect(week.apps.map(\.name) == ["b", "c", "Alpha", "Zed", "a"])
        #expect(week.total.thisWeek == (10 + 50 + 30 + 20 + 20 + 5 + 500) * 60)
    }

    @Test("Against last week, in words")
    func changes() {
        typealias Time = ScreenTimeWeek.Time
        let week = ScreenTimeWeek(total: Time(), apps: [], lastWeekRecorded: true)
        #expect(week.change(Time(perDay: 600, lastWeekPerDay: 1_320)) == "12 min less than last week")
        #expect(week.change(Time(perDay: 4_500, lastWeekPerDay: 600)) == "1 h 5 min more than last week")
        #expect(week.change(Time(perDay: 610, lastWeekPerDay: 590)) == "Same as last week")
        #expect(week.change(Time(perDay: 600, lastWeekPerDay: 0)) == "None last week")
        let firstWeek = ScreenTimeWeek(total: Time(), apps: [], lastWeekRecorded: false)
        #expect(firstWeek.change(Time(perDay: 600, lastWeekPerDay: 0)) == nil)
    }

    @Test("This week's time, as running at the rate runs bank minutes")
    func running() {
        let week = ScreenTimeWeek(usage: [Self.app("a", minutes: 302)], daysThisWeek: 2)
        #expect(week.running(minutesPerKm: 15) == "This week so far: 5 h 2 min, or 20.1 km of running at 15 min a km.")
        let short = ScreenTimeWeek(usage: [Self.app("a", minutes: 0.4)], daysThisWeek: 1)
        #expect(short.running(minutesPerKm: 15) == nil)
        #expect(!short.isEmpty)
        #expect(ScreenTimeWeek(usage: [], daysThisWeek: 1).isEmpty)
    }

    @Test("Weeks from the iPhone's first weekday")
    func weeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        func day(_ day: Int, hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        // Wednesday 25 November 2026.
        let fortnight = ScreenTimeWeek.fortnight(of: day(25), calendar: calendar)
        #expect(fortnight.start == day(16, hour: 0))
        #expect(fortnight.end == day(30, hour: 0))
        let thisWeek = ScreenTimeWeek.thisWeek(from: fortnight, calendar: calendar)
        #expect(thisWeek == day(23, hour: 0))
        #expect(ScreenTimeWeek.daysThisWeek(since: thisWeek, now: day(25), calendar: calendar) == 3)
        #expect(ScreenTimeWeek.daysThisWeek(since: thisWeek, now: day(23, hour: 0), calendar: calendar) == 1)
        #expect(ScreenTimeWeek.daysThisWeek(since: thisWeek, now: day(29, hour: 23), calendar: calendar) == 7)
    }

    @Test("Times in words")
    func words() {
        #expect(ScreenTimeWeek.text(0) == "0 min")
        #expect(ScreenTimeWeek.text(20) == "Under 1 min")
        #expect(ScreenTimeWeek.text(1_440) == "24 min")
        #expect(ScreenTimeWeek.text(3_900) == "1 h 5 min")
        #expect(ScreenTimeWeek.text(7_200) == "2 h")
        #expect(ScreenTimeWeek.tallest.apps.count == ScreenTimeWeek.shown)
    }
}
