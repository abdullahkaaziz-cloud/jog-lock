"""Anti-cheat gate: only GPS distance backed by steps, and not in a vehicle, counts.

Line-for-line mirror of Packages/JogLockCore/Sources/JogLockCore/StepGate.swift.
If you change the rules here, change them there too (both test suites check
the same scenarios).

How it works:
- Every new step from the pedometer adds "credit": steps x max_step_length
  metres, spread over the time those steps were taken.
- Each piece of GPS distance the engine counts waits settle_delay seconds,
  so late step and motion data can arrive, then spends credit from steps
  taken within match_window of it, nearest in time first. Whatever credit
  can't cover is "no steps".
- Distance while Core Motion is reasonably sure the phone is in a car or on
  a bike is "vehicle", whatever the steps say.
- If the pedometer goes quiet for stall_limit seconds while GPS keeps
  counting, the waiting distance is settled anyway, as no steps.
"""

from __future__ import annotations

from dataclasses import dataclass

VEHICLE_KINDS = ("cycling", "automotive")
CONFIDENCE = {"low": 0, "medium": 1, "high": 2}


@dataclass(frozen=True)
class GateSettings:
    max_step_length: float = 2.0  # m: more GPS distance per step than this isn't on foot
    match_window: float = 5.0  # s: steps this far either side of GPS distance can back it
    settle_delay: float = 60.0  # s: how long distance waits for late step and motion data
    stall_limit: float = 120.0  # s: GPS this far past the last step update settles as no steps
    vehicle_confidence: int = 1  # 0 low, 1 medium, 2 high: this sure of a car or bike rejects distance


GATE_SETTINGS_KEYS = {
    "maxStepLength": "max_step_length",
    "matchWindow": "match_window",
    "settleDelay": "settle_delay",
    "stallLimit": "stall_limit",
    "vehicleConfidence": "vehicle_confidence",
}


def gate_settings_from_dict(d: dict | None) -> GateSettings:
    base = GateSettings()
    if not d:
        return base
    changes = {py: d[js] for js, py in GATE_SETTINGS_KEYS.items() if js in d}
    if isinstance(changes.get("vehicle_confidence"), str):
        changes["vehicle_confidence"] = CONFIDENCE[changes["vehicle_confidence"]]
    return GateSettings(**{**base.__dict__, **changes})


@dataclass
class _Segment:
    start: float
    end: float
    meters: float


@dataclass
class _Credit:
    start: float
    end: float
    meters: float


@dataclass(frozen=True)
class Motion:
    start: float
    kind: str
    confidence: int


class StepGate:
    def __init__(self, start: float, settings: GateSettings | None = None):
        self.s = settings or GateSettings()
        self.counted = 0.0
        self.no_steps = 0.0
        self.vehicle = 0.0
        self.steps = 0
        self._pending: list[_Segment] = []
        self._credits: list[_Credit] = []
        self._motions: list[Motion] = []
        self._step_t = start  # newest pedometer time (the run start until the first update)
        self._gps_t = start  # end of the newest GPS distance

    @property
    def pending(self) -> float:
        return sum(seg.meters for seg in self._pending)

    # -- inputs --------------------------------------------------------------
    def add_distance(self, meters: float, start: float, end: float) -> None:
        if meters <= 0:
            return
        self._pending.append(_Segment(start, end, meters))
        self._gps_t = max(self._gps_t, end)
        self._settle(final=False)

    def add_steps(self, t: float, cumulative: int) -> None:
        """Steps since the run started, as of time t (from the pedometer)."""
        if cumulative > self.steps:
            new = cumulative - self.steps
            self._credits.append(_Credit(self._step_t, max(t, self._step_t), new * self.s.max_step_length))
            self.steps = cumulative
        self._step_t = max(self._step_t, t)
        self._settle(final=False)

    def add_motion(self, start: float, kind: str, confidence: int) -> bool:
        """A Core Motion activity, in effect from `start` until the next one.

        Returns False if the same sample was already added.
        """
        sample = Motion(start, kind, confidence)
        if sample in self._motions:
            return False
        i = len(self._motions)
        while i > 0 and self._motions[i - 1].start > start:
            i -= 1
        self._motions.insert(i, sample)
        return True

    def finish(self) -> None:
        """Settles everything. Call once at the end of the run."""
        self._settle(final=True)

    # -- private -------------------------------------------------------------
    def _settle(self, final: bool) -> None:
        s = self.s
        while self._pending:
            seg = self._pending[0]
            ready = final or self._step_t >= seg.end + s.settle_delay or self._gps_t >= seg.end + s.stall_limit
            if not ready:
                break
            self._pending.pop(0)
            self._drop_old_motions(before=seg.start)
            if self._in_vehicle(seg.start, seg.end):
                self.vehicle += seg.meters
                continue
            # Credit too old to back this distance can't back any later distance either.
            lo, hi = seg.start - s.match_window, seg.end + s.match_window
            self._credits = [c for c in self._credits if c.end >= lo and c.meters > 0]
            mid = (seg.start + seg.end) / 2
            nearby = [c for c in self._credits if c.start <= hi]
            nearby.sort(key=lambda c: (abs((c.start + c.end) / 2 - mid), c.start))
            need = seg.meters
            for c in nearby:
                if need <= 0:
                    break
                take = min(c.meters, need)
                c.meters -= take
                need -= take
            self.counted += seg.meters - need
            self.no_steps += need

    def _drop_old_motions(self, before: float) -> None:
        # Keep the activity in effect at `before` and everything after it.
        while len(self._motions) >= 2 and self._motions[1].start <= before:
            self._motions.pop(0)

    def _in_vehicle(self, start: float, end: float) -> bool:
        current = self._effective_at(start)
        if current is not None and self._is_vehicle(current):
            return True
        for m in self._motions:
            if m.start >= end:
                break
            if m.start > start and self._is_vehicle(m):
                return True
        return False

    def _effective_at(self, t: float) -> Motion | None:
        current = None
        for m in self._motions:
            if m.start > t:
                break
            current = m
        return current

    def _is_vehicle(self, m: Motion) -> bool:
        return m.kind in VEHICLE_KINDS and m.confidence >= self.s.vehicle_confidence
