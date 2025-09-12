import os
import asyncio
from typing import Optional, Dict
from fastapi import FastAPI, WebSocket, Request, Header, status
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Load configuration from environment variables
WEBHOOK_TOKENS = os.environ.get("WEBHOOK_TOKENS", "your-super-secret-token")
SITE_TITLE = os.environ.get("SITE_TITLE", "HooknSock - Webhook to WebSocket Relay")
DISABLE_SYSTEM_INFO = os.environ.get("DISABLE_SYSTEM_INFO", "false").lower() == "true"

# Parse token-to-channel mapping
# Format: "token1:channel1,token2:channel2" or just "single-token" for backward compatibility
def parse_token_config(token_str: str) -> Dict[str, str]:
    tokens = {}
    if ':' in token_str:
        # New format: token:channel pairs
        for pair in token_str.split(','):
            if ':' in pair:
                token, channel = pair.strip().split(':', 1)
                tokens[token] = channel
    else:
        # Backward compatibility: single token or comma-separated tokens
        for token in token_str.split(','):
            token = token.strip()
            tokens[token] = 'default'
    return tokens

TOKEN_CHANNELS = parse_token_config(WEBHOOK_TOKENS)

app = FastAPI()

# Create separate queues for each channel
message_queues: Dict[str, asyncio.Queue] = {}
for channel in set(TOKEN_CHANNELS.values()):
    message_queues[channel] = asyncio.Queue()

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
    if x_auth_token not in TOKEN_CHANNELS:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=status.HTTP_401_UNAUTHORIZED)
    
    channel = TOKEN_CHANNELS[x_auth_token]
    data = await request.json()
    await message_queues[channel].put(data)
    return {"status": "queued", "channel": channel}

@app.websocket("/ws/{channel}")
async def ws_channel_endpoint(websocket: WebSocket, channel: str, token: Optional[str] = None):
    await websocket.accept()
    
    # Verify token is valid and matches the channel
    if token not in TOKEN_CHANNELS or TOKEN_CHANNELS[token] != channel:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    
    # Ensure the channel queue exists
    if channel not in message_queues:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
        
    try:
        while True:
            data = await message_queues[channel].get()
            await websocket.send_json(data)
    except Exception as e:
        await websocket.close()

# Backward compatibility: /ws endpoint routes to default channel
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: Optional[str] = None):
    await websocket.accept()
    
    if token not in TOKEN_CHANNELS:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
        
    # Route to the token's assigned channel
    channel = TOKEN_CHANNELS[token]
    try:
        while True:
            data = await message_queues[channel].get()
            await websocket.send_json(data)
    except Exception as e:
        await websocket.close()

@app.get("/health")
async def health():
    if DISABLE_SYSTEM_INFO:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Not found")
    return {
        "status": "ok", 
        "channels": list(message_queues.keys()),
        "tokens_configured": len(TOKEN_CHANNELS)
    }

@app.get("/", response_class=HTMLResponse)
async def home():
    html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>{SITE_TITLE}</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: monospace; max-width: 600px; margin: 100px auto; padding: 20px; text-align: center; }}
        .status {{ color: #22c55e; font-size: 18px; }}
        h1 {{ margin-bottom: 30px; }}
    </style>
</head>
<body>
    <h1>{SITE_TITLE}</h1>
    <p class="status">● Server Status: Online</p>
</body>
</html>
"""
    return html_content
