#!/usr/bin/env python3
"""Builds fixtures/synthetic-gated-run.jsonl, a made-up run with step and
motion data, so the Swift and Python step gates can be checked against
each other.

The run: a simulated 1 km track jog. Steps come in at 2.7 a second for
the first two thirds, then the pedometer goes quiet (that distance should
count as "too few steps"), and Core Motion reports a car for the last
part. The stop event carries the totals the Python replay works out; the
Swift test must land on the same numbers.

  python3 make_gate_fixture.py
"""

from __future__ import annotations

import json
import os

from replay import replay_gated
from simulate import simulate

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "synthetic-gated-run.jsonl")


def build() -> list[dict]:
    sim, _ = simulate("track", 3)
    header = dict(sim[0])
    header["gate"] = {
        "maxStepLength": 2.0,
        "matchWindow": 5.0,
        "settleDelay": 60.0,
        "stallLimit": 120.0,
        "vehicleConfidence": 1,
    }
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


if __name__ == "__main__":
    lines = build()
    with open(OUT, "w", encoding="utf-8") as fh:
        for ln in lines:
            fh.write(json.dumps(ln, separators=(",", ":")) + "\n")
    stop = lines[-1]
    print(
        f"Wrote {OUT}: counted {stop['counted']:.1f} m, no steps {stop['noSteps']:.1f} m, "
        f"vehicle {stop['vehicle']:.1f} m of {stop['clean']:.1f} m cleaned"
    )
