# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Race Day · Track design, step 8: the plan as cards to pick from (Every day, Each week, 5K plan) with a big distance, rest days and Save; the 5K plan's week with this week's three runs, what's coming and Repeat week; Settings in groups (you, voice coach, running, lock, help) with privacy and testing notes on their own screens; and Shoes with the pair you're wearing, how far it has left, and the other pairs.
- Race Day · Track design, step 7: the Lock tab, with where the lock stands on an ink card, what stays locked until you run, today's plan, banked time and borrowing, a switch for run-only apps, the lock buddy, time on apps and how to make the lock unbreakable. "Need your apps now?" puts banked time, borrowing and the run side by side, from Today and the Lock tab. The lock buddy, websites and time on apps screens are redrawn; the receipt gets a PAID stamp.
- Race Day · Track design, step 6: the Runs tab adds up this week, month or year with a bar for each day (`PeriodTotals`, with tests), offers last month wrapped, and lists runs under This week, Last week and earlier months with their routes. A run opens with its route, kilometre splits (`RunSplits`), how it was counted, Strava's distance, the shoes, notes and its files. The month wrapped is a short story to tap through, with a card to share.
- Race Day · Track design, step 5: after a run, the unlock moment in track red when it opened the apps, otherwise the run's summary (route, how it was counted, shoes, share and reel). Share cards in three styles (Track, Route, Receipt) with Save to Photos, and the reel redrawn on a paper map; its lock only opens if the run met its target.
- Race Day · Track design, step 4: the run in progress fills the screen, with the track standing up and what's left to unlock, km run, pace, steps and the last km (`KmSplits`, with tests). 5K plan runs show the run or walk under way with a countdown and the phases round it. The treadmill gets its tips, "Nice try" is a sheet with a card to share, the route opens as a map, the voice coach switches on and off, and a run finishes by holding the button.
- Race Day · Track design, steps 2 and 3: four tabs (Today, Runs, Lock, Settings), and Today rebuilt round the track: what's left to run or Unlocked, the chosen apps (names and icons drawn by iOS), the week's bars, Outdoor or Treadmill and Start, banked minutes and borrowing, and your lock buddy. Rest days and a lock paused by Screen Time have their own looks (`TodayWeek`, with tests).
- Race Day · Track design, step 1: Archivo cut into three fonts (`Tools/fonts/make_fonts.py`), the colours, the buttons, cards and list rows, and the running track that shows progress (`TrackGeometry`, with tests). Plan and status in `docs/design/BUILD-PLAN.md`.
- Lock buddies over iCloud: Together (both run, then both open) or For each other (your buddy's running opens your apps). Rules in core (`TeamMode`, `BuddyDay`), with tests; syncing with CloudKit and silent pushes, no server.
- Make a reel: a 10-second 1080 × 1920 video of a run, made on the phone (timing in `ReelTimeline`, with tests).
- Time on apps as a receipt to screenshot: km paid this week against what the app time would cost at 15 minutes a km. A monthly Wrapped card from the Runs screen (`MonthWrap`, with tests).
- Shoe mileage: kilometres per pair, credited once per run to the pair being worn, with a heads-up at 80% of the pair's limit and at the limit.
- Run-only apps: a second set of apps, locked except while a run is going (their own shield store, with a monitor that locks them four hours on at the latest).
- Plans for the lock: daily, weekly (running ahead earns days off) or a nine-week 5K plan with the voice coach calling the run and walk intervals; rest days in any plan. Rules in `RunPlan`, with tests.
- Route maps: live during a run, on each run's details, and all runs together.
- A voice coach with funny lines every 500 m, at halfway, near the end and at the unlock, in a choice of voices. Settings for the voice and the app you're running for.
- "Nice try" cards (shareable) when the step check throws out distance.
- Story-sized share card for each run.
- Lock-screen and Dynamic Island countdown during a run (Live Activity).
- The app lock (Screen Time), built on Tilawah Key's blocking:
  - Pick apps to lock; they stay locked each day until you've run the daily target, then open until 4:00.
  - A shield on locked apps saying how far away they are ("TikTok is 1.8 km away"), with a line that changes each minute. Run now opens Jog Lock (iOS 26.5+) or sends a notification that does.
  - An unlock celebration.
  - Banked minutes (15 a kilometre past the target, up to an hour), counted only while the locked apps are used, with a warning a minute before they run out.
  - Borrowing 30 minutes from tomorrow for 1 km more tomorrow.
  - While locked, apps can only be added and the lock can't be turned off.
  - Websites are blocked in other browsers too (iOS's web filter).
  - Websites typed in by name, for the ones the picker doesn't list (from Tilawah Key). Up to 40 in all; add-only while locked.
  - Time on apps on the home screen, from Screen Time: a day on average this week against last week, what it would take to run for, and the apps used most. Drawn by a new Device Activity Report extension, JogLockReport; the app never sees the numbers.
  - Shareable lock diagnostics in Settings.
  - Rules in `LockLedger` and `LockState`, with tests; ADR-0005.
- CI checks that each extension is built into the app with the right extension point and class. It checks the report extension in the app's Extensions folder too.
- The step check (anti-cheat): only GPS distance backed by steps, and not covered in a car or on a bike, counts toward unlocking. Run logs now include step and motion lines, and the stop event and run summary record what counted and what didn't.
- Motion & Fitness permission, with a warning when it's off.
- Treadmill mode: distance from steps × a stride length learned on your outdoor runs (or the iPhone's own estimate until then), with the same car, bike and standing-still checks.
- CI on every pull request: Python lint and mirror tests on Linux, and an unsigned iOS build on macOS.
- A regression test built from the first real jog (anonymised), pinning its cleaned, speed-based and raw totals.
- `Tools/anonymize_log.py`, to make a run log safe to commit.
- Contribution guide with the Definition of Done, a pull request template, and ADR-0001.
- A shared Xcode scheme, so the app builds the same way on any Mac.
- Swift unit tests for the distance engine, run files and the real-run fixture, run on Linux in CI.
- VoiceOver labels on the live screen.
- A privacy manifest (`PrivacyInfo.xcprivacy`).

### Changed

- The unlock moment comes after the run is saved, with the run's distance and time, instead of in the middle of it.
- The steps for testing a run against Strava moved to Settings.
- The app is called Jog Lock on the home screen, has a light look only, and its accent is track red.
- iOS 18 or later is required (same iPhones as iOS 17). This removes a deprecated location API.
- The speed-based distance is no longer shown or notified. It is still logged for comparison.
- The distance engine, run log formats and run files moved into a local Swift package, `JogLockCore`. The app links it. No change in behaviour.

### Fixed

- The Time tile no longer resets to 0:00 when a run is saved. It shows the finished run's length.
- Differences that round to zero show as +0.0%, not -0.0%.

## [0.1.0] - 2026-11-22

### Added

- Test build of the jog tracker: Core Location fitness updates, Strava-style clean-up, three distance estimates, run logs, GPX export.
- Python replay, simulation and engine checks.
- First real jog: cleaned distance 3.012 km against Strava's 3.00 km.
