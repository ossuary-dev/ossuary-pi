#!/bin/bash

# Ossuary Pi - Clean Installation Script
# Uses raspi-captive-portal submodule for AP management

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
LOG_FILE="/tmp/ossuary-install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "==========================================="
echo "    Ossuary Pi Installation"
echo "==========================================="
echo ""
echo "This will install:"
echo "  • raspi-captive-portal for AP management"
echo "  • Ossuary web interface for WiFi/startup configuration"
echo "  • Automatic failover when WiFi disconnects"
echo ""
echo "Installation log: $LOG_FILE"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Check SSH warning
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    warning "Installing over SSH - services won't start until reboot"
    echo "Continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Check if already installed
if [ -d "$INSTALL_DIR" ]; then
    warning "Previous installation found at $INSTALL_DIR"
    echo "Remove and reinstall? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Removing previous installation..."
        systemctl stop ossuary-monitor 2>/dev/null || true
        systemctl disable ossuary-monitor 2>/dev/null || true
        rm -rf "$INSTALL_DIR"
        rm -rf "$CONFIG_DIR"
    else
        exit 0
    fi
fi

# Initialize git submodule
log "Initializing raspi-captive-portal submodule..."
cd "$REPO_DIR"
if [ ! -f captive-portal/.git ]; then
    git submodule update --init --recursive >> "$LOG_FILE" 2>&1 || error "Failed to init submodule"
fi

# Check if captive-portal exists
if [ ! -d "$REPO_DIR/captive-portal" ]; then
    error "captive-portal submodule not found. Run: git submodule update --init"
fi

# Install system packages
log "Installing system packages..."
apt-get update >> "$LOG_FILE" 2>&1 || error "Failed to update package lists"

PACKAGES="python3 python3-pip python3-venv python3-flask git"
apt-get install -y $PACKAGES >> "$LOG_FILE" 2>&1 || error "Failed to install packages"

# Configure captive-portal settings BEFORE running their setup
log "Configuring captive portal settings..."

mkdir -p "$REPO_DIR/captive-portal/access-point"

# Configure hostapd
cat > "$REPO_DIR/captive-portal/access-point/hostapd.conf" << 'EOF'
# Ossuary Access Point Configuration
interface=wlan0
driver=nl80211
ssid=Ossuary-Setup
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
# Open network (no password for captive portal)
EOF

# Configure dhcpcd
cat > "$REPO_DIR/captive-portal/access-point/dhcpcd.conf" << 'EOF'
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

# Configure dnsmasq
cat > "$REPO_DIR/captive-portal/access-point/dnsmasq.conf" << 'EOF'
interface=wlan0
bind-interfaces
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h

# DNS settings
domain=ossuary
address=/ossuary.local/192.168.4.1

# Captive portal - redirect all DNS to us
address=/#/192.168.4.1
EOF

# Configure iptables rules
cat > "$REPO_DIR/captive-portal/access-point/iptables-rules-dhcpcd.sh" << 'EOF'
#!/bin/bash
# Forward HTTP traffic to our server
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.4.1:8080
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 192.168.4.1:8080
EOF

chmod +x "$REPO_DIR/captive-portal/access-point/iptables-rules-dhcpcd.sh"

# Run raspi-captive-portal setup
log "Running raspi-captive-portal setup..."
cd "$REPO_DIR/captive-portal"

# Auto-answer yes to their prompts
echo "y" | sudo python3 setup.py >> "$LOG_FILE" 2>&1 || {
    warning "raspi-captive-portal setup had issues, continuing..."
}

# Stop and disable their Node.js server
log "Disabling default captive portal server..."
systemctl stop access-point-server 2>/dev/null || true
systemctl disable access-point-server 2>/dev/null || true

# Create Python virtual environment for our code
log "Setting up Python environment..."
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install --upgrade pip >> "$LOG_FILE" 2>&1
pip install flask werkzeug >> "$LOG_FILE" 2>&1

