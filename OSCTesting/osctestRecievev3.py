from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import time
import threading
import statistics

WINDOW_TIME = 1
SENS = 2
#sensitivity for CUSUM
THRESHOLD_HIGH = 2
THRESHOLD_LOW = 1
#Threshold for CUSUM aka how long do you have to be elevated to trigger



last_process = time.monotonic()
elevated = False

sensors = {
    "HR": {
        "raw_data": [],
        "prev_cusum": 0,
        "cusum": 0,
        "weight": 1,
        "baseline_mean": 0,
        "baseline_stdev": 2
    },
    "EDA": {
        "raw_data": [],
        "prev_cusum": 0,
        "cusum": 0,
        "weight": -1,
        "baseline_mean": 0,
        "baseline_stdev": 2
    },
    "TEMP": {
        "raw_data": [],
        "prev_cusum": 0,
        "cusum": 0,
        "weight": 1,
        "baseline_mean": 0,
        "baseline_stdev": 2
    },
}







def handler(address, *args):
    global sensors
    # EMOTIBIT CHANGE MAYBE???
    # if "EmotiBit" not in address or args[0] is None:
    #     return
    
    sensor_name = address.split("/")[-1]
    sensor = sensors[sensor_name]
    sensor["raw_data"].append(args[0])

    # print(sensor_name, "Data: {args[0]}")


def update():
    global sensors, elevated

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
        sensor["cusum"] = min(max(0,sensor["prev_cusum"]+(z_score_weighted-SENS)),THRESHOLD_HIGH*1.2)
        #possibly implement lower cusum
        sensor["prev_cusum"] = last_cusum

        cusums.append(sensor["cusum"])
        
        #clear old data
        sensor["raw_data"] = []

    if len(cusums) == 0:
        return
    
    avg_cusum = statistics.mean(cusums)
    
    print(avg_cusum)
    
    if avg_cusum >= THRESHOLD_HIGH:
        elevated = True
    elif avg_cusum <= THRESHOLD_LOW:
        elevated = False





dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)  


# # Set up server
server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)


#Timer for window
def timer():
    global last_process
    while True:
        if (time.monotonic() - last_process >= WINDOW_TIME):
            update()
            print(elevated)
            last_process = time.monotonic()
        time.sleep(0.01)

threading.Thread(target=timer,daemon=True).start()

print("Recieving...")
server.serve_forever()