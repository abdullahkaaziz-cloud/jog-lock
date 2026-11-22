#!/usr/bin/env python3
"""Builds the synthetic fixtures that both test suites replay, so the Swift
code and its Python mirror are checked against the same numbers. The stop
event of each fixture carries what the Python code works out; the Swift
tests must land on the same results.

- synthetic-gated-run.jsonl: a simulated 1 km track jog. Steps come in at
  2.7 a second for the first two thirds, then the pedometer goes quiet
  (that distance counts as "too few steps"), and Core Motion reports a car
  for the last part.
- synthetic-honest-run.jsonl: a 20-minute jog whose cadence rises and
  falls, with step length = 0.5 m + 0.2 m per step/s of cadence. The stop
  event carries the stride model learned from it.
- synthetic-treadmill-run.jsonl: a 15-minute treadmill run using that
  stride model, with five minutes the app spent in the background (one
  big pedometer update) and a minute Core Motion called "standing still".

  python3 make_fixtures.py
"""

from __future__ import annotations

import json
import math
import os

from replay import replay_gated
from simulate import simulate
from treadmill import fit_stride, replay_treadmill, stride_samples

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
GATE = {"maxStepLength": 2.0, "matchWindow": 5.0, "settleDelay": 60.0, "stallLimit": 120.0, "vehicleConfidence": 1}
TREADMILL = {
    "maxCadence": 4.0,
    "defaultStepLength": 0.75,
    "settleDelay": 60.0,
    "stillConfidence": 1,
    "vehicleConfidence": 1,
}
T0 = 946_684_800.0  # 2000-01-01


def build_gated() -> list[dict]:
    sim, _ = simulate("track", 3)
    header = dict(sim[0])
    header["gate"] = GATE
    fixes = [ln for ln in sim if ln["type"] == "fix"]
    t0, t1 = header["t"], fixes[-1]["t"]
    quiet_from = t0 + (t1 - t0) * 2 / 3
    car_from = t0 + (t1 - t0) * 0.85

    extra = [{"type": "motion", "t": t0 + 1.0, "activity": "running", "confidence": 2}]
    t, steps = t0, 0
    while t + 2.5 <= quiet_from:
        t += 2.5
        steps += round(2.7 * 2.5)
        extra.append({"type": "steps", "t": t, "steps": steps, "cadence": 2.7})
    extra.append({"type": "motion", "t": car_from, "activity": "automotive", "confidence": 2})

    # Interleave by time, fixes first on ties (the order the phone would log them).
    body = sorted(fixes + extra, key=lambda ln: (ln["t"], 0 if ln["type"] == "fix" else 1))
    lines = [header, *body]

    e, g = replay_gated(lines)
    lines.append(
        {
            "type": "event",
            "t": t1 + 1.0,
            "name": "stop",
            "clean": e.clean,
            "speedDist": e.speed_dist,
            "raw": e.raw,
            "counted": g.counted,
            "noSteps": g.no_steps,
            "vehicle": g.vehicle,
            "steps": g.steps,
        }
    )
    return lines


def cadence_at(t: float) -> float:
    return 2.6 + 0.3 * math.sin(2 * math.pi * t / 300)


def build_honest() -> list[dict]:
    """Straight jog north; speed = cadence x (0.5 + 0.2 x cadence)."""
    header = {
        "type": "header",
        "t": T0,
        "name": "honest",
        "device": "synthetic",
        "os": "-",
        "app": "-",
        "settings": json.loads(open(os.path.join(FIXTURES, "synthetic-gated-run.jsonl")).readline())["settings"],
        "gate": GATE,
        "mode": "outdoor",
    }
    lines = [header, {"type": "motion", "t": T0 + 1, "activity": "running", "confidence": 2}]
    north = steps = 0.0
    dt = 0.1
    for k in range(1, 1200 * 10 + 1):
        t = T0 + k * dt
        c = cadence_at(t - T0)
        speed = c * (0.5 + 0.2 * c)
        north += speed * dt
        steps += c * dt
        if k % 10 == 0:
            lines.append(
                {
                    "type": "fix",
                    "t": round(t, 3),
                    "lat": 51.5 + north / 111_257.8,
                    "lon": -0.12,
                    "hAcc": 5.0,
                    "speed": round(speed, 3),
                    "speedAcc": 0.5,
                    "stationary": False,
                }
            )
        if k % 25 == 0:
            lines.append({"type": "steps", "t": round(t, 3), "steps": int(steps), "cadence": round(c, 3)})
    model = fit_stride(stride_samples(lines))
    e, g = replay_gated(lines)
    lines.append(
        {
            "type": "event",
            "t": T0 + 1201,
            "name": "stop",
            "clean": e.clean,
            "speedDist": e.speed_dist,
            "raw": e.raw,
            "counted": g.counted,
            "noSteps": g.no_steps,
            "vehicle": g.vehicle,
            "steps": g.steps,
            "stride": model.to_dict(),
        }
    )
    return lines


def build_treadmill(stride: dict) -> list[dict]:
    header = {
        "type": "header",
        "t": T0,
        "name": "treadmill",
        "device": "synthetic",
        "os": "-",
        "app": "-",
        "mode": "treadmill",
        "stride": stride,
        "treadmill": TREADMILL,
    }
    lines = [header, {"type": "motion", "t": T0 + 2, "activity": "running", "confidence": 2}]
    steps = 0.0
    for k in range(1, 900 * 10 + 1):
        t = T0 + k * 0.1
        steps += (2.8 + 0.1 * math.sin(k / 400)) * 0.1
        in_background = 300 < t - T0 < 600
        if k % 25 == 0 and not in_background:
            lines.append(
                {"type": "steps", "t": round(t, 3), "steps": int(steps), "pedMeters": round(int(steps) * 0.8, 2)}
            )
        if abs(t - (T0 + 420)) < 1e-6:
            lines.append({"type": "motion", "t": T0 + 420, "activity": "stationary", "confidence": 2})
        if abs(t - (T0 + 480)) < 1e-6:
            lines.append({"type": "motion", "t": T0 + 480, "activity": "running", "confidence": 2})
    c = replay_treadmill(lines)
    lines.append(
        {"type": "event", "t": T0 + 901, "name": "stop", "counted": c.counted, "rejected": c.rejected, "steps": c.steps}
    )
    return lines


def write(name: str, lines: list[dict]) -> None:
    with open(os.path.join(FIXTURES, name), "w", encoding="utf-8") as fh:
        for ln in lines:
            fh.write(json.dumps(ln, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    gated = build_gated()
    write("synthetic-gated-run.jsonl", gated)
    honest = build_honest()
    write("synthetic-honest-run.jsonl", honest)
    treadmill = build_treadmill(honest[-1]["stride"])
    write("synthetic-treadmill-run.jsonl", treadmill)
    g, h, t = gated[-1], honest[-1], treadmill[-1]
    print(f"gated: counted {g['counted']:.1f} m, no steps {g['noSteps']:.1f} m, vehicle {g['vehicle']:.1f} m")
    print(f"honest: stride {h['stride']}")
    print(f"treadmill: counted {t['counted']:.1f} m, rejected {t['rejected']:.1f} m, {t['steps']} steps")
