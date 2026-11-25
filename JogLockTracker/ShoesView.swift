//
//  ShoesView.swift
//  JogLockTracker
//
//  Shoe mileage: the pair you're wearing on the home screen, and the list
//  of pairs with how worn each is. Each run's counted distance goes to the
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

/// The pair being worn, on the home screen.
struct ShoesRow: View {
    @ObservedObject private var store = ShoeStore.shared
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shoe.2.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                if let shoe = store.rack.active {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(shoe.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Format.shortDistance(max(10, shoe.meters)))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(1, shoe.wear))
                            .tint(ShoesView.tint(shoe.wear))
                    }
                } else {
                    Text("Track your running shoes' kilometres")
                        .font(.subheadline)
                    Spacer()
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            NavigationStack {
                ShoesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
        }
    }
}

struct ShoesView: View {
    @ObservedObject private var store = ShoeStore.shared
    @State private var adding = false
    @State private var editing: Shoe?

    var body: some View {
        let rack = store.rack
        List {
            Section {
                ForEach(rack.shoes.filter { $0.retired == nil }) { shoe in
                    row(shoe, wearing: shoe.id == rack.activeID)
                }
                Button {
                    adding = true
                } label: {
                    Label("Add a pair", systemImage: "plus")
                }
            } header: {
                Text("Your shoes")
            } footer: {
                Text("Each run's distance goes to the pair you're wearing. Running shoes usually last 500–800 km; you'll get a heads-up at 80% of each pair's limit, and at the limit.")
            }
            let retired = rack.shoes.filter { $0.retired != nil }
            if !retired.isEmpty {
                Section("Retired") {
                    ForEach(retired) { shoe in
                        LabeledContent(shoe.name, value: Format.shortDistance(max(10, shoe.meters)))
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { retired[$0].id }
                        store.change { rack in ids.forEach { rack.remove($0) } }
                    }
                }
            }
        }
        .navigationTitle("Shoes")
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

    private func row(_ shoe: Shoe, wearing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shoe.name)
                    .font(.body.weight(wearing ? .semibold : .regular))
                if wearing {
                    Text("Wearing")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text("\(Format.shortDistance(max(10, shoe.meters))) of \(Format.shortDistance(shoe.limitMeters))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, shoe.wear))
                .tint(Self.tint(shoe.wear))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.change { $0.wear(shoe.id) }
        }
        .swipeActions {
            Button("Retire") {
                store.change { $0.retire(shoe.id, at: Date()) }
            }
            .tint(.orange)
            Button("Edit") { editing = shoe }
        }
    }

    static func tint(_ wear: Double) -> Color {
        wear >= 1 ? .red : wear >= Shoe.nearlyShare ? .orange : .green
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
