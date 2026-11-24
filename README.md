# Jog Tracker: Jog Lock distance test build (approach 1)

This test app measures jog distance with Core Location's fitness updates, then cleans up the GPS points the way Strava does. It works out three distances so you can see which one matches reality. The app shows the cleaned and raw numbers; the speed-based one is only in the run files, because it came out 4.6% short on the first real jog.

| Number | How it's worked out |
|---|---|
| **Jog Lock (cleaned)** | The main number. It waits for a good GPS signal, drops weak or jumpy points, ignores time standing still, then adds up moves of 5 m or more. |
| **Speed-based** | Adds up the iPhone's GPS speed reading × time. It isn't fooled by position wobble, but it's only as good as the iPhone's speed reading. |
| **Raw, no clean-up** | Joins up every point. This is what a naive app shows, and it usually comes out too long. |

The app saves every GPS point to a log, so a run can be replayed later with different settings without running again.

It also locks the apps you choose until you've run the day's distance: see [App lock](#app-lock).

## The step check (anti-cheat)

Only distance you cover on foot counts toward unlocking. The app checks the GPS distance against the iPhone's step counter and its motion activity (Motion & Fitness permission):

- **Steps back the distance.** Each step can cover at most 2 m, which is more than any jogger's step. GPS distance that the steps nearby (within 5 seconds) can't cover isn't counted. Driving, or a phone left on a car seat, gets no steps, so it doesn't count.
- **Cars and bikes don't count.** If Core Motion is fairly sure you're in a car or on a bike, that distance doesn't count, even if the phone is being shaken to fake steps.
- **It takes a minute to settle.** Step and motion data can arrive late, so each bit of distance waits up to a minute before it's settled. The ring shows it straight away; the unlock happens once it's settled, or as soon as you tap Stop.
- **Motion & Fitness must be on.** Without it there are no steps, so nothing counts. The app says so at the start of a run.

The live screen and run details show what counted and what didn't (too few steps, or car or bike). Walking counts the same as running.

## App lock

Tap **Choose apps to lock** on the home screen. iOS asks for Screen Time access (Face ID or passcode), then shows its own app picker. Jog Lock never learns which apps you picked; iOS draws their icons. The blocking follows Tilawah Key's, which has been through dozens of iPhone tests ([ADR-0005](docs/adr/0005-app-lock-with-screen-time.md)).

- **Locked each day until you've run.** Runs add up during the day, using counted distance only (after the step check). When they reach the daily target, the apps open until the day ends at 4:00, so a late evening isn't cut off at midnight.
- **The unlock moment.** The run that meets the target opens the apps straight away, mid-run. When you next open Jog Lock you get a full-screen celebration: the lock pops, the apps' icons spring out, confetti falls and the phone buzzes. The voice coach says it out loud during the run.
- **"TikTok is 1.8 km away".** The shield on a locked app shows how far you still have to run, a line that changes every minute, and your banked minutes.
  - **Run now** opens Jog Lock on iOS 26.5 and later. On older iOS it sends a notification that opens it.
  - **Close** closes the locked app.
- **Banked minutes.** Every kilometre past the day's target banks 15 minutes, up to an hour.
  - **Use banked minutes** opens the apps. Each minute you actually spend in them takes one off, until they're gone or you tap **Lock again now**.
  - A notification warns you a minute before they run out.
- **Borrow from tomorrow.** When you have under 15 banked minutes, you can borrow 30 minutes now, and tomorrow's target goes up by 1 km. It's once a day; distance you don't run carries over, and borrowing stops once you owe 3 km.
- **No easy way out.** While the apps are locked you can add apps but not remove them. The lock can only be turned off (the ⋯ menu on the card) after the day's run.
  - **Settings → App lock** shows how to stop yourself switching off Screen Time access: someone you trust keeps a Screen Time passcode.
- **Changing the target** while the lock is on takes effect tomorrow, so you can't lower it to unlock today.
- **Your plan** (**Change** on the plan card):
  - **Daily:** the same distance every run day.
  - **Weekly:** a week's distance shared over your run days. Run more one day and the next days need less; finish the week and the rest of it is open. A missed day isn't added to the next, and minutes bank only past the week's distance.
  - **5K plan:** nine weeks of three runs, from 1 km of running and walking to 5 km without stopping. Each run starts with a 3-minute walk, and the voice coach calls every run and walk.
  - **Rest days** in any plan are open all day. Distance owed from borrowing waits for the next run day. Like the target, a change starts tomorrow while the lock is on.
- **Run-only apps.** Pick a podcast, music or audiobook app on the Run-only apps card. It stays locked except while a run is going: it opens when you start and locks again when you stop, or four hours on if Jog Lock isn't running by then. Its shield says "Spotify is for runs". You can change these apps any time; they're a treat for running, not the lock.
- **Websites typed in by name.** For websites the picker doesn't list: ⋯ → **Websites**, then type `instagram.com` (or paste a whole address). They're blocked in Safari and other browsers, subdomains too, with iOS's own "Restricted" page. Up to 40 websites in all, chosen and typed; while locked they can only be added.
- **Time on apps.** Once Screen Time is connected, a card at the bottom of the home screen shows a day on average this week against last week, what this week's time would take to run for (15 minutes a km), and the five apps used most. With the lock on it covers the locked apps; otherwise every app. A separate extension draws it, and iOS keeps the numbers inside that extension: Jog Lock never sees them.
- **Diagnostics.** If something looks wrong, Settings → App lock → **Share lock diagnostics**. It shows what the lock did and when, never which apps you chose.

It needs a paid Apple Developer team, because free Personal Teams can't use Family Controls. See [Put it on your iPhone](#put-it-on-your-iphone).

## Maps, voice coach and sharing

- **Maps.** The live screen shows your route as you run. Each run's details open with its route, and the map button on the Runs screen shows everywhere you've run.
- **Voice coach.** Every 500 m, at halfway, near the end and at the unlock, a voice line like "TikTok is getting closer. 1.8 kilometres to go." Pick the app you're running for and a voice (Chipmunk, Robot, Movie trailer, Normal) in Settings (gear icon). Music ducks while it talks.
- **Nice try.** When the step check throws out distance (car, bike, or GPS distance without the steps), a "Nice try." card appears and the coach says so. The card can be shared.
- **Lock-screen countdown.** During a run the lock screen and Dynamic Island show "0.8 km to TikTok", a progress bar and the time. It stays on the lock screen for 15 minutes after the run.
- **Share card.** After a run, "Share this run" makes a story-sized image (1080 × 1920): your route as line art, the distance, time and pace.
- **Shoe mileage.** Add your pairs (home screen or Settings → Shoes). Each run's counted distance goes to the pair you're wearing, treadmill runs included. You get a notification at 80% of a pair's limit (650 km unless you change it; running shoes usually last 500–800 km) and at the limit.

## Treadmill mode

Pick **Treadmill** before starting. There's no GPS indoors, so distance comes from your steps:

- **Your own stride.** Every outdoor run that passes the step check teaches the app your step length at different cadences (half-minute windows of GPS distance ÷ steps). On a treadmill, each step counts as that length at the cadence you're running. Until you've done an outdoor run, it uses the iPhone's own step-based distance.
- **Keep the phone on you**, in a pocket or an armband. On the treadmill's console it can't count steps.
- **The app can be in the background.** Distance catches up when you open it again; tap Stop at the end for the final count, which also fills in Core Motion's activity history for the run.
- **Checks:** steps faster than 4 a second don't count, and neither does time Core Motion is fairly sure you were in a car, on a bike or standing still.

Treadmill distance is an estimate: expect it within a few per cent once your stride is learned, and less accurate before that.

## Put it on your iPhone

You need Xcode 16 or later (Xcode 26 is fine) and an iPhone on iOS 18 or later.

1. Open `JogLockTracker.xcodeproj`.
2. Signing is automatic, with the team already set in the project.
   - **Another team?** Pick it in **Signing & Capabilities** for each of the six targets: JogLockTracker, JogLockWidgets, JogLockMonitor, JogLockShield, JogLockShieldAction and JogLockReport.
   - **The team must be paid.** Free Personal Teams can't use Family Controls, which the app lock needs.
   - **The first build registers things.** Xcode registers the four extensions' bundle IDs, the App Group and the Family Controls (Development) capability. If a target shows a signing error, select it and click **Try Again** in Signing & Capabilities.
   - **Your own bundle ID prefix?** Change it in all six targets; the extensions' IDs must start with the app's. Then change the App Group in `Config/*.entitlements` and `LockShared/LockStore.swift`.
3. Plug in your iPhone, select it as the run destination and press **Run** (⌘R). If iOS asks, turn on Developer Mode on the phone.
4. Tap **Start run**, then allow:
   - **While Using the App**, with **Precise Location** on
   - notifications
5. To try the lock, tap **Choose apps to lock** and allow Screen Time access.

Background location and the permission texts are already set up in `Config/Info.plist`.

## Test jog protocol

**Where to run:** a 400 m athletics track is best, because 2.5 laps of lane 1 is exactly 1 km. If you can't get to one, use any route you can measure on a map afterwards (for example gpx.studio, or Google Maps' "Measure distance").

