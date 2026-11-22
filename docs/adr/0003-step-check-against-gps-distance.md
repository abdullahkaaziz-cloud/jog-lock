# ADR-0003: Check GPS distance against steps and motion activity

## Status

Accepted

## Date

2026-11-22

## Context

Apps unlock when the runner covers N km. GPS alone can't tell a jog from a drive, a bike ride or a phone handed to a friend on a scooter. The check has to run on the phone, cope with honest runners whose data is imperfect (steps reported late or in batches, GPS a few per cent long), and never need a network.

iPhones give two signals besides GPS: the pedometer (`CMPedometer`, a step count updated every few seconds) and motion activity (`CMMotionActivityManager`: walking, running, cycling, automotive, with a confidence).

## Decision

Add a step gate between the distance engine and the unlock (`StepGate.swift`, mirrored in `Tools/stepgate.py`):

- Each new step adds credit of 2 m (`maxStepLength`). A recreational runner's step is 0.8 to 1.5 m, so this leaves room for GPS error and long strides.
- Each piece of GPS distance the engine counts waits up to 60 s (`settleDelay`) for late data, then spends credit from steps within 5 s of it (`matchWindow`), nearest first. Distance the credit can't cover is "too few steps".
- Distance while Core Motion reports a car or bike with at least medium confidence is rejected whatever the steps say.
- If the pedometer goes quiet for 120 s (`stallLimit`) while GPS keeps counting, the waiting distance settles as too few steps.
- Unlocking uses only settled, counted distance. Stopping the run takes a final pedometer reading and settles everything.

`RunCounter` feeds the engine and the gate in the order inputs arrived. The same type rebuilds a run from its log after a relaunch, and the Python replay does the same, so live, resumed and replayed totals agree. A synthetic gated run in `Tools/fixtures/` is replayed by both test suites.

## Alternatives considered

- **Compare total steps with total distance at the end.** Simple, but a walk around the house plus a drive passes. Matching steps to distance in time closes that.
- **Use Apple's pedometer distance instead of GPS.** It's calibrated per person but drifts by several per cent and is easy to inflate by shaking the phone.
- **Reject a whole run if any part looks wrong.** Punishes honest runners for one bad patch, such as a few seconds on a bus.

## Consequences

- Driving and cycling stop counting. Simulations: a drive with a shaken phone counts nothing when Core Motion spots the car; cycling with a few false steps counts about 12%; jogging and driving in one-minute turns adds about 9% of the driven distance.
- Motion & Fitness permission becomes necessary: without it nothing counts.
- The unlock lags the live distance by up to a minute, except when the runner taps Stop.
- Shaking the phone in a slow car can still fool it if Core Motion misses the car. A later version could compare cadence with speed, or check the whole run again at the end with Core Motion's full history.
