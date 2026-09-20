"""9-axis IMU -> Madgwick filter -> orientation.

Brief CLAUDE_CODE_BRIEF.md §3: "Orientation: 9-axis IMU -> Madgwick filter
(ahrs library) -> quaternion/euler."

Axis mapping from the EmotiBit's IMU frame to Godot's (pitch, yaw, roll) is
hardware-calibration work -- a human task once real hardware and a real head
are in the loop (§0.1: "Hardware tuning is a later human task"). This
wrapper exposes the raw ahrs euler output and the instantaneous gyro
magnitude (for the motion gate) and leaves remapping/sign-flipping to
whoever does that calibration pass.
"""
from __future__ import annotations

import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.filters import Madgwick


class OrientationEstimator:
    def __init__(self, frequency: float = 25.0):
        self._madgwick = Madgwick(frequency=frequency)
        self._q = np.array([1.0, 0.0, 0.0, 0.0])

    def update(self, gyro, acc, mag) -> tuple[tuple[float, float, float], float]:
        """gyro in rad/s; acc/mag in whatever units the sensor reports (ahrs
        only cares that they're internally consistent). Returns
        (euler_xyz_radians, angular_velocity_rad_s)."""
        self._q = self._madgwick.updateMARG(self._q, gyr=gyro, acc=acc, mag=mag)
        euler = q2euler(self._q)
        angular_velocity = float(np.linalg.norm(gyro))
        return euler, angular_velocity
