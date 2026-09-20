"""Process A -- the Python sensor bridge.

Brief: CLAUDE_CODE_BRIEF.md §2, §3, §13 Phase 1.

Ingests EmotiBit's raw 9-axis IMU and green-channel PPG over OSC, runs the
Madgwick orientation filter and the HeartPy heart-rate pipeline, applies the
motion gate, and forwards clean orientation + heart-rate(+validity) to Godot
over OSC on the address scheme Godot's LiveOSCSource listens on.

This process is the ONLY place signal processing happens -- Godot never does
IMU fusion or PPG filtering (§2). Nothing here decides "elevated" or
"overload": it only reports orientation and BPM(+validity). The relative
baseline comparison and the conjunctive detector live in Godot (GameState /
OverloadDetector), because that's where the game state they're conjoined
with actually lives, and because the detector must never claim to measure
cognitive load from this signal alone (§0.1, §5).

Run this only when real EmotiBit hardware is in the loop. It is NOT needed
for day-to-day development -- Godot's MockSource replays canned traces with
no Python process running at all (§3.5, mock-first development).

EmotiBit OSC address convention assumed here: "<prefix>/<SENSOR>:<AXIS>",
e.g. ".../GYRO:X", ".../ACC:Y", ".../PPG:GRN". Sensor/axis names are matched
on the address tail, so the prefix doesn't matter. Verify the exact addresses
your EmotiBit firmware/oscilloscope setup emits with a plain OSC monitor
before assuming this matches -- that's hardware bring-up, a human task.
"""
from __future__ import annotations

import argparse
import math

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

from heart_rate import HeartRateEstimator
from motion_gate import MotionGate
from orientation import OrientationEstimator

# Outgoing addresses Godot's LiveOSCSource (sensor/live_osc_source.gd) listens for.
ORIENTATION_ADDRESS = "/echoes/orientation"
HEART_RATE_ADDRESS = "/echoes/heart_rate"

# EmotiBit's onboard green-channel PPG stream. Brief §3.1: green PPG, not the
# onboard HR estimate, and not red/IR.
PPG_GREEN_SENSOR = "PPG:GRN"

AXIS_INDEX = {"X": 0, "Y": 1, "Z": 2}


class SensorBridge:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.orientation = OrientationEstimator(frequency=args.imu_rate)
        self.heart_rate = HeartRateEstimator(sample_rate=args.ppg_rate, window_seconds=args.hr_window)
        self.motion_gate = MotionGate(still_threshold=args.still_threshold)

        self._axes = {"GYRO": [None, None, None], "ACC": [None, None, None], "MAG": [None, None, None]}
        self._last_is_still = False

        self.client = SimpleUDPClient(args.godot_host, args.godot_port)

    # --- incoming EmotiBit OSC ----------------------------------------------

    def handle_message(self, address: str, *values) -> None:
        tail = address.rsplit("/", 1)[-1]
        if ":" in tail:
            sensor, axis = tail.split(":", 1)
            if sensor in self._axes:
                self._set_axis(sensor, axis, values)
                self._maybe_process_imu()
                return
        if tail == PPG_GREEN_SENSOR:
            if values:
                self.heart_rate.add_sample(float(values[0]))
                self._maybe_process_hr()

    def _set_axis(self, sensor: str, axis: str, values) -> None:
        index = AXIS_INDEX.get(axis)
        if index is None or not values:
            return
        self._axes[sensor][index] = float(values[0])

    def _maybe_process_imu(self) -> None:
        gyro_deg = self._axes["GYRO"]
        acc = self._axes["ACC"]
        mag = self._axes["MAG"]
        if any(v is None for v in gyro_deg + acc + mag):
            return

        gyro = [math.radians(v) for v in gyro_deg]
        euler, angular_velocity = self.orientation.update(gyro, acc, mag)
        self._last_is_still = self.motion_gate.update(angular_velocity)

        self.client.send_message(ORIENTATION_ADDRESS, [float(euler[0]), float(euler[1]), float(euler[2])])
        self._axes = {"GYRO": [None, None, None], "ACC": [None, None, None], "MAG": [None, None, None]}

    def _maybe_process_hr(self) -> None:
        if not self.heart_rate.ready():
            return
        bpm = self.heart_rate.estimate_bpm() if self._last_is_still else None
        if bpm is not None:
            self.client.send_message(HEART_RATE_ADDRESS, [bpm, 1])
        else:
            self.client.send_message(HEART_RATE_ADDRESS, [0.0, 0])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listen-port", type=int, default=12346, help="Port EmotiBit's OSC stream arrives on")
    parser.add_argument("--godot-host", default="127.0.0.1")
    parser.add_argument("--godot-port", type=int, default=8687, help="Port Godot's OSCServer/GodOSC listens on")
    parser.add_argument("--imu-rate", type=float, default=25.0, help="IMU packet rate, Hz")
    parser.add_argument("--ppg-rate", type=float, default=25.0, help="Green-PPG sample rate, Hz")
    parser.add_argument("--hr-window", type=float, default=10.0, help="HeartPy sliding window, seconds")
    parser.add_argument("--still-threshold", type=float, default=0.05, help="rad/s below which the head counts as still")
    args = parser.parse_args()

    bridge = SensorBridge(args)

    dispatcher = Dispatcher()
    dispatcher.set_default_handler(bridge.handle_message)

    server = BlockingOSCUDPServer(("0.0.0.0", args.listen_port), dispatcher)
    print(f"Sensor bridge listening on :{args.listen_port}, forwarding to {args.godot_host}:{args.godot_port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