1. At the start line, set the target to 1.00 km and tap **Start run**. Wait for **"GPS ready"** (the phone buzzes and shows a banner).
2. Open Strava and start a run recording on the same phone.
3. Lock the phone, carry it the way you normally would, and go.
4. When **"1.00 km reached"** pops up, note where you are, for example "about 10 m before the 2.5-lap line".
5. Optional: stand still for about a minute halfway round. This tests whether distance builds up while you aren't moving.
6. Finish at a known point, and stop Strava and Jog Tracker there.
7. In Jog Tracker, open **Last run**:
   - Type in Strava's distance and the true distance, then tap **Save**.
   - Tap **Share run files** and AirDrop them to your Mac, or save them to Files.

Send me `raw.jsonl` and `summary.json`, and I'll analyse the run.

The run files are also in the Files app, under **On My iPhone > Jog Tracker > Runs**.

## Analyse a run on your Mac

```
python3 Tools/replay.py path/to/raw.jsonl --true-km 1.0 --strava-km 1.02 --sweep --gpx compare.gpx
```

The script:

- **Recomputes all three distances.** The engine in `replay.py` mirrors `DistanceEngine.swift` line for line, so it prints a check that it matches the phone's own total.
- **Lists why points were dropped,** with GPS accuracy stats and any gaps.
- **Runs "Experiments"** with two smoothing variants that aren't in the app yet.
- **Shows the effect of each setting** (`--sweep`), so tuning is based on real data.
- **Writes a GPX file** (`--gpx`) with every point plus the points that were counted. Open it next to Strava's GPX export in gpx.studio to compare the tracks.

