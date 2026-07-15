import time
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import sys
import threading
import numpy as np

last_process = time.monotonic()

#in seconds
CALIBRATION_PERIOD = 5

sensors = {
    "GYRO": {
        "X": [],
        "Y": [],
        "Z": [],
    },
    "ACC": {
        "X": [],
        "Y": [],
        "Z": [],
    },
    "MAG": {
        "X": [],
        "Y": [],
        "Z": [],
    },
}

calibration = [[0,0,0],[0,0,-9.81],[0,0,0]]

def calc_calibration():
    #GYRO calibration is on in deg
    for index, axis_data in enumerate(sensors["GYRO"].values()):
        data = np.array(axis_data)
        mean = np.mean(data)
        calibration[0][index] = mean
    for index, axis_data in enumerate(sensors["ACC"].values()):
        data = np.array(axis_data)
        mean = np.mean(data)
        calibration[1][index] += mean
    for index, axis_data in enumerate(sensors["MAG"].values()):
        data = np.array(axis_data)
        data_min = data.min(axis=0)
        data_max = data.max(axis=0)
        bias = (data_min + data_max) / 2
        calibration[2][index] = bias


def write_calibration():
    result = "/".join(",".join(map(str, sensor)) for sensor in calibration)
    with open("calibration.txt", "w") as f:
        f.write(result)



def timer():
    global last_process
    while True:
        if (time.monotonic() - last_process >= CALIBRATION_PERIOD):
            calc_calibration()
            write_calibration()
            print("Calibration finished :D")
            sys.exit(0)
        time.sleep(0.01)

threading.Thread(target=timer,daemon=True).start()




def handler(address, *args):
    if "EmotiBit" not in address or len(args) != 1:
        return
    
    #Extracting data from address
    val = args[0]
    sensor_info = address.split("/")[-1].split(":")
    sensor_name = sensor_info[0]
    axis = sensor_info[1]

    sensors[sensor_name][axis].append(val)




dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)


server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
print("Recieving...")
server.serve_forever()