"""DualSense adaptive-trigger resistance, requested by the game over OSC.

Godot can't set trigger resistance itself, so the game sends
/echoes/trigger [side, strength] (side -1 = L2, +1 = R2; strength 0..1) to
--trigger-port, and this applies it over HID with pydualsense.

Optional: if pydualsense (and the hidapi library it needs) isn't installed, or
no controller is found, it says so once and the game plays without
resistance. Install:
    brew install hidapi
    .venv/bin/pip install pydualsense

Untested on this Mac: whether pydualsense can talk to the controller while
Godot also has it open. If resistance never appears, that's the first thing
to check.
"""
from __future__ import annotations

import threading

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer

TRIGGER_ADDRESS = "/echoes/trigger"


class TriggerOut:
    def __init__(self) -> None:
        self.ds = None
        self.modes = None
        try:
            from pydualsense import pydualsense, TriggerModes
        except Exception as error:  # missing module or hidapi
            print(f"Triggers: pydualsense unavailable ({error}); no trigger resistance.", flush=True)
            return
        try:
            ds = pydualsense()
            ds.init()
        except Exception as error:
            print(f"Triggers: no DualSense found over HID ({error}); no trigger resistance.", flush=True)
            return
        self.ds = ds
        self.modes = TriggerModes
        print("Triggers: DualSense found; L2/R2 resistance on.", flush=True)

    def set(self, side: int, strength: float) -> None:
        if self.ds is None:
            return
        trigger = self.ds.triggerL if side < 0 else self.ds.triggerR
        if strength <= 0.0:
            trigger.setMode(self.modes.Off)
        else:
            trigger.setMode(self.modes.Rigid)
            trigger.setForce(1, int(255 * min(strength, 1.0)))

    def close(self) -> None:
        if self.ds is not None:
            for trigger in (self.ds.triggerL, self.ds.triggerR):
                trigger.setMode(self.modes.Off)
            self.ds.close()


def start(port: int) -> TriggerOut:
    """Listens on port in a background thread; returns the TriggerOut."""
    out = TriggerOut()
    dispatcher = Dispatcher()
    dispatcher.map(TRIGGER_ADDRESS, lambda _addr, side, strength: out.set(int(side), float(strength)))
    server = ThreadingOSCUDPServer(("127.0.0.1", port), dispatcher)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Triggers: listening for the game on :{port}", flush=True)
    return out
