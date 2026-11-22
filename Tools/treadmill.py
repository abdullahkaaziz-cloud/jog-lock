"""Treadmill mode: distance from steps, using a stride length learned on GPS runs.

Line-for-line mirror of Packages/JogLockCore/Sources/JogLockCore/Treadmill.swift.
If you change the rules here, change them there too (both test suites check
the same scenarios and fixtures).

- Outdoor runs that pass the step check teach the stride model: in each
  30-second window, step length = counted GPS distance / steps, against
  cadence (steps per second). A straight line through those points gives
  step length at any cadence; with too little spread in cadence it's the
  median step length.
- On a treadmill, each pedometer update's new steps cover
  steps x step_length(cadence) metres. Without a model the iPhone's own
  pedometer distance is used, and without that a short default step.
- Steps faster than max_cadence aren't counted, and the share of time
  Core Motion is fairly sure the phone is in a car, on a bike or standing
  still doesn't count.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass

from replay import replay_gated

MIN_SAMPLES = 10  # windows needed before the model is used
MIN_STEP, MAX_STEP = 0.3, 2.0  # m: limits on any step length the model gives
MAX_SLOPE = 2.0  # m per (step/s): limit on how fast step length grows with cadence
SUSPICIOUS_STILL = ("stationary",)
SUSPICIOUS_VEHICLE = ("cycling", "automotive")
CONFIDENCE = {"low": 0, "medium": 1, "high": 2}


@dataclass(frozen=True)
class StrideSample:
    cadence: float  # steps per second
    length: float  # metres per step


@dataclass(frozen=True)
class StrideModel:
    intercept: float
    slope: float
    min_cadence: float
    max_cadence: float
    samples: int

    def step_length(self, cadence: float) -> float:
        c = min(max(cadence, self.min_cadence), self.max_cadence)
        return min(max(self.intercept + self.slope * c, MIN_STEP), MAX_STEP)

    def to_dict(self) -> dict:
        return {
            "intercept": self.intercept,
            "slope": self.slope,
            "minCadence": self.min_cadence,
            "maxCadence": self.max_cadence,
            "samples": self.samples,
        }

    @staticmethod
    def from_dict(d: dict | None) -> StrideModel | None:
        if not d:
            return None
        return StrideModel(d["intercept"], d["slope"], d["minCadence"], d["maxCadence"], int(d["samples"]))


def _median(values: list[float]) -> float:
    v = sorted(values)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2


def fit_stride(samples: list[StrideSample]) -> StrideModel | None:
    usable = [s for s in samples if 1.0 <= s.cadence <= 4.0 and MIN_STEP <= s.length <= MAX_STEP]
    n = len(usable)
    if n < MIN_SAMPLES:
        return None
    cs = [s.cadence for s in usable]
    ls = [s.length for s in usable]
    mean_c = sum(cs) / n
    mean_l = sum(ls) / n
    var = sum((c - mean_c) * (c - mean_c) for c in cs) / n
    if var < 0.01:  # cadence too steady (sd under 0.1 steps/s) to fit a slope
        slope = 0.0
        intercept = _median(ls)
    else:
        cov = sum((c - mean_c) * (x - mean_l) for c, x in zip(cs, ls, strict=True)) / n
        slope = min(max(cov / var, 0.0), MAX_SLOPE)
        intercept = mean_l - slope * mean_c
    return StrideModel(intercept, slope, min(cs), max(cs), n)


def _interp(steps: list[tuple[float, int]], t: float) -> float | None:
    for (t0, s0), (t1, s1) in itertools.pairwise(steps):
        if t0 <= t <= t1:
            return s0 + (s1 - s0) * (t - t0) / (t1 - t0)
    return None


def _overlap_meters(seg: tuple[float, float, float], a: float, b: float) -> float:
    start, end, meters = seg
    if end <= start:
        return meters if a <= end < b else 0.0
    overlap = max(0.0, min(end, b) - max(start, a))
    return meters * overlap / (end - start)


def stride_samples(lines: list[dict], window: float = 30.0, min_counted_share: float = 0.9) -> list[StrideSample]:
    """Step length against cadence, from an outdoor run that passed the step check."""
    segments: list[tuple[float, float, float]] = []
    e, g = replay_gated(lines, segments=segments)
    if e.clean <= 0 or g.counted < min_counted_share * e.clean:
        return []
    steps: list[tuple[float, int]] = []
    for ln in lines:
        if ln.get("type") == "steps" and "steps" in ln:
            t, n = float(ln["t"]), int(ln["steps"])
            if not steps or (t > steps[-1][0] and n >= steps[-1][1]):
                steps.append((t, n))
    if len(steps) < 2:
        return []
    out = []
    w = steps[0][0]
    while w + window <= steps[-1][0]:
        s0, s1 = _interp(steps, w), _interp(steps, w + window)
        if s0 is not None and s1 is not None:
            n = s1 - s0
            d = sum(_overlap_meters(seg, w, w + window) for seg in segments)
            if n >= 20 and d >= 30:
                out.append(StrideSample(n / window, d / n))
        w += window
    return out


@dataclass(frozen=True)
class TreadmillSettings:
    max_cadence: float = 4.0  # steps/s: steps faster than this don't count
    default_step_length: float = 0.75  # m: with no model and no pedometer distance
    settle_delay: float = 60.0  # s: how long steps wait for late motion data
    still_confidence: int = 1  # this sure the phone is standing still: those steps don't count
    vehicle_confidence: int = 1  # this sure of a car or bike: those steps don't count


TREADMILL_KEYS = {
    "maxCadence": "max_cadence",
    "defaultStepLength": "default_step_length",
    "settleDelay": "settle_delay",
    "stillConfidence": "still_confidence",
    "vehicleConfidence": "vehicle_confidence",
}


def treadmill_settings_from_dict(d: dict | None) -> TreadmillSettings:
    base = TreadmillSettings()
    if not d:
        return base
    return TreadmillSettings(**{**base.__dict__, **{py: d[js] for js, py in TREADMILL_KEYS.items() if js in d}})


@dataclass
class _Interval:
    start: float
    end: float
    steps: int
    ped_meters: float | None


@dataclass(frozen=True)
class _Motion:
    start: float
    kind: str
    confidence: int


class TreadmillCounter:
    def __init__(self, start: float, model: StrideModel | None = None, settings: TreadmillSettings | None = None):
        self.s = settings or TreadmillSettings()
        self.model = model
        self.counted = 0.0
        self.rejected = 0.0
        self.steps = 0
        self._pending: list[_Interval] = []
        self._motions: list[_Motion] = []
        self._step_t = start
        self._ped = 0.0

    @property
    def pending(self) -> float:
        return sum(self._distance(iv) for iv in self._pending)

    def add_steps(self, t: float, cumulative: int, ped_meters: float | None = None) -> None:
        if cumulative > self.steps:
            new_ped = None
            if ped_meters is not None and ped_meters >= self._ped:
                new_ped = ped_meters - self._ped
            self._pending.append(_Interval(self._step_t, max(t, self._step_t), cumulative - self.steps, new_ped))
            self.steps = cumulative
        if ped_meters is not None:
            self._ped = max(self._ped, ped_meters)
        self._step_t = max(self._step_t, t)
        self._settle(final=False)

    def add_motion(self, start: float, kind: str, confidence: int) -> bool:
        sample = _Motion(start, kind, confidence)
        if sample in self._motions:
            return False
        i = len(self._motions)
        while i > 0 and self._motions[i - 1].start > start:
            i -= 1
        self._motions.insert(i, sample)
        return True

    def finish(self) -> None:
        self._settle(final=True)

    def _settle(self, final: bool) -> None:
        while self._pending:
            iv = self._pending[0]
            if not (final or self._step_t >= iv.end + self.s.settle_delay):
                break
            self._pending.pop(0)
            d = self._distance(iv)
            bad = self._suspicious_share(iv.start, iv.end)
            self.counted += d * (1 - bad)
            self.rejected += d * bad

    def _distance(self, iv: _Interval) -> float:
        dt = iv.end - iv.start
        n = float(iv.steps) if dt <= 0 else min(float(iv.steps), self.s.max_cadence * dt)
        if self.model is not None:
            return n * self.model.step_length(n / dt if dt > 0 else 0.0)
        if iv.ped_meters is not None:
            return min(iv.ped_meters * n / iv.steps, n * MAX_STEP)
        return n * self.s.default_step_length

    def _suspicious(self, m: _Motion) -> bool:
        if m.kind in SUSPICIOUS_VEHICLE:
            return m.confidence >= self.s.vehicle_confidence
        if m.kind in SUSPICIOUS_STILL:
            return m.confidence >= self.s.still_confidence
        return False

    def _suspicious_share(self, start: float, end: float) -> float:
        """Share of [start, end] during which a suspicious activity was in effect."""
        if end <= start:
            current = None
            for m in self._motions:
                if m.start > start:
                    break
                current = m
            return 1.0 if current is not None and self._suspicious(current) else 0.0
        bad = 0.0
        for i, m in enumerate(self._motions):
            until = self._motions[i + 1].start if i + 1 < len(self._motions) else float("inf")
            overlap = min(end, until) - max(start, m.start)
            if overlap > 0 and self._suspicious(m):
                bad += overlap
        return min(1.0, bad / (end - start))


def replay_treadmill(lines: list[dict], finish: bool = True) -> TreadmillCounter:
    """Mirror of TreadmillCounter.replaying() + finish()."""
    header = next((ln for ln in lines if ln.get("type") == "header"), {})
    start = float(header.get("t", lines[0]["t"] if lines else 0))
    c = TreadmillCounter(
        start, StrideModel.from_dict(header.get("stride")), treadmill_settings_from_dict(header.get("treadmill"))
    )
    for ln in lines:
        kind = ln.get("type")
        if kind == "steps" and "steps" in ln:
            c.add_steps(float(ln["t"]), int(ln["steps"]), ln.get("pedMeters"))
        elif kind == "motion" and "activity" in ln and "confidence" in ln:
            c.add_motion(float(ln["t"]), ln["activity"], int(ln["confidence"]))
        elif kind == "event" and ln.get("name") == "stop":
            break
    if finish:
        c.finish()
    return c
