"""Works out how a head nod looks to the sensor, however it is mounted.

`bridge.py --calibrate` has the player look ahead, then up, holding each still.
Gravity's direction in those two holds gives the axis the head turned around
as a vector in sensor space, so no sensor axis or sign is assumed. The gyro's
sign is checked against the same movement.

The result is saved beside this file and read by every later run.
"""
from __future__ import annotations

import json
import math
import time
from pathlib import Path

import numpy as np

CALIBRATION_PATH = Path(__file__).with_name("nod_calibration.json")

SETTLE_SECONDS = 1.5
HOLD_SECONDS = 2.0
MOVE_SECONDS = 2.0
MIN_NOD_DEG = 15.0
# Low-pass on acceleration, so a jolt doesn't read as a change of tilt.
GRAVITY_SMOOTHING = 0.15


def _unit(v) -> np.ndarray:
    return np.asarray(v, dtype=float) / np.linalg.norm(v)


def solve(ahead, up, gyro_move, dt: float) -> dict:
    """ahead and up are acceleration samples from the two holds; gyro_move is
    gyro samples (rad/s) from the movement between them."""
    g0 = _unit(np.mean(ahead, axis=0))
    g1 = _unit(np.mean(up, axis=0))
    turned = np.cross(g1, g0)
    angle = math.degrees(math.atan2(np.linalg.norm(turned), float(g0 @ g1)))
    if angle < MIN_NOD_DEG:
        raise ValueError(f"only saw {angle:.0f} degrees of tilt; look further up and hold it")
    axis = _unit(turned)
    swept = float(np.sum(np.asarray(gyro_move, dtype=float) @ axis)) * dt
    return {"axis": [float(v) for v in axis], "gyro_sign": 1.0 if swept >= 0.0 else -1.0, "angle_deg": angle}


class NodCalibrator:
    """Times the prompts from the IMU stream, and saves when it has both holds."""

    def __init__(self, sample_rate: float):
        self.done = False
        self._dt = 1.0 / sample_rate
        self._t_start = None
        self._ahead = []
        self._up = []
        self._gyro = []
        self._step = 0

    def add(self, gyro, acc) -> None:
        now = time.monotonic()
        if self._t_start is None:
            self._t_start = now
            print("Sensor found. Look STRAIGHT AHEAD and hold still...", flush=True)
        t = now - self._t_start
        ahead_end = SETTLE_SECONDS + HOLD_SECONDS
        up_start = ahead_end + MOVE_SECONDS
        up_end = up_start + HOLD_SECONDS
        if t < SETTLE_SECONDS:
            return
        if t < ahead_end:
            self._ahead.append(acc)
        elif t < up_start:
            if self._step == 0:
                self._step = 1
                print("Now LOOK UP as far as is comfortable and hold it...", flush=True)
            self._gyro.append(gyro)
        elif t < up_end:
            self._up.append(acc)
        else:
            self._finish()

    def _finish(self) -> None:
        self.done = True
        try:
            result = solve(self._ahead, self._up, self._gyro, self._dt)
        except ValueError as error:
            print(f"Calibration failed: {error}. Run it again.", flush=True)
            return
        CALIBRATION_PATH.write_text(json.dumps(result, indent=2))
        print(f"Done, saw a {result['angle_deg']:.0f} degree nod. Saved {CALIBRATION_PATH.name}.", flush=True)


class NodTracker:
    """The calibrated nod: pitch rate from the gyro, pitch angle from gravity.
    Positive is up. Pitch is measured from the head's position at start-up."""

    def __init__(self, calibration: dict):
        self._axis = np.asarray(calibration["axis"], dtype=float)
        self._gyro_sign = float(calibration["gyro_sign"])
        self._gravity = None
        self._level = None
        self._tangent = None

    @classmethod
    def load(cls) -> "NodTracker | None":
        if not CALIBRATION_PATH.exists():
            return None
        return cls(json.loads(CALIBRATION_PATH.read_text()))

    def pitch_rate(self, gyro) -> float:
        return float(np.asarray(gyro, dtype=float) @ self._axis) * self._gyro_sign

    def pitch(self, acc) -> float:
        reading = _unit(acc)
        if self._gravity is None:
            self._gravity = reading
            self._level = reading
            self._tangent = -np.cross(self._axis, reading)
            return 0.0
        self._gravity = self._gravity + (reading - self._gravity) * GRAVITY_SMOOTHING
        return math.atan2(float(self._gravity @ self._tangent), float(self._gravity @ self._level))
