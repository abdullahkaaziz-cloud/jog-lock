#!/usr/bin/env python3
"""Checks for the distance engine using simulated runs.

python3 test_engine.py
"""

from __future__ import annotations

import json
import os
import random
import sys
import tempfile

from replay import Engine, Fix, Settings, distance_m, read_log, run_engine
from simulate import simulate

FAILED = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global FAILED
    print(f"[{'PASS' if ok else 'FAIL'}] {name}{' - ' + detail if detail else ''}")
    if not ok:
        FAILED += 1


def to_fixes(lines):
    return [
        Fix(ln["t"], ln["lat"], ln["lon"], ln["hAcc"], ln["speed"], ln["speedAcc"], ln["stationary"])
        for ln in lines
        if ln["type"] == "fix"
    ]


def run(kind, seed=1, settings=None):
    lines, true_m = simulate(kind, seed)
    e, dec = run_engine(to_fixes(lines), settings or Settings())
    return e, dec, true_m


def test_geometry():
    try:
        from geographiclib.geodesic import Geodesic
    except ImportError:
        print("[SKIP] geographiclib not installed")
        return
    rng = random.Random(7)
    worst = 0.0
    for _ in range(2000):
        lat = rng.uniform(-70, 70)
        lon = rng.uniform(-179, 179)
        # hops of up to ~1.2 km in any direction
        dlat = rng.uniform(-0.011, 0.011)
        dlon = rng.uniform(-0.011, 0.011)
        ref = Geodesic.WGS84.Inverse(lat, lon, lat + dlat, lon + dlon)["s12"]
        mine = distance_m(lat, lon, lat + dlat, lon + dlon)
        if ref > 1:
            worst = max(worst, abs(mine - ref) / ref)
    check("local WGS84 distance matches geodesic", worst < 1e-5, f"worst relative error {worst:.2e}")
    # dateline wrap
    d = distance_m(0.0, 179.9999, 0.0, -179.9999)
    check("dateline wrap", abs(d - 22.26) < 0.1, f"{d:.2f} m")


def test_track_accuracy():
    errs, raw_errs, speed_errs = [], [], []
    for seed in range(1, 21):
        e, _, true_m = run("track", seed)
        errs.append((e.clean - true_m) / true_m * 100)
        raw_errs.append((e.raw - true_m) / true_m * 100)
        speed_errs.append((e.speed_dist - true_m) / true_m * 100)
    mean = sum(errs) / len(errs)
    worst = max(errs, key=abs)
    check(
        "clean on a 1 km track run: mean within ±2.5%, every run within ±5% (20 seeds)",
        abs(mean) < 2.5 and all(abs(x) < 5 for x in errs),
        f"mean {mean:+.2f}%, worst {worst:+.2f}%",
    )
    check(
        "speed-based within ±2% on the track",
        all(abs(x) < 2 for x in speed_errs),
        f"mean {sum(speed_errs) / len(speed_errs):+.2f}%",
    )
    check(
        "raw over-counts more than clean",
        sum(raw_errs) / len(raw_errs) > mean,
        f"raw mean {sum(raw_errs) / len(raw_errs):+.2f}%",
    )


def test_slow_jog():
    errs = []
    for seed in range(1, 11):
        e, _, true_m = run("slow", seed)
        errs.append((e.clean - true_m) / true_m * 100)
    check(
        "slow jog (2.2 m/s) within ±4%",
        all(abs(x) < 4 for x in errs),
        f"mean {sum(errs) / len(errs):+.2f}%, worst {max(errs, key=abs):+.2f}%",
    )


def test_streets():
    errs, spd = [], []
    for seed in range(1, 11):
        e, _, true_m = run("streets", seed)
        errs.append((e.clean - true_m) / true_m * 100)
        spd.append((e.speed_dist - true_m) / true_m * 100)
    mean = sum(errs) / len(errs)
    check(
        "street grid (90° turn every 120 m): mean within ±2.5%, every run within ±5%",
        abs(mean) < 2.5 and all(abs(x) < 5 for x in errs),
        f"clean mean {mean:+.2f}%, worst {max(errs, key=abs):+.2f}%, speed mean {sum(spd) / len(spd):+.2f}%",
    )


