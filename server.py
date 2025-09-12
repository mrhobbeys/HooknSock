import os
import asyncio
from typing import Optional
from fastapi import FastAPI, WebSocket, Request, Header, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Load token from environment variable for security
VALID_TOKEN = os.environ.get("WEBHOOK_TOKEN", "your-super-secret-token")

app = FastAPI()
message_queue = asyncio.Queue()

# Allow CORS (customize origins as needed)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For production, set specific origins!
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/webhook")
async def webhook(request: Request, x_auth_token: str = Header(None)):
    if x_auth_token != VALID_TOKEN:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=status.HTTP_401_UNAUTHORIZED)
    data = await request.json()
    await message_queue.put(data)
    return {"status": "queued"}

@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: Optional[str] = None):
    await websocket.accept()
    if token != VALID_TOKEN:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    try:
        while True:
            data = await message_queue.get()
            await websocket.send_json(data)
    except Exception as e:
        await websocket.close()

@app.get("/health")
async def health():
    return {"status": "ok"}
