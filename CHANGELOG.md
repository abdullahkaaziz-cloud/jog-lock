# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- CI on every pull request: Python lint and mirror tests on Linux, and an unsigned iOS build on macOS.
- A regression test built from the first real jog (anonymised), pinning its cleaned, speed-based and raw totals.
- `Tools/anonymize_log.py`, to make a run log safe to commit.
- Contribution guide with the Definition of Done, a pull request template, and ADR-0001.
- A shared Xcode scheme, so the app builds the same way on any Mac.

## [0.1.0] - 2026-11-22

### Added

- Test build of the jog tracker: Core Location fitness updates, Strava-style clean-up, three distance estimates, run logs, GPX export.
- Python replay, simulation and engine checks.
- First real jog: cleaned distance 3.012 km against Strava's 3.00 km.
