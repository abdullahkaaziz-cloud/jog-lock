#!/usr/bin/env python3
"""Generate synthetic run logs in the app's raw.jsonl format.

Used to test the distance engine without leaving the desk. The GPS error model
is a slow random drift (Gauss-Markov) plus a little white jitter, which is a
rough stand-in for what a phone reports. Real logs from the app are the truth;
this only checks that the logic behaves sensibly.

  python3 simulate.py track --out sim_track.jsonl
  python3 simulate.py --list
"""
from __future__ import annotations

import argparse
import json
import math
import random
from dataclasses import dataclass

from replay import WGS84_A, WGS84_E2, Settings, settings_to_swift_dict

REF_LAT, REF_LON = 51.5000, -0.1200  # arbitrary reference point
T0 = 1_763_830_000.0                 # arbitrary start time (unix seconds)

# Standard 400 m track, lane 1 running line: two straights + two semicircles.
STRAIGHT = 84.39
RADIUS = (400.0 - 2 * STRAIGHT) / (2 * math.pi)  # ~36.80 m


def local_radii(lat_deg: float) -> tuple[float, float]:
    s = math.sin(math.radians(lat_deg))
    w = math.sqrt(1 - WGS84_E2 * s * s)
    return WGS84_A * (1 - WGS84_E2) / w ** 3, WGS84_A / w  # (M, N)


M_REF, N_REF = local_radii(REF_LAT)


def to_latlon(x: float, y: float) -> tuple[float, float]:
    lat = REF_LAT + math.degrees(y / M_REF)
    lon = REF_LON + math.degrees(x / (N_REF * math.cos(math.radians(REF_LAT))))
    return lat, lon


def track_xy(s: float) -> tuple[float, float]:
    """Point at distance s (m) along the 400 m running line."""
    s %= 400.0
    half_circle = math.pi * RADIUS
    if s < STRAIGHT:                       # bottom straight, heading +x
        return s, 0.0
    s -= STRAIGHT
    if s < half_circle:                    # right bend
        a = s / RADIUS
        return STRAIGHT + RADIUS * math.sin(a), RADIUS - RADIUS * math.cos(a)
    s -= half_circle
    if s < STRAIGHT:                       # top straight, heading -x
        return STRAIGHT - s, 2 * RADIUS
    s -= STRAIGHT
    a = s / RADIUS                         # left bend
    return -RADIUS * math.sin(a), RADIUS + RADIUS * math.cos(a)


def line_xy(s: float) -> tuple[float, float]:
    return s, 0.0


