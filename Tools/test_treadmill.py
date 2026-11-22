#!/usr/bin/env python3
"""Checks for treadmill mode (treadmill.py): the stride model and step counting.

Packages/JogLockCore/Tests/JogLockCoreTests/TreadmillTests.swift runs the
same scenarios against the Swift code.

  python3 test_treadmill.py
"""

from __future__ import annotations

import json
import os
import sys

from treadmill import StrideModel, StrideSample, TreadmillCounter, fit_stride, replay_treadmill, stride_samples

FAILED = 0
T0 = 1_700_000_000.0
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
MODEL = StrideModel(intercept=0.5, slope=0.2, min_cadence=2.2, max_cadence=3.2, samples=40)


def check(name: str, ok: bool, detail: str = "") -> None:
    global FAILED
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" - {detail}" if detail else ""))
    if not ok:
        FAILED += 1


def load(name: str) -> list[dict]:
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as fh:
        return [json.loads(x) for x in fh if x.strip()]


def treadmill_run(
    counter: TreadmillCounter,
    seconds: int,
    cadence: float,
    every: float = 2.5,
    ped_per_step: float | None = None,
    start: float = T0,
) -> None:
    for k in range(1, int(seconds / every) + 1):
        n = int(cadence * every * k)
        counter.add_steps(start + every * k, n, None if ped_per_step is None else n * ped_per_step)


def test_fit_steady_cadence():
    samples = [StrideSample(2.7, x) for x in (1.0, 1.1, 1.05, 0.95, 1.2, 1.0, 1.1, 0.9, 1.05, 1.15, 1.0)]
    m = fit_stride(samples)
    check(
        "steady cadence: flat model at the median step", m is not None and m.slope == 0 and m.intercept == 1.05, f"{m}"
    )


def test_fit_recovers_a_line():
    samples = [StrideSample(2.2 + 0.1 * i, 0.5 + 0.2 * (2.2 + 0.1 * i)) for i in range(11)]
    m = fit_stride(samples)
    ok = m is not None and abs(m.slope - 0.2) < 1e-9 and abs(m.intercept - 0.5) < 1e-9
    check("cadence spread: fits step length = 0.5 + 0.2 x cadence", ok, f"{m}")


def test_fit_needs_ten_samples():
    check("fewer than 10 usable windows: no model", fit_stride([StrideSample(2.7, 1.0)] * 9) is None)


def test_step_length_limits():
    ok = (
        abs(MODEL.step_length(5.0) - (0.5 + 0.2 * 3.2)) < 1e-12
        and abs(MODEL.step_length(1.0) - (0.5 + 0.2 * 2.2)) < 1e-12
    )
    wild = StrideModel(intercept=-3.0, slope=2.0, min_cadence=1.0, max_cadence=4.0, samples=10)
    check(
        "cadence is held to the learned range; step length to 0.3-2.0 m",
        ok and wild.step_length(1.0) == 0.3 and wild.step_length(4.0) == 2.0,
    )


def test_model_distance():
    c = TreadmillCounter(T0, MODEL)
    treadmill_run(c, 600, 2.8)
    c.finish()
    expected = c.steps * (0.5 + 0.2 * 2.8)
    check(
        "with a stride model: steps x step length at that cadence",
        abs(c.counted - expected) < 1e-6,
        f"{c.counted:.1f} vs {expected:.1f} m",
    )


def test_pedometer_distance_without_model():
    c = TreadmillCounter(T0)
    treadmill_run(c, 600, 2.8, ped_per_step=0.8)
    c.finish()
    check("no model: the iPhone's own pedometer distance", abs(c.counted - c.steps * 0.8) < 1e-6, f"{c.counted:.1f} m")


def test_default_step_without_anything():
    c = TreadmillCounter(T0)
    treadmill_run(c, 600, 2.8)
    c.finish()
    check(
        "no model, no pedometer distance: 0.75 m a step", abs(c.counted - c.steps * 0.75) < 1e-6, f"{c.counted:.1f} m"
    )


