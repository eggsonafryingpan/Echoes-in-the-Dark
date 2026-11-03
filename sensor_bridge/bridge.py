"""Process A -- the Python sensor bridge.

Brief: CLAUDE_CODE_BRIEF.md §2, §3, §13 Phase 1.

Ingests EmotiBit's raw 9-axis IMU and red-channel PPG over OSC, runs the
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
e.g. ".../GYRO:X", ".../ACC:Y", ".../PPG:RED". Sensor/axis names are matched
on the address tail, so the prefix doesn't matter. Verify the exact addresses
your EmotiBit firmware/oscilloscope setup emits with a plain OSC monitor
before assuming this matches -- that's hardware bring-up, a human task.
"""
from __future__ import annotations

import argparse
import math
import time
from collections import deque

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

import trigger_out
from heart_rate import HeartRateEstimator
from motion_gate import MotionGate
from nod_calibration import NodCalibrator, NodTracker
from orientation import OrientationEstimator

# Outgoing addresses Godot's LiveOSCSource (sensor/live_osc_source.gd) listens for.
ORIENTATION_ADDRESS = "/echoes/orientation"
PITCH_RATE_ADDRESS = "/echoes/pitch_rate"
HEART_RATE_ADDRESS = "/echoes/heart_rate"

# EmotiBit's onboard red-channel PPG stream. Brief §3.1: red PPG, not the
# onboard HR estimate.
PPG_RED_SENSOR = "PPG:RED"

AXIS_INDEX = {"X": 0, "Y": 1, "Z": 2}


