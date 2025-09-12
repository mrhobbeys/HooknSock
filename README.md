# HooknSock

A lightweight, secure FastAPI service for **receiving webhooks** and **relaying them in real time to WebSocket clients**. Designed for regulatory compliance, minimal server maintenance, and complete automation.

---

## Features

- **Webhook HTTP endpoint**: Receives POST requests, authenticates sender.
- **WebSocket endpoint**: Authenticates clients, streams webhook events in real time.
- **In-memory queue**: No long-term data storage; events are held only until delivered.
- **Authentication**: Simple token-based for both webhook and WebSocket connections.
- **SSL/TLS**: Secured traffic using Let's Encrypt and automated renewal.
- **Automated server maintenance**: OS security updates, SSL renewal, and service restarts are fully automated.
- **Modern Python deployment**: Uses `venv` (or `pipenv`), `uvicorn` with reverse proxy, and `systemd` for robust process management.

---

## Automated Setup

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
- Generate and configure webhook token

**Note**: Make the script executable first: `chmod +x hooknsock.sh`

### Re-running the Setup Script

The setup script is designed to be re-runnable for updates and reconfiguration:

```bash
# Update HooknSock to latest version
sudo ./hooknsock.sh

# Then choose option 1 from the menu
```

Available options when re-running:
1. **Update HooknSock** - Pull latest version and update dependencies
2. **Reconfigure** - Change domain, SSL settings, or other options
3. **Update system** - Update OS packages and security patches
4. **View configuration** - Show current settings and status
5. **Restart services** - Restart HooknSock and related services
6. **View logs** - Access application and system logs
7. **Uninstall** - Remove HooknSock completely

---

## Manual Deployment Guide

## Architecture

1. **FastAPI server** runs on your VPS/cloud (1 vCPU, 1 GB RAM is plenty).
2. **Webhook sender** POSTs events to `/webhook` with an auth token.
3. **Server queues each event in memory** for delivery.
4. **Local client** connects to `/ws` WebSocket endpoint, authenticates, and receives events live.
5. **No data is stored on disk**; messages are ephemeral and dropped after a timeout.

---

## Deployment Guide

### 1. Python Environment

#### Using `venv` (default, simple)

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Or, using `pipenv` (optional, more features)

```bash
pip install pipenv
pipenv install -r requirements.txt
pipenv shell
```

### Development Setup

For development and testing, also install dev dependencies:

```bash
pip install -r requirements-dev.txt
```

Run tests with:
```bash
pytest test_server.py
```

Format code with:
```bash
black server.py client.py test_server.py
```

Lint with:
```bash
flake8 server.py client.py test_server.py
```

### 2. Systemd Service

Create a file `/etc/systemd/system/hooknsock.service`:

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

- Reload and start:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable hooknsock
  sudo systemctl start hooknsock
  ```

### 3. SSL/TLS Automation

- **Let's Encrypt/Certbot**:
  ```bash
  sudo apt install certbot python3-certbot-nginx
  sudo certbot --nginx -d yourdomain.com
  # Or for standalone FastAPI:
  sudo certbot certonly --standalone -d yourdomain.com
  ```

- **Caddy (alternative, even more automated):**
  - Install Caddy, set up reverse proxy, and Caddy auto-manages SSL.

### 4. OS Security Updates

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
```
- This enables automatic security updates and reboots if needed.

### 5. Firewall

```bash
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw allow 8000/tcp  # If exposing FastAPI directly
sudo ufw enable
```

---

## Modern Alternatives to systemd

While **systemd** is still the gold standard for Linux service management (auto-restart, logging, timed jobs), newer tools exist:

- **Caddy**: Web server/reverse proxy that auto-manages SSL and can run apps as services.
- **Supervisor**: Simpler process manager for non-systemd systems.
- **pm2**: Popular in Node.js world, but not for Python.

For most Python apps on Linux, **systemd remains best for reliability and automation**.

---

## Example FastAPI Skeleton

```python
from fastapi import FastAPI, WebSocket, Request, Header
import asyncio

app = FastAPI()
message_queue = asyncio.Queue()
VALID_TOKEN = "your-super-secret-token"  # Use env vars in production!

@app.post("/webhook")
async def webhook(request: Request, x_auth_token: str = Header(None)):
    if x_auth_token != VALID_TOKEN:
        return {"error": "Unauthorized"}
    data = await request.json()
    await message_queue.put(data)
    return {"status": "queued"}

@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: str = None):
    await websocket.accept()
    if token != VALID_TOKEN:
        await websocket.close(code=1008)
        return
    while True:
        data = await message_queue.get()
        await websocket.send_json(data)
```

---

## Roadmap / TODO

- [x] Automated setup scripts
- [ ] Token rotation (manual or automated)
- [ ] Message timeout/drop logic
- [ ] Optional support for multiple clients
- [ ] Dockerfile (optional, for those who want containers)

---

## License

MIT

---

## Contributing

PRs and issues welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
