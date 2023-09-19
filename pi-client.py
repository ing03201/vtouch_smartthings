import asyncio
import websockets
import json

async def client():
    async with websockets.connect('ws://192.168.137.100:20000') as websocket:
        while True:
            try:
                data = await websocket.recv()
                # 데이터를 다른 서버로 전달
                async with websockets.connect('ws://localhost:20000') as server_websocket:
                    await server_websocket.send(data)
            except websockets.exceptions.ConnectionClosed:
                print("Connection closed. Reconnecting...")
                await asyncio.sleep(1)  # 재연결 대기 시간 설정

if __name__ == "__main__":
    asyncio.get_event_loop().run_until_complete(client())
