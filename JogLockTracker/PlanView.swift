//
//  PlanView.swift
//  JogLockTracker
//
//  Your plan: every day, each week or the 5K plan, as cards to pick from,
//  with the distance and rest days. Changes are saved together, and while
//  the apps are locked they start tomorrow. The 5K plan's week has its
//  own screen: this week's three runs, what's coming, and repeating a
//  week that was too hard.
//

import JogLockCore
import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    /// The daily distance, kept by the run tracker.
    @Binding var targetKm: Double
    @State private var draft = RunPlan()
    @State private var dailyKm = 1.0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    option(.daily, "Every day", "The same distance each day.") {
                        stepper(dailyKm, unit: "KM", down: { dailyKm = max(0.25, dailyKm - 0.25) },
                                up: { dailyKm = min(20, dailyKm + 0.25) })
                        restDays
                    }
                    option(.weekly, "Each week", "A weekly total, on any days you like.") {
                        stepper(draft.weeklyMeters / 1_000, unit: "KM",
                                down: { draft.weeklyMeters = max(2_000, draft.weeklyMeters - 1_000) },
                                up: { draft.weeklyMeters = min(100_000, draft.weeklyMeters + 1_000) })
                        Text("That's \(Format.shortDistance(draft.weeklyShare)) a run day.")
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                        restDays
                    }
                    option(.fiveK, "5K plan", "Nine weeks of walk–run, three runs a week.") {
                        let week = fiveKPreview.fiveKWeek(on: lock.today)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Week \(week.number) of \(FiveKWeek.all.count) · \(Format.shortDistance(week.meters)) a run")
                                .font(.subheadline.weight(.bold))
                            Text("\(week.intervalsText), after a 3-minute walk.")
                                .font(.subheadline)
                                .foregroundStyle(JL.ink2)
                        }
                        if lock.plan.kind == .fiveK {
                            NavigationLink {
                                FiveKPlanView { dismiss() }
                            } label: {
                                Label("This week's runs", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(JL.redText)
                            }
                        }
                        restDays
                    }
                    if lock.isLocked {
                        Label {
                            Text("You're locked today, so a new plan starts tomorrow. Today stays at \(Format.shortDistance(lock.ledger.targetMeters)).")
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(JL.redText)
                        }
                        .font(.footnote)
                        .foregroundStyle(JL.ink2)
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(JL.ink)
                .padding(20)
            }
            .jlScreen()
            .navigationTitle("Your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = lock.plan
                dailyKm = targetKm
                loaded = true
            }
        }
    }

    /// The 5K plan as it is, or as it would start.
    private var fiveKPreview: RunPlan {
        if lock.plan.kind == .fiveK {
            return lock.plan
        }
        return RunPlan(kind: .fiveK, restDays: RunPlan.fiveKRestDays, fiveKStart: lock.today)
    }

    /// One plan as a card: picked, it opens to show its settings.
    private func option<Content: View>(_ kind: RunPlan.Kind, _ title: String, _ detail: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        let picked = draft.kind == kind
        return VStack(alignment: .leading, spacing: 16) {
            Button {
                pick(kind)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .strokeBorder(picked ? JL.ink : JL.line, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if picked {
                                Circle().fill(JL.red).frame(width: 10, height: 10)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if picked {
                content()
            }
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(picked ? JL.ink : .clear, lineWidth: 2))
    }

    /// A big number between − and +.
    private func stepper(_ value: Double, unit: String, down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        HStack {
            Button(action: down) {
                Image(systemName: "minus")
            }
            .buttonStyle(.jlRound)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.truncatingRemainder(dividingBy: 0.5) == 0 ? String(format: "%.1f", value) : String(format: "%.2f", value))
                    .jlNumber(48)
                Text(unit)
                    .font(.jlHeading(18))
            }
            Spacer()
            Button(action: up) {
                Image(systemName: "plus")
            }
            .buttonStyle(.jlRound)
        }
    }

    private var restDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Rest days")
                    .font(.subheadline.weight(.bold))
                Text("· apps open all day")
                    .font(.subheadline)
                    .foregroundStyle(JL.ink2)
            }
            WeekdayPicker(selected: Binding(get: { draft.validRestDays }, set: { days in
                if days.count <= RunPlan.mostRestDays {
                    draft.restDays = days
                }
            }), firstWeekday: draft.firstWeekday)
        }
    }

    private func pick(_ kind: RunPlan.Kind) {
        guard kind != draft.kind else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            if kind == .fiveK && lock.plan.kind != .fiveK {
                draft.restDays = RunPlan.fiveKRestDays
            }
            if kind != .daily {
                draft.firstWeekday = Calendar.current.firstWeekday
            }
            draft.kind = kind
        }
    }

    private func save() {
        let old = lock.plan
        if draft.kind == .fiveK && old.kind != .fiveK {
            lock.startFiveK(restDays: draft.restDays)
        } else if draft != old {
            lock.setPlan(draft)
        }
        if draft.kind == .daily && dailyKm != targetKm {
            targetKm = dailyKm
        }
        dismiss()
    }
}

