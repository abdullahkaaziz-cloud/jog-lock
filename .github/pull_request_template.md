## What and why

<!-- One short paragraph: the problem, and the approach taken. -->

## Changes made

- `path/to/file`: what changed

## Things I didn't touch (on purpose)

- 

## Potential concerns

- 

## How it was verified

- [ ] Swift tests: `swift test` in `Packages/JogLockCore`
- [ ] Python mirror tests: `python3 Tools/test_engine.py && python3 Tools/test_stepgate.py`
- [ ] App builds (CI job `ios-build`)
- [ ] On a phone: <!-- what was run (jog, walk, treadmill), or why it isn't needed -->

## Definition of Done

- [ ] Acceptance criteria met
- [ ] New behaviour is covered by tests that fail without the change
- [ ] Engine rule changes are made in Swift **and** in the Python mirror, and the parity tests pass
- [ ] No real GPS tracks, secrets or personal data committed
- [ ] README, CHANGELOG and ADRs updated where relevant
