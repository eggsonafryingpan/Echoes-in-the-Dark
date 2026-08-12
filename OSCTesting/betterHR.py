from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient
import time
import threading
import heartpy as hp
from pathlib import Path
import numpy as np

#How big is window for data (seconds)
WINDOW_TIME = 2

# calibration_path = Path(__file__).parent / "calibrationElevation.json"
# with calibration_path.open("r", encoding="utf-8") as f:
#     calibration = json.load(f)

last_process = time.monotonic()
sample_rate = 4
heartrate = 80

sensors = {
    "PPG:RED": {
        "raw_data": [],
        # "prev_cusum": 0,
        # "cusum": 0,
        # "weight": 1,
        # "baseline_mean": calibration["HR"]["mean"],
        # "baseline_stdev": calibration["HR"]["stdev"]
    },
    # "EDA": {
    #     "raw_data": [],
    #     "prev_cusum": 0,
    #     "cusum": 0,
    #     "weight": 0.3,
    #     "baseline_mean": calibration["EDA"]["mean"],
    #     "baseline_stdev": calibration["EDA"]["stdev"]
    # },
    # "TEMP": {
    #     "raw_data": [],
    #     "prev_cusum": 0,
    #     "cusum": 0,
    #     "weight": 1,
    #     "baseline_mean": calibration["TEMP"]["mean"],
    #     "baseline_stdev": calibration["TEMP"]["stdev"]
    # },
}





def handler(address, *args):

    sensor_name = address.split("/")[-1]
    if sensor_name not in sensors:
        return
    sensor = sensors[sensor_name]
    sensor["raw_data"].append(args[0])

    # print(sensor_name, "Data:",args[0])

client = SimpleUDPClient("127.0.0.1", 8687)

def sendElevated():
    global client
    print("Sending...")
    client.send_message("/Godot/elevated",heartrate)


def update():
    global heartrate,sensors
    ppg = sensors["PPG:RED"]["raw_data"]
    print(ppg)
    working_data, measures = hp.process(
        np.array(ppg, dtype=float),
        sample_rate=sample_rate,
        bpmmin=40,
        bpmmax=180
    )
    heartrate = measures["bpm"]

    sensors["PPG:RED"]["raw_data"] = []
    print(heartrate)







dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)  



#Timer for window
def timer():
    global last_process
    while True:
        if (time.monotonic() - last_process >= WINDOW_TIME):
            update()
            last_process = time.monotonic()
        time.sleep(0.01)

threading.Thread(target=timer,daemon=True).start()


#IP AND PORT
server = BlockingOSCUDPServer(("127.0.0.1", 12347), dispatcher)
print("Recieving...")
server.serve_forever()


