from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient
import time
import threading
import statistics
import math
import json
from pathlib import Path
import numpy as np

#How big is window for data (seconds)
WINDOW_TIME = 1

#sensitivity for CUSUM
SENS = 0.5

#Threshold for CUSUM aka how long do you have to be elevated to trigger
THRESHOLD_HIGH = 3
THRESHOLD_LOW = 2

calibration_path = Path(__file__).parent / "calibrationElevation.json"
with calibration_path.open("r", encoding="utf-8") as f:
    calibration = json.load(f)

last_process = time.monotonic()
elevated = False

sensors = {
    "HR": {
        "raw_data": [],
        "prev_cusum": 0,
        "cusum": 0,
        "weight": 1,
        "baseline_mean": calibration["HR"]["mean"],
        "baseline_stdev": calibration["HR"]["stdev"]
    },
    "EDA": {
        "raw_data": [],
        "prev_cusum": 0,
        "cusum": 0,
        "weight": 0.3,
        "baseline_mean": calibration["EDA"]["mean"],
        "baseline_stdev": calibration["EDA"]["stdev"]
    },
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
    client.send_message("/Godot/elevated",elevated)


def update():
    global sensors, elevated

    #Individual cusums
    cusums = []

    for sensor in sensors.values():
        if (len(sensor["raw_data"]) == 0):
            break
        mean = statistics.mean(sensor["raw_data"])
        z_score = (mean - sensor["baseline_mean"]) / sensor["baseline_stdev"]

        #directional correction with weight
        #aka positive = elevated state no matter what & negative means calmer state (don't really care about that rn)
        z_score_weighted = z_score * sensor["weight"]

        last_cusum = sensor["cusum"]
        #Capping cusum
        sensor["cusum"] = min(max(0,sensor["prev_cusum"]+(z_score_weighted-SENS)),THRESHOLD_HIGH*1.2) #*1.2 to allow Cusum to not hit on threshold, change later
        #possibly implement lower cusum
        sensor["prev_cusum"] = last_cusum

        cusums.append(sensor["cusum"])
        
        #clear old data
        sensor["raw_data"] = []

    if len(cusums) == 0:
        return
    
    #rms for averaging cusum
    print(cusums)
    # rms_cusum = np.mean(cusums)
    rms_cusum = math.sqrt(sum(x*x for x in cusums) / len(cusums))
    
    print("CUSUM: ",rms_cusum) #Larger number = more elevated
    

    if rms_cusum >= THRESHOLD_HIGH:
        elevated = True
        sendElevated()
    elif rms_cusum <= THRESHOLD_LOW:
        elevated = False
        sendElevated()
    print(elevated)





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


