import os
import asyncio
import time
import logging
from collections import defaultdict
from typing import Optional, Dict, List
from fastapi import FastAPI, WebSocket, Request, Header, status, HTTPException
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()


# Function to redact token for logging
def redact_token(token: str) -> str:
    """Redact token for secure logging"""
    if not token or len(token) < 3:
        return "***"
    return f"{token[:1]}***{token[-1]}"


# Load configuration from environment variables
WEBHOOK_TOKENS = os.environ.get("WEBHOOK_TOKENS", "your-super-secret-token")
SITE_TITLE = os.environ.get("SITE_TITLE", "HooknSock - Webhook to WebSocket Relay")
DISABLE_SYSTEM_INFO = os.environ.get("DISABLE_SYSTEM_INFO", "false").lower() == "true"


# Parse token-to-channel-domain mapping
# Format: "token1:channel1:domain1.com,token2:channel2:*" or legacy formats
def parse_token_config(token_str: str) -> Dict[str, Dict[str, str]]:
    tokens = {}
    if ":" in token_str:
        # New format: token:channel:domain or token:channel pairs
        for pair in token_str.split(","):
            parts = pair.strip().split(":", 2)
            if len(parts) == 3:  # token:channel:domain
                token, channel, domain = parts
                tokens[token] = {"channel": channel, "domain": domain}
            elif len(parts) == 2:  # token:channel (no domain restriction)
                token, channel = parts
                tokens[token] = {"channel": channel, "domain": "*"}
    else:
        # Backward compatibility: single token or comma-separated tokens
        for token in token_str.split(","):
            token = token.strip()
            tokens[token] = {"channel": "default", "domain": "*"}
    return tokens


# Rate limiting storage
rate_limit_storage = defaultdict(list)
RATE_LIMIT_REQUESTS = int(os.environ.get("RATE_LIMIT_REQUESTS", "100"))
RATE_LIMIT_WINDOW = int(os.environ.get("RATE_LIMIT_WINDOW", "60"))  # seconds
MAX_PAYLOAD_SIZE = int(os.environ.get("MAX_PAYLOAD_SIZE", "1048576"))  # 1MB default


def check_rate_limit(token: str) -> bool:
    """Check if token has exceeded rate limit"""
    now = time.time()
    # Clean old entries
    rate_limit_storage[token] = [
        t for t in rate_limit_storage[token] if now - t < RATE_LIMIT_WINDOW
    ]
    # Check limit
    if len(rate_limit_storage[token]) >= RATE_LIMIT_REQUESTS:
        return False
    # Record this request
    rate_limit_storage[token].append(now)
    return True


TOKEN_CONFIG = parse_token_config(WEBHOOK_TOKENS)

# Extract allowed origins from token config
allowed_origins = set()
for config in TOKEN_CONFIG.values():
    domain = config["domain"]
    if domain == "*":
        allowed_origins.add("*")
    else:
        allowed_origins.add(f"https://{domain}")
        allowed_origins.add(f"http://{domain}")  # Support both HTTP and HTTPS

# If any token allows *, use wildcard (but warn in logs)
if "*" in allowed_origins:
    cors_origins = ["*"]
    print(
        "⚠️  WARNING: CORS configured for ALL origins (*) - this may be insecure for production!"
    )
else:
    cors_origins = list(allowed_origins)

app = FastAPI()

# Create separate queues for each channel
message_queues: Dict[str, asyncio.Queue] = {}
for config in TOKEN_CONFIG.values():
    channel = config["channel"]
    if channel not in message_queues:
        message_queues[channel] = asyncio.Queue()

# CORS configuration based on token domains
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


# Security middleware for additional headers
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)

    # Add security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

    # Only add HSTS if we're using HTTPS
    if request.url.scheme == "https":
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )

    return response


