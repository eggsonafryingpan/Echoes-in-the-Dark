from ahrs.filters import Madgwick
import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.common.quaternion import Quaternion
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient
from pathlib import Path
import math
import json

madgwick = Madgwick(frequency=8) #frequency = packets/second

prev_q = np.array([1.0, 0.0, 0.0, 0.0])
curr_q = np.array([1.0, 0.0, 0.0, 0.0])

sensors = {
    "GYRO": [None] * 3, #In radians
    "ACC": [None] * 3,
    "MAG": [None] * 3,
}

calibration_path = Path(__file__).parent / "calibrationIMU.json"
with calibration_path.open("r", encoding="utf-8") as f:
    calibration = json.load(f)




def updateSensor(sensor_name, axis, val):
    sensor = sensors[sensor_name]
    #In case xyz come in different orders
    match axis:
        case "X":
            sensor[0] = val - calibration[sensor_name][0]
        case "Y":
            sensor[1] = val - calibration[sensor_name][1]
        case "Z":
            sensor[2] = val - calibration[sensor_name][2]


def processData():
    global prev_q, curr_q
    #DEG TO RAD
    sensors["GYRO"] = [deg * math.pi / 180 for deg in sensors["GYRO"]]

    prev_q = curr_q.copy()
    curr_q = madgwick.updateMARG(prev_q, gyr=sensors["GYRO"], acc=sensors["ACC"], mag=sensors["MAG"])

    q1 = Quaternion(q=prev_q)
    q2 = Quaternion(q=curr_q)

    #Quaternion difference
    delta_q = q2.product(q1.conjugate)

    euler = q2euler(delta_q) # IN RADIANS
    print("--------------")
    print(euler)
    return euler



def handler(address, *args):
    if ":" not in address:
        return
    
    #Extracting data from address
    val = args[0]
    sensor_info = address.split("/")[-1].split(":")
    sensor_name = sensor_info[0]
    axis = sensor_info[1]
    if sensor_name not in sensors.keys():
        return

    updateSensor(sensor_name, axis, val)

    #When all data is collected
    if all(all(x is not None for x in sensor) for sensor in sensors.values()):
        imu = processData()
        sendGodot(imu)
        clearData()


client = SimpleUDPClient("127.0.0.1", 8687)

def sendGodot(data):
    client.send_message("/Godot/IMU",data)

def clearData():
    for key in sensors:
        sensors[key] = [None] * 3


dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)


server = BlockingOSCUDPServer(("127.0.0.1", 12346), dispatcher)
print("Recieving...")
server.serve_forever()


