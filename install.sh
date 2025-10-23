#!/bin/bash

# Ossuary Pi - Clean Installation using Balena WiFi Connect
# SSH-safe installation with automatic recovery

set -e

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
CUSTOM_UI_DIR="$INSTALL_DIR/custom-ui"
LOG_FILE="/tmp/ossuary-install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# SSH safety wrapper
run_ssh_safe() {
    local script_path="/tmp/ossuary-install-wrapped.sh"

    # Create the actual installation script
    cat > "$script_path" << 'WRAPPER_EOF'
#!/bin/bash

LOG_FILE="/tmp/ossuary-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo "ERROR: $1" >&2
    exit 1
}

# Actual installation starts here
REPO_DIR="REPO_DIR_PLACEHOLDER"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
CUSTOM_UI_DIR="$INSTALL_DIR/custom-ui"

log "Starting SSH-safe installation..."

# Step 1: Install dependencies
log "Installing dependencies..."
apt-get update >> "$LOG_FILE" 2>&1
apt-get install -y network-manager python3 curl wget jq >> "$LOG_FILE" 2>&1

# Stop and disable dhcpcd if present
if systemctl is-active --quiet dhcpcd; then
    log "Disabling dhcpcd in favor of NetworkManager..."
    systemctl stop dhcpcd >> "$LOG_FILE" 2>&1
    systemctl disable dhcpcd >> "$LOG_FILE" 2>&1
fi

# Step 2: Install WiFi Connect
log "Installing Balena WiFi Connect..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    WIFI_CONNECT_ARCH="aarch64"
elif [ "$ARCH" = "armv7l" ]; then
    WIFI_CONNECT_ARCH="armv7hf"
else
    error "Unsupported architecture: $ARCH"
fi

# Try official installer first
if curl -L https://github.com/balena-io/wifi-connect/raw/master/scripts/raspbian-install.sh 2>/dev/null | bash >> "$LOG_FILE" 2>&1; then
    log "WiFi Connect installed via official script"
