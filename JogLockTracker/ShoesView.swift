//
//  ShoesView.swift
//  JogLockTracker
//
//  Shoe mileage: the pair you're wearing and the other pairs, with how
//  worn each is. Each run's counted distance goes to the
//  pair being worn (ShoeRack), and a notification comes at 80% of a pair's
//  limit and at the limit. Kept on the phone only.
//

import JogLockCore
import SwiftUI

@MainActor
final class ShoeStore: ObservableObject {
    static let shared = ShoeStore()
    private static let key = "shoes.v1"

    @Published private(set) var rack: ShoeRack

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(ShoeRack.self, from: data) {
            rack = saved
        } else {
            rack = ShoeRack()
        }
    }

    func change(_ body: (inout ShoeRack) -> Void) {
        body(&rack)
        if let data = try? JSONEncoder().encode(rack) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// A run's counted distance, for the pair being worn. The heads-up, if
    /// the pair just got tired.
    func credit(run id: String, meters: Double) -> ShoeAlert? {
        var alert: ShoeAlert?
        change { alert = $0.credit(run: id, meters: meters) }
        return alert
    }
}

/// Your shoes: the pair you're wearing, how worn each pair is, and the
/// ones you've retired. Each run's counted distance goes to the pair
/// being worn.
struct ShoesView: View {
    @ObservedObject private var store = ShoeStore.shared
    @ObservedObject private var lock = AppLock.shared
    @State private var adding = false
    @State private var editing: Shoe?

    var body: some View {
        let rack = store.rack
        let others = rack.shoes.filter { $0.retired == nil && $0.id != rack.active?.id }
        let retired = rack.shoes.filter { $0.retired != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let shoe = rack.active {
                    wearing(shoe)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Track your running shoes' kilometres")
                            .font(.headline)
                        Text("Running shoes usually last 500 to 800 km. Add a pair and every run counts towards it.")
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                        Button {
                            adding = true
                        } label: {
                            Label("Add a pair", systemImage: "plus")
                        }
                        .buttonStyle(.jlInk)
                    }
                    .padding(16)
                    .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if !others.isEmpty || !retired.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Other pairs")
                        JLList {
                            ForEach(others) { shoe in
                                other(shoe)
                            }
                            ForEach(retired) { shoe in
                                HStack {
                                    Text("\(shoe.name) · retired")
                                        .foregroundStyle(JL.ink2)
                                    Spacer()
                                    Text(Format.shortDistance(max(10, shoe.meters)))
                                        .monospacedDigit()
                                        .foregroundStyle(JL.ink2)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        store.change { $0.remove(shoe.id) }
                                    }
                                }
                            }
                        }
                    }
                }
                Text("Each run adds to the pair you're wearing. Set your own limit per pair; you get a nudge at 80% and at 100%. Touch and hold a pair to wear, edit or retire it.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .padding(20)
        }
        .jlScreen()
        .navigationTitle("Shoes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) {
            ShoeEditor(shoe: nil) { name, start, limit in
                store.change { $0.add(name: name, startMeters: start, limitMeters: limit, at: Date()) }
            }
        }
        .sheet(item: $editing) { shoe in
            ShoeEditor(shoe: shoe) { name, _, limit in
                store.change { $0.update(shoe.id, name: name, limitMeters: limit) }
            }
        }
    }

    /// The pair you're wearing: how far it's gone and how far it has left.
    private func wearing(_ shoe: Shoe) -> some View {
        let left = max(0, shoe.limitMeters - shoe.meters)
        let runs = Int(left / max(250, lock.rules.dailyMeters))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wearing")
                    .jlLabel()
                    .foregroundStyle(JL.ink2)
                Spacer()
                Image(systemName: "shoe.2.fill")
                    .foregroundStyle(JL.ink2)
            }
            Text(shoe.name)
                .font(.jlHeading(26, relativeTo: .title))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(shoe.meters / 1_000))")
                    .jlNumber(48)
                Text("of \(Int(shoe.limitMeters / 1_000)) km")
                    .font(.headline)
                    .foregroundStyle(JL.ink2)
            }
            ProgressView(value: min(1, shoe.wear))
                .tint(Self.tint(shoe.wear))
            Text(left > 0
                 ? "\(Format.shortDistance(left)) left, about \(runs) \(runs == 1 ? "run" : "runs") at \(Format.shortDistance(lock.rules.dailyMeters))."
                 : "Past their limit. Time for a new pair.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
        }
        .padding(18)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button("Edit") { editing = shoe }
            Button("Retire") {
                store.change { $0.retire(shoe.id, at: Date()) }
            }
        }
    }

    private func other(_ shoe: Shoe) -> some View {
        Button {
            store.change { $0.wear(shoe.id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shoe.name)
                        .fontWeight(.bold)
                    Spacer()
                    Text("\(Int(shoe.meters / 1_000)) of \(Int(shoe.limitMeters / 1_000)) km")
                        .monospacedDigit()
                        .foregroundStyle(JL.ink2)
                }
                ProgressView(value: min(1, shoe.wear))
                    .tint(Self.tint(shoe.wear))
                if shoe.wear >= Shoe.nearlyShare {
                    Text(shoe.wear >= 1 ? "Past their limit." : "Past 80%. Time to look for a new pair.")
                        .font(.footnote)
                        .foregroundStyle(JL.redText)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Wear these") {
                store.change { $0.wear(shoe.id) }
            }
            Button("Edit") { editing = shoe }
            Button("Retire") {
                store.change { $0.retire(shoe.id, at: Date()) }
            }
        }
    }

    static func tint(_ wear: Double) -> Color {
        wear >= Shoe.nearlyShare ? JL.red : JL.ink
    }
}

/// A new pair, or a pair's name and limit.
struct ShoeEditor: View {
    let shoe: Shoe?
    let save: (_ name: String, _ startMeters: Double, _ limitMeters: Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startKm = 0.0
    @State private var limitKm = Shoe.defaultLimit / 1_000

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, like Pegasus 41", text: $name)
                if shoe == nil {
                    Stepper("Already run in them: \(Int(startKm)) km", value: $startKm, in: 0...2_000, step: 25)
                }
                Stepper("New ones at: \(Int(limitKm)) km", value: $limitKm, in: 300...1_200, step: 50)
            }
            .scrollContentBackground(.hidden)
            .background(JL.paper)
            .navigationTitle(shoe == nil ? "New pair" : "Edit pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(name, startKm * 1_000, limitKm * 1_000)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let shoe {
                    name = shoe.name
                    limitKm = shoe.limitMeters / 1_000
                }
            }
        }
    }
}
