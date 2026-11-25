//
//  WebsitesView.swift
//  JogLockTracker
//
//  Websites typed in by name, for the ones Screen Time's picker doesn't
//  list. Locked with the apps in Safari and other browsers. From Tilawah
//  Key's typed websites (K10).
//

import JogLockCore
import SwiftUI

struct WebsitesView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var typing = ""
    @State private var error: String?
    @FocusState private var typingFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("instagram.com", text: $typing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .focused($typingFocused)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(typing.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Type a website")
                } footer: {
                    Text("Locked with your apps in Safari and other browsers, subdomains too: instagram.com covers m.instagram.com. iOS shows its own \"Restricted\" page for these. While websites are locked, Safari's Private Browsing is off.")
                }

                if !lock.websites.isEmpty {
                    Section {
                        ForEach(lock.websites, id: \.self) { site in
                            Label(site, systemImage: "globe")
                        }
                        .onDelete(perform: lock.isLocked ? nil : remove)
                    } header: {
                        Text("Locked websites")
                    } footer: {
                        Text(lock.isLocked
                             ? "While your apps are locked you can only add websites. Once today's run is done you can remove them."
                             : "Swipe left on one to remove it.")
                    }
                }
            }
            .navigationTitle("Websites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                typingFocused = lock.websites.isEmpty
            }
            .alert("App lock", isPresented: problemShown) {
                Button("OK") { lock.problem = nil }
            } message: {
                Text(lock.problem ?? "")
            }
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { lock.problem != nil }, set: { if !$0 { lock.problem = nil } })
    }

    private func add() {
        error = lock.addWebsite(typing)
        if error == nil {
            typing = ""
        }
    }

    private func remove(_ offsets: IndexSet) {
        lock.removeWebsites(offsets.map { lock.websites[$0] })
    }
}
