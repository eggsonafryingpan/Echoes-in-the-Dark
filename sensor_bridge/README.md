# Sensor bridge (Process A)

Signal processing lives here, not in Godot (brief §2). Only needed when real
EmotiBit hardware is in the loop — day-to-day development uses Godot's
`MockSource` instead, no Python process required (brief §3.5).

```
pip install -r requirements.txt
python bridge.py --listen-port 12346 --godot-port 8687
```

Pipeline: EmotiBit OSC (9-axis IMU + green-channel PPG) → Madgwick
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