else
    log "Official installer failed, trying manual installation..."
    WIFI_CONNECT_VERSION=$(curl -s https://api.github.com/repos/balena-os/wifi-connect/releases/latest | jq -r '.tag_name')
    DOWNLOAD_URL="https://github.com/balena-os/wifi-connect/releases/download/${WIFI_CONNECT_VERSION}/wifi-connect-linux-${WIFI_CONNECT_ARCH}.tar.gz"

    wget -O /tmp/wifi-connect.tar.gz "$DOWNLOAD_URL" >> "$LOG_FILE" 2>&1
    tar -xzf /tmp/wifi-connect.tar.gz -C /usr/local/bin/ >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/bin/wifi-connect
    rm /tmp/wifi-connect.tar.gz
fi

# Verify installation
if ! command -v wifi-connect &> /dev/null; then
    error "WiFi Connect installation failed"
fi

log "WiFi Connect installed successfully"

# Step 3: Install our custom UI and scripts
log "Installing Ossuary components..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$CUSTOM_UI_DIR"
mkdir -p "$CONFIG_DIR"

# Copy custom UI
if [ -d "$REPO_DIR/custom-ui" ]; then
    cp -r "$REPO_DIR/custom-ui"/* "$CUSTOM_UI_DIR/"
    log "Custom UI installed"
fi

# Copy scripts
if [ -f "$REPO_DIR/scripts/startup-manager.sh" ]; then
    cp "$REPO_DIR/scripts/startup-manager.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/startup-manager.sh"
fi

if [ -f "$REPO_DIR/scripts/config-handler.py" ]; then
    cp "$REPO_DIR/scripts/config-handler.py" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/config-handler.py"
fi

# Step 4: Create systemd services
log "Creating systemd services..."

cat > /etc/systemd/system/wifi-connect.service << EOF
[Unit]
Description=Balena WiFi Connect
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wifi-connect \\
    --portal-ssid "Ossuary-Setup" \\
    --ui-directory $CUSTOM_UI_DIR \\
    --activity-timeout 600 \\
    --portal-listening-port 80
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ossuary-startup.service << EOF
[Unit]
Description=Ossuary Startup Command Manager
After=network-online.target wifi-connect.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/python3 $INSTALL_DIR/config-handler.py
ExecStart=$INSTALL_DIR/startup-manager.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Step 5: Create default configuration
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    log "Creating default configuration..."
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF
fi

# Step 6: Enable services
log "Enabling services..."
systemctl daemon-reload
systemctl enable wifi-connect.service >> "$LOG_FILE" 2>&1
systemctl enable ossuary-startup.service >> "$LOG_FILE" 2>&1

# Step 7: Create uninstall script
cp "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/" 2>/dev/null || true
chmod +x "$INSTALL_DIR/uninstall.sh" 2>/dev/null || true

log "Installation completed successfully!"

# Mark installation as complete
touch /tmp/ossuary-install-complete

# Schedule reboot
log "Rebooting in 10 seconds..."
(sleep 10 && reboot) &

exit 0
WRAPPER_EOF

    # Replace placeholder with actual repo dir
    sed -i "s|REPO_DIR_PLACEHOLDER|$REPO_DIR|g" "$script_path"
    chmod +x "$script_path"

    # Run in background with nohup
    nohup bash "$script_path" > /tmp/ossuary-install-output.log 2>&1 &
    local pid=$!

    echo -e "${BLUE}Installation running in background (PID: $pid)${NC}"
    echo -e "${BLUE}You can monitor progress with: tail -f $LOG_FILE${NC}"

    # Wait a bit and check if it started successfully
    sleep 3
    if kill -0 $pid 2>/dev/null; then
        echo -e "${GREEN}Installation is running...${NC}"

        # Monitor for completion or timeout
        local timeout=300  # 5 minutes
        local elapsed=0

        while [ $elapsed -lt $timeout ]; do
            if [ -f /tmp/ossuary-install-complete ]; then
                echo -e "${GREEN}Installation completed successfully!${NC}"
                echo -e "${YELLOW}System will reboot in 10 seconds...${NC}"
                return 0
            fi

            if ! kill -0 $pid 2>/dev/null; then
                # Process ended, check if it was successful
                if [ -f /tmp/ossuary-install-complete ]; then
                    echo -e "${GREEN}Installation completed successfully!${NC}"
                    return 0
                else
                    echo -e "${RED}Installation failed. Check $LOG_FILE for details.${NC}"
                    return 1
                fi
            fi

            sleep 5
            elapsed=$((elapsed + 5))

            # Show progress dot every 5 seconds
            echo -n "."
        done

        echo ""
        echo -e "${RED}Installation timeout. Check $LOG_FILE for details.${NC}"
        return 1
    else
        echo -e "${RED}Failed to start installation. Check $LOG_FILE for details.${NC}"
        return 1
    fi
}

# Main script starts here
clear
cat << "EOF"
   ___                                      ____  _
  / _ \ ___ ___ _   _  __ _ _ __ _   _    |  _ \(_)
 | | | / __/ __| | | |/ _` | '__| | | |   | |_) | |
 | |_| \__ \__ \ |_| | (_| | |  | |_| |   |  __/| |
  \___/|___/___/\__,_|\__,_|_|   \__, |   |_|   |_|
                                 |___/
  WiFi Failover System with Captive Portal
  Powered by Balena WiFi Connect
EOF
echo ""
echo "==========================================="
echo ""

# Initialize log
echo "Installation started at $(date)" > "$LOG_FILE"

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Detect SSH session
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}         SSH SESSION DETECTED - IMPORTANT        ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "This installation will:"
    echo "  1. Disable dhcpcd and enable NetworkManager"
    echo "  2. Install WiFi Connect and dependencies"
    echo "  3. Configure services"
    echo -e "  4. ${YELLOW}REBOOT YOUR SYSTEM AUTOMATICALLY${NC}"
    echo ""
    echo -e "${YELLOW}Your SSH connection WILL be disconnected.${NC}"
    echo ""
    echo "The installation will continue even if SSH disconnects."
    echo "The system will automatically reboot when complete."
    echo ""
    echo -e "${BLUE}After reboot:${NC}"
    echo "  • Look for 'Ossuary-Setup' WiFi network if no WiFi found"
    echo "  • Or SSH back in using the same IP address"
    echo ""
    echo -n "Do you want to continue? (yes/no): "
    read -r response

    if [ "$response" != "yes" ]; then
        echo "Installation cancelled."
        exit 0
    fi

    echo ""
    echo -e "${BLUE}Starting SSH-safe installation...${NC}"
    echo "Installation will continue in background even if this session disconnects."
    echo ""

    # Run installation in background
    run_ssh_safe
else
    # Local installation - run normally
    echo "Starting local installation..."

    # Run the installation directly
    bash -c "$(cat << 'LOCAL_INSTALL'

# Same installation code as in the wrapper, but inline for local execution
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
CUSTOM_UI_DIR="$INSTALL_DIR/custom-ui"
LOG_FILE="/tmp/ossuary-install.log"

# Colors for local output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Install dependencies
log "Installing dependencies..."
apt-get update
apt-get install -y network-manager python3 curl wget jq

# Stop and disable dhcpcd if present
if systemctl is-active --quiet dhcpcd; then
    log "Disabling dhcpcd in favor of NetworkManager..."
    systemctl stop dhcpcd
    systemctl disable dhcpcd
fi

# Install WiFi Connect
log "Installing Balena WiFi Connect..."

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    WIFI_CONNECT_ARCH="aarch64"
elif [ "$ARCH" = "armv7l" ]; then
    WIFI_CONNECT_ARCH="armv7hf"
else
    error "Unsupported architecture: $ARCH"
fi

# Try official installer
if curl -L https://github.com/balena-io/wifi-connect/raw/master/scripts/raspbian-install.sh | bash; then
    log "WiFi Connect installed via official script"
else
    log "Official installer failed, trying manual installation..."
    WIFI_CONNECT_VERSION=$(curl -s https://api.github.com/repos/balena-os/wifi-connect/releases/latest | jq -r '.tag_name')
    DOWNLOAD_URL="https://github.com/balena-os/wifi-connect/releases/download/${WIFI_CONNECT_VERSION}/wifi-connect-linux-${WIFI_CONNECT_ARCH}.tar.gz"

    wget -O /tmp/wifi-connect.tar.gz "$DOWNLOAD_URL"
    tar -xzf /tmp/wifi-connect.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/wifi-connect
    rm /tmp/wifi-connect.tar.gz
fi

# Verify installation
if ! command -v wifi-connect &> /dev/null; then
    error "WiFi Connect installation failed"
fi

log "WiFi Connect installed successfully"

# Install our custom UI and scripts
log "Installing Ossuary components..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$CUSTOM_UI_DIR"
mkdir -p "$CONFIG_DIR"

# Copy files
if [ -d "$REPO_DIR/custom-ui" ]; then
    cp -r "$REPO_DIR/custom-ui"/* "$CUSTOM_UI_DIR/"
fi

if [ -f "$REPO_DIR/scripts/startup-manager.sh" ]; then
    cp "$REPO_DIR/scripts/startup-manager.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/startup-manager.sh"
fi

if [ -f "$REPO_DIR/scripts/config-handler.py" ]; then
    cp "$REPO_DIR/scripts/config-handler.py" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/config-handler.py"
fi

# Create systemd services
log "Creating systemd services..."

cat > /etc/systemd/system/wifi-connect.service << EOF
[Unit]
Description=Balena WiFi Connect
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wifi-connect \\
    --portal-ssid "Ossuary-Setup" \\
    --ui-directory $CUSTOM_UI_DIR \\
    --activity-timeout 600 \\
    --portal-listening-port 80
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ossuary-startup.service << EOF
[Unit]
Description=Ossuary Startup Command Manager
After=network-online.target wifi-connect.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/python3 $INSTALL_DIR/config-handler.py
ExecStart=$INSTALL_DIR/startup-manager.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create default configuration
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    log "Creating default configuration..."
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF
fi

# Enable services
log "Enabling services..."
systemctl daemon-reload
systemctl enable wifi-connect.service
systemctl enable ossuary-startup.service

# Copy uninstall script
if [ -f "$REPO_DIR/uninstall.sh" ]; then
    cp "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/uninstall.sh"
fi

# Start services
log "Starting services..."
systemctl start wifi-connect
systemctl start ossuary-startup

echo ""
echo "==========================================="
echo -e "${GREEN}    Installation Complete!${NC}"
echo "==========================================="
echo ""
echo "WiFi Setup:"
echo "  • If no WiFi found, AP 'Ossuary-Setup' will appear"
echo "  • Connect to configure WiFi and startup command"
echo "  • Portal accessible at http://192.168.4.1"
echo ""
echo "Configuration:"
echo "  • Config stored in: $CONFIG_DIR/config.json"
echo "  • Logs: journalctl -u wifi-connect"
echo "  • Startup logs: /var/log/ossuary-startup.log"
echo ""
echo "To uninstall: sudo $INSTALL_DIR/uninstall.sh"
echo ""
echo "Services are now running!"

LOCAL_INSTALL
)"
fi