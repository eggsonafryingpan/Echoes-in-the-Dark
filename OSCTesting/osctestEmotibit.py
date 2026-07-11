from pythonosc.udp_client import SimpleUDPClient
import time


client = SimpleUDPClient("127.0.0.1",12345)


eda = 100
hr = 100
temp = 67


client.send_message("/EmotiBit/EDA",eda)
client.send_message("/EmotiBit/HR",hr)
client.send_message("/EmotiBit/TEMP",temp)

print("Sending..." )
