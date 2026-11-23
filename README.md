# Jog Tracker: Jog Lock distance test build (approach 1)

This test app measures jog distance with Core Location's fitness updates, then cleans up the GPS points the way Strava does. It works out three distances so you can see which one matches reality. The app shows the cleaned and raw numbers; the speed-based one is only in the run files, because it came out 4.6% short on the first real jog.

| Number | How it's worked out |
|---|---|
| **Jog Lock (cleaned)** | The main number. It waits for a good GPS signal, drops weak or jumpy points, ignores time standing still, then adds up moves of 5 m or more. |
| **Speed-based** | Adds up the iPhone's GPS speed reading × time. It isn't fooled by position wobble, but it's only as good as the iPhone's speed reading. |
| **Raw, no clean-up** | Joins up every point. This is what a naive app shows, and it usually comes out too long. |

The app saves every GPS point to a log, so a run can be replayed later with different settings without running again.

There's no app blocking in this build, only the distance tracking.

## The step check (anti-cheat)

Only distance you cover on foot counts toward unlocking. The app checks the GPS distance against the iPhone's step counter and its motion activity (Motion & Fitness permission):

- **Steps back the distance.** Each step can cover at most 2 m, which is more than any jogger's step. GPS distance that the steps nearby (within 5 seconds) can't cover isn't counted. Driving, or a phone left on a car seat, gets no steps, so it doesn't count.
- **Cars and bikes don't count.** If Core Motion is fairly sure you're in a car or on a bike, that distance doesn't count, even if the phone is being shaken to fake steps.
- **It takes a minute to settle.** Step and motion data can arrive late, so each bit of distance waits up to a minute before it's settled. The ring shows it straight away; the unlock happens once it's settled, or as soon as you tap Stop.
- **Motion & Fitness must be on.** Without it there are no steps, so nothing counts. The app says so at the start of a run.

The live screen and run details show what counted and what didn't (too few steps, or car or bike). Walking counts the same as running.

## Maps, voice coach and sharing

- **Maps.** The live screen shows your route as you run. Each run's details open with its route, and the map button on the Runs screen shows everywhere you've run.
- **Voice coach.** Every 500 m, at halfway, near the end and at the unlock, a voice line like "TikTok is getting closer. 1.8 kilometres to go." Pick the app you're running for and a voice (Chipmunk, Robot, Movie trailer, Normal) in Settings (gear icon). Music ducks while it talks.
- **Nice try.** When the step check throws out distance (car, bike, or GPS distance without the steps), a "Nice try." card appears and the coach says so. The card can be shared.
- **Share card.** After a run, "Share this run" makes a story-sized image (1080 × 1920): your route as line art, the distance, time and pace.

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
2. Click the **JogLockTracker** target, then open **Signing & Capabilities**.
   - Pick your **Team**.
   - Change the **Bundle Identifier** from `com.yourname.joglock.tracker` to your own prefix.
3. Plug in your iPhone, select it as the run destination and press **Run** (⌘R). If iOS asks, turn on Developer Mode on the phone.
4. Tap **Start run**, then allow:
   - **While Using the App**, with **Precise Location** on
   - notifications

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
- **Force-quit:** swiping the app away stops tracking. If iOS ends the app itself, it relaunches and resumes the run on its own (the blue location pill stays on).

## If Xcode won't open the project

1. Make a new **iOS App** project (SwiftUI) called `JogLockTracker`.
2. Replace its Swift files with the ones in `JogLockTracker/`, then add `Packages/JogLockCore` with **File > Add Package Dependencies… > Add Local…**.
3. Copy the keys from `Config/Info.plist` into the target's **Info** tab.
4. In **Signing & Capabilities**, add **Background Modes** and tick **Location updates**.
5. Set **iOS Deployment Target** to 18.0.

## Development

Changes go through branches and pull requests, with CI on each one. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and the Definition of Done, [CHANGELOG.md](CHANGELOG.md) for what changed, and [docs/adr](docs/adr) for the main design decisions.

## Files

```
JogLockTracker.xcodeproj    Xcode project (Xcode 16+), with a shared scheme
Config/Info.plist           permissions, background location, Files app access
Packages/JogLockCore/       logic that doesn't need an iPhone, tested with `swift test`
  DistanceEngine.swift      clean-up rules + the three distance estimates
  StepGate.swift            the step check: GPS distance must be backed by steps
  RunCounter.swift          engine + step check, fed in arrival order; rebuilds a run from its log
  Treadmill.swift           treadmill distance from steps, and the stride model learned on GPS runs
  Format.swift              how distances and times are shown
  RunLog.swift              log line and run summary formats
  RunStore.swift            run files (raw.jsonl, summary.json, GPX export)
JogLockTracker/             the iPhone app
  RunTracker.swift          location stream, background session, logging, alerts, resume
  MotionTracker.swift       steps and motion activity from Core Motion
  StrideStore.swift         the learned stride samples, kept on the phone
  RunStore+Device.swift     where runs are saved on the phone
  ContentView.swift         live screen
  RunListView.swift         past runs, notes, sharing
  JogLockTrackerApp.swift   app entry, notification banners
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
