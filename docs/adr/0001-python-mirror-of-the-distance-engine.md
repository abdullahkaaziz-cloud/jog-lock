# ADR-0001: Keep a Python mirror of the distance engine

## Status

Accepted

## Date

2026-11-22

## Context

The distance engine decides which GPS points count toward the unlock distance. Tuning it needs fast experiments on real runs: change a setting, replay a logged run, compare with Strava. Doing that through the iPhone app means a build, an install and another jog for every change.

The app logs every GPS point (`raw.jsonl`), so a run can be replayed off the phone.

## Decision

Keep `Tools/replay.py`, a line-for-line Python copy of `DistanceEngine.swift`, for replay, simulation and tuning on a laptop.

Parity is enforced, not assumed:

- The phone writes its own live totals into the log. `replay.py` reports whether its replay matches them.
- The anonymised real run in `Tools/fixtures/` has pinned expected totals. Both the Swift and the Python test suites check the same numbers.
- Any rule change is made in both implementations in the same pull request.

## Alternatives considered

- **Swift only, replay in a macOS command-line tool.** One implementation, but every experiment needs the Swift toolchain, and the simulation and plotting scripts would have to be rewritten.
- **Python only, engine runs on a server.** Unlocking would need a network connection, and GPS tracks would leave the phone.

## Consequences

- Two implementations to keep in step. A rule changed in one and not the other shows up as a fixture failure.
- New settings and rules can be tried on every logged run in seconds.
- The parity check catches drift between the two quickly.