class SensorBridge:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.orientation = OrientationEstimator(frequency=args.imu_rate, up_axis=args.up_axis)
        self.heart_rate = HeartRateEstimator(sample_rate=args.ppg_rate, window_seconds=args.hr_window)
        self.motion_gate = MotionGate(still_threshold=args.still_threshold)

        self._axes = {name: [deque(), deque(), deque()] for name in ("GYRO", "ACC", "MAG")}
        self._last_is_still = False
        self._announced_up = False

        # Counted between status lines.
        self._packets = 0
        self._imu_samples = 0
        self._ppg_samples = 0
        self._omega_peak = 0.0
        self._last_bpm = None
        self._t_status = time.monotonic()

        self.calibrator = NodCalibrator(args.imu_rate) if args.calibrate else None
        self.nod = NodTracker.load()
        if self.nod is None and not args.calibrate:
            print(f"WARNING: no nod calibration, guessing the head's pitch axis ({args.pitch_axis}). "
                  "Run: bridge.py --calibrate", flush=True)
        self._nod_peak = 0.0
        self._pitch = 0.0

        self.client = SimpleUDPClient(args.godot_host, args.godot_port)

    # --- incoming EmotiBit OSC ----------------------------------------------

    def handle_message(self, address: str, *values) -> None:
        self._packets += 1
        tail = address.rsplit("/", 1)[-1]
        if ":" in tail:
            sensor, axis = tail.split(":", 1)
            if sensor in self._axes:
                self._set_axis(sensor, axis, values)
                self._maybe_process_imu()
                self._maybe_print_status()
                return
        if tail == PPG_RED_SENSOR and values:
            # EmotiBit batches several samples into one packet.
            for value in values:
                self.heart_rate.add_sample(float(value))
            self._ppg_samples += len(values)
            self._maybe_process_hr()
        self._maybe_print_status()

    def _set_axis(self, sensor: str, axis: str, values) -> None:
        index = AXIS_INDEX.get(axis)
        if index is None:
            return
        self._axes[sensor][index].extend(float(v) for v in values)

    def _maybe_process_imu(self) -> None:
        # The axes arrive as separate packets: one IMU sample is ready once
        # every axis has a value for it.
        queues = [q for sensor in self._axes.values() for q in sensor]
        while all(queues):
            self._process_imu_sample()

    def _process_imu_sample(self) -> None:
        gyro_deg = [q.popleft() for q in self._axes["GYRO"]]
        acc = [q.popleft() for q in self._axes["ACC"]]
        mag = [q.popleft() for q in self._axes["MAG"]]

        gyro = [math.radians(v) for v in gyro_deg]
        if self.calibrator is not None:
            self.calibrator.add(gyro, acc)
            return
        pitch_yaw_roll, angular_velocity = self.orientation.update(gyro, acc, mag)
        self._last_is_still = self.motion_gate.update(angular_velocity)
        self._imu_samples += 1
        self._omega_peak = max(self._omega_peak, abs(angular_velocity))
        if not self._announced_up and self.orientation.up_index is not None:
            self._announced_up = True
            print(f"Orientation: sensor {'XYZ'[self.orientation.up_index]} axis is up; sending yaw only.")

        # Already in Godot's (pitch, yaw, roll) order -- see orientation.py.
        if self.nod is not None:
            self._pitch = self.nod.pitch(acc)
            pitch_yaw_roll = (self._pitch, pitch_yaw_roll[1], pitch_yaw_roll[2])
        self.client.send_message(ORIENTATION_ADDRESS, [float(v) for v in pitch_yaw_roll])
        # Head flicks: the raw gyro about the axis the head nods around, so it
        # needs no mounting-dependent pitch angle. Positive = up.
        if self.nod is not None:
            pitch_rate = self.nod.pitch_rate(gyro)
        else:
            pitch_rate = gyro["xyz".index(self.args.pitch_axis)] * self.args.pitch_sign
        self._nod_peak = max(self._nod_peak, pitch_rate)
        self.client.send_message(PITCH_RATE_ADDRESS, [float(pitch_rate)])

    def _maybe_print_status(self) -> None:
        now = time.monotonic()
        elapsed = now - self._t_status
        if elapsed < 2.0 or self.calibrator is not None:
            return
        print(f"packets {self._packets / elapsed:.0f}/s  imu {self._imu_samples / elapsed:.1f} Hz  "
              f"ppg {self._ppg_samples / elapsed:.1f} Hz  "
              f"hr window {len(self.heart_rate._buffer)}/{self.heart_rate.window_size}  "
              f"peak turn {self._omega_peak:.3f} rad/s  nod up {math.degrees(self._nod_peak):.0f} deg/s  "
              f"pitch {math.degrees(self._pitch):.0f} deg  still {self._last_is_still}  bpm {self._last_bpm}", flush=True)
        self._packets = self._imu_samples = self._ppg_samples = 0
        self._omega_peak = 0.0
        self._nod_peak = 0.0
        self._t_status = now

    def _maybe_process_hr(self) -> None:
        if not self.heart_rate.ready():
            return
        bpm = self.heart_rate.estimate_bpm() if self._last_is_still else None
        self._last_bpm = bpm
        if bpm is not None:
            self.client.send_message(HEART_RATE_ADDRESS, [bpm, 1])
        else:
            self.client.send_message(HEART_RATE_ADDRESS, [0.0, 0])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--in-port", "--listen-port", dest="listen_port", type=int, default=12346,
                        help="Port EmotiBit's OSC stream arrives on (EmotiBit Oscilloscope sends to 12345 by default)")
    parser.add_argument("--godot-host", default="127.0.0.1")
    parser.add_argument("--godot-port", type=int, default=8687, help="Port Godot's OSCServer/GodOSC listens on")
    parser.add_argument("--trigger-port", type=int, default=12347,
                        help="Port the game sends DualSense trigger-resistance requests to (trigger_out.py)")
    parser.add_argument("--calibrate", action="store_true",
                        help="Measure how a nod looks to the sensor, save it, and exit")
    parser.add_argument("--pitch-axis", choices=["x", "y", "z"], default="z",
                        help="Sensor axis the head nods around, for head flicks")
    parser.add_argument("--pitch-sign", type=float, choices=[-1.0, 1.0], default=1.0,
                        help="Set to -1 if looking up reads as looking down")
    parser.add_argument("--imu-rate", type=float, default=25.0, help="IMU packet rate, Hz")
    parser.add_argument("--ppg-rate", type=float, default=25.0, help="Red-PPG sample rate, Hz")
    parser.add_argument("--hr-window", type=float, default=10.0, help="HeartPy sliding window, seconds")
    parser.add_argument("--still-threshold", type=float, default=0.3, help="rad/s below which the head counts as still")
    parser.add_argument("--up-axis", choices=["x", "y", "z"], default=None,
                        help="Sensor axis that points up when worn (default: detected from gravity at startup)")
    args = parser.parse_args()

    bridge = SensorBridge(args)

    dispatcher = Dispatcher()
    dispatcher.set_default_handler(bridge.handle_message)

    server = BlockingOSCUDPServer(("0.0.0.0", args.listen_port), dispatcher)
    if args.calibrate:
        print(f"Calibrating: waiting for the EmotiBit on :{args.listen_port}...", flush=True)
        while not bridge.calibrator.done:
            server.handle_request()
        return
    print(f"Sensor bridge listening on :{args.listen_port}, forwarding to {args.godot_host}:{args.godot_port}")
    triggers = trigger_out.start(args.trigger_port)
    try:
        server.serve_forever()
    finally:
        triggers.close()


if __name__ == "__main__":
    main()
