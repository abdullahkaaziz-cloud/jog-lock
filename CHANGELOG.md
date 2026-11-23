# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Route maps: live during a run, on each run's details, and all runs together.
- A voice coach with funny lines every 500 m, at halfway, near the end and at the unlock, in a choice of voices. Settings for the voice and the app you're running for.
- "Nice try" cards (shareable) when the step check throws out distance.
- Story-sized share card for each run.
- Lock-screen and Dynamic Island countdown during a run (Live Activity).
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
