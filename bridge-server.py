import asyncio
import websockets
from queue import Queue

ws_queue = Queue()


async def handle_websocket(websocket, path):
    
    # This function will be called whenever a new WebSocket connection is established
    print(f"New WebSocket connection from {websocket.remote_address}")
    
    # Send a welcome message to the client
    await websocket.send("Welcome to the WebSocket server!")
    
    # Keep the connection open and handle incoming messages
    async for message in websocket:
        print(f"Received message from {websocket.remote_address}: {message}")
        
        # Echo the message back to the client
        await websocket.send(f"You said: {message}")


async def main():
    # Start the WebSocket server on port 8765
    async with websockets.serve(server, "0.0.0.0", 20000):
        print("WebSocket server started")
        # Keep the event loop running forever
        await asyncio.Future()

async def forward_messages():
    async with websockets.connect('ws://192.168.137.100:20000') as source:
        async with websockets.connect('ws://localhost:3000') as destination:
            while True:
                message = await source.recv()
                await destination.send(message)

if __name__ == "__main__":
    asyncio.get_event_loop().run_until_complete(main())
