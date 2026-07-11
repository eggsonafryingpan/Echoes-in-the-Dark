from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

dispatcher = Dispatcher()

values = {}

def handler(address, *args):

    values[address] = args[0]

    if (len(values) == 3):
        print(values)

dispatcher.set_default_handler(handler)



server = BlockingOSCUDPServer(("127.0.0.1", 12345), dispatcher)
print("Recieving...")
server.serve_forever()