def test_stop_adds_little():
    worst = 0.0
    for seed in range(1, 11):
        lines, _ = simulate("stop", seed)
        e = Engine()
        added = 0.0
        for ln in lines:
            if ln["type"] != "fix":
                continue
            before = e.clean
            e.process(Fix(ln["t"], ln["lat"], ln["lon"], ln["hAcc"], ln["speed"], ln["speedAcc"], ln["stationary"]))
            if ln.get("simStop"):
                added += e.clean - before
        worst = max(worst, added)
    check("60 s stop mid-run adds < 5 m", worst < 5, f"worst {worst:.1f} m over 10 seeds")


def test_stop_with_update_pause():
    """iOS can stop sending updates while stationary; movement after resuming must count."""
    errs = []
    lost_resume = 0
    for seed in range(1, 11):
        e, dec, true_m = run("stop_pause", seed)
        errs.append((e.clean - true_m) / true_m * 100)
        lost_resume += dec.count("drift")
    mean = sum(errs) / len(errs)
    check(
        "stop with paused updates: resume movement still counted",
        abs(mean) < 2.5 and all(abs(x) < 5 for x in errs) and lost_resume == 0,
        f"mean {sum(errs) / len(errs):+.2f}%, drift decisions {lost_resume}",
    )


def test_standstill():
    worst = 0.0
    for seed in range(1, 11):
        e, _, _ = run("standstill", seed)
        worst = max(worst, e.clean)
    check("5 min standing still (no iOS flag) adds < 15 m", worst < 15, f"worst {worst:.1f} m")
    worst_ns = 0.0
    for seed in range(1, 11):
        e, _, _ = run("standstill_nospeed", seed)
        worst_ns = max(worst_ns, e.clean)
    check("5 min standing, no speed and no flag, adds < 30 m", worst_ns < 30, f"worst {worst_ns:.1f} m")


def test_outliers():
    e, dec, true_m = run("outliers", 2)
    clean_err = (e.clean - true_m) / true_m * 100
    check("outlier jumps rejected", dec.count("rejectedJump") >= 3, f"{dec.count('rejectedJump')} rejected")
    check("outliers barely move clean distance", abs(clean_err) < 3, f"{clean_err:+.2f}%")
    check("raw is badly hit by outliers", e.raw > true_m * 1.2, f"raw {e.raw:.0f} m")


def test_urban():
    errs, raw_errs = [], []
    for seed in range(1, 11):
        e, _, true_m = run("urban", seed)
        errs.append((e.clean - true_m) / true_m * 100)
        raw_errs.append((e.raw - true_m) / true_m * 100)
    mean, raw_mean = sum(errs) / len(errs), sum(raw_errs) / len(raw_errs)
    check(
        "urban (very noisy, 25 s dropout): mean within ±10% and far better than raw",
        abs(mean) < 10 and raw_mean > 2 * mean,
        f"clean mean {mean:+.2f}%, worst {max(errs, key=abs):+.2f}%, raw mean {raw_mean:+.2f}%",
    )


def test_drive_counts_nothing():
    e, _dec, _ = run("drive", 1)
    check("driving at 14 m/s counts ~0 m", e.clean < 30, f"clean {e.clean:.1f} m, raw {e.raw:.0f} m")
    check("speed-based ignores driving", e.speed_dist < 30, f"{e.speed_dist:.1f} m")


def test_warmup_gate():
    _e, dec, _ = run("track", 5)
    first = dec.index("warmupComplete")
    check("warm-up waits for good fixes", first >= 5, f"tracking began at fix {first}")


def test_out_of_order_and_duplicates():
    e = Engine()
    base = Fix(0, 51.5, -0.12, 5, 3, 0.5, False)
    for i in range(3):
        e.process(Fix(i, 51.5, -0.12, 5, 0, 0.5, False))
    d1 = e.process(Fix(2, 51.5, -0.12, 5, 3, 0.5, False))
    d2 = e.process(Fix(1.5, 51.5, -0.12, 5, 3, 0.5, False))
    check("duplicate / old timestamps rejected", d1 == d2 == "rejectedOutOfOrder", f"{d1}, {d2}")
    _ = base


