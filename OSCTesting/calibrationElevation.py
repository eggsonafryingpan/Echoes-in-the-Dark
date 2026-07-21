import time
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import sys
import threading
import numpy as np
import json
from pathlib import Path

last_process = time.monotonic()

#in seconds
CALIBRATION_PERIOD = 20

sensors = {
    "HR": [],
    "EDA": [],
    # "TEMP": [],
}

calibration = {
    "HR": {
        "mean": 0,
        "stdev": 0,
    },
    "EDA": {
        "mean": 0,
        "stdev": 0,
    },
    # "TEMP": {
    #     "mean": 0,
    #     "stdev": 0,
    # },
}

def calc_calibration():
    for sensor_name in calibration.keys():
        data = np.array(sensors[sensor_name])

        mean = np.mean(data)
        stdev = np.std(data)

        calibration[sensor_name]["mean"] = mean
        calibration[sensor_name]["stdev"] = stdev





def write_calibration():
    calibration_path = Path(__file__).parent / "calibrationElevation.json"
    with calibration_path.open("w", encoding="utf-8") as f:
        json.dump(calibration, f, indent=4)


def timer():
    global last_process, calibration_stage
    print("Calibrating...")
    while True:
        if (time.monotonic() - last_process >= CALIBRATION_PERIOD):
            calc_calibration()
            write_calibration()
            print("Calibration finished :D")
            break
        time.sleep(0.01)
    sys.exit()

threading.Thread(target=timer,daemon=True).start()




def handler(address, *args):
    if "EmotiBit" not in address:
        return
    
    #Extracting data from address
    val = args[0]
    sensor_name = address.split("/")[-1]
    if sensor_name not in sensors.keys():
        return

    sensors[sensor_name].append(val)




dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)


server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
server.serve_forever()