import neurokit2 as nk
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
import matplotlib.pyplot as plt




#How big is window for data (seconds)
WINDOW_TIME = 20
FREQUENCY = 15

last_process = time.monotonic()

sensors = {
    "EDA": {
        "raw_data": []
    }
}



def handler(address, *args):

    sensor_name = address.split("/")[-1]
    if sensor_name not in sensors:
        return
    sensor = sensors[sensor_name]
    sensor["raw_data"].extend(args)

    # print(sensor_name, "Data:",args[0])

client = SimpleUDPClient("127.0.0.1", 8687)

# def sendElevated():
#     global client
#     print("Sending...")
#     client.send_message("/Godot/elevated",elevated)


def update():
    data = np.array(sensors["EDA"]["raw_data"])
    signals, info = nk.eda_process(
        data,
        sampling_rate=FREQUENCY
    )
    sensors["EDA"]["raw_data"] = []
    # print(signals["EDA_Tonic"])
    # print(signals["EDA_Phasic"])
    nk.eda_plot(signals, info)
    plt.show()






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


