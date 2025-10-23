#!/bin/bash

set -e

INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ossuary-install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "==========================================="
echo "    Ossuary v2 Installation for Pi OS 2025"
echo "==========================================="
echo ""
echo "Designed for: Raspberry Pi 5 with Debian Trixie"
echo "Installation log: $LOG_FILE"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Detect network manager
log "Detecting network management system..."
NETWORK_SYSTEM=""

if systemctl is-active --quiet NetworkManager; then
    NETWORK_SYSTEM="NetworkManager"
    log "NetworkManager detected (standard for Pi OS 2025/Trixie)"
elif systemctl is-active --quiet dhcpcd; then
    NETWORK_SYSTEM="dhcpcd"
    log "dhcpcd detected (legacy mode)"
else
    NETWORK_SYSTEM="NetworkManager"
    log "No active network manager found, assuming NetworkManager"
fi

# Check for SSH session
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    warning "Installing over SSH - network services won't start until reboot"
fi

# Update system
log "Updating package lists..."
apt-get update >> "$LOG_FILE" 2>&1 || {
    error "Failed to update package lists"
    exit 1
}

# Install core packages
log "Installing core packages..."
PACKAGES="python3 python3-pip python3-flask python3-venv hostapd dnsmasq iptables-persistent wireless-tools net-tools git nftables"

apt-get install -y $PACKAGES >> "$LOG_FILE" 2>&1 || {
    error "Failed to install packages"
    exit 1
}

# Create Python virtual environment to avoid PEP 668 issues
log "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install flask werkzeug >> "$LOG_FILE" 2>&1

# Create directories
log "Creating directories..."
mkdir -p "$INSTALL_DIR"/{services,web/templates,web/static}
mkdir -p "$CONFIG_DIR"

# Copy files
log "Copying files..."
cp -r "$REPO_DIR/src/services/"* "$INSTALL_DIR/services/"
cp -r "$REPO_DIR/src/web/"* "$INSTALL_DIR/web/"

# Create improved captive portal wrapper for NetworkManager
log "Creating NetworkManager-compatible wrapper..."
cat > "$INSTALL_DIR/services/nm_portal_wrapper.sh" << 'EOF'
#!/bin/bash

# NetworkManager-compatible captive portal wrapper for Pi OS 2025

VENV_DIR="/opt/ossuary/venv"
WEB_DIR="/opt/ossuary/web"
LOG_FILE="/var/log/ossuary-portal.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

setup_ap() {
    log "Setting up access point with NetworkManager..."

    # Create access point connection profile
    nmcli con add type wifi ifname wlan0 con-name ossuary-ap \
        autoconnect no \
        ssid "Ossuary-Setup" \
        mode ap \
        ipv4.method shared \
        ipv4.addresses 192.168.4.1/24 \
        ipv6.method disabled

    # Activate the AP
    nmcli con up ossuary-ap

    # Configure dnsmasq for captive portal
    cat > /etc/dnsmasq.d/ossuary-captive.conf << DNSCONF
# Ossuary Captive Portal Configuration
interface=wlan0
bind-interfaces
domain-needed
bogus-priv

# DHCP range
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,12h

# DNS settings - redirect all queries to portal
address=/#/192.168.4.1

# Captive portal detection domains
address=/captive.apple.com/192.168.4.1
address=/connectivitycheck.gstatic.com/192.168.4.1
address=/detectportal.firefox.com/192.168.4.1
address=/www.msftconnecttest.com/192.168.4.1
address=/clients3.google.com/192.168.4.1
DNSCONF

    systemctl restart dnsmasq

    # Setup iptables for captive portal
    # Clear existing rules
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F

    # Allow local traffic
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow DHCP and DNS
    iptables -A INPUT -i wlan0 -p udp --dport 67 -j ACCEPT
    iptables -A INPUT -i wlan0 -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i wlan0 -p tcp --dport 53 -j ACCEPT

    # Allow web interface access
    iptables -A INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT
    iptables -A INPUT -i wlan0 -p tcp --dport 80 -j ACCEPT

    # Redirect HTTP to captive portal
    iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 \
        -j DNAT --to-destination 192.168.4.1:8080

    # Start web interface with virtual environment
    cd "$WEB_DIR"
    source "$VENV_DIR/bin/activate"
    python3 app.py > "$LOG_FILE" 2>&1 &
    echo $! > /var/run/ossuary-portal.pid

    log "Access point started successfully"
}

teardown_ap() {
    log "Stopping access point..."

    # Stop web interface
    if [ -f /var/run/ossuary-portal.pid ]; then
        kill $(cat /var/run/ossuary-portal.pid) 2>/dev/null || true
        rm -f /var/run/ossuary-portal.pid
    fi

    # Clear iptables rules
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    # Remove dnsmasq config
    rm -f /etc/dnsmasq.d/ossuary-captive.conf
    systemctl restart dnsmasq

    # Deactivate AP connection
    nmcli con down ossuary-ap 2>/dev/null || true
    nmcli con delete ossuary-ap 2>/dev/null || true

    log "Access point stopped"
}

case "$1" in
    start)
        setup_ap
        ;;
    stop)
        teardown_ap
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
EOF

chmod +x "$INSTALL_DIR/services/nm_portal_wrapper.sh"

# Create improved WiFi monitor for NetworkManager
log "Creating NetworkManager WiFi monitor..."
cat > "$INSTALL_DIR/services/nm_wifi_monitor.py" << 'EOF'
#!/usr/bin/env python3

import subprocess
import time
import logging
import json
import os
import sys
import signal
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('nm_wifi_monitor')

