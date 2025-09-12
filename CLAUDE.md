# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HooknSock is a lightweight FastAPI service for receiving webhooks and relaying them in real-time to WebSocket clients. It uses an in-memory queue for ephemeral message storage with token-based authentication.

## Common Development Commands

### Environment Setup
```bash
# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# For development (testing, formatting, linting)
pip install -r requirements-dev.txt
```

### Development Server
```bash
# Run development server with auto-reload
uvicorn server:app --reload

# Or for production-like testing
uvicorn server:app --host 0.0.0.0 --port 8000
```

### Testing
```bash
# Run all tests
pytest test_server.py

# Run specific test
pytest test_server.py::test_webhook_auth

# Run with verbose output
pytest -v test_server.py
```

### Code Quality
```bash
# Format code
black server.py client.py test_server.py

# Lint code
flake8 server.py client.py test_server.py

# Run both formatting and linting
black server.py client.py test_server.py && flake8 server.py client.py test_server.py
```

## Architecture

### Core Components
- **server.py**: Main FastAPI application with three endpoints:
  - `POST /webhook`: Receives webhook events with `x-auth-token` header auth
  - `WebSocket /ws`: Streams events to clients with `token` query param auth
  - `GET /health`: Health check endpoint
- **client.py**: Example WebSocket client for testing
- **test_server.py**: Comprehensive test suite covering auth, queue behavior, and WebSocket integration

### Key Design Patterns
- **In-memory Queue**: Uses `asyncio.Queue()` for thread-safe event buffering - no persistence
- **Token Authentication**: Single token for both webhook and WebSocket auth via environment variable
- **CORS Support**: Enabled via `CORSMiddleware` for web client compatibility
- **Async/Await**: All endpoints and queue operations use async patterns

### Environment Configuration
- **WEBHOOK_TOKEN**: Primary authentication token (defaults to "your-super-secret-token")
- Load via `python-dotenv` from `.env` file or system environment

## Development Guidelines

### Security Practices
- Never commit tokens or secrets to the repository
- Use `os.environ.get("WEBHOOK_TOKEN", "default")` pattern for token access
- Restrict CORS origins in production (currently set to "*" for development)

### Code Conventions
- **Import Order**: Standard library, FastAPI imports, then third-party packages
- **Async Pattern**: Use `async/await` for all I/O operations
- **Error Handling**: Return proper HTTP status codes (401 for auth failures)
- **WebSocket Cleanup**: Close connections with appropriate status codes (`WS_1008_POLICY_VIOLATION` for auth failures)

### Testing Patterns
- Use `pytest.mark.parametrize` for testing multiple auth scenarios
- Clear the message queue before each test with `autouse=True` fixture
- Test both successful and failed authentication paths
- Verify queue behavior (consumption, emptiness after delivery)

## Deployment

### Automated Setup
The `hooknsock.sh` script provides complete automated deployment for Debian/Ubuntu:
```bash
sudo ./hooknsock.sh
```

### Manual Deployment Components
- **systemd service**: Use provided `hooknsock.service` template
- **SSL/TLS**: Automated via Let's Encrypt/Certbot
- **Firewall**: UFW configuration for ports 80, 443, and optionally 8000
- **Security Updates**: Unattended upgrades for automated OS patching

## File Structure

```
├── server.py           # Main FastAPI application
├── client.py           # Example WebSocket client
├── test_server.py      # Test suite
├── requirements.txt    # Production dependencies
├── requirements-dev.txt # Development dependencies
├── hooknsock.sh        # Automated setup script
├── hooknsock.service   # systemd service template
├── setup.sh           # Alternative setup script
└── .github/
    └── copilot-instructions.md  # Additional development context
```

## API Reference

### Webhook Endpoint
- **URL**: `POST /webhook`
- **Auth**: `x-auth-token` header
- **Body**: JSON payload (any structure)
- **Response**: `{"status": "queued"}` on success

### WebSocket Endpoint  
- **URL**: `WebSocket /ws?token=<auth_token>`
- **Auth**: `token` query parameter
- **Protocol**: Streams JSON messages as received from webhooks

### Health Check
- **URL**: `GET /health`
- **Response**: `{"status": "ok"}`