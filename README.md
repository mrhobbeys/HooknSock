# HooknSock

A lightweight, secure FastAPI service for **receiving webhooks** and **relaying them in real time to WebSocket clients via channels**. Designed for regulatory compliance, minimal server maintenance, complete automation, and multi-service webhook routing.

## 🚀 Why HooknSock?

**Are you looking for a way to get webhooks to your locally hosted projects?** Need real-time notifications from external services but don't want to expose your local development environment to the internet?

**HooknSock is the perfect solution!** Here's why [I] developer[s] love it:

✅ **Bridge the Gap** - Your webhooks live in the cloud, your code runs locally - HooknSock connects them seamlessly  
✅ **Multi-Service Support** - Route different webhook sources (payments, notifications, CI/CD) to separate channels  
✅ **Zero Configuration Headaches** - One-command automated setup gets you running in minutes  
✅ **Rock-Solid Security** - Token-based authentication with optional system info lockdown  
✅ **Regulatory Friendly** - No data persistence, ephemeral messages, complete audit trail  
✅ **Minimal Resources** - Runs perfectly on a $5/month VPS (1 vCPU, 1GB RAM)  
✅ **Set-and-Forget** - Automated SSL, security updates, and service management  

**Perfect for:** Developers, agencies, and teams who need reliable webhook→local development workflows without the complexity of VPNs, tunnels, or exposed ports.

---

## Features

- **Multi-Channel Routing**: Route different webhook sources to separate WebSocket channels
- **Multi-Token Authentication**: Support multiple services with isolated channel access
- **Webhook HTTP endpoint**: Receives POST requests, authenticates sender, routes to channels
- **WebSocket endpoints**: Channel-specific and legacy WebSocket connections
- **In-memory queues**: No long-term data storage; events are held only until delivered
- **Security controls**: Optional system information endpoint disabling
- **Minimal public interface**: Clean status page safe for public exposure
- **SSL/TLS**: Secured traffic using Let's Encrypt and automated renewal
- **Automated server maintenance**: OS security updates, SSL renewal, and service restarts are fully automated
- **Modern Python deployment**: Uses `venv`, `uvicorn` with reverse proxy, and `systemd` for robust process management

---

## Quick Start

### 1. Automated Setup (Recommended)

For Debian/Ubuntu servers, use the automated setup script:

```bash
# Copy the project to your server
scp -r . user@your-server:/tmp/hooknsock
ssh user@your-server
cd /tmp/hooknsock
sudo ./hooknsock.sh
```

The script will:
- Install all required system packages
- Set up Python virtual environment
- Configure systemd service
- Set up Nginx reverse proxy
- Configure SSL with Let's Encrypt (if domain provided)
- Set up firewall and automatic updates
- Generate and configure webhook tokens

**Note**: Make the script executable first: `chmod +x hooknsock.sh`

### 2. Configuration

Create a `.env` file with your webhook routing configuration:

```bash
# Multi-service setup with channels
WEBHOOK_TOKENS=service1-token:service1,service2-token:payments,service3-token:notifications

# Security settings (recommended for production)
DISABLE_SYSTEM_INFO=true

# Optional customization
SITE_TITLE=My Webhook Relay Service
```

### 3. Development Setup

```bash
# Set up environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# For development and testing
pip install -r requirements-dev.txt

# Run development server
uvicorn server:app --reload
```

---

## Architecture

### Core Components

- **FastAPI server** runs on your VPS/cloud (1 vCPU, 1 GB RAM is plenty)
- **Webhook sources** POST events to `/webhook` with authentication tokens
- **Channel routing** queues events in separate in-memory channels based on token
- **WebSocket clients** connect to channel-specific endpoints to receive events live
- **No data persistence** on disk; messages are ephemeral and dropped after delivery

### Channel Routing Flow

```
Webhook Source → POST /webhook → Token Validation → Channel Queue → WebSocket Clients
```

