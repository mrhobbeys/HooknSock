# HooknSock Copilot Instructions

## Project Overview
HooknSock is a FastAPI-based service that relays webhooks to WebSocket clients in real-time. It uses an in-memory queue for ephemeral message storage, with token-based authentication for both webhook and WebSocket endpoints.

## Architecture
- **server.py**: Main FastAPI app with `/webhook` POST endpoint (receives events), `/ws` WebSocket endpoint (streams events), and `/health` healthcheck.
- **client.py**: Example WebSocket client for receiving events.
- **test_server.py**: Pytest-based tests covering auth, queue behavior, and WS integration.
- **hooknsock.sh**: Automated setup and management script for Debian/Ubuntu servers.
- No database; events are held in `asyncio.Queue` until consumed or timed out.

## Key Patterns
- **Authentication**: Use `WEBHOOK_TOKEN` env var. Webhook auth via `x-auth-token` header; WS auth via `token` query param.
- **CORS**: Enabled with `CORSMiddleware` for web clients; restrict origins in production.
- **Async Queue**: `message_queue = asyncio.Queue()` for thread-safe event buffering.
- **Error Handling**: WS closes on auth failure (`WS_1008_POLICY_VIOLATION`); webhook returns 401 JSON.
- **Secrets**: Never commit tokens; use `os.environ.get("WEBHOOK_TOKEN", "default")`.

## Development Workflow
- **Environment**: `python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt`
- **Run Dev**: `uvicorn server:app --reload`
- **Format/Lint**: `black server.py client.py test_server.py && flake8 server.py client.py test_server.py`
- **Test**: `pytest test_server.py` (includes async WS tests with TestClient)

## Deployment
- **Automated Setup**: Run `./hooknsock.sh` on Debian/Ubuntu servers for complete automated installation
- **Manual Setup**: Use `systemd` with `uvicorn` workers; systemd service in `hooknsock.service`
- **SSL**: Automate with Certbot for domains; setup script handles Let's Encrypt
- **Security**: `unattended-upgrades` for OS updates; UFW firewall configured by setup script

## Conventions
- **Imports**: Standard library first, then FastAPI, then third-party.
- **Async**: Use `async/await` for all endpoints and queue operations.
- **Responses**: JSON for webhooks; raw JSON over WS.
- **Testing**: Parametrize auth tests; use `pytest.mark.asyncio` for WS tests; clear queue in fixtures.
