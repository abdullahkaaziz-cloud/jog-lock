# ADR-0004: Treadmill distance from steps and a stride learned on GPS runs

## Status

Accepted

## Date

2026-11-22

## Context

Treadmill runs have no GPS, so the only distance signal is the step count. Distance = steps × step length, and step length varies a lot between people (height, leg length) and, for one person, with pace. The app can't ask the treadmill.

The iPhone has its own step-based distance (`CMPedometerData.distance`). Apple calibrates it in the background from GPS, but how well depends on settings the app can't see.

## Decision

- **Learn each runner's stride on their outdoor runs.** After an outdoor run that passes the step check (at least 90% counted), the app cuts it into 30-second windows. In each, step length = counted GPS distance ÷ steps and cadence = steps ÷ 30 s. A line, step length = a + b × cadence, is fitted by least squares once there are 10 windows. With too little spread in cadence it's the median step length. The slope is held between 0 and 2 m per step/s, and cadence is clamped to the range seen, so the model never extrapolates far. The last 300 windows are kept on the phone.
- **Treadmill distance**: each pedometer update's new steps × step length at that update's cadence. Without a model, use the iPhone's own pedometer distance; without that, 0.75 m a step (short on purpose, so it never over-counts).
- **Checks**: steps faster than 4 a second don't count; the share of time Core Motion is fairly sure the phone is in a car, on a bike or still (medium confidence or better) is removed. Distance waits up to 60 s for late motion data. At Stop the app adds Core Motion's activity history for the whole run, because live updates pause while the app is in the background.
- **No background keep-alive**: the app doesn't run location updates just to stay awake on a treadmill. The pedometer keeps counting while the app is suspended, and its first update on return covers the gap.

`TreadmillCounter`, `StrideModel` and `StrideCalibration` live in `JogLockCore` and are mirrored in `Tools/treadmill.py`. Both suites check the same scenarios and two synthetic fixtures: an outdoor run whose stride is known (the fit must recover it) and a treadmill run with a background gap and a still period.

## Alternatives considered

- **Only Apple's pedometer distance.** No learning needed, but it can be several per cent off and the app can't tell when it hasn't been calibrated.
- **Ask for the runner's height.** A rough formula (about 0.4 × height for walking, more for running) is a guess that ignores pace.
- **Ask for the treadmill's distance at the end.** Accurate, but anyone can type any number, which defeats the point of the app.

## Consequences

- Treadmill distance gets better as the runner does outdoor runs. The first treadmill runs before any outdoor run are less accurate.
- It can't be checked against GPS, so it's easier to cheat than outdoor distance. The cadence limit and activity checks make it slower than just running.
- The app doesn't need to stay awake on a treadmill, but the live distance only updates while the app is open.