1. **Webhook source** POSTs events to `/webhook` with `x-auth-token` header
2. **Server** validates token and determines target channel
3. **Event** is queued in the appropriate channel's in-memory queue
4. **WebSocket clients** connected to that channel receive the event immediately

---

## Configuration

### Token Formats

**Multi-service with channels (recommended):**
```bash
WEBHOOK_TOKENS=service1-token:service1,service2-token:payments,service3-token:notifications
```

**Single token (backward compatible):**
```bash
WEBHOOK_TOKENS=your-secret-token
```

**Comma-separated tokens (all use default channel):**
```bash
WEBHOOK_TOKENS=token1,token2,token3
```

### Generate Tokens Securely

Use the helper CLI to mint high-entropy tokens during provisioning (the install script invokes it automatically, but you can rerun it for rotations):

```bash
python scripts/generate_tokens.py --service service1 --service payments:example.com --env-file /etc/hooknsock/webhook.env --show
```

- Secrets are written to `/etc/hooknsock/webhook.env` with `chmod 600`; track only placeholders in git.
- Copy the plaintext tokens once, store them in a password manager, then update your webhook providers.
- For local development, point `--env-file` at `.env` to refresh tokens without touching production secrets.

### Security Options

```bash
# Disable system info endpoints for production
DISABLE_SYSTEM_INFO=true

# Custom site title
SITE_TITLE=My Webhook Relay Service
```

---

## API Reference

### Webhook Endpoint

- **URL**: `POST /webhook`
- **Authentication**: `x-auth-token` header (must match configured token)
- **Content-Type**: `application/json`
- **Body**: Any valid JSON payload
- **Response**: `{"status": "queued", "channel": "channel_name"}`
- **Routing**: Automatically routes to channel based on token configuration

### WebSocket Endpoints

**Channel-specific (recommended):**
```
WebSocket /ws/{channel}?token=<auth_token>
```
- Only receives messages for the specified channel
- Token must be authorized for that channel

**Legacy endpoint (backward compatible):**
```
WebSocket /ws?token=<auth_token>
```
- Auto-routes to the token's assigned channel
- Works with single-token setups

### Status Endpoints

**Homepage:** `GET /`
- Minimal status page showing service name and online status
- Safe for public exposure

**Health Check:** `GET /health` (optional)
- Returns system information including channels and token count
- Can be disabled with `DISABLE_SYSTEM_INFO=true`
- When disabled, returns 404 to hide endpoint existence

---

## Usage Examples

### Basic Integration

**Configure your webhook service:**
- **URL**: `https://your-domain.com/webhook`
- **Header**: `x-auth-token: your-service-token`
- **Content-Type**: `application/json`

**Connect WebSocket client:**
```javascript
// Service-specific channel
const serviceWs = new WebSocket('wss://your-domain.com/ws/service1?token=service1-token');
serviceWs.onmessage = (event) => {
    const webhook = JSON.parse(event.data);
    console.log('Webhook received:', webhook);
};

// Legacy connection (auto-routes)
const ws = new WebSocket('wss://your-domain.com/ws?token=service1-token');
```

### Multi-Service Setup

**Configuration:**
```bash
WEBHOOK_TOKENS=payments-token:payments,notifications-token:alerts,ci-token:builds
DISABLE_SYSTEM_INFO=true
```

**Different clients for different services:**
```javascript
// Payment webhooks
const paymentsWs = new WebSocket('wss://domain.com/ws/payments?token=payments-token');

// Notification webhooks  
const alertsWs = new WebSocket('wss://domain.com/ws/alerts?token=notifications-token');

// CI/CD webhooks
const buildsWs = new WebSocket('wss://domain.com/ws/builds?token=ci-token');
```

---

## Deployment

### Re-running the Setup Script

The setup script is re-runnable for updates and reconfiguration:

```bash
# Update HooknSock to latest version
sudo ./hooknsock.sh

# Then choose option from the menu
```

