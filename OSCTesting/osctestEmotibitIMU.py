from pythonosc.udp_client import SimpleUDPClient
import time
import math

client = SimpleUDPClient("127.0.0.1",12345)

hr = 0
eda = 0
temp = 0

period = 0.04

t = 0



dt = 0.04          # 25 Hz
yaw = 0.0
yaw_rate = 30  # 30 deg/s

# Earth magnetic field in world frame
mag_world = [1.0, 0.0, 0.2]

while True:
    # Gyroscope
    # gx = 0.0
    # gy = 0.0
    # gz = yaw_rate
    gx = 0.0
    gy = 0.0
    gz = 0.5

    # Accelerometer (gravity)
    ax = 0.0
    ay = 0.0
    az = 9.81 + 0.5

    # Rotate world magnetic field into sensor frame
    # mx = mag_world[0] * math.cos(yaw) + mag_world[1] * math.sin(yaw)
    # my = -mag_world[0] * math.sin(yaw) + mag_world[1] * math.cos(yaw)
    # mz = mag_world[2]
    mx = 0.0
    my = 0.0
    mz = 0.5


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


