//
//  Onboarding.swift
//  JogLockTracker
//
//  The first launch: what Jog Lock does, which apps to lock, how far to run
//  for them, the permissions it needs and why, and a summary before the
//  apps lock. Nothing locks until LOCK MY APPS. People who already use Jog
//  Lock never see it.
//

import CoreLocation
import CoreMotion
import FamilyControls
import JogLockCore
import SwiftUI
import UserNotifications

/// Whether the first-launch steps still need showing.
enum Onboarding {
    private static let key = "onboarding.done"

    /// True on a first launch. Someone who already uses Jog Lock (the lock
    /// on, runs saved, or a distance set) is marked done instead.
    @MainActor
    static func isNeeded() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key) {
            return false
        }
        if AppLock.shared.isEnabled || defaults.object(forKey: "targetKm") != nil
            || !RunStore.onDevice.allSummaries().isEmpty {
            defaults.set(true, forKey: key)
            return false
        }
        return true
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var tracker: RunTracker
    @StateObject private var permissions = PermissionStatus()
    @State private var page = Page.welcome
    @State private var selection = FamilyActivitySelection()
    @State private var picking = false
    @State private var km = 3.0
    @State private var restDays: Set<Int> = []
    @State private var fiveK = false
    @State private var editingWebsites = false

    private enum Page: Int, CaseIterable {
        case welcome, apps, distance, permissions, ready
    }

    var body: some View {
        VStack(spacing: 0) {
            if page != .welcome {
                header
            }
            Group {
                switch page {
                case .welcome: welcome
                case .apps: apps
                case .distance: distance
                case .permissions: permissionsPage
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(JL.paper.ignoresSafeArea())
        .familyActivityPicker(isPresented: $picking, selection: $selection)
        .sheet(isPresented: $editingWebsites) {
            NavigationStack {
                WebsitesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingWebsites = false }
                        }
                    }
            }
            .environmentObject(lock)
        }
    }

    private func go(_ next: Page) {
        withAnimation(.easeInOut(duration: 0.25)) {
            page = next
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                go(Page(rawValue: page.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.jlRound)
            HStack(spacing: 6) {
                ForEach(1..<Page.allCases.count, id: \.self) { step in
                    Capsule()
                        .fill(step <= page.rawValue ? JL.ink : Color(hex: 0xD6CEBF))
                        .frame(height: 4)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("JOG LOCK")
                .font(.jlHeading(16))
                .tracking(5)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            TrackView(progress: 0.72) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(JL.paper)
                    .frame(width: 76, height: 76)
                    .background(JL.ink, in: Circle())
            }
            .frame(height: 230)
            .overlay(alignment: .top) {
                HStack(spacing: 10) {
                    tile("play.fill", 0x2A2622, angle: -4)
                    tile("camera", 0x3A2A30, angle: 2)
                    tile("text.alignleft", 0x2A3032, angle: -3)
                }
                .offset(y: -18)
            }
            .padding(.top, 50)
            Text("No run,\nno scroll.")
                .font(.jlDisplay(64))
                .tracking(-2.6)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 50)
            Text("Pick the apps that eat your day. They stay locked until you've run your distance. Then they're yours.")
                .font(.title3)
                .foregroundStyle(JL.ink2)
                .padding(.top, 16)
            Spacer(minLength: 20)
            Button("Get started") {
                go(.apps)
            }
            .buttonStyle(.jlPrimary)
            Text("Built on Apple's Screen Time. Your runs stay on your phone.")
                .font(.footnote)
                .foregroundStyle(JL.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
    }

    /// A made-up app icon for the welcome picture.
    private func tile(_ symbol: String, _ color: UInt32, angle: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color(hex: 0xD6CEBF))
            .frame(width: 64, height: 64)
            .background(Color(hex: color), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: JL.ink.opacity(0.3), radius: 10, y: 8)
            .rotationEffect(.degrees(angle))
    }

    // MARK: - Apps

    private var picked: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which apps steal your time?")
                    .font(.jlHeading(30, relativeTo: .largeTitle))
                Text("You pick them from Apple's Screen Time list. Only iOS knows which apps they are.")
                    .font(.body)
                    .foregroundStyle(JL.ink2)
            }
            VStack(alignment: .leading, spacing: 14) {
                if picked > 0 {
                    HStack {
                        Text("\(picked) \(picked == 1 ? "app" : "apps") to lock")
                            .font(.headline)
                        Spacer()
                        Button("Change", action: choose)
                            .buttonStyle(.jlSmall)
                    }
                    FlowNames(selection: selection)
                } else {
                    Button(action: choose) {
                        Label("Choose apps", systemImage: "apps.iphone")
                    }
                    .buttonStyle(.jlInk)
                }
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .frame(width: 28, height: 28)
                        .background(JL.sand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Websites")
                            .font(.headline)
                        Text(lock.websites.isEmpty ? "The ones the list doesn't have" : lock.websites.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Add") {
                        editingWebsites = true
                    }
                    .buttonStyle(.jlSmall)
                }
            }
            .padding(16)
            .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Label {
                Text("You can add apps any time. Removing them, or turning the lock off, waits until you've run.")
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(JL.redText)
            }
            .font(.subheadline)
            .foregroundStyle(JL.ink2)
            Spacer(minLength: 0)
            Button("Continue") {
                go(.distance)
            }
            .buttonStyle(.jlPrimary)
            .disabled(picked == 0 && lock.websites.isEmpty)
            if picked == 0 && lock.websites.isEmpty {
                Button("Skip for now") {
                    go(.distance)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JL.ink2)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func choose() {
        Task {
            guard await lock.authorize() else { return }
            permissions.refresh()
            picking = true
        }
    }

    // MARK: - Distance

    private var distance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How far for your apps back?")
                .font(.jlHeading(30, relativeTo: .largeTitle))
            if fiveK {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The 5K plan")
                        .font(.headline)
                    Text("Week 1: \(FiveKWeek.all[0].intervalsText.lowercased()), \(Format.shortDistance(FiveKWeek.all[0].meters)) a run, three runs a week. Nine weeks to 5 km.")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JL.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Button {
                            km = max(0.5, km - 0.5)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(JLRoundButtonStyle(size: 52))
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", km))
                                .jlNumber(72)
                            Text("KM")
                                .font(.jlHeading(22))
                        }
                        Spacer()
                        Button {
                            km = min(20, km + 0.5)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(JLRoundButtonStyle(size: 52))
                    }
                    Text("a day · about \(Int((km * 6.5 / 5).rounded()) * 5) minutes at an easy pace")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                HStack(spacing: 8) {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { preset in
                        Button("\(Int(preset)) km") {
                            km = preset
                        }
                        .buttonStyle(JLSmallButtonStyle(fill: km == preset ? JL.ink : JL.sand, text: km == preset ? JL.paper : JL.ink))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Rest days")
                        .font(.subheadline.weight(.bold))
                    Text("· apps open all day")
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                WeekdayPicker(selected: Binding(get: { restDays }, set: { days in
                    if days.count <= RunPlan.mostRestDays {
                        restDays = days
                    }
                }), firstWeekday: Calendar.current.firstWeekday)
            }
            Button {
                fiveK.toggle()
                restDays = fiveK ? RunPlan.fiveKRestDays : []
            } label: {
                HStack(spacing: 12) {
                    Text("5K")
                        .font(.jlHeading(17))
                        .foregroundStyle(JL.card)
                        .frame(width: 48, height: 48)
                        .background(fiveK ? JL.red : JL.ink, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fiveK ? "Back to a daily distance" : "New to running?")
                            .font(.headline)
                        Text(fiveK ? "The same distance each run day instead." : "The 5K plan: nine weeks from walk–run to 5 km, three runs a week.")
                            .font(.subheadline)
                            .foregroundStyle(JL.ink2)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(JL.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button("Continue") {
                permissions.refresh()
                go(.permissions)
            }
            .buttonStyle(.jlPrimary)
        }
    }

    // MARK: - Permissions

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("So it can tell a run from a ride")
                    .font(.jlHeading(30, relativeTo: .largeTitle))
                Text("iOS asks for each one. You can change them later in Settings.")
                    .font(.body)
                    .foregroundStyle(JL.ink2)
            }
            JLList {
                permission("lock.fill", "Screen Time", "Locks and unlocks your apps.", done: lock.isAuthorized) {
                    Task {
                        _ = await lock.authorize()
                        permissions.refresh()
                    }
                }
                permission("location.fill", "Location", "Measures your run, only while you're running.",
                           done: permissions.location) {
                    permissions.askLocation()
                }
                permission("figure.walk", "Motion & Fitness", "Counts your steps, so car and bike trips don't count.",
                           done: permissions.motion) {
                    permissions.askMotion()
                }
                permission("bell.fill", "Notifications · optional", "When you've unlocked, and when your buddy runs.",
                           done: permissions.notifications, isLast: true) {
                    permissions.askNotifications()
                }
            }
            Text("Your runs, your route and the apps you lock stay on your phone.")
                .font(.subheadline)
                .foregroundStyle(JL.ink2)
            Spacer(minLength: 0)
            Button("Continue") {
                go(.ready)
            }
            .buttonStyle(.jlPrimary)
        }
        .onAppear {
            permissions.refresh()
        }
    }

    private func permission(_ symbol: String, _ title: String, _ detail: String, done: Bool, isLast: Bool = false,
                            ask: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(JL.redText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(JL.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if done {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(JL.ink2)
                } else {
                    Button("Allow", action: ask)
                        .buttonStyle(JLSmallButtonStyle(fill: JL.ink, text: JL.paper))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xEDE7DB))
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }

    // MARK: - Ready

    private var targetMeters: Double {
        fiveK ? FiveKWeek.all[0].meters : km * 1_000
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            TrackView(progress: 0) {
                VStack(spacing: 4) {
                    let big = Format.bigDistance(targetMeters)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(big.value)
                            .jlNumber(56)
                        Text(big.unit)
                            .font(.jlHeading(18))
                            .textCase(.uppercase)
                    }
                    Text("To unlock today")
                        .font(.footnote.weight(.heavy))
                        .tracking(1.3)
                        .textCase(.uppercase)
                    if picked > 0 {
                        AppTiles(selection: selection, size: 26, border: JL.infield)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .frame(height: 210)
            Text("You're set.")
                .font(.jlDisplay(44))
                .tracking(-1.8)
            VStack(alignment: .leading, spacing: 14) {
                point("calendar", "**\(fiveK ? "The 5K plan" : "\(Format.shortDistance(targetMeters)) a day")** unlocks your apps until the day ends.\(restText)")
                point("plus.circle", "**Run further, bank time.** Each extra km saves \(Int(lock.rules.minutesPerExtraKm)) minutes for a day you can't run.")
                point("arrow.uturn.backward.circle", "**Really need it now?** Borrow \(Int(lock.rules.borrowMinutes)) minutes. Tomorrow's run goes up by \(Format.shortDistance(lock.rules.borrowMeters)).")
            }
            Spacer(minLength: 0)
            Button(action: finish) {
                if picked > 0 || !lock.websites.isEmpty {
                    Label("Lock my apps", systemImage: "lock.fill")
                } else {
                    Text("Start")
                }
            }
            .buttonStyle(.jlPrimary)
        }
    }

    private var restText: String {
        guard !restDays.isEmpty else { return "" }
        let names = PlanText.weekOrder(firstWeekday: Calendar.current.firstWeekday)
            .filter(restDays.contains)
            .map { Calendar.current.weekdaySymbols[$0 - 1] + "s" }
        return " \(ListFormatter.localizedString(byJoining: names)) are rest days."
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(JL.redText)
                .frame(width: 24)
            Text(LocalizedStringKey(text))
                .font(.body)
        }
    }

    /// Saves the plan, then locks the apps. Nothing locked before this.
    private func finish() {
        if fiveK {
            lock.startFiveK(restDays: restDays)
        } else {
            tracker.targetKm = km
            var plan = lock.plan
            plan.kind = .daily
            plan.restDays = restDays
            lock.setPlan(plan)
        }
        if picked > 0 || !lock.websites.isEmpty {
            lock.choose(selection)
        }
        Onboarding.finish()
        onDone()
    }
}

/// The picked apps' names as iOS draws them, in rows that wrap.
private struct FlowNames: View {
    let selection: FamilyActivitySelection

    var body: some View {
        let tokens = ChosenToken.all(selection)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                HStack(spacing: 6) {
                    token.icon
                        .frame(width: 22, height: 22)
                    token.name
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(JL.sand, in: Capsule())
            }
        }
    }
}

/// Location, motion and notification permissions, for the onboarding's
/// checklist. Each is asked for only when its Allow button is tapped.
@MainActor
final class PermissionStatus: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location = false
    @Published private(set) var motion = false
    @Published private(set) var notifications = false
    private let manager = CLLocationManager()
    private let activity = CMMotionActivityManager()

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func refresh() {
        let status = manager.authorizationStatus
        location = status == .authorizedWhenInUse || status == .authorizedAlways
        motion = CMMotionActivityManager.authorizationStatus() == .authorized
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifications = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }

    func askLocation() {
        manager.requestWhenInUseAuthorization()
    }

    func askMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activity.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func askNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            refresh()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}
