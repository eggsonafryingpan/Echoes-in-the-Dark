"""Motion gate: heart rate is only trustworthy when the head is holding still.

Brief CLAUDE_CODE_BRIEF.md §3.2: "angular velocity gates heart rate readings,
and state transitions are evaluated only on settled data." PPG is wrecked by
motion, and that's fine because HR is only needed during CALM, when the
player is deliberately holding still anyway.
"""


class MotionGate:
    def __init__(self, still_threshold: float = 0.05, smoothing: float = 0.2):
        # still_threshold is in rad/s. smoothing is an EMA factor (0-1); a
        # single fast spin shouldn't instantly flip the gate back to "still"
        # the moment it stops, so we smooth the magnitude before comparing.
        self.still_threshold = still_threshold
        self.smoothing = smoothing
        self._smoothed_omega = 0.0

    def update(self, angular_velocity: float) -> bool:
        """angular_velocity is instantaneous |gyro| in rad/s. Returns the
        current is_still state."""
        self._smoothed_omega += (abs(angular_velocity) - self._smoothed_omega) * self.smoothing
        return self._smoothed_omega < self.still_threshold
