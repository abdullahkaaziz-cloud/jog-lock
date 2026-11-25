//
//  WrappedView.swift
//  JogLockTracker
//
//  Your month on Jog Lock, wrapped up as a story-sized card to share:
//  kilometres run for your apps, runs, the longest run and streak, the
//  time of day you run most, the "Nice try"s caught, and the distance next
//  to things people know (MonthWrap). Made from the runs kept on the phone.
//

import JogLockCore
import SwiftUI

struct WrappedView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var month = Date()
    @State private var runs: [MonthWrap.Run] = []
    @State private var image: Image?

    var body: some View {
        let wrap = MonthWrap(runs: runs, month: month)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            shift(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(wrap.title)
                            .font(.headline)
                        Spacer()
                        Button {
                            shift(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
                    }
                    .padding(.horizontal)
                    WrappedCardView(wrap: wrap, app: settings.nemesis)
                        .scaleEffect(0.9)
                        .frame(width: 324, height: 576)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    if let image {
                        ShareLink(item: image, preview: SharePreview("My month on Jog Lock", image: image)) {
                            Label("Share my month", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Your month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: month) {
                runs = RunStore.onDevice.allSummaries().map(MonthWrap.Run.init)
                image = ShareCards.render(WrappedCardView(wrap: MonthWrap(runs: runs, month: month), app: settings.nemesis))
            }
        }
    }

    private func shift(by months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }
}

/// The month's card, 1080 × 1920 when shared.
struct WrappedCardView: View {
    let wrap: MonthWrap
    let app: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.08), .black],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                Text("JOG LOCK")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(wrap.title.uppercased()) · WRAPPED")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.green)
                Spacer(minLength: 8)
                Text(wrap.meters < 10 ? "0 km" : Format.shortDistance(wrap.meters))
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                Text("run to unlock \(app)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                VStack(alignment: .leading, spacing: 8) {
                    fact("figure.run", "\(wrap.runs) \(wrap.runs == 1 ? "run" : "runs") · \(ScreenTimeWeek.text(Int(wrap.seconds)))")
                    if wrap.longest > 0 {
                        fact("trophy.fill", "Longest run: \(Format.shortDistance(wrap.longest))")
                    }
                    if wrap.streak > 1 {
                        fact("flame.fill", "\(wrap.streak) days in a row")
                    }
                    if let time = wrap.timeOfDay {
                        fact("sun.horizon.fill", "You're \(time.runner)")
                    }
                    if wrap.niceTries > 0 {
                        fact("hand.raised.fill", "\(wrap.niceTries) Nice \(wrap.niceTries == 1 ? "try" : "tries") caught")
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 8)
                Text(wrap.journey)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                if let scrolling = wrap.scrolling(minutesPerKm: LockRules().minutesPerExtraKm) {
                    Text(scrolling)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.green)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
    }
}
