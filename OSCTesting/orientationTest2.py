from ahrs.filters import Madgwick
import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.common.quaternion import Quaternion
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient
import time
import math

madgwick = Madgwick(frequency=25) #packets/second

#curr * prev^-1   .inverse()
prev_q = np.array([1.0, 0.0, 0.0, 0.0])
curr_q = np.array([1.0, 0.0, 0.0, 0.0])

#UGH IM SO DONE IM NOT DOING BUFFER IDC
sensors = {
    "GYRO": [None] * 3, #RADIANNNSSSS
    "ACC": [None] * 3,
    "MAG": [None] * 3,
}



calibrationFile = open("calibration.txt")
calib = calibrationFile.read().split(",")
calib = [float(x) for x in calib]
print(calib)


def updateSensor(curr, axis, val):
    #PREPROCESS PLZ

    #In case xyz come in different orders
    match axis:
        case "X":
            curr[0] = val
        case "Y":
            curr[1] = val
        case "Z":
            curr[2] = val


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
    if "EmotiBit" not in address or len(args) != 1:
        return
    
    #Extracting data from address
    val = args[0]
    sensor_info = address.split("/")[-1].split(":")
    sensor_name = sensor_info[0]
    axis = sensor_info[1]

    sensor = sensors[sensor_name]
    updateSensor(sensor, axis, val)

    if all(all(x is not None for x in sensor) for sensor in sensors.values()):
        imu = processData()
        sendGodot(imu)
        clearData()


client = SimpleUDPClient("127.0.0.1", 8687)

def sendGodot(data):
    print("Sending...")
    client.send_message("/Godot/IMU",data)

def clearData():
    for key in sensors:
        sensors[key] = [None] * 3


dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)


server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
print("Recieving...")
server.serve_forever()


