#!/bin/bash

# HooknSock - Webhook-to-WebSocket Relay Setup Script
# For Debian/Ubuntu servers
# This script handles complete automated setup, updates, and configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}=======================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}=======================================${NC}"
}

# Configuration variables
SCRIPT_VERSION="1.0.0"
PROJECT_NAME="HooknSock"
PROJECT_REPO="https://github.com/yourusername/hooknsock.git"  # Update this with actual repo
DEFAULT_APP_DIR="/home/$USER/hooknsock"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    log_error "sudo is required but not installed. Please install sudo first."
    exit 1
fi

log_info "Starting Webhook-to-WebSocket Relay setup..."

# Update system
log_info "Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install required packages
log_info "Installing required packages..."
sudo apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx ufw unattended-upgrades fail2ban

# Install websockets for Python (if not in requirements)
# Note: This will be handled by requirements.txt

# Create application directory
read -p "Enter the installation directory (default: /home/$USER/webhook-relay): " APP_DIR
APP_DIR=${APP_DIR:-/home/$USER/webhook-relay}

if [[ -d "$APP_DIR" ]]; then
    log_warning "Directory $APP_DIR already exists. Contents will be overwritten."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log_info "Creating application directory: $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown $USER:$USER "$APP_DIR"

# Copy application files (assuming script is run from project root)
log_info "Copying application files..."
cp -r . "$APP_DIR/"
cd "$APP_DIR"

# Setup Python virtual environment
log_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
log_info "Installing Python dependencies..."
pip install -r requirements.txt

