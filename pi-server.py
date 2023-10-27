import asyncio
import websockets
from websocket import create_connection, WebSocketConnectionClosedException
client = create_connection("ws://192.168.137.100:20000")
def clientReConnect():
    global client
    client = create_connection("ws://192.168.137.100:20000")

async def server(connected_client, path):
    while True:
        try:
            data = client.recv()
        # 데이터를 다른 서버로 전달
            if data:
                await connected_client.send(data)
        except websockets.exceptions.ConnectionClosed:
            print("ConnectionClosed from client")
            pass
        except WebSocketConnectionClosedException:
            print("ConnectionClosed from vps")
            clientReConnect()

if __name__ == "__main__":
    global client
    start_server = websockets.serve(server, '0.0.0.0', 20000)
    client = create_connection("ws://192.168.137.100:20000")
    asyncio.get_event_loop().run_until_complete(start_server)
    asyncio.get_event_loop().run_forever()