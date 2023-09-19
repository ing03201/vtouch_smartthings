import asyncio
import websockets

connected_clients = set()

async def server(websocket, path):
    # 연결된 클라이언트를 저장
    if(websocket.remote_address not in ["localhost", '127.0.0.1']):
        connected_clients.add(websocket)
    try:
        async for data in websocket:
            # 받은 데이터를 모든 연결된 클라이언트에게 전송
            for client in connected_clients:
                await client.send(data)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        # 연결이 종료되면 클라이언트 목록에서 제거
        connected_clients.remove(websocket)

if __name__ == "__main__":
    start_server = websockets.serve(server, '0.0.0.0', 20000)
    asyncio.get_event_loop().run_until_complete(start_server)
    asyncio.get_event_loop().run_forever()