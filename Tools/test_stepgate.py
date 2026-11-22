#!/usr/bin/env python3
"""Checks for the anti-cheat gate (stepgate.py), on made-up runs.

Packages/JogLockCore/Tests/JogLockCoreTests/StepGateTests.swift runs the
same scenarios against the Swift gate.

  python3 test_stepgate.py
"""

from __future__ import annotations

import json
import os
import sys

from replay import replay_gated
from stepgate import StepGate

FAILED = 0
T0 = 1_700_000_000.0


def check(name: str, ok: bool, detail: str = "") -> None:
    global FAILED
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" - {detail}" if detail else ""))
    if not ok:
        FAILED += 1


class Feed:
    """Plays GPS distance and pedometer updates into a gate in time order.

    GPS distance arrives every 2 s (what the engine counts at jogging pace);
    the pedometer reports cumulative steps every `step_every` seconds.
    """

    def __init__(self, gate: StepGate, start: float = T0):
        self.gate = gate
        self.t = start
        self.steps = 0.0
        self.gps_meters = 0.0

    def move(self, seconds: int, speed: float, cadence: float, step_every: float = 2.5, gps: bool = True) -> None:
        events = []
        if gps:
            for k in range(1, int(seconds / 2) + 1):
                events.append((self.t + 2 * k, 0, speed * 2))
        steps0 = self.steps
        n = int(seconds / step_every)
        for k in range(1, n + 1):
            events.append((self.t + step_every * k, 1, int(steps0 + cadence * step_every * k)))
        for t, kind, value in sorted(events):
            if kind == 0:
                self.gate.add_distance(value, t - 2, t)
                self.gps_meters += value
            else:
                self.gate.add_steps(t, value)
        self.steps = steps0 + cadence * seconds
        self.t += seconds


def test_honest_jog():
    g = StepGate(T0)
    f = Feed(g)
    f.move(600, speed=3, cadence=2.7)
    check(
        "jog: the last minute waits for late data until the end", 0 < g.pending <= 3 * 62, f"pending {g.pending:.0f} m"
    )
    g.finish()
    check("jog: all 1800 m counted", abs(g.counted - 1800) < 1e-6 and g.no_steps == 0, f"{g.counted:.1f} m")


def test_no_step_data():
    g = StepGate(T0)
    f = Feed(g)
    f.move(300, speed=3, cadence=0)
    g.finish()
    check("no steps at all: nothing counted", g.counted == 0 and abs(g.no_steps - 900) < 1e-6, f"{g.no_steps:.0f} m")


def test_driving_with_shaken_phone():
    g = StepGate(T0)
    g.add_motion(T0, "automotive", 2)
    f = Feed(g)
    f.move(300, speed=8, cadence=3)
    g.finish()
    check(
        "car + shaken phone: all rejected as vehicle",
        g.counted == 0 and abs(g.vehicle - 2400) < 1e-6,
        f"vehicle {g.vehicle:.0f} m",
    )


def test_low_confidence_vehicle_ignored():
    g = StepGate(T0)
    g.add_motion(T0, "automotive", 0)
    f = Feed(g)
    f.move(300, speed=3, cadence=2.7)
    g.finish()
    check("low-confidence 'car' doesn't block a real jog", abs(g.counted - 900) < 1e-6, f"{g.counted:.0f} m")


def test_cycling_without_motion_data():
    g = StepGate(T0)
    f = Feed(g)
    f.move(300, speed=5, cadence=0.3)
    g.finish()
    share = g.counted / 1500
    check("bike, few steps: under 15% counted", share < 0.15, f"{share:.0%} of 1500 m")


def test_batched_steps_still_count():
    g = StepGate(T0)
    f = Feed(g)
    f.move(600, speed=3, cadence=2.7, step_every=20)
    g.finish()
    check("steps reported every 20 s: all counted", abs(g.counted - 1800) < 1e-6, f"{g.counted:.1f} m")


