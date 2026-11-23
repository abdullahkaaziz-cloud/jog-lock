# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