# Install our files
log "Installing Ossuary components..."
mkdir -p "$INSTALL_DIR"/{services,web/templates,web/static}
mkdir -p "$CONFIG_DIR"

# Copy our web interface
cp -r "$REPO_DIR/src/web/"* "$INSTALL_DIR/web/"

# Copy WiFi monitor
cp "$REPO_DIR/src/services/wifi_monitor.py" "$INSTALL_DIR/services/"

# Update Flask app to use venv Python
sed -i '1s|.*|#!/opt/ossuary/venv/bin/python3|' "$INSTALL_DIR/web/app.py"
chmod +x "$INSTALL_DIR/web/app.py"

# Create simplified WiFi monitor
cat > "$INSTALL_DIR/services/monitor.py" << 'EOF'
#!/opt/ossuary/venv/bin/python3

import subprocess
import time
import logging
import sys
import os
import signal

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('ossuary-monitor')

CHECK_INTERVAL = 30
FAIL_THRESHOLD = 60

def check_internet():
    """Check internet connectivity"""
    try:
        result = subprocess.run(
            ['ping', '-c', '1', '-W', '2', '8.8.8.8'],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except:
        return False

def check_wifi():
    """Check if WiFi is connected"""
    try:
        result = subprocess.run(
            ['iwgetid', '-r'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return bool(result.stdout.strip())
    except:
        return False

def start_ap():
    """Start access point mode"""
    logger.info("Starting access point...")

    # Start AP services
    subprocess.run(['systemctl', 'start', 'hostapd'], check=False)
    subprocess.run(['systemctl', 'start', 'dnsmasq'], check=False)

    # Start our Flask app
    subprocess.Popen([
        '/opt/ossuary/venv/bin/python3',
        '/opt/ossuary/web/app.py'
    ])

    logger.info("Access point started")

def stop_ap():
    """Stop access point mode"""
    logger.info("Stopping access point...")

    # Kill Flask app
    subprocess.run(['pkill', '-f', 'app.py'], check=False)

    # Stop AP services
    subprocess.run(['systemctl', 'stop', 'hostapd'], check=False)
    subprocess.run(['systemctl', 'stop', 'dnsmasq'], check=False)

    # Restart normal WiFi
    subprocess.run(['systemctl', 'restart', 'wpa_supplicant'], check=False)

    logger.info("Access point stopped")

def signal_handler(sig, frame):
    logger.info("Shutting down...")
    stop_ap()
    sys.exit(0)

def main():
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("Monitor started")

    ap_active = False
    fail_time = None

    while True:
        has_wifi = check_wifi()
        has_internet = check_internet() if has_wifi else False

        if has_wifi and has_internet:
            fail_time = None
            if ap_active:
                stop_ap()
                ap_active = False
        else:
            if fail_time is None:
                fail_time = time.time()
                logger.warning("Connection lost")

            if time.time() - fail_time > FAIL_THRESHOLD and not ap_active:
                start_ap()
                ap_active = True

        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
EOF

chmod +x "$INSTALL_DIR/services/monitor.py"

# Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/ossuary-monitor.service << EOF
[Unit]
Description=Ossuary WiFi Monitor
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/services/monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create default config
log "Creating configuration..."
cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF

# Set permissions
chown -R root:root "$INSTALL_DIR"
chown -R root:root "$CONFIG_DIR"

# Enable service
systemctl daemon-reload
systemctl enable ossuary-monitor.service

# Start if not over SSH
if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    systemctl start ossuary-monitor.service
    log "Service started"
else
    warning "Service will start on reboot (SSH session detected)"
fi

echo ""
echo "==========================================="
echo "    Installation Complete!"
echo "==========================================="
echo ""
echo "Access Point SSID: Ossuary-Setup (open network)"
echo "Configuration URL: http://192.168.4.1:8080"
echo ""
echo "Status: systemctl status ossuary-monitor"
echo "Logs: journalctl -fu ossuary-monitor"
echo ""
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "IMPORTANT: Reboot to activate all services"
fi