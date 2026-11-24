//
//  PlanCard.swift
//  JogLockTracker
//
//  The home screen's plan: the daily distance, the week's progress or the
//  5K plan's week, rest days, and Change. PlanView changes it.
//

import JogLockCore
import SwiftUI

struct PlanCard: View {
    @EnvironmentObject private var lock: AppLock
    /// The daily distance, kept by the run tracker.
    @Binding var targetKm: Double
    @State private var editing = false

    var body: some View {
        let plan = lock.plan
        let ledger = lock.ledger
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(PlanText.title(plan.kind), systemImage: PlanText.icon(plan.kind))
                    .font(.headline)
                Spacer()
                Button("Change") { editing = true }
                    .font(.subheadline.weight(.semibold))
            }
            if lock.isEnabled && ledger.isRestDay {
                Label("Rest day: your apps are open all day.", systemImage: "bed.double.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            switch plan.kind {
            case .daily:
                Stepper(value: $targetKm, in: 0.25...20, step: 0.25) {
                    HStack {
                        Text(lock.isEnabled ? "Each run day" : "Unlock target")
                        Spacer()
                        Text("\(Format.km(targetKm)) km")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if lock.isEnabled && !ledger.isRestDay
                    && abs(ledger.targetMeters - ledger.owedMeters - lock.rules.dailyMeters) > 1 {
                    Text("Today stays at \(Format.shortDistance(ledger.targetMeters)). The new target starts tomorrow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .weekly:
                Stepper(value: weeklyKm, in: 2...100, step: 1) {
                    HStack {
                        Text("Each week")
                        Spacer()
                        Text("\(Format.km(plan.weeklyMeters / 1_000)) km")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(1, ledger.weekMeters / max(1, plan.weeklyMeters)))
                    .tint(.green)
                Text("This week: \(Format.km(ledger.weekMeters / 1_000)) of \(Format.km(plan.weeklyMeters / 1_000)) km. "
                     + (ledger.isRestDay || ledger.targetMeters <= 0
                        ? "Today's covered."
                        : "Today: \(Format.shortDistance(ledger.targetMeters))."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .fiveK:
                let week = plan.fiveKWeek(on: lock.today)
                Text("Week \(week.number) of \(FiveKWeek.all.count): \(Format.shortDistance(week.meters)) a run")
                    .font(.subheadline.weight(.semibold))
                Text("\(week.intervalsText), after a 3-minute walk.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let start = plan.fiveKStart, start > lock.today {
                    Text("Starts tomorrow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !plan.validRestDays.isEmpty {
                Text("Rest days: \(PlanText.days(plan.validRestDays, firstWeekday: plan.firstWeekday))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $editing) {
            PlanView(targetKm: $targetKm)
                .environmentObject(lock)
        }
    }

    private var weeklyKm: Binding<Double> {
        Binding(get: { lock.plan.weeklyMeters / 1_000 }, set: { km in
            var plan = lock.plan
            plan.weeklyMeters = km * 1_000
            lock.setPlan(plan)
        })
    }
}

/// Your plan: daily, weekly or the 5K plan, and rest days.
struct PlanView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @Binding var targetKm: Double

    var body: some View {
        let plan = lock.plan
        NavigationStack {
            Form {
                Section {
                    Picker("Plan", selection: kind) {
                        ForEach(RunPlan.Kind.allCases, id: \.self) { kind in
                            Text(PlanText.short(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(PlanText.explanation(plan.kind))
                }

                switch plan.kind {
                case .daily:
                    Section {
                        Stepper("Each run day: \(Format.km(targetKm)) km", value: $targetKm, in: 0.25...20, step: 0.25)
                    }
                case .weekly:
                    Section {
                        Stepper("Each week: \(Format.km(plan.weeklyMeters / 1_000)) km", value: weeklyKm, in: 2...100, step: 1)
                    } footer: {
                        Text("That's \(Format.shortDistance(plan.weeklyShare)) a run day.")
                    }
                case .fiveK:
                    fiveKSection(plan)
                }

                Section {
                    WeekdayPicker(selected: restDays, firstWeekday: plan.firstWeekday)
                } header: {
                    Text("Rest days")
                } footer: {
                    Text(plan.kind == .fiveK
                         ? "Three run days with a rest day between them suits the 5K plan. Rest days are open all day."
                         : "Rest days are open all day. Distance you owe from borrowing waits for the next run day.")
                }

                if lock.isEnabled {
                    Section {
                        Text("While the lock is on, changes start tomorrow, so today can't be made easier.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func fiveKSection(_ plan: RunPlan) -> some View {
        let week = plan.fiveKWeek(on: lock.today)
        Section {
            LabeledContent("This week", value: "Week \(week.number) of \(FiveKWeek.all.count)")
            LabeledContent("Each run", value: Format.shortDistance(week.meters))
            LabeledContent("Intervals", value: week.intervalsText)
            if week.number > 1 {
                Button("Repeat this week") { lock.repeatFiveKWeek() }
            }
            Button("Start again from week 1") { lock.startFiveK(restDays: plan.restDays) }
        } footer: {
            Text("Nine weeks, three runs a week, from 1 km of running and walking to 5 km without stopping. "
                 + "Each run starts with a 3-minute walk, and the voice coach calls every run and walk.")
        }
    }

    private var kind: Binding<RunPlan.Kind> {
        Binding(get: { lock.plan.kind }, set: { kind in
            guard kind != lock.plan.kind else { return }
            switch kind {
            case .fiveK:
                lock.startFiveK(restDays: RunPlan.fiveKRestDays)
            case .weekly:
                var plan = lock.plan
                plan.kind = .weekly
                plan.firstWeekday = Calendar.current.firstWeekday
                lock.setPlan(plan)
            case .daily:
                var plan = lock.plan
                plan.kind = .daily
                lock.setPlan(plan)
            }
        })
    }

    private var weeklyKm: Binding<Double> {
        Binding(get: { lock.plan.weeklyMeters / 1_000 }, set: { km in
            var plan = lock.plan
            plan.weeklyMeters = km * 1_000
            lock.setPlan(plan)
        })
    }

    private var restDays: Binding<Set<Int>> {
        Binding(get: { lock.plan.validRestDays }, set: { days in
            guard days.count <= RunPlan.mostRestDays else { return }
            var plan = lock.plan
            plan.restDays = days
            lock.setPlan(plan)
        })
    }
}

/// Seven day buttons, in the order of the iPhone's week.
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
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum PlanText {
    static func title(_ kind: RunPlan.Kind) -> String {
        switch kind {
        case .daily: "Daily target"
        case .weekly: "Weekly target"
        case .fiveK: "5K plan"
        }
    }

    static func short(_ kind: RunPlan.Kind) -> String {
        switch kind {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .fiveK: "5K plan"
        }
    }

    static func icon(_ kind: RunPlan.Kind) -> String {
        switch kind {
        case .daily: "lock.fill"
        case .weekly: "calendar"
        case .fiveK: "figure.run"
        }
    }

    static func explanation(_ kind: RunPlan.Kind) -> String {
        switch kind {
        case .daily:
            "The same distance every run day."
        case .weekly:
            "A week's distance, shared over your run days. Run more one day and the next days need less; finish the week and the rest of it is open."
        case .fiveK:
            "Never run before? Start at 1 km of running and walking and build to 5K in nine weeks."
        }
    }

    /// Weekday numbers (1 Sunday to 7 Saturday) from the week's first day.
    static func weekOrder(firstWeekday: Int) -> [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// "Tue, Thu" in the order of the week.
    static func days(_ days: Set<Int>, firstWeekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekOrder(firstWeekday: firstWeekday).filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
