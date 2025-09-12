# HooknSock Copilot Instructions

## Project Overview
HooknSock is a FastAPI-based service that relays webhooks to WebSocket clients in real-time via channels. It supports multi-token authentication with channel routing, uses separate in-memory queues for each channel, and includes security features for production deployment.

## Architecture
- **server.py**: Main FastAPI app with webhook routing and WebSocket channel endpoints
  - `POST /webhook`: Receives events, routes to channels based on token
  - `WebSocket /ws/{channel}`: Channel-specific WebSocket connections  
  - `WebSocket /ws`: Legacy endpoint (auto-routes by token)
  - `GET /`: Minimal public status page
  - `GET /health`: System info endpoint (can be disabled)
- **client.py**: Example WebSocket client for testing
- **test_server.py**: Comprehensive test suite covering auth, routing, and channel isolation
- **hooknsock.sh**: Automated setup and management script for Debian/Ubuntu servers
- **Multi-channel architecture**: Separate `asyncio.Queue` per channel for isolated event buffering

## Key Features
- **Multi-Token Channel Routing**: Different tokens route to different WebSocket channels
- **Backward Compatibility**: Single-token setups still work via legacy endpoints
- **Security Controls**: Optional system info endpoint disabling for production
- **Minimal Public Interface**: Clean homepage with just service name and status

## Configuration Patterns
- **Multi-token with channels**: `WEBHOOK_TOKENS=service1-token:service1,service2-token:service2`
- **Single token (legacy)**: `WEBHOOK_TOKENS=your-secret-token`
- **Security lockdown**: `DISABLE_SYSTEM_INFO=true` (disables /health endpoint)
- **Customization**: `SITE_TITLE=My Webhook Relay Service`

## Authentication Flow
- **Webhook auth**: `x-auth-token` header must match configured token
- **Channel routing**: Token determines which channel receives the message
- **WebSocket auth**: `token` query param must match and be authorized for channel
- **Token validation**: Tokens validated against `TOKEN_CHANNELS` mapping

## Development Workflow
- **Environment**: `python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt`
- **Configuration**: Create `.env` file with token and security settings
- **Run Dev**: `uvicorn server:app --reload`
- **Format/Lint**: `black server.py client.py test_server.py && flake8 server.py client.py test_server.py`
- **Test**: `pytest test_server.py -v` (includes channel routing and security tests)

## Deployment
- **Automated Setup**: Run `./hooknsock.sh` on Debian/Ubuntu servers for complete installation
- **Production Security**: Set `DISABLE_SYSTEM_INFO=true` to hide system information
- **SSL**: Automate with Certbot for domains; setup script handles Let's Encrypt
- **systemd**: Use provided service template with proper user/directory configuration

## Code Conventions
- **Imports**: Standard library first, then FastAPI, then third-party
- **Async**: Use `async/await` for all endpoints and queue operations  
- **Channel Management**: Validate token→channel permissions before routing
- **Error Handling**: Return proper HTTP codes; close WebSockets with appropriate status codes
- **Security**: Never expose system info when `DISABLE_SYSTEM_INFO=true`

## Testing Patterns
- **Multi-token testing**: Test different tokens routing to correct channels
- **Channel isolation**: Verify messages don't leak between channels
- **Security testing**: Test system info endpoint disabling
- **Backward compatibility**: Ensure legacy single-token setups work
- **Queue management**: Clear all channel queues in test fixtures

## Production Considerations
- **Token Security**: Use strong, unique tokens per service/channel
- **System Info**: Always set `DISABLE_SYSTEM_INFO=true` for public deployments
- **Channel Naming**: Use descriptive channel names (service1, payments, notifications, etc.)
- **Monitoring**: Use the /health endpoint (when enabled) for internal monitoring only
- **Performance**: Each channel has its own queue for optimal isolation and performance