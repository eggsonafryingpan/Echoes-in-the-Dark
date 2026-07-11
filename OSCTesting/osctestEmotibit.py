from pythonosc.udp_client import SimpleUDPClient
import time
import random

client = SimpleUDPClient("127.0.0.1",12345)

hr = 0
eda = 0
temp = 0


while True :
    delta = random.randint(-2,2)
    if (hr + delta > -10 and hr + delta < 10):
        hr += delta
        eda -= delta
        temp += delta
    client.send_message("/EmotiBit/HR",hr)
    client.send_message("/EmotiBit/EDA",eda)
    client.send_message("/EmotiBit/TEMP",temp)
    time.sleep(0.2)
    print("Sending: ", hr, eda, temp)


