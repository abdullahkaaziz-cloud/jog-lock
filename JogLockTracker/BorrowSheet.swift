//
//  BorrowSheet.swift
//  JogLockTracker
//
//  "Need your apps now?": the ways in before today's run. Banked minutes
//  from extra km, borrowing from tomorrow, or the run itself. Opened from
//  Today's chips and the Lock tab.
//

import JogLockCore
import SwiftUI

struct BorrowSheet: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var tracker: RunTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ledger = lock.ledger
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Need your apps now?")
                    .font(.jlHeading(24, relativeTo: .title2))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.jlRound)
            }
            .padding(.top, 20)
            if ledger.spending {
                spending(ledger)
            } else {
                banked(ledger)
            }
            borrow(ledger)
            if ledger.remainingMeters > 0 {
                Button {
                    dismiss()
                    tracker.start()
                } label: {
                    Label("Or run \(Format.shortDistance(ledger.remainingMeters)) and keep them till \(dayEnd)",
                          systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JL.redText)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .presentationDetents([.medium, .large])
        .presentationBackground(JL.paper)
    }

    private func banked(_ ledger: LockLedger) -> some View {
        let minutes = ledger.spendableMinutes
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Use banked time")
                    .font(.headline)
                Spacer()
                Text("\(minutes) min")
                    .font(.jlDisplay(28))
                    .monospacedDigit()
            }
            Text(minutes > 0
                 ? "You earned these with extra km. Your apps open for \(minutes) minutes, counted only while you're in them."
                 : "Each km past your target banks \(Int(lock.rules.minutesPerExtraKm)) minutes for a day like this.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            Button("Use \(minutes) min") {
                lock.spend()
                dismiss()
            }
            .buttonStyle(.jlInk)
            .disabled(minutes < 1 || ledger.isTargetMet)
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func spending(_ ledger: LockLedger) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ledger.isOpen ? "Open on banked time" : "Opening…")
                    .font(.headline)
                Spacer()
                Text("\(ledger.spendableMinutes) min")
                    .font(.jlDisplay(28))
                    .monospacedDigit()
            }
            Text("Minutes only count while you're in the locked apps. Lock them again and what's left stays banked.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            Button("Lock again now") {
                lock.stopSpending()
                dismiss()
            }
            .buttonStyle(.jlInk)
        }
        .padding(16)
        .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func borrow(_ ledger: LockLedger) -> some View {
        let problem = ledger.borrowProblem(rules: lock.rules)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Borrow from tomorrow")
                    .font(.headline)
                Spacer()
                Text("\(Int(lock.rules.borrowMinutes)) min")
                    .font(.jlDisplay(28))
                    .monospacedDigit()
            }
            Text(problem.map { AppLock.message(for: $0) } ?? tomorrowText)
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            Button("Borrow \(Int(lock.rules.borrowMinutes)) min") {
                lock.borrow()
                dismiss()
            }
            .buttonStyle(JLSmallButtonStyle(fill: JL.card))
            .disabled(problem != nil)
            .opacity(problem == nil ? 1 : 0.45)
        }
        .padding(16)
        .background(JL.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "Tomorrow's run goes from 3 km to 4 km."
    private var tomorrowText: String {
        let extra = lock.rules.borrowMeters
        let tomorrow = lock.today.adding(days: 1)
        let plan = lock.plan
        guard plan.kind == .daily, !plan.isRestDay(tomorrow) else {
            return "Your next run goes up by \(Format.shortDistance(extra)). Your apps open now, and every minute in them counts."
        }
        let from = lock.rules.dailyMeters
        return "Tomorrow's run goes from \(Format.shortDistance(from)) to \(Format.shortDistance(from + extra))."
    }

    /// "04:00", or "midnight".
    private var dayEnd: String {
        let end = lock.rules.dayEnd(after: Date())
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        return parts.hour == 0 && parts.minute == 0 ? "midnight" : end.formatted(date: .omitted, time: .shortened)
    }
}
