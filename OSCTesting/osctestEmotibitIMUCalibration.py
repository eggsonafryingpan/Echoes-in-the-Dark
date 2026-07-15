from pythonosc.udp_client import SimpleUDPClient
import time
import math

client = SimpleUDPClient("127.0.0.1",12345)

hr = 0
eda = 0
temp = 0

period = 0.04

t = 0


while True:
    # Gyroscope
    gx = 0.0
    gy = 0.0
    gz = 0.1

    # Accelerometer (gravity)
    ax = 0.1
    ay = 0.1
    az = 9.81

    # Rotate world magnetic field into sensor frame
    mx = 1
    my = 0
    mz = 0


    client.send_message("/EmotiBit/0/GYRO:X",gx)
    client.send_message("/EmotiBit/0/GYRO:Y",gy)
    client.send_message("/EmotiBit/0/GYRO:Z",gz)

    client.send_message("/EmotiBit/0/ACC:X",ax)
    client.send_message("/EmotiBit/0/ACC:Y",ay)
    client.send_message("/EmotiBit/0/ACC:Z",az)

    client.send_message("/EmotiBit/0/MAG:X",mx)
    client.send_message("/EmotiBit/0/MAG:Y",my)
    client.send_message("/EmotiBit/0/MAG:Z",mz)

    t += period

    time.sleep(period)
    print("Sending...")


