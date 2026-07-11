from pythonosc.dispatcher import Dispatcher
from typing import List, Any

dispatcher = Dispatcher()

#resting z-score
#prev CUSUM
#index

restingZScore = [10,4,2]
prevCUSUM = [0,2,1]
direction = [1,-1,1]
sensors = {
    "HR": 0,
    "EDA": 1,
    "TEMP": 2,
}


def set_emotibit(address: str, *args: List[Any]) -> None:
    # We expect two float arguments
    # if not len(args) == 2 or type(args[0]) is not float or type(args[1]) is not float:
    #     return

    # # Check that address starts with filter
    # if not address[:-1] == "/emotibit":  # Cut off the last character
    #     return

    value1 = args[0]
    # filterno = address[-1]
    print(address, "Data: {set_emotibit}")
    # print(f"Setting emotibit {filterno} HR: {value1} Rotation: {value2}")


dispatcher.map("/EmotiBit/*", set_emotibit)  # Map wildcard address to set_filter function

# # Set up server and client for testing
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
# client = SimpleUDPClient(""127.0.0.1", 12345)

# Send message and receive exactly one message (blocking)
# client.send_message("/emotibit1", [100, 180])
print("Recieving...")
server.serve_forever()