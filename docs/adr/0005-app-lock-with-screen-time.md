# ADR-0005: The app lock: Screen Time for iOS, rules in the core, state in an App Group

## Status

Accepted

## Date

2026-11-23

## Context

Jog Lock's point is to keep chosen apps locked until the day's run is done. On iOS a third-party app can only do that with the Screen Time frameworks:

- **FamilyControls**: permission (`.individual`, for the phone's own user) and the app picker. The app only gets opaque tokens and never learns which apps were picked.
- **ManagedSettings**: shields over apps, categories and websites.
- **DeviceActivity**: schedules that wake an extension at set times. The shortest interval is 15 minutes.
- **ManagedSettingsUI**: an extension that draws the shield. Only it gets the locked app's name.

Each extension runs in its own process, and the only state they share with the app is an App Group. A shield can't open the app that owns it.

On top of that, the lock has rules that change during a day: runs add up, distance past the target banks minutes, and borrowing changes tomorrow's target.

## Decision

- **The rules live in JogLockCore.** `LockLedger` holds one day:
  - the target: the daily distance plus anything owed, fixed when the day starts
  - each run's counted distance
  - banked minutes and borrowed distance
  - the current unlock session

  It has no iOS code and is tested on Linux (`LockLedgerTests`).
- **The state lives in the App Group** `group.com.abdullahaziz.JogLockTracker`. It holds:
  - whether the lock is on
  - the picked apps (`FamilyActivitySelection`, as JSON)
  - the rules and the ledger

  `LockStore` reads and writes it. It's compiled into the app and the extensions (`LockShared/`).
- **One "apply" that's safe to repeat.** `LockShield.apply()` shields the picked apps unless today's target is met or a session is on. Three places call it:
  - the app: when a run meets the target, after spending or borrowing, and when it comes to the front
  - the monitor extension at midnight: a repeating all-day schedule, whose start is the re-lock
  - the monitor extension when a session ends: a one-off schedule

  It reads the state instead of assuming it, so a missed or doubled call does no harm.
- **Unlocks last at least 15 minutes**, because DeviceActivity can't time less. Banked minutes are spent in 15, 30 or 60 minutes; borrowing gives 30. One-off schedules use times of day only, the form developers report fires reliably.
- **Only counted distance** (after the step check, ADR-0003) is credited to the ledger. It's saved every 25 m, at the unlock and at the end, so the shield's "1.8 km away" stays close without writing on every GPS fix.
- **Today's target is fixed when the day starts**, so lowering the setting can't unlock today.
- **The shield's button closes the app.** iOS has no supported way for a shield to open the app that owns it.
- **Built fresh.** Tilawah Key (the author's other app) already blocks apps, but its repository wasn't available to this work. Nothing was copied, and aligning the two is a follow-up.

## Alternatives considered

- **All the lock logic in the extensions.** It couldn't be unit-tested off a phone, and it would only run at schedule boundaries.
- **Usage thresholds** (open until you've used the apps for N minutes) instead of timed sessions. This is closer to "minutes of scrolling". But iOS reports thresholds late, it still needs a schedule per session, and it's harder to explain on a shield.
- **Files in the App Group container** instead of its UserDefaults. At this size there's no benefit.

## Consequences

- **A paid developer team is needed.** Family Controls isn't available to free Personal Teams. Before TestFlight or the App Store, Apple must also approve the Family Controls (Distribution) entitlement for the app and its extensions.
- **The app has four extensions:** the widget, the monitor, the shield and the shield action.
- **If iOS delays the end of a session, the apps stay open a bit longer.** At worst that lasts until a locked app is opened or Jog Lock comes to the front.
- **The App Group ID appears in three entitlements files and `LockStore.swift`.** Changing the bundle prefix means changing all of them.
