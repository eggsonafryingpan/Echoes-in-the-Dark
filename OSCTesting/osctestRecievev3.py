from pythonosc.dispatcher import Dispatcher
from typing import List, Any

dispatcher = Dispatcher()


#resting z-score
#prev CUSUM
#direction
#index

# restingZScore = [10,4,2]
# direction = [1,-1,1]
# sensors = {
#     "HR": 0,
#     "EDA": 1,
#     "TEMP": 2,
# }





values = {}

def handler(address, *args):
    # filterno = address[-1]
    values[address] = args[0]
    # print(address, "Data: {value1}")
    # print(f"Setting emotibit {filterno} HR: {value1} Rotation: {value2}")
    print(values)



    #example
    i = sensors[address] ##!!!! parse to get last after /

    #z score and CUSUM


dispatcher.set_default_handler(handler)  # Map wildcard address to set_filter function

# # Set up server and client for testing
from pythonosc.osc_server import BlockingOSCUDPServer

server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
print("Recieving...")
server.serve_forever()