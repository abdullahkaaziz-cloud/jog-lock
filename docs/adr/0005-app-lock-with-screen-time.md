# ADR-0005: The app lock: Screen Time, built on Tilawah Key's blocking

## Status

Accepted

## Date

2026-11-23

## Context

Jog Lock's point is to keep chosen apps locked until the day's run is done. On iOS a third-party app can only do that with the Screen Time frameworks:

- **FamilyControls**: permission (`.individual`, for the phone's own user) and the app picker. The app only gets opaque tokens and never learns which apps were picked.
- **ManagedSettings**: shields over apps, categories and websites, and a web filter.
- **DeviceActivity**: schedules that wake an extension at set times, and usage events after so many minutes of use. iOS monitors no interval under 15 minutes.
- **ManagedSettingsUI**: an extension that draws the shield. Only it gets the locked app's name.

Each extension runs in its own process. The only state they share with the app is an App Group.

Tilawah Key, the author's other app, has locked apps behind reading the Qur'an since October 2026. Its blocking went through dozens of iPhone tests, and its decision log records what iOS actually does. The first version of this lock was written before that code was available. It used wall-clock unlocks of at least 15 minutes, a repeating midnight schedule and shared UserDefaults.

## Decision

Take Tilawah Key's approach, with Jog Lock's rules.

- **The rules live in JogLockCore** (`LockLedger`, `LockState`) and are tested on Linux.
- **Banked minutes are minutes of use.** While they're spent, iOS sends one usage event per minute the chosen apps are used (`includesPastActivity: false`). Spending stops when they're used up or the runner taps Lock again now, so there's no 15-minute minimum. A notification comes a minute before they run out.
- **The day starts at 4:00**, Tilawah Key's default for its daily unlock, so a late evening isn't cut off at midnight.
- **One-off monitors with new names.** There's one for the day (until 4:00, and at least 16 minutes) or one for the minutes (a day long, renewed if minutes are left). Callbacks from older names are ignored. iOS ending the day's monitor up to a minute early counts as on time.
- **The apps open only once iOS has accepted the monitor** that will lock them again. If registering fails, they stay locked.
- **The state is one JSON file in the App Group.**
  - It's only ever replaced whole, with file protection that lets the extensions read it once the phone has been unlocked after a restart.
  - Every change happens under a file lock that's never waited on for more than half a second.
  - DeviceActivity calls are made outside the lock, because iOS may call the monitor while one is being registered.
  - Usage events go to an inbox first, so a busy lock never loses one.
- **One "apply the state" for the shield**, from the app or the monitor, in one named store.
  - Chosen websites also go to iOS's web filter, which blocks them in Chrome and other browsers.
  - Websites can also be typed in by name (Tilawah Key's K10), for ones the picker doesn't list. They're kept as the domain the web filter takes (`instagram.com`, subdomains included) and get iOS's own "Restricted" page. A state saved before them reads with none.
  - At most 50 apps and 40 websites, chosen and typed, can be locked.
- **The app does its lock work on a background actor.** It catches up at launch, when it comes to the front, on the monitor's signal, when a monitor's time comes, and every minute while it's open.
- **No easy way out while locked.** Apps can only be added, and the lock can only be turned off after the day's run. Settings explains Tilawah Key's "Strict" set-up: someone trusted keeps a Screen Time passcode.
- **The shield** says "TikTok is 1.8 km away", with a line that changes each minute and the banked minutes.
  - Run now opens Jog Lock on iOS 26.5 and later (`openParentalControlsApp`, confirmed on Tilawah Key with an individual authorisation). Before 26.5 it sends a notification that opens the app.
  - Close closes the locked app.
- **Diagnostics.** The app, the monitor and the shield each keep a short log in the App Group, shared from Settings. It holds counts, never which apps.
- **Time on apps** (Tilawah Key's H5, D94). A Device Activity Report extension draws the home screen's card: a day on average this week against last week, and the five apps used most. With the lock on it reports on the locked apps; otherwise on every app.
  - It's an ExtensionKit extension in the app's `Extensions` folder, with Family Controls and no App Group. iOS keeps the numbers inside it, so the app never sees them and nothing about them can reach the diagnostics.
  - The extension can't say how tall it is, so the card is sized by the same view drawn hidden at its tallest. The report takes no touches, so the page scrolls over it (Tilawah Key's D95).

## Alternatives considered

- **Wall-clock unlocks (the first version).** Minutes ran out whether or not the apps were used, and iOS can't time anything under 15 minutes.
- **A repeating midnight schedule.** Its start re-locked the apps, but a day that starts at 4:00 would need it to span midnight, which hasn't been tested. One-off monitors are what Tilawah Key has proved.
- **Shared UserDefaults.** There's no lock across processes, so the app and the monitor could overwrite each other's changes.

## Consequences

- **A paid developer team is needed.** Family Controls isn't available to free Personal Teams. Before TestFlight or the App Store, Apple must also approve the Family Controls (Distribution) entitlement for the app and its extensions.
- **iOS 17.4 or later is needed for usage counting.** Jog Lock needs iOS 18 anyway.
- **iOS counts whole minutes**, so part of a minute before Lock again now isn't taken.
- **Not brought over:** parent-managed protection (not wanted).
- **iOS can't count time on websites typed in by name.** While banked minutes are spent, they're open with the apps without using minutes up.
- **The App Group ID appears in four entitlements files and `LockShared/LockStore.swift`.** The report extension has none.
- **Six bundle IDs** need Apple's Family Controls (Distribution) approval before TestFlight: the app and its five extensions, `.Report` included.