# Function to redact token for logging
redact_token() {
    local token="$1"
    if [ ${#token} -gt 3 ]; then
        echo "${token:0:1}***${token: -1}"
    else
        echo "***"
    fi
}

# Generate random webhook token
WEBHOOK_TOKEN=$(openssl rand -hex 32)
REDACTED_TOKEN=$(redact_token "$WEBHOOK_TOKEN")
log_info "Generated webhook token: $REDACTED_TOKEN"

# Ask about multi-service setup
read -p "Do you want to set up multiple services/channels? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Multi-service setup selected"
    read -p "Enter service name for primary token (e.g., 'webhook', 'service1'): " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-webhook}
    
    read -p "Enter allowed domain for webhooks (e.g., 'example.com' or '*' for any): " WEBHOOK_DOMAIN
    WEBHOOK_DOMAIN=${WEBHOOK_DOMAIN:-"*"}
    
    if [[ "$WEBHOOK_DOMAIN" == "*" ]]; then
        log_warning "WARNING: Using wildcard (*) allows webhooks from ANY domain - this may be insecure!"
    fi
    
    WEBHOOK_TOKENS="$WEBHOOK_TOKEN:$SERVICE_NAME:$WEBHOOK_DOMAIN"
else
    log_info "Single service setup (backward compatible)"
    WEBHOOK_TOKENS="$WEBHOOK_TOKEN:default:*"
    log_warning "Using wildcard domain (*) for single service setup"
fi

# Create .env file with new format
cat > .env << EOF
WEBHOOK_TOKENS=$WEBHOOK_TOKENS
DISABLE_SYSTEM_INFO=true
SITE_TITLE=HooknSock - Webhook Relay
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60
MAX_PAYLOAD_SIZE=1048576
EOF

log_info "Created .env file with webhook configuration"

# Ask for domain/IP
read -p "Do you have a domain name for SSL? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your domain name: " DOMAIN
    USE_SSL=true
    USE_NGINX=true
    log_info "SSL will be configured for domain: $DOMAIN"
else
    log_warning "SSL requires a domain name. The application will run without SSL."
    log_warning "You can configure SSL later by running: sudo certbot --nginx -d yourdomain.com"
    USE_SSL=false
    read -p "Do you want to set up Nginx reverse proxy anyway? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_NGINX=true
    else
        USE_NGINX=false
    fi
fi

# Configure systemd service
log_info "Configuring systemd service..."

SERVICE_FILE="/etc/systemd/system/webhookrelay.service"
if [[ "$USE_NGINX" == "true" ]]; then
    EXEC_START="$APP_DIR/venv/bin/uvicorn server:app --host 127.0.0.1 --port 8000"
else
    EXEC_START="$APP_DIR/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8000"
fi

sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Webhook-to-WebSocket relay FastAPI app
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$EXEC_START
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable webhookrelay

# Configure Nginx (if requested)
if [[ "$USE_NGINX" == "true" ]]; then
    if [[ "$USE_SSL" == "true" ]]; then
        log_info "Configuring Nginx reverse proxy with SSL..."

        NGINX_CONF="/etc/nginx/sites-available/webhookrelay"
        sudo tee $NGINX_CONF > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

        sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
        sudo nginx -t
        sudo systemctl reload nginx

        # Get SSL certificate
        log_info "Obtaining SSL certificate from Let's Encrypt..."
        sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

        log_success "SSL configured successfully!"
    else
        # Configure Nginx without SSL
        log_info "Configuring Nginx reverse proxy (HTTP only)..."

        NGINX_CONF="/etc/nginx/sites-available/webhookrelay"
        sudo tee $NGINX_CONF > /dev/null << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

        sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
        sudo nginx -t
        sudo systemctl reload nginx
    fi

    # Configure firewall for nginx
    sudo ufw allow 'Nginx Full'
else
    # No nginx, configure firewall for direct access
    sudo ufw allow 8000/tcp
fi

# Configure firewall and SSH security
log_info "Configuring firewall and SSH security..."
sudo ufw --force enable
sudo ufw allow ssh  # Ensure SSH access is not blocked

# Check SSH password authentication
log_info "Checking SSH configuration..."
if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
    log_warning "SSH password authentication is enabled. For security, consider switching to key-based authentication."
    log_warning "To disable passwords: sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart ssh"
fi

# Configure fail2ban
log_info "Configuring fail2ban for SSH protection..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Configure unattended upgrades
log_info "Configuring automatic security updates..."
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailOnlyOnError "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Start the service
log_info "Starting the webhook relay service..."
sudo systemctl start webhookrelay

# Verify service is running
sleep 2
if sudo systemctl is-active --quiet webhookrelay; then
    log_success "Webhook relay service is running!"
else
    log_error "Failed to start webhook relay service"
    exit 1
fi

# Display setup summary
log_success "Setup completed successfully!"
echo
echo "========================================"
echo "Setup Summary:"
echo "========================================"
echo "Application Directory: $APP_DIR"
echo "Webhook Token: $REDACTED_TOKEN"
echo "Service Setup: $(echo $WEBHOOK_TOKENS | cut -d':' -f2)"
echo "Domain Restriction: $(echo $WEBHOOK_TOKENS | cut -d':' -f3)"
if [[ "$USE_SSL" == "true" ]]; then
    echo "Domain: $DOMAIN"
    echo "Webhook URL: https://$DOMAIN/webhook"
    echo "WebSocket URL: wss://$DOMAIN/ws"
elif [[ "$USE_NGINX" == "true" ]]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Server IP: $SERVER_IP"
    echo "Webhook URL: http://$SERVER_IP/webhook"
    echo "WebSocket URL: ws://$SERVER_IP/ws"
else
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Server IP: $SERVER_IP"
    echo "Webhook URL: http://$SERVER_IP:8000/webhook"
    echo "WebSocket URL: ws://$SERVER_IP:8000/ws"
fi
echo "Service Status: sudo systemctl status webhookrelay"
echo "Logs: sudo journalctl -u webhookrelay -f"
echo "========================================"
echo
log_warning "IMPORTANT: Save the webhook token securely!"
log_warning "Update your webhook sender to use the token in the x-auth-token header"
if [[ "$USE_SSL" == "true" ]]; then
    log_warning "Update your WebSocket client to include ?token=$REDACTED_TOKEN in the URL"
    if [[ $WEBHOOK_TOKENS == *":"* ]]; then
        SERVICE=$(echo $WEBHOOK_TOKENS | cut -d':' -f2)
        log_info "Channel-specific WebSocket: wss://$DOMAIN/ws/$SERVICE?token=YOUR_TOKEN"
        log_info "Legacy WebSocket (auto-route): wss://$DOMAIN/ws?token=YOUR_TOKEN"
    fi
else
    log_warning "Update your WebSocket client to include ?token=$REDACTED_TOKEN in the URL"
    if [[ $WEBHOOK_TOKENS == *":"* ]]; then
        SERVICE=$(echo $WEBHOOK_TOKENS | cut -d':' -f2)
        if [[ "$USE_NGINX" == "true" ]]; then
            log_info "Channel-specific WebSocket: ws://$SERVER_IP/ws/$SERVICE?token=YOUR_TOKEN"
            log_info "Legacy WebSocket (auto-route): ws://$SERVER_IP/ws?token=YOUR_TOKEN"
        else
            log_info "Channel-specific WebSocket: ws://$SERVER_IP:8000/ws/$SERVICE?token=YOUR_TOKEN"
            log_info "Legacy WebSocket (auto-route): ws://$SERVER_IP:8000/ws?token=YOUR_TOKEN"
        fi
    fi
fi
echo
log_info "Setup complete! Your webhook-to-websocket relay is ready to use."
