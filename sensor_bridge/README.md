# Sensor bridge (Process A)

Signal processing lives here, not in Godot (brief §2). Only needed when real
EmotiBit hardware is in the loop — day-to-day development uses Godot's
`MockSource` instead, no Python process required (brief §3.5).

```
python3.12 -m venv .venv            # Python 3.10+; macOS's bundled 3.9 won't import ahrs
.venv/bin/pip install -r requirements.txt
.venv/bin/python bridge.py --listen-port 12346 --godot-port 8687
```

Godot's `SensorBridge` defaults to DEV_MOUSE, so launch the game with
`-- --sensor=live` (or set `ECHOES_SENSOR=live`) for real heart rate and head
orientation to reach `GameState`. Until live orientation arrives the mouse
steers; the F10 readout's `source` line says which is driving. LIVE takes
port 8687, so the scene OSC receivers (`/Godot/IMU`, `/Godot/elevated`, as
sent by `OSCTesting/*_WORKING.py`) only hear packets when it is off.

Pipeline: EmotiBit OSC (9-axis IMU + red-channel PPG) → Madgwick
orientation filter (`orientation.py`) + motion gate (`motion_gate.py`) +
HeartPy sliding-window BPM (`heart_rate.py`) → forwarded to Godot's
`LiveOSCSource` as `/echoes/orientation` (pitch, yaw, roll radians) and
`/echoes/heart_rate` (bpm, valid 0/1).

This process never decides "elevated" or "overload" — it only reports
orientation and BPM(+validity). See `bridge.py`'s module docstring for why,
and for the EmotiBit OSC address convention it assumes.

Verifying the actual OSC addresses/axis order your EmotiBit setup emits, and
tuning `--still-threshold`/`--hr-window` against a real head, is
hardware-bring-up work for a human, not this script.
