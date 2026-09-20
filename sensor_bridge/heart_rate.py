"""Green-channel PPG -> bandpass filter -> HeartPy sliding window -> BPM.

Brief CLAUDE_CODE_BRIEF.md §3: "Heart rate: green-channel PPG (not the
onboard estimate) -> bandpass filter -> HeartPy over a sliding window -> BPM."

This class does not apply the motion gate itself -- the caller decides
whether the window it just processed was still throughout and whether to
keep or discard the result. That split exists so this class stays a pure
signal-processing unit, testable without any notion of "the game."
"""
from __future__ import annotations

import numpy as np
import heartpy as hp


class HeartRateEstimator:
    def __init__(self, sample_rate: float = 25.0, window_seconds: float = 10.0):
        self.sample_rate = sample_rate
        self.window_size = int(sample_rate * window_seconds)
        self._buffer: list[float] = []

    def add_sample(self, value: float) -> None:
        self._buffer.append(value)
        if len(self._buffer) > self.window_size:
            self._buffer.pop(0)

    def ready(self) -> bool:
        return len(self._buffer) >= self.window_size

    def estimate_bpm(self) -> float | None:
        """Returns None if there isn't a full window yet, or if HeartPy
        couldn't find clean beats in it (motion artifact, bad contact,
        etc). None is a valid, expected outcome here -- callers should treat
        it as "no reading this cycle," not an error. Unconditional
        progression (§1) applies to the sensor pipeline too: the game must
        keep running without a BPM."""
        if not self.ready():
            return None
        try:
            filtered = hp.filter_signal(
                np.array(self._buffer, dtype=float),
                cutoff=[0.7, 3.5],
                sample_rate=self.sample_rate,
                order=3,
                filtertype="bandpass",
            )
            _, measures = hp.process(filtered, sample_rate=self.sample_rate)
            bpm = measures.get("bpm")
            if bpm is None or np.isnan(bpm):
                return None
            return float(bpm)
        except Exception:
            return None