def test_cadence_cap():
    c = TreadmillCounter(T0, MODEL)
    treadmill_run(c, 60, 6.0)  # phone shaken by hand
    c.finish()
    most = 4.0 * 60 * MODEL.step_length(4.0)
    check("steps faster than 4 a second don't count", c.counted <= most + 1e-6, f"{c.counted:.1f} m, cap {most:.1f} m")


def test_standing_still_share_rejected():
    c = TreadmillCounter(T0, MODEL)
    c.add_motion(T0, "running", 2)
    c.add_motion(T0 + 150, "stationary", 2)
    c.add_steps(T0 + 300, 840)  # one update after five minutes in the background
    c.finish()
    total = 840 * MODEL.step_length(840 / 300)
    check(
        "half the time 'standing still': half the distance rejected",
        abs(c.rejected - total / 2) < 1e-6,
        f"rejected {c.rejected:.1f} of {total:.1f} m",
    )


def test_vehicle_rejected_low_confidence_still_counts():
    c = TreadmillCounter(T0, MODEL)
    c.add_motion(T0, "automotive", 2)
    treadmill_run(c, 120, 2.8)
    c.finish()
    d = TreadmillCounter(T0, MODEL)
    d.add_motion(T0, "stationary", 0)
    treadmill_run(d, 120, 2.8)
    d.finish()
    check(
        "car: nothing counts; low-confidence 'still': everything counts",
        c.counted == 0 and d.rejected == 0,
        f"car counted {c.counted:.1f} m, low-confidence rejected {d.rejected:.1f} m",
    )


def test_pending_until_settled():
    c = TreadmillCounter(T0, MODEL)
    treadmill_run(c, 300, 2.8)
    waiting = c.pending
    c.finish()
    check(
        "the last minute waits for late motion data",
        0 < waiting <= 61 * 2.8 * MODEL.step_length(2.8),
        f"waiting {waiting:.1f} m",
    )


def test_stride_from_honest_fixture():
    lines = load("synthetic-honest-run.jsonl")
    m = fit_stride(stride_samples(lines))
    recorded = StrideModel.from_dict(lines[-1]["stride"])
    ok = m is not None and abs(m.slope - 0.2) < 0.02 and abs(m.intercept - 0.5) < 0.05
    check("learns the stride that generated the honest run (0.5 + 0.2 x cadence)", ok, f"{m}")
    check("honest run: same model as recorded in the fixture", m == recorded)


def test_treadmill_fixture_parity():
    lines = load("synthetic-treadmill-run.jsonl")
    stop = lines[-1]
    c = replay_treadmill(lines)
    ok = abs(c.counted - stop["counted"]) < 0.01 and abs(c.rejected - stop["rejected"]) < 0.01
    check(
        "treadmill run replays to its recorded totals",
        ok and c.steps == stop["steps"],
        f"counted {c.counted:.2f} m (recorded {stop['counted']:.2f} m)",
    )


def test_gated_run_with_too_few_steps_teaches_nothing():
    check("a run that failed the step check teaches nothing", stride_samples(load("synthetic-gated-run.jsonl")) == [])


if __name__ == "__main__":
    for fn in [
        test_fit_steady_cadence,
        test_fit_recovers_a_line,
        test_fit_needs_ten_samples,
        test_step_length_limits,
        test_model_distance,
        test_pedometer_distance_without_model,
        test_default_step_without_anything,
        test_cadence_cap,
        test_standing_still_share_rejected,
        test_vehicle_rejected_low_confidence_still_counts,
        test_pending_until_settled,
        test_stride_from_honest_fixture,
        test_treadmill_fixture_parity,
        test_gated_run_with_too_few_steps_teaches_nothing,
    ]:
        fn()
    print()
    print("All checks passed." if FAILED == 0 else f"{FAILED} check(s) failed.")
    sys.exit(1 if FAILED else 0)