@app.post("/webhook")
async def webhook(request: Request, x_auth_token: str = Header(None)):
    client_ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "unknown")

    # Check authentication
    if x_auth_token not in TOKEN_CONFIG:
        logger.warning(
            f"Unauthorized webhook attempt from {client_ip} with token: {redact_token(x_auth_token or 'none')}"
        )
        return JSONResponse(
            content={"error": "Unauthorized"}, status_code=status.HTTP_401_UNAUTHORIZED
        )

    # Check rate limiting
    if not check_rate_limit(x_auth_token):
        logger.warning(
            f"Rate limit exceeded for token {redact_token(x_auth_token)} from {client_ip}"
        )
        return JSONResponse(
            content={"error": "Rate limit exceeded"},
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    # Check payload size
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_PAYLOAD_SIZE:
        logger.warning(f"Payload too large from {client_ip}: {content_length} bytes")
        return JSONResponse(
            content={"error": "Payload too large"},
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
        )

    channel = TOKEN_CONFIG[x_auth_token]["channel"]
    try:
        data = await request.json()
        logger.info(
            f"Webhook received from {client_ip} for channel '{channel}' (token: {redact_token(x_auth_token)})"
        )
    except Exception as e:
        logger.warning(f"Invalid JSON from {client_ip}: {str(e)}")
        return JSONResponse(
            content={"error": "Invalid JSON"}, status_code=status.HTTP_400_BAD_REQUEST
        )

    await message_queues[channel].put(data)
    return {"status": "queued", "channel": channel}


@app.websocket("/ws/{channel}")
async def ws_channel_endpoint(
    websocket: WebSocket, channel: str, token: Optional[str] = None
):
    client_ip = websocket.client.host if websocket.client else "unknown"
    origin = websocket.headers.get("origin", "unknown")

    # Validate origin if domain restrictions are in place
    if origin and not any(
        origin.startswith(f"https://{domain}") or origin.startswith(f"http://{domain}")
        for config in TOKEN_CONFIG.values()
        for domain in [config["domain"]]
        if config["domain"] != "*"
    ):
        # If any token has domain restrictions, validate origin
        has_domain_restrictions = any(
            config["domain"] != "*" for config in TOKEN_CONFIG.values()
        )
        if has_domain_restrictions:
            logger.warning(
                f"WebSocket origin validation failed from {client_ip} (origin: {origin})"
            )
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await websocket.accept()

    # Verify token is valid and matches the channel
    if token not in TOKEN_CONFIG or TOKEN_CONFIG[token]["channel"] != channel:
        logger.warning(
            f"WebSocket auth failed from {client_ip} for channel '{channel}' (token: {redact_token(token or 'none')})"
        )
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    logger.info(
        f"WebSocket connected from {client_ip} to channel '{channel}' (token: {redact_token(token)})"
    )

    # Ensure the channel queue exists
    if channel not in message_queues:
        logger.error(
            f"Channel '{channel}' does not exist for WebSocket connection from {client_ip}"
        )
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    try:
        while True:
            data = await message_queues[channel].get()
            await websocket.send_json(data)
    except Exception as e:
        logger.info(f"WebSocket disconnected from {client_ip} for channel '{channel}'")
        await websocket.close()


# Backward compatibility: /ws endpoint routes to default channel
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: Optional[str] = None):
    client_ip = websocket.client.host if websocket.client else "unknown"
    origin = websocket.headers.get("origin", "unknown")

    # Validate origin if domain restrictions are in place
    if origin and not any(
        origin.startswith(f"https://{domain}") or origin.startswith(f"http://{domain}")
        for config in TOKEN_CONFIG.values()
        for domain in [config["domain"]]
        if config["domain"] != "*"
    ):
        # If any token has domain restrictions, validate origin
        has_domain_restrictions = any(
            config["domain"] != "*" for config in TOKEN_CONFIG.values()
        )
        if has_domain_restrictions:
            logger.warning(
                f"WebSocket origin validation failed from {client_ip} (origin: {origin})"
            )
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await websocket.accept()

    if token not in TOKEN_CONFIG:
        logger.warning(
            f"WebSocket auth failed from {client_ip} (token: {redact_token(token or 'none')})"
        )
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    # Route to the token's assigned channel
    channel = TOKEN_CONFIG[token]["channel"]
    logger.info(
        f"WebSocket connected from {client_ip} to channel '{channel}' (legacy endpoint, token: {redact_token(token)})"
    )

    try:
        while True:
            data = await message_queues[channel].get()
            await websocket.send_json(data)
    except Exception as e:
        logger.info(
            f"WebSocket disconnected from {client_ip} for channel '{channel}' (legacy endpoint)"
        )
        await websocket.close()


@app.get("/health")
async def health():
    if DISABLE_SYSTEM_INFO:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="Not found")
    return {
        "status": "ok",
        "channels": list(message_queues.keys()),
        "tokens_configured": len(TOKEN_CONFIG),
        "rate_limiting": f"{RATE_LIMIT_REQUESTS} requests/{RATE_LIMIT_WINDOW}s",
        "max_payload_size": f"{MAX_PAYLOAD_SIZE} bytes",
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
