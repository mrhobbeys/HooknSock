import websockets
import asyncio

async def listen():
    uri = "ws://your-vps-ip-or-domain/ws"
    async with websockets.connect(uri) as ws:
        while True:
            msg = await ws.recv()
            print("Received from webhook:", msg)

asyncio.run(listen())