Two other useful commands:

- `--set minStepFloor=3` (repeatable) tries a different setting.
- `python3 Tools/test_engine.py` runs the checks on simulated runs: track, slow jog, street corners, stops, GPS jumps, a noisy city route, driving, and standing still.

## Settings

The settings are `EngineSettings` in `DistanceEngine.swift`, mirrored by `Settings` in `Tools/replay.py`. If you change a rule, change both files.

| Setting | Default | Meaning |
|---|---|---|
| warmupAccuracy / warmupFixes | 15 m / 3 | Counting starts after 3 fixes in a row that are accurate to ±15 m. |
| maxAccuracy | 25 m | Weaker fixes are ignored while tracking. |
| maxSpeed | 9 m/s | Any faster movement is treated as a GPS jump, so driving never counts. |
| stopSpeed | 0.5 m/s | Below this you're standing still, so no distance is added. |
| minStepFloor | 5 m | Smallest move that gets counted. Higher values cut wobble but cut corners. |
| maxGap | 120 s | Signal gaps longer than this aren't joined with a straight line. |
| speedMaxAccuracy | 3 m/s | The speed-based number ignores speed readings less accurate than this. |

## What simulation says, and what it can't

Simulated GPS noise suggests:

| Distance | Typical result on a 1 km run |
|---|---|
| Cleaned | Usually 0.5–2% too long, worst single run about 4% |
| Speed-based | Within about ±0.5% |
| Raw | About 8% too long |

Standing still with iOS's stationary signal adds nothing, and driving adds nothing.

These numbers come from a made-up noise model, so your jog decides which method wins.

## Known limits of approach 1

- **Determined cheating:** the step check stops driving and cycling, but someone shaking the phone in a slow car could fool it if Core Motion misses the car. Jogging and driving in short turns adds at most about 10% of the driven distance.
- **Treadmill:** distance is steps × your learned stride, so it can't be checked against GPS. Someone could shake the phone by hand; the cadence limit and Core Motion's activity make that slower than running.
- **App lock:**
  - Before iOS 26.5, a shield can't open Jog Lock, so Run now sends a notification instead.
  - iOS counts whole minutes of use, so part of a minute before **Lock again now** isn't taken.
  - iOS can report a minute of use, or the end of the day's unlock, a little late; sometimes not until a locked app is next opened.
  - While a website is blocked, Safari's private browsing is off (that's iOS's web filter, which also blocks it in Chrome).
  - iOS can't count time on websites typed in by name. While banked minutes are being spent they're open with the apps and don't use minutes up, and the Time on apps card leaves them out.
  - Locking a run-only app doesn't stop sound it's already playing: an episode started on a run can finish.
  - The Time on apps card is blank while iOS draws it, and comes from Screen Time's own numbers, which can lag a little.
  - Turning off Screen Time access for Jog Lock in Settings switches the lock off, unless a Screen Time passcode protects it.
- **Force-quit:** swiping the app away stops tracking. If iOS ends the app itself, it relaunches and resumes the run on its own (the blue location pill stays on).