def test_gap_not_bridged():
    e = Engine()
    lat0, lon0 = 51.5, -0.12
    for i in range(3):
        e.process(Fix(i, lat0, lon0, 5, 0.0, 0.5, False))
    # moving fix, then a 10 minute gap, then 2 km away (e.g. app was killed)
    e.process(Fix(10, lat0 + 0.0003, lon0, 5, 3.0, 0.5, False))
    before = e.clean
    d = e.process(Fix(610, lat0 + 0.018, lon0, 5, 3.0, 0.5, False))
    check("long gap while moving is not bridged", d == "gapReset" and e.clean == before, d)


def test_finalize_tail():
    e = Engine()
    for i in range(3):
        e.process(Fix(i, 51.5, -0.12, 5, 0.0, 0.5, False))
    step = 3.0 / 111_250  # ~3 m north per fix, below the 5 m min step
    e.process(Fix(3, 51.5 + step, -0.12, 5, 3.0, 0.5, False))
    before = e.clean
    e.finalize()
    check("finalize counts the last partial segment", before == 0 and 2.5 < e.clean < 3.5, f"{e.clean:.2f} m")


def test_replay_parity_roundtrip():
    """The app logs cumulative totals per fix; replaying must reproduce them."""
    lines, _ = simulate("stop", 4)
    e = Engine()
    out = []
    for ln in lines:
        if ln["type"] == "fix":
            f = Fix(ln["t"], ln["lat"], ln["lon"], ln["hAcc"], ln["speed"], ln["speedAcc"], ln["stationary"])
            dec = e.process(f)
            ln = dict(ln, decision=dec, clean=e.clean, speedDist=e.speed_dist, raw=e.raw)
        out.append(ln)
    e.finalize()
    out.append(
        {
            "type": "event",
            "t": out[-1]["t"] + 1,
            "name": "stop",
            "clean": e.clean,
            "speedDist": e.speed_dist,
            "raw": e.raw,
        }
    )
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "raw.jsonl")
        with open(p, "w") as fh:
            for ln in out:
                fh.write(json.dumps(ln) + "\n")
        log = read_log(p)
        e2, _ = run_engine(log.fixes, Settings())
    check("replay reproduces logged totals", abs(e2.clean - e.clean) < 1e-6, f"{e2.clean:.3f} vs {e.clean:.3f}")


FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def test_run1_fixture():
    """Real run, 22 Nov 2026 (anonymised): Strava 3.00 km, phone said 3.012 km.

    Guards against any change to the engine silently moving the numbers on
    real data. If a deliberate rule change moves them, update the expected
    values here and say why in the commit message.
    """
    log = read_log(os.path.join(FIXTURES, "run1-anon.jsonl"))
    e, _ = run_engine(log.fixes, Settings())
    stop = next(ln for ln in log.lines if ln.get("type") == "event" and ln.get("name") == "stop")
    check(
        "run 1: replay matches the phone's live total",
        abs(e.clean - stop["clean"]) < 0.5,
        f"replay {e.clean:.2f} m, phone {stop['clean']:.2f} m",
    )
    check("run 1: cleaned distance is 3012.2 m (Strava 3000 m)", abs(e.clean - 3012.22) < 0.5, f"{e.clean:.2f} m")
    check("run 1: speed-based distance is 2863.4 m", abs(e.speed_dist - 2863.39) < 0.5, f"{e.speed_dist:.2f} m")
    check("run 1: raw distance is 3048.5 m", abs(e.raw - 3048.47) < 0.5, f"{e.raw:.2f} m")


if __name__ == "__main__":
    for fn in [
        test_geometry,
        test_track_accuracy,
        test_slow_jog,
        test_streets,
        test_stop_adds_little,
        test_stop_with_update_pause,
        test_standstill,
        test_outliers,
        test_urban,
        test_drive_counts_nothing,
        test_warmup_gate,
        test_out_of_order_and_duplicates,
        test_gap_not_bridged,
        test_finalize_tail,
        test_replay_parity_roundtrip,
        test_run1_fixture,
    ]:
        fn()
    print()
    print("All checks passed." if FAILED == 0 else f"{FAILED} check(s) failed.")
    sys.exit(1 if FAILED else 0)
