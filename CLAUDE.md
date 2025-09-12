# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HooknSock is a lightweight FastAPI service for receiving webhooks and relaying them in real-time to WebSocket clients via channels. It supports multi-token authentication with channel routing, uses in-memory queues for ephemeral message storage, and includes security features for production deployment.

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

### Configuration
Create a `.env` file with your configuration:
```bash
# Multi-token with channels (recommended)
WEBHOOK_TOKENS=service1-token:service1,service2-token:service2,service3-token:service3

# Single token (backward compatible)
WEBHOOK_TOKENS=your-secret-token

# Security settings
DISABLE_SYSTEM_INFO=true  # Disables /health endpoint for production

# Optional customization
SITE_TITLE=My Webhook Relay Service
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
- **server.py**: Main FastAPI application with endpoints:
  - `POST /webhook`: Receives webhook events with `x-auth-token` header auth, routes to channels
  - `WebSocket /ws/{channel}`: Channel-specific WebSocket connections
  - `WebSocket /ws`: Legacy WebSocket (auto-routes by token)
  - `GET /`: Minimal status page for browser visitors
  - `GET /health`: Health check endpoint (can be disabled)
- **client.py**: Example WebSocket client for testing
- **test_server.py**: Comprehensive test suite covering auth, routing, and WebSocket integration
- **hooknsock.sh**: Automated setup and management script for Debian/Ubuntu servers
- No database; events are held in separate `asyncio.Queue` instances per channel

### Key Design Patterns
- **Channel Routing**: Multi-token support with channel-based message routing
- **In-memory Queues**: Separate `asyncio.Queue()` per channel for isolated event buffering
- **Token-to-Channel Mapping**: Configurable token→channel assignments via environment variables
- **Security Controls**: Optional system info endpoint disabling for production
- **CORS Support**: Enabled via `CORSMiddleware` for web client compatibility
- **Async/Await**: All endpoints and queue operations use async patterns

### Environment Configuration
- **WEBHOOK_TOKENS**: Multi-token configuration with channel mapping
  - Format: `"token1:channel1,token2:channel2"` (with channels)
  - Format: `"token1,token2,token3"` (all use 'default' channel)
  - Format: `"single-token"` (backward compatible)
- **DISABLE_SYSTEM_INFO**: Set to `"true"` to disable `/health` endpoint for security
- **SITE_TITLE**: Customize the homepage title (optional)
- Load via `python-dotenv` from `.env` file or system environment

## Development Guidelines

### Security Practices
- Never commit tokens or secrets to the repository
- Use `WEBHOOK_TOKENS` environment variable for token configuration
- Set `DISABLE_SYSTEM_INFO=true` in production to hide system information
- Restrict CORS origins in production (currently set to "*" for development)

### Code Conventions
- **Import Order**: Standard library, FastAPI imports, then third-party packages
- **Async Pattern**: Use `async/await` for all I/O operations
- **Error Handling**: Return proper HTTP status codes (401 for auth failures)
- **WebSocket Cleanup**: Close connections with appropriate status codes (`WS_1008_POLICY_VIOLATION` for auth failures)
- **Channel Routing**: Always validate token→channel permissions

### Testing Patterns
- Use `pytest.mark.parametrize` for testing multiple auth scenarios
- Clear message queues before each test with `autouse=True` fixture
- Test both successful and failed authentication paths
- Test channel routing and isolation
- Verify queue behavior (consumption, emptiness after delivery)

## Deployment

### Automated Setup
The `hooknsock.sh` script provides complete automated deployment for Debian/Ubuntu:
```bash
sudo ./hooknsock.sh
```

### Production Configuration
**Recommended `.env` settings for production:**
```bash
WEBHOOK_TOKENS=service1-prod-token:service1,service2-prod-token:service2
DISABLE_SYSTEM_INFO=true
SITE_TITLE=Webhook Relay Service
```

### Manual Deployment Components
- **systemd service**: Use provided `hooknsock.service` template
- **SSL/TLS**: Automated via Let's Encrypt/Certbot
- **Firewall**: UFW configuration for ports 80, 443, and optionally 8000
- **Security Updates**: Unattended upgrades for automated OS patching
- **Security**: Set `DISABLE_SYSTEM_INFO=true` to hide system information

## Usage Examples

### Basic Integration
**Webhook service configuration:**
- **URL**: `https://your-domain.com/webhook`
- **Header**: `x-auth-token: your-service-token`

**Client connection:**
```javascript
// Service-specific channel
const serviceWs = new WebSocket('wss://your-domain.com/ws/service1?token=service1-token');
serviceWs.onmessage = (event) => {
    const webhook = JSON.parse(event.data);
    console.log('Webhook Event:', webhook.type, webhook);
};

// Legacy connection (auto-routes)
const ws = new WebSocket('wss://your-domain.com/ws?token=service1-token');
```

### Multi-Service Setup
```bash
# .env configuration
WEBHOOK_TOKENS=service1-token:service1,service2-token:payments,service3-token:notifications
DISABLE_SYSTEM_INFO=true
```

```javascript
// Different clients for different services
const service1Ws = new WebSocket('wss://domain.com/ws/service1?token=service1-token');
const paymentsWs = new WebSocket('wss://domain.com/ws/payments?token=service2-token');
const notificationsWs = new WebSocket('wss://domain.com/ws/notifications?token=service3-token');
```

## File Structure

```
├── server.py           # Main FastAPI application
├── client.py           # Example WebSocket client
├── test_server.py      # Test suite
├── requirements.txt    # Production dependencies
├── requirements-dev.txt # Development dependencies
├── .env               # Local configuration (create from examples)
├── hooknsock.sh        # Automated setup script
├── hooknsock.service   # systemd service template
└── .github/
    └── copilot-instructions.md  # Development context
```

## API Reference

### Webhook Endpoint
- **URL**: `POST /webhook`
- **Auth**: `x-auth-token` header (must match configured tokens)
- **Body**: JSON payload (any structure)
- **Response**: `{"status": "queued", "channel": "channel_name"}` on success
- **Routing**: Automatically routes to channel based on token configuration

### WebSocket Endpoints
- **Channel-specific**: `WebSocket /ws/{channel}?token=<auth_token>`
  - Only receives messages for the specified channel
  - Token must be authorized for that channel
- **Legacy endpoint**: `WebSocket /ws?token=<auth_token>`
  - Auto-routes to token's assigned channel
  - Backward compatible with single-token setups

### Status Endpoints
- **Homepage**: `GET /`
  - Minimal status page showing service name and online status
  - Safe for public exposure
- **Health Check**: `GET /health` (optional)
  - Returns system information including channels and token count
  - Can be disabled with `DISABLE_SYSTEM_INFO=true` for security
  - When disabled, returns 404 to hide endpoint existence