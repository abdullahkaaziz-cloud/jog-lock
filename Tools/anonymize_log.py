#!/usr/bin/env python3
"""Make a run log safe to commit as a test fixture.

Real run logs contain a precise GPS track and timestamps, so they show
where and when someone runs. This moves the track to a point in the
middle of the Atlantic (0° N, 30° W), turns it by a random angle, moves
the timestamps so the run starts on 2000-01-01, drops altitude and
heading, and replaces the run name.

Distances are kept: each point is converted to metres east and north of
the track's centre, rotated, and placed the same number of metres from
the new centre. Over a few kilometres that changes no distance by more
than a few millimetres, so replays of the fixture land on the totals the
phone logged.

  python3 anonymize_log.py raw.jsonl fixtures/run.jsonl
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys

FIXTURE_EPOCH = 946_684_800.0  # 2000-01-01T00:00:00Z
NEW_CENTRE = (0.0, -30.0)  # lat, lon: open ocean, so the fixture points at nobody
DROPPED = ("alt", "course", "courseAcc")  # altitude and heading would hint at the place and the turn

A = 6_378_137.0
F = 1.0 / 298.257223563
E2 = F * (2.0 - F)


def radii(lat_deg: float) -> tuple[float, float]:
    """Meridional (M) and prime-vertical (N) radii of curvature, WGS84."""
    s = math.sin(math.radians(lat_deg))
    w = math.sqrt(1 - E2 * s * s)
    return A * (1 - E2) / (w * w * w), A / w


def relocate(lines: list[dict], angle_deg: float) -> list[dict]:
    fixes = [ln for ln in lines if isinstance(ln.get("lat"), (int, float)) and isinstance(ln.get("lon"), (int, float))]
    if not fixes:
        return lines
    lat0 = sum(ln["lat"] for ln in fixes) / len(fixes)
    lon0 = sum(ln["lon"] for ln in fixes) / len(fixes)
    m0, n0 = radii(lat0)
    m1, n1 = radii(NEW_CENTRE[0])
    cos0, cos1 = math.cos(math.radians(lat0)), math.cos(math.radians(NEW_CENTRE[0]))
    a = math.radians(angle_deg)
    out = []
    for ln in lines:
        ln = {k: v for k, v in ln.items() if k not in DROPPED}
        if isinstance(ln.get("lat"), (int, float)) and isinstance(ln.get("lon"), (int, float)):
            d_lon = (ln["lon"] - lon0 + 180.0) % 360.0 - 180.0
            east = math.radians(d_lon) * n0 * cos0
            north = math.radians(ln["lat"] - lat0) * m0
            east, north = east * math.cos(a) - north * math.sin(a), east * math.sin(a) + north * math.cos(a)
            ln["lat"] = NEW_CENTRE[0] + math.degrees(north / m1)
            ln["lon"] = NEW_CENTRE[1] + math.degrees(east / (n1 * cos1))
        out.append(ln)
    return out


def shift_time(lines: list[dict]) -> list[dict]:
    times = [ln["t"] for ln in lines if isinstance(ln.get("t"), (int, float))]
    if not times:
        return lines
    offset = min(times) - FIXTURE_EPOCH
    return [{**ln, "t": round(ln["t"] - offset, 3)} if isinstance(ln.get("t"), (int, float)) else ln for ln in lines]


def anonymize(lines: list[dict], name: str, angle_deg: float) -> list[dict]:
    out = shift_time(relocate(lines, angle_deg))
    for ln in out:
        if ln.get("type") == "header":
            ln["name"] = name
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("dest")
    ap.add_argument("--name", default="anonymised-run")
    ap.add_argument("--angle", type=float, default=None, help="rotation in degrees (default: random, not recorded)")
    args = ap.parse_args(argv)

    angle = args.angle if args.angle is not None else random.SystemRandom().uniform(0, 360)
    with open(args.source, encoding="utf-8") as fh:
        lines = [json.loads(raw) for raw in fh if raw.strip()]
    result = anonymize(lines, args.name, angle)
    with open(args.dest, "w", encoding="utf-8") as fh:
        for ln in result:
            fh.write(json.dumps(ln, separators=(",", ":")) + "\n")
    print(f"Wrote {args.dest} ({len(result)} lines)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