CONFIG_FILE = '/etc/ossuary/config.json'
CAPTIVE_PORTAL_SCRIPT = '/opt/ossuary/services/nm_portal_wrapper.sh'
CHECK_INTERVAL = 30
CONNECTION_TIMEOUT = 60

def load_config():
    """Load configuration file"""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
    return {}

def check_network_connectivity():
    """Check network connectivity using NetworkManager"""
    try:
        result = subprocess.run(
            ['nmcli', 'networking', 'connectivity', 'check'],
            capture_output=True,
            text=True,
            timeout=10
        )
        connectivity = result.stdout.strip()
        return connectivity == 'full'
    except Exception as e:
        logger.error(f"Error checking connectivity: {e}")
        return False

def get_wifi_state():
    """Get WiFi connection state"""
    try:
        result = subprocess.run(
            ['nmcli', 'device', 'status'],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.split('\n'):
            if 'wlan0' in line:
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2] == 'connected'
        return False
    except Exception as e:
        logger.error(f"Error getting WiFi state: {e}")
        return False

def try_known_networks():
    """Try to connect to known networks using NetworkManager"""
    try:
        # List available WiFi networks
        result = subprocess.run(
            ['nmcli', 'device', 'wifi', 'list'],
            capture_output=True,
            text=True,
            timeout=15
        )

        # Get saved connections
        saved_result = subprocess.run(
            ['nmcli', 'connection', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )

        # Try to connect to any saved network that's available
        for line in saved_result.stdout.split('\n'):
            if 'wifi' in line.lower():
                conn_name = line.split()[0]
                logger.info(f"Trying to connect to {conn_name}")
                try:
                    subprocess.run(
                        ['nmcli', 'connection', 'up', conn_name],
                        timeout=15
                    )
                    time.sleep(5)
                    if check_network_connectivity():
                        logger.info(f"Successfully connected to {conn_name}")
                        return True
                except:
                    continue

        return False
    except Exception as e:
        logger.error(f"Error trying known networks: {e}")
        return False

def start_captive_portal():
    """Start the captive portal"""
    try:
        logger.info("Starting captive portal...")
        subprocess.run(
            [CAPTIVE_PORTAL_SCRIPT, 'start'],
            check=True,
            timeout=30
        )
        return True
    except Exception as e:
        logger.error(f"Failed to start captive portal: {e}")
        return False

def stop_captive_portal():
    """Stop the captive portal"""
    try:
        logger.info("Stopping captive portal...")
        subprocess.run(
            [CAPTIVE_PORTAL_SCRIPT, 'stop'],
            timeout=30
        )
        return True
    except Exception as e:
        logger.error(f"Failed to stop captive portal: {e}")
        return False

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info("Received shutdown signal, cleaning up...")
    stop_captive_portal()
    sys.exit(0)

def main():
    """Main monitoring loop"""
    logger.info("NetworkManager WiFi Monitor started")

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    captive_portal_active = False
    connection_lost_time = None

    while True:
        try:
            connected = get_wifi_state()
            has_connectivity = check_network_connectivity()

            if connected and has_connectivity:
                logger.debug("Network connectivity OK")
                connection_lost_time = None

                if captive_portal_active:
                    logger.info("Network restored, stopping captive portal")
                    stop_captive_portal()
                    captive_portal_active = False

            else:
                if connection_lost_time is None:
                    connection_lost_time = time.time()
                    logger.warning("Network connectivity lost")

                time_disconnected = time.time() - connection_lost_time

                if time_disconnected > CONNECTION_TIMEOUT and not captive_portal_active:
                    logger.info(f"No connectivity for {CONNECTION_TIMEOUT}s")

                    if not try_known_networks():
                        logger.info("Starting captive portal")
                        if start_captive_portal():
                            captive_portal_active = True
                    else:
                        connection_lost_time = None

        except Exception as e:
            logger.error(f"Error in main loop: {e}")

        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
EOF

chmod +x "$INSTALL_DIR/services/nm_wifi_monitor.py"

# Update Flask app to work with venv
log "Updating Flask app for virtual environment..."
sed -i '1s|^#!/usr/bin/env python3|#!/opt/ossuary/venv/bin/python3|' "$INSTALL_DIR/web/app.py"

# Create systemd service for NetworkManager-based monitor
log "Creating systemd services..."
cat > /etc/systemd/system/ossuary-nm-monitor.service << EOF
[Unit]
Description=Ossuary NetworkManager WiFi Monitor
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/services/nm_wifi_monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create default configuration
log "Creating default configuration..."
cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF

# Set permissions
chown -R root:root "$INSTALL_DIR"
chown -R root:root "$CONFIG_DIR"

# Enable IP forwarding (modern way for Trixie)
log "Enabling IP forwarding..."
cat > /etc/sysctl.d/99-ossuary.conf << EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl --system >> "$LOG_FILE" 2>&1

# Reload systemd
log "Reloading systemd..."
systemctl daemon-reload

# Enable services
log "Enabling services..."
systemctl enable ossuary-nm-monitor.service >> "$LOG_FILE" 2>&1

# Start services if not over SSH
if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    log "Starting services..."
    systemctl start ossuary-nm-monitor.service >> "$LOG_FILE" 2>&1
else
    warning "Services will start after reboot to preserve SSH connection"
fi

echo ""
echo "==========================================="
echo "    Installation Complete!"
echo "==========================================="
echo ""
echo "The system is configured for NetworkManager (Pi OS 2025)"
echo "WiFi monitor will activate captive portal when needed"
echo ""
echo "Access point SSID: Ossuary-Setup"
echo "Portal URL: http://192.168.4.1:8080"
echo ""
echo "To check status:"
echo "  sudo systemctl status ossuary-nm-monitor"
echo "  sudo journalctl -fu ossuary-nm-monitor"
echo ""
echo "Reboot recommended for full activation."