Available options when re-running:
1. **Update HooknSock** - Pull latest version and update dependencies
2. **Reconfigure** - Change domain, SSL settings, or other options
3. **Update system** - Update OS packages and security patches
4. **View configuration** - Show current settings and status
5. **Restart services** - Restart HooknSock and related services
6. **View logs** - Access application and system logs
7. **Uninstall** - Remove HooknSock completely

### Manual Deployment (Alternative)

#### Python Environment

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### systemd Service

Create `/etc/systemd/system/hooknsock.service`:

```ini
[Unit]
Description=HooknSock - Webhook-to-WebSocket relay
After=network.target

[Service]
User=youruser
WorkingDirectory=/home/youruser/app
Environment="PATH=/home/youruser/app/venv/bin"
ExecStart=/home/youruser/app/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable hooknsock
sudo systemctl start hooknsock
```

#### SSL/TLS with Let's Encrypt

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

#### Security & Firewall

```bash
# Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades

# Configure firewall
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw enable
```

---

## Development

### Testing

```bash
# Run all tests
pytest test_server.py

# Run with verbose output
pytest -v test_server.py
```

### Code Quality

```bash
# Format code
black server.py client.py test_server.py

# Lint code
flake8 server.py client.py test_server.py

# Run both
black server.py client.py test_server.py && flake8 server.py client.py test_server.py
```

---

## Security Best Practices

### Production Configuration

```bash
# Always disable system info in production
DISABLE_SYSTEM_INFO=true

# Use strong, unique tokens
WEBHOOK_TOKENS=prod-service1-a8f9d2e:service1,prod-service2-x7k3m9q:service2

# Custom title (optional)
SITE_TITLE=Webhook Relay Service
```

### Token Security

- Use strong, randomly generated tokens (32+ characters)
- Use different tokens for each service
- Rotate tokens regularly and restart the service after updating `/etc/hooknsock/webhook.env`
- Generate secrets with `python scripts/generate_tokens.py` so they land in `/etc/hooknsock/webhook.env` with `chmod 600`
- Never commit production tokens; store plaintext in a password manager or dedicated secret store

### Network Security

- Always use HTTPS/WSS in production
- Configure firewall to only allow necessary ports
- Use Let's Encrypt for automated SSL certificate management
- Consider IP allowlisting for webhook sources if possible

---

## Performance & Scaling

### Resource Requirements

- **Minimum**: 1 vCPU, 1GB RAM
- **Handles**: 1000+ webhooks/minute easily
- **Memory usage**: ~100MB for multi-channel setup
- **Network**: Minimal bandwidth requirements

### Scaling Considerations

- Each channel has its own isolated queue
- No database dependencies
- Stateless design allows horizontal scaling
- Consider load balancer for high-availability setups

---

## Troubleshooting

### Common Issues

**Webhook returning 401 Unauthorized:**
- Check `x-auth-token` header matches configured token
- Verify token is properly configured in `.env`

**WebSocket connection failing:**
- Verify token in query parameter
- Check token has access to the specified channel
- Ensure WebSocket URL uses `wss://` for HTTPS sites

**Health endpoint returns 404:**
- This is expected when `DISABLE_SYSTEM_INFO=true`
- Disable the setting to re-enable the endpoint

### Logging

```bash
# View service logs
sudo journalctl -u hooknsock -f

# View nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## Roadmap

- [x] Multi-token channel routing
- [x] Security controls for production
- [x] Automated setup scripts
- [ ] Token rotation (manual or automated)
- [ ] Message timeout/drop logic
- [ ] Optional support for multiple clients per channel
- [ ] Dockerfile (optional, for those who want containers)
- [ ] Metrics and monitoring endpoints
- [ ] Rate limiting per token/channel

---

## License

MIT

---

## Contributing

PRs and issues welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For service-specific integration examples, create a local `local_only.md` file (automatically ignored by git) for your development reference.