def streets_xy(s: float, leg: float = 120.0) -> tuple[float, float]:
    """Street grid: alternate 120 m legs east and north (a 90 degree turn every leg)."""
    k = int(s // leg)
    r = s - k * leg
    x = (k + 1) // 2 * leg + (r if k % 2 == 0 else 0.0)
    y = k // 2 * leg + (r if k % 2 == 1 else 0.0)
    return x, y


@dataclass
class Noise:
    sigma_drift: float = 2.5    # m, slow wander
    tau: float = 30.0           # s, how slowly it wanders
    sigma_white: float = 0.6    # m, per-fix jitter
    h_acc: tuple[float, float] = (4.0, 7.0)
    sigma_speed: float = 0.15   # m/s
    speed_acc: tuple[float, float] = (0.3, 0.7)


class GPSError:
    def __init__(self, noise: Noise, rng: random.Random):
        self.n = noise
        self.rng = rng
        self.ex = rng.gauss(0, noise.sigma_drift)
        self.ey = rng.gauss(0, noise.sigma_drift)

    def step(self, dt: float = 1.0) -> tuple[float, float]:
        phi = math.exp(-dt / self.n.tau)
        k = math.sqrt(1 - phi * phi) * self.n.sigma_drift
        self.ex = phi * self.ex + k * self.rng.gauss(0, 1)
        self.ey = phi * self.ey + k * self.rng.gauss(0, 1)
        return (self.ex + self.rng.gauss(0, self.n.sigma_white),
                self.ey + self.rng.gauss(0, self.n.sigma_white))


def fix_line(t, x, y, h_acc, speed, speed_acc, stationary=False, **extra):
    lat, lon = to_latlon(x, y)
    line = {"type": "fix", "t": round(t, 3), "lat": lat, "lon": lon,
            "hAcc": round(h_acc, 2), "speed": round(speed, 3), "speedAcc": round(speed_acc, 2),
            "stationary": stationary}
    line.update(extra)
    return line


def header(name: str) -> dict:
    return {"type": "header", "t": T0, "name": name, "device": "simulator", "os": "sim",
            "app": "sim", "settings": settings_to_swift_dict(Settings())}


def simulate(kind: str, seed: int = 1) -> tuple[list[dict], float]:
    """Return (log lines, true distance in metres)."""
    rng = random.Random(seed)
    lines = [header(kind)]
    t = T0
    noise = Noise()
    path = track_xy

    def add(x, y, speed_true, stationary=False, noise_obj=None, err=None, h_rng=None, no_speed=False, **extra):
        ex, ey = err.step()
        lo, hi = (h_rng or noise_obj.h_acc)
        h = rng.uniform(lo, hi)
        sp = max(0.0, speed_true + rng.gauss(0, noise_obj.sigma_speed))
        sa = rng.uniform(*noise_obj.speed_acc)
        if no_speed:
            sp, sa = -1.0, -1.0
        lines.append(fix_line(t, x + ex, y + ey, h, sp, sa, stationary, **extra))

    if kind == "urban":
        noise = Noise(sigma_drift=6.0, tau=20.0, sigma_white=2.0, h_acc=(8.0, 35.0),
                      sigma_speed=0.35, speed_acc=(0.6, 2.5))
    if kind == "streets":
        path = streets_xy
    err = GPSError(noise, rng)

    # Warm-up: standing at the start for 12 s while accuracy improves.
    x0, y0 = path(0.0)
    for i in range(12):
        h_rng = (max(6.0, 45 - 4 * i), max(8.0, 50 - 4 * i))
        add(x0 + (30 - 2.5 * i) * 0.5, y0 + (30 - 2.5 * i) * 0.3, 0.0, noise_obj=noise, err=err, h_rng=h_rng)
        t += 1.0

    true_m = 0.0
    if kind in ("track", "stop", "stop_pause", "outliers", "urban", "slow", "streets"):
        target = 1000.0
        v = 2.2 if kind == "slow" else 3.0
        s = 0.0
        stopped = False
        while s < target:
            if kind == "stop" and not stopped and s >= 500.0:
                stopped = True
                x, y = path(s)
                for k in range(60):  # 60 s standing still at a crossing
                    flag = k >= 8     # iOS flags stationary after a few seconds
                    add(x, y, 0.0, stationary=flag, noise_obj=noise, err=err, simStop=True)
                    t += 1.0
            if kind == "stop_pause" and not stopped and s >= 500.0:
                # iOS flags stationary, then stops sending updates until the runner moves again.
                stopped = True
                x, y = path(s)
                for k in range(9):
                    add(x, y, 0.0, stationary=(k == 8), noise_obj=noise, err=err, simStop=True)
                    t += 1.0
                for _ in range(50):
                    err.step()
                    t += 1.0
            vi = max(1.5, v + rng.gauss(0, 0.15))
            s = min(target, s + vi)
            x, y = path(s)
            if kind == "urban" and 300 <= s < 300 + 25 * v:
                err.step()  # signal lost: no fix, error keeps evolving
                t += 1.0
                continue
            if kind == "outliers" and int(s) % 250 < 3:
                lines.append(fix_line(t, x + 90, y - 60, rng.uniform(5, 9), vi, 0.5))
                err.step()
                t += 1.0
                continue
            add(x, y, vi, noise_obj=noise, err=err)
            t += 1.0
        true_m = target
    elif kind == "drive":
        # 2 km straight road at 14 m/s: should count ~0 for a jog.
        s = 0.0
        while s < 2000.0:
            s += 14.0
            x, y = line_xy(s)
            add(x, y, 14.0, noise_obj=noise, err=err)
            t += 1.0
        true_m = 0.0  # nothing should count as jogging
    elif kind in ("standstill", "standstill_nospeed"):
        x, y = path(0.0)
        for k in range(300):  # 5 minutes standing, iOS never flags stationary
            add(x, y, 0.0, stationary=False, noise_obj=noise, err=err, no_speed=(kind == "standstill_nospeed"))
            t += 1.0
        true_m = 0.0
    else:
        raise ValueError(kind)
    return lines, true_m


KINDS = ["track", "slow", "streets", "stop", "stop_pause", "outliers", "urban", "drive", "standstill",
         "standstill_nospeed"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", nargs="?", choices=KINDS)
    ap.add_argument("--out", default=None)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list or not a.kind:
        print("Scenarios:", ", ".join(KINDS))
        return 0
    lines, true_m = simulate(a.kind, a.seed)
    out = a.out or f"sim_{a.kind}.jsonl"
    with open(out, "w") as fh:
        for ln in lines:
            fh.write(json.dumps(ln) + "\n")
    print(f"Wrote {out} ({len(lines) - 1} fixes, true distance {true_m:.0f} m)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
