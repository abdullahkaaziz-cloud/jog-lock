#!/usr/bin/env python3
"""Replay a Jog Tracker run log through the distance engine.

The engine here is a line-for-line mirror of JogLockTracker/DistanceEngine.swift,
so a recorded jog can be re-run with different settings without running again.

Usage:
  python3 replay.py raw.jsonl
  python3 replay.py raw.jsonl --true-km 1.0 --strava-km 1.02
  python3 replay.py raw.jsonl --set minStepFloor=3 --set maxAccuracy=30
  python3 replay.py raw.jsonl --sweep
  python3 replay.py raw.jsonl --gpx track.gpx
"""
from __future__ import annotations

import argparse
import itertools
import json
import math
import statistics
import sys
from collections.abc import Iterable
from dataclasses import dataclass, fields, replace
from datetime import UTC, datetime

# ---------------------------------------------------------------------------
# Geometry: local WGS84 radii (matches Geo.distance in Swift)
# ---------------------------------------------------------------------------
WGS84_A = 6378137.0
WGS84_F = 1 / 298.257223563
WGS84_E2 = WGS84_F * (2 - WGS84_F)


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distance in metres between two nearby points.

    Uses the WGS84 meridional and prime-vertical radii at the mid latitude,
    which is far more accurate than a spherical haversine for the short hops
    between GPS fixes.
    """
    phi = math.radians((lat1 + lat2) / 2)
    s = math.sin(phi)
    w = math.sqrt(1 - WGS84_E2 * s * s)
    n = WGS84_A / w
    m = WGS84_A * (1 - WGS84_E2) / (w * w * w)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    if dlon > math.pi:
        dlon -= 2 * math.pi
    elif dlon < -math.pi:
        dlon += 2 * math.pi
    dy = dlat * m
    dx = dlon * n * math.cos(phi)
    return math.sqrt(dx * dx + dy * dy)


# ---------------------------------------------------------------------------
# Engine (mirror of DistanceEngine.swift)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Fix:
    t: float
    lat: float
    lon: float
    h_acc: float
    speed: float
    speed_acc: float
    stationary: bool


@dataclass(frozen=True)
class Settings:
    warmup_accuracy: float = 15.0      # m: a fix this good counts toward warm-up
    warmup_fixes: int = 3              # consecutive good fixes before counting starts
    max_accuracy: float = 25.0         # m: worse fixes are ignored while tracking
    max_speed: float = 9.0             # m/s: faster implied movement is a GPS jump
    stop_speed: float = 0.5            # m/s: slower reported speed means standing still
    min_step_floor: float = 5.0        # m: minimum move before a segment is counted
    min_step_accuracy_factor: float = 0.5  # min step also >= factor * accuracy
    max_gap: float = 120.0             # s: longer gaps while moving are not bridged
    jump_reset_count: int = 3          # consecutive jumps before re-anchoring
    speed_max_accuracy: float = 3.0    # m/s: worse speed readings are ignored
    speed_max_dt: float = 10.0         # s: longer intervals use straight-line distance
    resume_gap: float = 5.0            # s: an update pause this long means iOS paused while stationary


SWIFT_KEYS = {
    "warmupAccuracy": "warmup_accuracy",
    "warmupFixes": "warmup_fixes",
    "maxAccuracy": "max_accuracy",
    "maxSpeed": "max_speed",
    "stopSpeed": "stop_speed",
    "minStepFloor": "min_step_floor",
    "minStepAccuracyFactor": "min_step_accuracy_factor",
    "maxGap": "max_gap",
    "jumpResetCount": "jump_reset_count",
    "speedMaxAccuracy": "speed_max_accuracy",
    "speedMaxDt": "speed_max_dt",
    "resumeGap": "resume_gap",
}
INT_FIELDS = {"warmup_fixes", "jump_reset_count"}


def settings_from_dict(d: dict, base: Settings | None = None) -> Settings:
    base = base or Settings()
    changes = {}
    for k, v in d.items():
        name = SWIFT_KEYS.get(k, k)
        if name not in {f.name for f in fields(Settings)}:
            raise KeyError(f"unknown setting: {k}")
        changes[name] = int(v) if name in INT_FIELDS else float(v)
    return replace(base, **changes)


def settings_to_swift_dict(s: Settings) -> dict:
    inv = {v: k for k, v in SWIFT_KEYS.items()}
    return {inv[f.name]: getattr(s, f.name) for f in fields(Settings)}


class Engine:
    def __init__(self, settings: Settings | None = None):
        self.s = settings or Settings()
        self.phase = "warmingUp"
        self.clean = 0.0
        self.speed_dist = 0.0
        self.raw = 0.0
        self.moving = 0.0
        self.fix_count = 0
        self.accepted = 0
        self.rejected: dict[str, int] = {}
        self.paused = False
        self._good_streak = 0
        self._anchor: Fix | None = None
        self._last_seen: Fix | None = None
        self._last_good: Fix | None = None
        self._raw_last: Fix | None = None
        self._speed_last: Fix | None = None
        self._jump_streak = 0
        self._motion_t0 = -math.inf
        self.anchors: list[tuple[str, Fix]] = []  # for GPX of counted points

    # -- public ------------------------------------------------------------
    def process(self, f: Fix) -> str:
        s = self.s
        self.fix_count += 1

        # Raw estimator: every fix with a valid accuracy, from the first one.
        if f.h_acc >= 0:
            if self._raw_last is not None and f.t > self._raw_last.t:
                self.raw += _dist(self._raw_last, f)
            if self._raw_last is None or f.t > self._raw_last.t:
                self._raw_last = f

        if self.phase == "warmingUp":
            if 0 <= f.h_acc <= s.warmup_accuracy:
                self._good_streak += 1
            else:
                self._good_streak = 0
            if self._good_streak >= s.warmup_fixes:
                self.phase = "tracking"
                self._anchor = f
                self._last_seen = f
                self._last_good = f
                self._speed_last = f
                self.anchors.append(("start", f))
                return "warmupComplete"
            return "warmingUp"

        if f.h_acc < 0:
            return self._reject("rejectedInvalid")
        if self._last_seen is not None and f.t <= self._last_seen.t:
            return self._reject("rejectedOutOfOrder")
        since_prev = f.t - self._last_seen.t if self._last_seen is not None else 0.0
        self._last_seen = f
        if self.paused and since_prev > s.resume_gap:
            # iOS paused updates while we stood still and has just resumed:
            # assume movement began about a second before this fix.
            self._motion_t0 = f.t - 1.0

        self._update_speed(f)

        if f.h_acc > s.max_accuracy:
            return self._reject("rejectedLowAccuracy")

        a = self._anchor
        if a is None:  # defensive; tracking always has an anchor
            self._anchor = f
            self._last_good = f
            return "pending"

        dt = f.t - a.t
        d = _dist(a, f)

        if dt > s.max_gap and not self.paused:
            self._anchor = f
            self._last_good = f
            self._jump_streak = 0
            self.anchors.append(("start", f))
            return "gapReset"

        if dt > 0 and d / dt > s.max_speed:
            self._jump_streak += 1
            if self._jump_streak >= s.jump_reset_count:
                self._anchor = f
                self._last_good = f
                self._jump_streak = 0
                self.anchors.append(("start", f))
                return "jumpReset"
            return self._reject("rejectedJump")
        self._jump_streak = 0
        self._last_good = f

        min_step = max(s.min_step_floor, s.min_step_accuracy_factor * max(a.h_acc, f.h_acc))
        slow = 0 <= f.speed < s.stop_speed and d < 2 * min_step
        if f.stationary or slow:
            self._anchor = f  # drag the anchor so standing still never adds distance
            self.paused = True
            return "stationary"
        self.paused = False

        if d >= min_step:
            # If it took too long to get this far, it is GPS drift around a
            # standing runner, not movement.
            dt_move = f.t - max(a.t, self._motion_t0)
            if dt_move > 0 and d / dt_move < s.stop_speed:
                self._anchor = f
                self.paused = True
                return "drift"
            self.clean += d
            self.moving += dt_move
            self.accepted += 1
            self._anchor = f
            self.anchors.append(("point", f))
            return "accepted"
        return "pending"

    def finalize(self) -> None:
        """Count the last partial segment when the run ends."""
        s = self.s
        a, g = self._anchor, self._last_good
        if self.phase != "tracking" or self.paused or a is None or g is None or g.t <= a.t:
            return
        dt = g.t - a.t
        d = _dist(a, g)
        if dt <= s.max_gap and d / dt <= s.max_speed:
            self.clean += d
            self.moving += max(0.0, g.t - max(a.t, self._motion_t0))
            self._anchor = g
            self.anchors.append(("point", g))

    # -- private -----------------------------------------------------------
    def _reject(self, reason: str) -> str:
        self.rejected[reason] = self.rejected.get(reason, 0) + 1
        return reason

    def _speed_ok(self, x: Fix) -> bool:
        s = self.s
        return (x.speed >= 0 and 0 <= x.speed_acc <= s.speed_max_accuracy
                and 0 <= x.h_acc <= s.max_accuracy)

    def _update_speed(self, f: Fix) -> None:
        s = self.s
        p = self._speed_last
        self._speed_last = f
        if p is None:
            return
        dt = f.t - p.t
        if dt <= 0 or f.stationary:
            return
        if dt <= s.speed_max_dt:
            if self._speed_ok(p) and self._speed_ok(f):
                v = (p.speed + f.speed) / 2
                if s.stop_speed <= v <= s.max_speed:
                    self.speed_dist += v * dt
            return
        # Long interval: fall back to the straight line if it is plausible.
        if dt <= s.max_gap and 0 <= p.h_acc <= s.max_accuracy and 0 <= f.h_acc <= s.max_accuracy:
            d = _dist(p, f)
            if d / dt <= s.max_speed:
                self.speed_dist += d


def _dist(a: Fix, b: Fix) -> float:
    return distance_m(a.lat, a.lon, b.lat, b.lon)


# ---------------------------------------------------------------------------
# Log reading
# ---------------------------------------------------------------------------
@dataclass
class RunLog:
    header: dict
    fixes: list[Fix]
    lines: list[dict]


def read_log(path: str) -> RunLog:
    header: dict = {}
    fixes: list[Fix] = []
    lines: list[dict] = []
    with open(path, encoding="utf-8") as fh:
        for n, raw_line in enumerate(fh, 1):
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                obj = json.loads(raw_line)
            except json.JSONDecodeError:
                print(f"warning: skipping bad line {n}", file=sys.stderr)
                continue
            lines.append(obj)
            kind = obj.get("type")
            if kind == "header" and not header:
                header = obj
            elif kind == "fix" and "lat" in obj and "lon" in obj:
                fixes.append(Fix(
                    t=float(obj["t"]),
                    lat=float(obj["lat"]),
                    lon=float(obj["lon"]),
                    h_acc=float(obj.get("hAcc", -1)),
                    speed=float(obj.get("speed", -1)),
                    speed_acc=float(obj.get("speedAcc", -1)),
                    stationary=bool(obj.get("stationary", False)),
                ))
    return RunLog(header, fixes, lines)


def run_engine(fixes: Iterable[Fix], settings: Settings, finalize: bool = True) -> tuple[Engine, list[str]]:
    e = Engine(settings)
    decisions = [e.process(f) for f in fixes]
    if finalize:
        e.finalize()
    return e, decisions


def smoothed(fixes: list[Fix], mode: str) -> list[Fix]:
    """Replay-only experiments: smooth positions before the engine sees them.

    "ema0.5" is causal exponential smoothing (what the phone could do live);
    "center3" is a 1-2-1 centred average (needs one fix of delay live).
    Fixes more than 3 s apart, or with bad accuracy, are left alone.
    """
    out: list[Fix] = []
    if mode.startswith("ema"):
        alpha = float(mode[3:])
        prev: Fix | None = None
        for f in fixes:
            if prev is not None and 0 <= f.h_acc and f.t - prev.t <= 3 and 0 <= prev.h_acc:
                f = replace(f, lat=alpha * f.lat + (1 - alpha) * prev.lat,
                            lon=alpha * f.lon + (1 - alpha) * prev.lon)
            out.append(f)
            prev = f
        return out
    if mode == "center3":
        for i, f in enumerate(fixes):
            if 0 < i < len(fixes) - 1:
                a, b = fixes[i - 1], fixes[i + 1]
                if f.t - a.t <= 3 and b.t - f.t <= 3 and min(a.h_acc, f.h_acc, b.h_acc) >= 0:
                    f = replace(f, lat=(a.lat + 2 * f.lat + b.lat) / 4, lon=(a.lon + 2 * f.lon + b.lon) / 4)
            out.append(f)
        return out
    raise ValueError(mode)


# ---------------------------------------------------------------------------
# GPX
# ---------------------------------------------------------------------------
def _iso(t: float) -> str:
    return datetime.fromtimestamp(t, tz=UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def write_gpx(path: str, name: str, fixes: list[Fix], engine: Engine) -> None:
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<gpx version="1.1" creator="JogLockTracker replay" xmlns="http://www.topografix.com/GPX/1/1">']
    out.append(f"  <trk><name>{name} - all fixes</name><trkseg>")
    for f in fixes:
        if f.h_acc >= 0:
            out.append(f'    <trkpt lat="{f.lat:.7f}" lon="{f.lon:.7f}"><time>{_iso(f.t)}</time></trkpt>')
    out.append("  </trkseg></trk>")
    out.append(f"  <trk><name>{name} - counted points</name>")
    open_seg = False
    for kind, f in engine.anchors:
        if kind == "start":
            if open_seg:
                out.append("  </trkseg>")
            out.append("  <trkseg>")
            open_seg = True
        out.append(f'    <trkpt lat="{f.lat:.7f}" lon="{f.lon:.7f}"><time>{_iso(f.t)}</time></trkpt>')
    if open_seg:
        out.append("  </trkseg>")
    out.append("  </trk>")
    out.append("</gpx>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def _pct(value: float, ref: float | None) -> str:
    if not ref:
        return ""
    return f"  ({(value - ref) / ref * 100:+.1f}%)"


def _fmt_dur(sec: float) -> str:
    sec = round(sec)
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def report(log: RunLog, settings: Settings, true_km: float | None, strava_km: float | None,
           compare_phone: bool = True) -> Engine:
    e, decisions = run_engine(log.fixes, settings)
    fixes = log.fixes
    dur = fixes[-1].t - fixes[0].t if len(fixes) > 1 else 0.0
    true_m = true_km * 1000 if true_km else None
    strava_m = strava_km * 1000 if strava_km else None

    print(f"Fixes: {len(fixes)}   duration {_fmt_dur(dur)}   moving {_fmt_dur(e.moving)}")
    if log.header:
        print(f"Device: {log.header.get('device', '?')}  iOS {log.header.get('os', '?')}  app {log.header.get('app', '?')}")
    print()
    print("Distances")
    for label, meters in (("Clean (Jog Lock)", e.clean), ("Speed-based", e.speed_dist), ("Raw (no clean-up)", e.raw)):
        line = f"  {label:<19} {meters / 1000:7.3f} km"
        if true_m:
            line += f"  vs true{_pct(meters, true_m)}"
        if strava_m:
            line += f"  vs Strava{_pct(meters, strava_m)}"
        print(line)
    if true_m:
        print(f"  {'True distance':<19} {true_km:7.3f} km")
    if strava_m:
        print(f"  {'Strava':<19} {strava_km:7.3f} km{_pct(strava_m, true_m) and '  vs true' + _pct(strava_m, true_m)}")

    # Parity check: the app logs its own running totals, so a replay with the
    # same settings should land on exactly the same numbers.
    if compare_phone:
        stop = next((ln for ln in reversed(log.lines)
                     if ln.get("type") == "event" and ln.get("name") == "stop" and ln.get("clean") is not None), None)
        if stop is not None:
            phone_clean, mine = stop["clean"], e.clean
        else:
            last = next((ln for ln in reversed(log.lines)
                         if ln.get("type") == "fix" and ln.get("clean") is not None), None)
            phone_clean = last["clean"] if last else None
            mine = run_engine(log.fixes, settings, finalize=False)[0].clean
        if phone_clean is not None:
            diff = abs(phone_clean - mine)
            status = "matches this replay" if diff < 0.5 else f"DIFFERS from this replay by {diff:.1f} m"
            print(f"  Phone's own clean total: {phone_clean / 1000:.3f} km ({status})")

    print()
    print("Experiments (replay only, not in the app yet)")
    for mode, label in (("ema0.5", "Clean + live smoothing"), ("center3", "Clean + centred smoothing")):
        ex, _ = run_engine(smoothed(fixes, mode), settings)
        line = f"  {label:<26} {ex.clean / 1000:7.3f} km"
        if true_m:
            line += f"  vs true{_pct(ex.clean, true_m)}"
        if strava_m:
            line += f"  vs Strava{_pct(ex.clean, strava_m)}"
        print(line)

    print()
    counts: dict[str, int] = {}
    for d in decisions:
        counts[d] = counts.get(d, 0) + 1
    print("Decisions: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))

    h = [f.h_acc for f in fixes if f.h_acc >= 0]
    sa = [f.speed_acc for f in fixes if f.speed_acc >= 0]
    if h:
        hs = sorted(h)
        p90 = hs[int(0.9 * (len(hs) - 1))]
        print(f"GPS accuracy: median {statistics.median(h):.1f} m, p90 {p90:.1f} m, worst {max(h):.1f} m")
    if sa:
        print(f"Speed accuracy: median {statistics.median(sa):.2f} m/s")
    gaps = [b.t - a.t for a, b in itertools.pairwise(fixes) if b.t - a.t > 5]
    if gaps:
        print(f"Gaps > 5 s: {len(gaps)} (longest {max(gaps):.0f} s)")
    stationary_n = sum(1 for f in fixes if f.stationary)
    if stationary_n:
        print(f"Fixes flagged stationary by iOS: {stationary_n}")
    return e


SWEEPS = {
    "min_step_floor": [0.0, 2.0, 3.0, 5.0, 8.0, 12.0],
    "max_accuracy": [10.0, 15.0, 25.0, 40.0, 65.0],
    "stop_speed": [0.0, 0.3, 0.5, 0.8, 1.2],
    "min_step_accuracy_factor": [0.0, 0.25, 0.5, 1.0],
    "speed_max_accuracy": [1.0, 2.0, 3.0, 5.0, 100.0],
}


def sweep(log: RunLog, base: Settings, true_km: float | None) -> None:
    true_m = true_km * 1000 if true_km else None
    print()
    print("Sensitivity (one setting changed at a time; clean / speed-based km)")
    for name, values in SWEEPS.items():
        parts = []
        for v in values:
            s = replace(base, **{name: v})
            e, _ = run_engine(log.fixes, s)
            tag = f"{v:g}"
            val = f"{e.clean / 1000:.3f}/{e.speed_dist / 1000:.3f}"
            if true_m:
                val += f" ({(e.clean - true_m) / true_m * 100:+.1f}%)"
            mark = "*" if getattr(base, name) == v else " "
            parts.append(f"{mark}{tag}: {val}")
        print(f"  {name}:")
        for p in parts:
            print(f"     {p}")


def _read_summary_notes(log_path: str) -> dict:
    """Pick up Strava / true distance typed into the app (summary.json next to the log)."""
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(log_path)), "summary.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {k: data[k] for k in ("trueKm", "stravaKm") if data.get(k)}
    except (OSError, ValueError):
        return {}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", help="raw.jsonl exported from the app")
    ap.add_argument("--true-km", type=float, help="measured true distance in km")
    ap.add_argument("--strava-km", type=float, help="Strava's distance for the same run in km")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="override a setting (Swift or Python name), e.g. minStepFloor=3")
    ap.add_argument("--sweep", action="store_true", help="show how the distance changes with each setting")
    ap.add_argument("--gpx", help="write a GPX with all fixes and the counted points")
    ap.add_argument("--use-defaults", action="store_true",
                    help="ignore settings recorded in the log header and use current defaults")
    args = ap.parse_args(argv)

    log = read_log(args.log)
    if not log.fixes:
        print("No fixes in this log.", file=sys.stderr)
        return 1

    base = Settings()
    if log.header.get("settings") and not args.use_defaults:
        base = settings_from_dict(log.header["settings"])
    overrides = {}
    for item in args.set:
        k, _, v = item.partition("=")
        overrides[k.strip()] = v.strip()
    settings = settings_from_dict(overrides, base) if overrides else base

    meta = log.header or {}
    notes = _read_summary_notes(args.log)
    true_km = args.true_km if args.true_km is not None else notes.get("trueKm")
    strava_km = args.strava_km if args.strava_km is not None else notes.get("stravaKm")

    e = report(log, settings, true_km, strava_km, compare_phone=not overrides and not args.use_defaults)
    if args.sweep:
        sweep(log, settings, true_km)
    if args.gpx:
        write_gpx(args.gpx, meta.get("name", "run"), log.fixes, e)
        print(f"\nWrote {args.gpx}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
