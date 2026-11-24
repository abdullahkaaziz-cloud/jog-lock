//
//  Shoes.swift
//  JogLockCore
//
//  Shoe mileage: each run's counted distance goes to the pair you're
//  wearing, and you hear when they're getting tired. Running shoes are
//  usually replaced at roughly 500 to 800 km (300 to 500 miles).
//

import Foundation

public struct Shoe: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Distance already on them when they were added.
    public var startMeters: Double
    /// When to think about new ones.
    public var limitMeters: Double
    public var added: Date
    public var retired: Date?
    /// Counted distance of each run in them, by run ID.
    public var runs: [String: Double]

    public init(id: String, name: String, startMeters: Double = 0, limitMeters: Double = Shoe.defaultLimit,
                added: Date, retired: Date? = nil, runs: [String: Double] = [:]) {
        self.id = id
        self.name = name
        self.startMeters = startMeters
        self.limitMeters = limitMeters
        self.added = added
        self.retired = retired
        self.runs = runs
    }

    /// The middle of the usual 500–800 km.
    public static let defaultLimit: Double = 650_000
    /// The heads-up comes at this share of the limit.
    public static let nearlyShare = 0.8

    public var meters: Double {
        startMeters + runs.values.reduce(0, +)
    }

    /// Share of the limit used: 1 at the limit.
    public var wear: Double {
        meters / max(1_000, limitMeters)
    }
}

public enum ShoeAlert: Equatable, Sendable {
    case nearlyDone(name: String, meters: Double)
    case done(name: String, meters: Double)

    public var title: String {
        switch self {
        case .nearlyDone(let name, _): "\(name) are getting tired"
        case .done(let name, _): "Time for new shoes"
        }
    }

    public var body: String {
        switch self {
        case .nearlyDone(let name, let meters):
            "\(name) have done \(Format.shortDistance(meters)). Running shoes usually last 500–800 km, so start looking for new ones."
        case .done(let name, let meters):
            "\(name) have done \(Format.shortDistance(meters)). Worn-out cushioning is hard on your legs: time to retire them."
        }
    }
}

public struct ShoeRack: Codable, Equatable, Sendable {
    public private(set) var shoes: [Shoe] = []
    /// The pair runs are credited to.
    public private(set) var activeID: String?

    public init() {}

    public var active: Shoe? {
        shoes.first { $0.id == activeID && $0.retired == nil }
    }

    /// Adds a pair and wears it from now on.
    @discardableResult
    public mutating func add(name: String, startMeters: Double = 0, limitMeters: Double = Shoe.defaultLimit,
                             id: String = UUID().uuidString, at date: Date) -> Shoe {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shoe = Shoe(id: id, name: trimmed.isEmpty ? "My shoes" : trimmed, startMeters: max(0, startMeters),
                        limitMeters: max(50_000, limitMeters), added: date)
        shoes.append(shoe)
        activeID = shoe.id
        return shoe
    }

    /// The pair to wear (nil: none). A retired pair can't be worn.
    public mutating func wear(_ id: String?) {
        guard let id else {
            activeID = nil
            return
        }
        guard shoes.contains(where: { $0.id == id && $0.retired == nil }) else { return }
        activeID = id
    }

    public mutating func update(_ id: String, name: String, limitMeters: Double) {
        guard let index = shoes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            shoes[index].name = trimmed
        }
        shoes[index].limitMeters = max(50_000, limitMeters)
    }

    public mutating func retire(_ id: String, at date: Date) {
        guard let index = shoes.firstIndex(where: { $0.id == id }) else { return }
        shoes[index].retired = date
        if activeID == id {
            activeID = nil
        }
    }

    public mutating func remove(_ id: String) {
        shoes.removeAll { $0.id == id }
        if activeID == id {
            activeID = nil
        }
    }

    /// Credits a run's counted distance to the pair being worn. A run
    /// counts once, at its highest figure. Returns the heads-up if this run
    /// took the pair past 80% of its limit, or past the limit.
    public mutating func credit(run id: String, meters: Double) -> ShoeAlert? {
        guard let index = shoes.firstIndex(where: { $0.id == activeID && $0.retired == nil }) else { return nil }
        let shoe = shoes[index]
        guard meters > (shoe.runs[id] ?? 0) else { return nil }
        // A run started in another pair stays there.
        if shoes.contains(where: { $0.id != shoe.id && $0.runs[id] != nil }) {
            return nil
        }
        let before = shoe.wear
        shoes[index].runs[id] = meters
        let after = shoes[index].wear
        if before < 1, after >= 1 {
            return .done(name: shoe.name, meters: shoes[index].meters)
        }
        if before < Shoe.nearlyShare, after >= Shoe.nearlyShare {
            return .nearlyDone(name: shoe.name, meters: shoes[index].meters)
        }
        return nil
    }
}
