"""9-axis IMU -> Madgwick filter -> head yaw, in Godot's convention.

Brief CLAUDE_CODE_BRIEF.md §3: "Orientation: 9-axis IMU -> Madgwick filter
(ahrs library) -> quaternion/euler."

Output is (pitch, yaw, roll) in radians, Godot's order, with only YAW
filled in. Why yaw alone, and why not straight Euler angles:

- The headband mounts the EmotiBit sideways (the old OSCTesting pipeline
  treated rotation about the sensor's X axis as yaw), and Euler angles of a
  sensor lying on its side sit right at gimbal lock. Instead, yaw is the
  world heading of one of the sensor's HORIZONTAL axes: whichever way the
  board is mounted, turning the head turns that axis about the vertical by
  the same angle. A constant offset between that axis and "the nose" doesn't
  matter -- Godot's recenter (C / DualSense touchpad) removes it.
- Which sensor axis is vertical is detected from gravity over the first
  samples (override with up_axis), so no mounting calibration is needed.
- Pitch and roll are returned as 0: the mounting's forward axis isn't known
  here. bridge.py fills pitch in from the calibrated nod (nod_calibration.py).

Conventions verified with synthetic, physically consistent IMU data for an
upright and a sideways mount (the q is initialised from an NED e-compass,
then yaw = atan2 of the axis's world y/x through the filter's DCM): a 60 deg
turn to the LEFT reads as +60 deg yaw, which is Godot's positive (left) yaw.
Real-hardware drift and magnetometer calibration are still a human task.
"""
from __future__ import annotations

import math

import numpy as np
from ahrs import Quaternion
from ahrs.common.orientation import ecompass
from ahrs.filters import Madgwick

AXES = {"x": 0, "y": 1, "z": 2}

# Samples averaged to find "up" before the filter starts.
_SETTLE_SAMPLES = 10


class OrientationEstimator:
    def __init__(self, frequency: float = 25.0, up_axis: str | None = None):
        self._madgwick = Madgwick(frequency=frequency)
        self._q: np.ndarray | None = None
        self._up_index: int | None = AXES[up_axis] if up_axis else None
        self._acc_seen: list[np.ndarray] = []
        self._mag_seen: list[np.ndarray] = []

    @property
    def up_index(self) -> int | None:
        return self._up_index

    def update(self, gyro, acc, mag) -> tuple[tuple[float, float, float], float]:
        """gyro in rad/s; acc/mag in whatever units the sensor reports (ahrs
        only cares that they're internally consistent). Returns
        ((pitch, yaw, roll) radians in Godot's order, angular_velocity_rad_s)."""
        gyro = np.asarray(gyro, dtype=float)
        acc = np.asarray(acc, dtype=float)
        mag = np.asarray(mag, dtype=float)
        angular_velocity = float(np.linalg.norm(gyro))

        if self._q is None:
            self._acc_seen.append(acc)
            self._mag_seen.append(mag)
            if len(self._acc_seen) < _SETTLE_SAMPLES:
                return (0.0, 0.0, 0.0), angular_velocity
            mean_acc = np.mean(self._acc_seen, axis=0)
            mean_mag = np.mean(self._mag_seen, axis=0)
            if self._up_index is None:
                self._up_index = int(np.argmax(np.abs(mean_acc)))
            self._q = ecompass(mean_acc, mean_mag, frame="NED", representation="quaternion")

        self._q = self._madgwick.updateMARG(self._q, gyr=gyro, acc=acc, mag=mag)
        dcm = Quaternion(self._q).to_DCM()
        reference = np.zeros(3)
        reference[(self._up_index + 1) % 3] = 1.0
        heading_vector = dcm @ reference
        yaw = math.atan2(heading_vector[1], heading_vector[0])
        return (0.0, yaw, 0.0), angular_velocity
