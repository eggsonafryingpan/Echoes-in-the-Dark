from ahrs.filters import Madgwick
import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.common.quaternion import Quaternion
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient
import math

madgwick = Madgwick(frequency=25) #frequency = packets/second

prev_q = np.array([1.0, 0.0, 0.0, 0.0])
curr_q = np.array([1.0, 0.0, 0.0, 0.0])

sensors = {
    "GYRO": [None] * 3, #In radians
    "ACC": [None] * 3,
    "MAG": [None] * 3,
}



def get_calibration():
    calibrationFile = open("calibration.txt")
    calib_vals = calibrationFile.read().split("/")
    calib_strings = [sensor.split(",") for sensor in calib_vals]
    calib = [[float(value) for value in row] for row in calib_strings]
    print(calib)
    return calib

calib = get_calibration()





def updateSensor(sensor_name, axis, val):

    sensor_index = list(sensors.keys()).index(sensor_name)
    sensor = sensors[sensor_name]
    #In case xyz come in different orders
    match axis:
        case "X":
            sensor[0] = val - calib[sensor_index][0]
        case "Y":
            sensor[1] = val - calib[sensor_index][1]
        case "Z":
            sensor[2] = val - calib[sensor_index][2]


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

    updateSensor(sensor_name, axis, val)

    #When all data is collected
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