## If Xcode won't open the project

1. Make a new **iOS App** project (SwiftUI) called `JogLockTracker`.
2. Replace its Swift files with the ones in `JogLockTracker/`, then add `Packages/JogLockCore` with **File > Add Package Dependencies… > Add Local…**.
3. Copy the keys from `Config/Info.plist` into the target's **Info** tab.
4. In **Signing & Capabilities**, add **Background Modes** and tick **Location updates**.
5. Set **iOS Deployment Target** to 18.0.
6. The app lock needs three more targets (**File > New > Target**): a Device Activity Monitor extension, a Shield Configuration extension and a Shield Action extension.
   - Give them the files in `JogLockMonitor/`, `JogLockShield/` and `JogLockShieldAction/`.
   - Add `LockShared/` and the `JogLockCore` package to the app and all three extensions.
   - Add the **Family Controls** and **App Groups** capabilities to all four.
7. Time on apps needs a **Device Activity Report** extension: give it `JogLockReport/` and `ReportShared/`, add `ReportShared/` and the `JogLockCore` package to the app too, and give the extension **Family Controls** only (no App Group).

## Development

Changes go through branches and pull requests, with CI on each one. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and the Definition of Done, [CHANGELOG.md](CHANGELOG.md) for what changed, and [docs/adr](docs/adr) for the main design decisions.

## Files

```
JogLockTracker.xcodeproj    Xcode project (Xcode 16+), with a shared scheme
Config/Info.plist           permissions, background location, Files app access
Config/*.entitlements       Family Controls and the App Group, for the app and its extensions
Packages/JogLockCore/       logic that doesn't need an iPhone, tested with `swift test`
  DistanceEngine.swift      clean-up rules + the three distance estimates
  StepGate.swift            the step check: GPS distance must be backed by steps
  RunCounter.swift          engine + step check, fed in arrival order; rebuilds a run from its log
  Treadmill.swift           treadmill distance from steps, and the stride model learned on GPS runs
  LockLedger.swift          the app lock's rules: daily target, banked minutes, borrowing
  Format.swift              how distances and times are shown
  RunLog.swift              log line and run summary formats
  RunStore.swift            run files (raw.jsonl, summary.json, GPX export)
JogLockTracker/             the iPhone app
  RunTracker.swift          location stream, background session, logging, alerts, resume
  MotionTracker.swift       steps and motion activity from Core Motion
  RunActivityController.swift  starts and updates the lock-screen countdown
  AppLock.swift             the app lock: Screen Time access, picked apps, unlocks
  AppLockCard.swift         the lock on the home screen
  PlanCard.swift            the plan: daily, weekly or the 5K plan, and rest days
  RunOnlyCard.swift         apps that open only while you run
  ShoesView.swift           shoe mileage
  WebsitesView.swift        websites typed in by name
  TimeOnAppsCard.swift      the Time on apps card (the report extension draws its numbers)
  UnlockCelebration.swift   the unlock moment
  StrideStore.swift         the learned stride samples, kept on the phone
  RunStore+Device.swift     where runs are saved on the phone
  ContentView.swift         live screen
  RunListView.swift         past runs, notes, sharing
  JogLockTrackerApp.swift   app entry, notification banners
JogLockWidgets/             widget extension: the lock-screen / Dynamic Island countdown
Shared/                     code built into the app and the widget extension
LockShared/                 the lock's shared state, shield and monitor logic (from Tilawah Key), built into the app and its Screen Time extensions
JogLockMonitor/             locks again when the day ends, counts banked minutes as they're used (DeviceActivity monitor)
JogLockShield/              the shield: "TikTok is 1.8 km away"
JogLockShieldAction/        the shield's buttons: Run now and Close
JogLockReport/              Time on apps, from Screen Time (Device Activity Report extension)
ReportShared/               the Time on apps view and filter, built into the app and the report extension
Tools/
  replay.py                 re-run a log with any settings, compare, export GPX
  simulate.py               make synthetic runs
  test_engine.py            checks on simulated runs and the real-run fixture
  stepgate.py               Python mirror of the step check
  test_stepgate.py          step check scenarios (the Swift tests use the same ones)
  treadmill.py              Python mirror of treadmill mode and stride learning
  test_treadmill.py         treadmill scenarios (the Swift tests use the same ones)
  make_fixtures.py          builds the synthetic runs used by both test suites
  anonymize_log.py          make a run log safe to commit
  fixtures/                 anonymised real runs used as regression tests
docs/adr/                   architecture decision records
.github/                    CI workflow, pull request template, Dependabot
```
