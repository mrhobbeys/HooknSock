import websockets
import asyncio
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Get configuration from environment
WEBSOCKET_URL = os.environ.get("WEBSOCKET_URL", "ws://localhost:8000/ws")
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "your-token-here")

async def listen():
    uri = f"{WEBSOCKET_URL}?token={AUTH_TOKEN}"
    print(f"Connecting to: {uri}")
    async with websockets.connect(uri) as ws:
        print("Connected to webhook relay")
        while True:
            msg = await ws.recv()
            print("Received from webhook:", msg)

if __name__ == "__main__":
    asyncio.run(listen())