from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

dispatcher = Dispatcher()

clientIMU = SimpleUDPClient("127.0.0.1", 12346)
clientElevated = SimpleUDPClient("127.0.0.1", 12347)


def handler(address, *args):
    if "EmotiBit" not in address:
        return
    
    print("Fowarding...", address, args) 
    clientIMU.send_message(address,list(args))
    clientElevated.send_message(address,list(args))


dispatcher.set_default_handler(handler)

server = BlockingOSCUDPServer(("0.0.0.0", 12345), dispatcher)
server.serve_forever()