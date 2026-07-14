from ahrs.filters import Madgwick
import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.common.quaternion import Quaternion
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import time
import math

madgwick = Madgwick(frequency=25.0)

#curr * prev^-1   .inverse()
prev_q = np.array([1.0, 0.0, 0.0, 0.0])
curr_q = np.array([1.0, 0.0, 0.0, 0.0])

#UGH IM SO DONE IM NOT DOING BUFFER IDC
#No time buffer and no mag since game does not need them
sensors = {
    "GYRO": [], #RADIANNNSSSS
    "ACC": [],
    "MAG": [],
}

#IM USING QUATERNION DIFFERENCE !!!!

def updateSensor(curr, axis, val):

    #plz come in order I beg
    if len(curr)==3:
        return
    #In case xyz come in different orders
    match axis:
        case "X":
            curr[0] = val
        case "Y":
            curr[1] = val
        case "Z":
            curr[2] = val


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

    if all(len(sensor) == 3 for sensor in sensors.values()):
        orien = processData()
        sendGodot(orien)

    

def processData():

    #DEG TO RAD
    sensors["GYRO"] = [deg * math.pi / 180 for deg in sensors["GYRO"]]

    prev_q = curr_q.copy()
    curr_q = madgwick.updateMARG(prev_q, gyr=sensors["GYRO"], acc=sensors["ACC"], mag=sensors["MAG"])

    q1 = Quaternion(prev_q)
    q2 = Quaternion(curr_q)

    #Quaternion difference
    delta_q = q2 * q1.conj()

    euler = q2euler(delta_q) # IN RADIANS
    print(euler)
    return euler


def sendGodot(data):
    #TODO
    return



dispatcher = Dispatcher()
dispatcher.set_default_handler(handler)


server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
print("Recieving...")
server.serve_forever()


calibrationFile = open("calibration.txt")
calib = calibrationFile.read().split(",")
calib = [float(x) for x in calib]
print(calib)