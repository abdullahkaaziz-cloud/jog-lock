//
//  WebsitesView.swift
//  JogLockTracker
//
//  Websites typed in by name, for the ones Screen Time's picker doesn't
//  list. Locked with the apps in Safari and other browsers. While the apps
//  are locked, sites can be added but not removed. From Tilawah Key's typed
//  websites (K10).
//

import JogLockCore
import SwiftUI

struct WebsitesView: View {
    @EnvironmentObject private var lock: AppLock
    @State private var typing = ""
    @State private var error: String?
    @FocusState private var typingFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sites you type here are blocked in Safari and other browsers until you've run, subdomains too: instagram.com covers m.instagram.com.")
                    .font(.subheadline)
                    .foregroundStyle(JL.ink2)
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Website")
                    HStack(spacing: 10) {
                        TextField("e.g. youtube.com", text: $typing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .focused($typingFocused)
                            .onSubmit(add)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .background(JL.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button("Add", action: add)
                            .buttonStyle(JLSmallButtonStyle(fill: JL.ink, text: JL.paper))
                            .disabled(typing.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(JL.redText)
                    }
                }
                if !lock.websites.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Blocked · \(lock.websites.count) of \(TypedWebsite.limit)")
                        JLList {
                            ForEach(Array(lock.websites.enumerated()), id: \.element) { index, site in
                                siteRow(site, isLast: index == lock.websites.count - 1)
                            }
                        }
                    }
                }
                if lock.isLocked {
                    Label {
                        Text("You're locked right now, so you can add sites but not remove them. Removing opens up after today's run.")
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(JL.redText)
                    }
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
                }
                Text("iOS shows its own \"Restricted\" page for these. While websites are locked, Safari's Private Browsing is off.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .jlScreen()
        .navigationTitle("Websites")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            typingFocused = lock.websites.isEmpty
        }
    }

    private func siteRow(_ site: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .frame(width: 28, height: 28)
                    .background(JL.sand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(site)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if lock.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(JL.redText)
                } else {
                    Button {
                        lock.removeWebsites([site])
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(JL.redText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 56)
            }
        }
    }

    private func add() {
        error = lock.addWebsite(typing)
        if error == nil {
            typing = ""
        }
    }
}