/// The 5K plan's week: how far it's come, this week's three runs, what's
/// next, and repeating a week that was too hard.
struct FiveKPlanView: View {
    /// Closes the plan, so a run can start.
    let close: () -> Void
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var tracker: RunTracker
    @State private var runs: [RunSummary] = []

    var body: some View {
        let plan = lock.plan
        let week = plan.fiveKWeek(on: lock.today)
        let days = TodayWeek(runs: runs.map { MonthWrap.Run($0) }, today: lock.today, plan: plan,
                             dailyMeters: lock.rules.dailyMeters, startHour: lock.rules.dayStartHour).days
            .filter { !$0.isRest }
        let next = days.firstIndex { $0.isToday && $0.fraction < 1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Week \(week.number)")
                            .font(.jlDisplay(40))
                            .tracking(-1.6)
                            .textCase(.uppercase)
                        Text("of \(FiveKWeek.all.count)")
                            .font(.jlHeading(18))
                            .textCase(.uppercase)
                            .foregroundStyle(JL.ink2)
                    }
                    HStack(spacing: 4) {
                        ForEach(1...FiveKWeek.all.count, id: \.self) { number in
                            Capsule()
                                .fill(number < week.number ? JL.ink : number == week.number ? JL.red : JL.sand)
                                .frame(height: 8)
                        }
                    }
                    Text("\(week.intervalsText), after a 3-minute walk. \(Format.shortDistance(week.meters)) a run.")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                JLList {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        runRow(index + 1, day, isLast: index == days.count - 1)
                    }
                }
                if week.number < FiveKWeek.all.count {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Coming up")
                        let after = FiveKWeek.all[week.number]
                        Text("**Week \(after.number)** · \(after.intervalsText.lowercased())")
                        if let last = FiveKWeek.all.last, last.number > after.number {
                            Text("**Week \(last.number)** · run the whole way. \(Format.shortDistance(last.meters)).")
                        }
                    }
                    .font(.subheadline)
                }
                if let next {
                    Button {
                        close()
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            tracker.start()
                        }
                    } label: {
                        Label("Start run \(next + 1)", systemImage: "play.fill")
                    }
                    .buttonStyle(.jlPrimary)
                }
                if week.number > 1 {
                    Button("Too hard? Repeat week \(week.number)") {
                        lock.repeatFiveKWeek()
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.jlOutlineWide)
                }
                Button("Start again from week 1") {
                    lock.startFiveK(restDays: plan.restDays)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JL.redText)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(JL.ink)
            .padding(20)
        }
        .jlScreen()
        .navigationTitle("5K plan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            runs = RunStore.onDevice.allSummaries()
        }
    }

    private func runRow(_ number: Int, _ day: WeekDayProgress, isLast: Bool) -> some View {
        let name = Calendar.current.weekdaySymbols[(day.day.weekday - 1 + 7) % 7]
        let done = day.fraction >= 1 || (!day.isToday && !day.isFuture && day.meters > 0)
        let detail: String
        if done {
            detail = "\(day.isToday ? "Today" : name) · \(Format.shortDistance(day.meters))"
        } else if day.isToday {
            detail = day.meters > 0 ? "Today · \(Format.shortDistance(day.meters)) so far" : "Today"
        } else if day.isFuture {
            detail = name
        } else {
            detail = "\(name) · missed"
        }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    if done {
                        Circle().fill(JL.ink)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(JL.paper)
                    } else if day.isToday {
                        Circle().fill(JL.red)
                    } else {
                        Circle().strokeBorder(JL.line, lineWidth: 2)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run \(number)")
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 52)
            }
        }
    }
}

/// Seven day buttons, in the order of the iPhone's week. Picked days are ink.
struct WeekdayPicker: View {
    @Binding var selected: Set<Int>
    let firstWeekday: Int

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(PlanText.weekOrder(firstWeekday: firstWeekday), id: \.self) { day in
                let on = selected.contains(day)
                Button {
                    if on { selected.remove(day) } else { selected.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(on ? JL.paper : JL.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? JL.ink : JL.sand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The plan in words, and the order of the week.
enum PlanText {
    /// The plan in a few words: "3 km a day", "20 km a week", "5K · week 3".
    static func summary(_ plan: RunPlan, dailyMeters: Double, today: LockDay) -> String {
        switch plan.kind {
        case .daily: "\(Format.shortDistance(dailyMeters)) a day"
        case .weekly: "\(Format.shortDistance(plan.weeklyMeters)) a week"
        case .fiveK: "5K · week \(plan.fiveKWeekNumber(on: today))"
        }
    }

    /// "1.8 km", or "0 km" before any running.
    static func distance(_ meters: Double) -> String {
        meters < 10 ? "0 km" : Format.shortDistance(meters)
    }

    /// Weekday numbers (1 Sunday to 7 Saturday) from the week's first day.
    static func weekOrder(firstWeekday: Int) -> [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
