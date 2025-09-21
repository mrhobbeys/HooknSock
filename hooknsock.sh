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
PROJECT_REPO="https://github.com/mrhobbeys/HooknSock.git"
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
    if [ ${#token} -gt 6 ]; then
        echo "${token:0:3}***${token: -3}"
    else
        echo "***"
    fi
}

# Prepare secure secret storage
SECRETS_DIR="/etc/hooknsock"
TOKEN_ENV="$SECRETS_DIR/webhook.env"
sudo mkdir -p "$SECRETS_DIR"
sudo chown root:root "$SECRETS_DIR"
sudo chmod 750 "$SECRETS_DIR"

generate_tokens_via_helper() {
    local channels_input
    read -p "Enter comma-separated channel names (default: default): " channels_input
    channels_input=${channels_input:-default}

    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels_input"
    declare -a SERVICE_ARGS=()
    for raw_channel in "${CHANNEL_ARRAY[@]}"; do
        local channel="$(echo "$raw_channel" | xargs)"
        if [[ -z "$channel" ]]; then
            continue
        fi
        local domain
        read -p "Restrict domain for channel '$channel' (default: *): " domain
        domain=${domain:-*}
        if [[ "$domain" == "*" ]]; then
            log_warning "Channel '$channel' accepts webhooks from ANY domain. Consider narrowing this in production."
        fi
        SERVICE_ARGS+=("--service" "${channel}:${domain}")
    done

    if [[ ${#SERVICE_ARGS[@]} -eq 0 ]]; then
        log_error "No valid channel names provided; aborting token generation."
        exit 1
    fi

    log_info "Generating tokens with scripts/generate_tokens.py (values shown once)..."
    sudo python3 scripts/generate_tokens.py "${SERVICE_ARGS[@]}" --env-file "$TOKEN_ENV" --show
    WEBHOOK_TOKENS=$(sudo awk -F'=' '/^WEBHOOK_TOKENS=/{print $2}' "$TOKEN_ENV")
}

if [[ -f "$TOKEN_ENV" ]]; then
    log_warning "Existing token file found at $TOKEN_ENV."
    read -p "Regenerate tokens? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        generate_tokens_via_helper
    else
        WEBHOOK_TOKENS=$(sudo awk -F'=' '/^WEBHOOK_TOKENS=/{print $2}' "$TOKEN_ENV")
    fi
else
    read -p "Generate new deployment tokens now? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Paste existing WEBHOOK_TOKENS value (token:channel:domain,...): " MANUAL_TOKENS
        if [[ -z "$MANUAL_TOKENS" ]]; then
            log_error "WEBHOOK_TOKENS cannot be empty."
            exit 1
        fi
        printf "WEBHOOK_TOKENS=%s\n" "$MANUAL_TOKENS" | sudo tee "$TOKEN_ENV" > /dev/null
        sudo chmod 600 "$TOKEN_ENV"
        WEBHOOK_TOKENS="$MANUAL_TOKENS"
    else
        generate_tokens_via_helper
    fi
fi

if [[ -z "$WEBHOOK_TOKENS" ]]; then
    log_error "WEBHOOK_TOKENS could not be established."
    exit 1
fi

PRIMARY_TOKEN=$(echo "$WEBHOOK_TOKENS" | cut -d',' -f1 | cut -d':' -f1)
REDACTED_TOKEN=$(redact_token "$PRIMARY_TOKEN")
log_info "Primary webhook token generated: $REDACTED_TOKEN"

CHANNEL_SUMMARY=$(echo "$WEBHOOK_TOKENS" | tr ',' '\n' | awk -F':' '{print $2}' | tr '\n' ',' | sed 's/,$//')
DOMAIN_SUMMARY=$(echo "$WEBHOOK_TOKENS" | tr ',' '\n' | awk -F':' '{print $3}' | tr '\n' ',' | sed 's/,$//')

cat > .env << EOF
# Local developer overrides (deployment secrets live in $TOKEN_ENV)
DISABLE_SYSTEM_INFO=true
SITE_TITLE=HooknSock - Webhook Relay
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60
MAX_PAYLOAD_SIZE=1048576
EOF

chmod 600 .env
log_info "Created .env template (tokens remain in $TOKEN_ENV)"
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
EnvironmentFile=$TOKEN_ENV
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$EXEC_START
Restart=always
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$APP_DIR
RuntimeDirectory=hooknsock
RuntimeDirectoryMode=0750

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
echo "Token store: $TOKEN_ENV (root:root 600)"
echo "Channels: ${CHANNEL_SUMMARY:-unknown}"
echo "Domains: ${DOMAIN_SUMMARY:-*}"
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
log_warning "IMPORTANT: Store the full tokens displayed above securely; the service reads them from $TOKEN_ENV"
log_warning "Update your webhook sender to use the token in the x-auth-token header"
if [[ "$USE_SSL" == "true" ]]; then
    log_warning "Update your WebSocket client to include ?token=<your_generated_token> in the URL"
    if [[ $WEBHOOK_TOKENS == *":"* ]]; then
        SERVICE=$(echo $WEBHOOK_TOKENS | cut -d':' -f2)
        log_info "Channel-specific WebSocket: wss://$DOMAIN/ws/$SERVICE?token=YOUR_TOKEN"
        log_info "Legacy WebSocket (auto-route): wss://$DOMAIN/ws?token=YOUR_TOKEN"
    fi
else
    log_warning "Update your WebSocket client to include ?token=<your_generated_token> in the URL"
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