def test_steps_before_gps_dont_carry_over():
    g = StepGate(T0)
    f = Feed(g)
    f.move(300, speed=0, cadence=2, gps=False)  # walking around indoors, no GPS
    f.move(120, speed=8, cadence=0)  # then driving, no motion data
    g.finish()
    # Steps reach back at most match_window plus one pedometer interval (5 + 2.5 s).
    check(
        "indoor steps back at most ~8 s of later driving",
        g.counted <= 2 * 7.5 * 2.0 + 1e-6,
        f"{g.counted:.0f} of 960 m",
    )


def test_alternating_jog_and_drive():
    g = StepGate(T0)
    f = Feed(g)
    jog = drive = 0.0
    for _ in range(5):
        before = f.gps_meters
        f.move(60, speed=3, cadence=2.7)
        jog += f.gps_meters - before
        before = f.gps_meters
        f.move(60, speed=8, cadence=0)
        drive += f.gps_meters - before
    g.finish()
    extra = g.counted - jog
    check(
        "jog/drive cheat: driving adds under 10% of its distance",
        extra < 0.1 * drive,
        f"counted {g.counted:.0f} m = jog {jog:.0f} + {extra:.0f} of {drive:.0f} driven",
    )


def test_stalled_pedometer_settles():
    g = StepGate(T0)
    f = Feed(g)
    f.move(60, speed=3, cadence=2.7)
    f.move(240, speed=3, cadence=0)  # pedometer goes quiet, GPS carries on
    check("quiet pedometer: waiting distance settles as no steps", g.no_steps > 0, f"{g.no_steps:.0f} m")


def test_step_count_going_down_is_ignored():
    g = StepGate(T0)
    g.add_steps(T0 + 10, 30)
    g.add_steps(T0 + 12, 20)
    g.add_steps(T0 + 14, 36)
    check("step count going down is ignored", g.steps == 36, f"{g.steps}")


def test_late_vehicle_sample():
    g = StepGate(T0)
    f = Feed(g)
    f.move(100, speed=3, cadence=2.7)
    f.move(20, speed=8, cadence=2.7)
    g.add_motion(T0 + 100, "automotive", 1)  # Core Motion notices the car 20 s late
    f.move(100, speed=8, cadence=2.7)
    g.finish()
    check(
        "car noticed late: distance since it started is rejected",
        abs(g.vehicle - 960) < 1e-6 and abs(g.counted - 300) < 1e-6,
        f"vehicle {g.vehicle:.0f} m, counted {g.counted:.0f} m",
    )


def test_duplicate_motion_ignored():
    g = StepGate(T0)
    first = g.add_motion(T0, "running", 2)
    second = g.add_motion(T0, "running", 2)
    check("the same motion sample twice is only added once", first and not second)


def test_gated_fixture_parity():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "synthetic-gated-run.jsonl")
    with open(path, encoding="utf-8") as fh:
        lines = [json.loads(x) for x in fh if x.strip()]
    stop = next(ln for ln in lines if ln.get("type") == "event" and ln.get("name") == "stop")
    e, g = replay_gated(lines)
    ok = all(
        abs(a - b) < 0.01
        for a, b in (
            (g.counted, stop["counted"]),
            (g.no_steps, stop["noSteps"]),
            (g.vehicle, stop["vehicle"]),
            (e.clean, stop["clean"]),
        )
    )
    check(
        "synthetic gated run replays to its recorded totals",
        ok and g.steps == stop["steps"],
        f"counted {g.counted:.2f} m (recorded {stop['counted']:.2f} m)",
    )


if __name__ == "__main__":
    for fn in [
        test_honest_jog,
        test_no_step_data,
        test_driving_with_shaken_phone,
        test_low_confidence_vehicle_ignored,
        test_cycling_without_motion_data,
        test_batched_steps_still_count,
        test_steps_before_gps_dont_carry_over,
        test_alternating_jog_and_drive,
        test_stalled_pedometer_settles,
        test_step_count_going_down_is_ignored,
        test_late_vehicle_sample,
        test_duplicate_motion_ignored,
        test_gated_fixture_parity,
    ]:
        fn()
    print()
    print("All checks passed." if FAILED == 0 else f"{FAILED} check(s) failed.")
    sys.exit(1 if FAILED else 0)
