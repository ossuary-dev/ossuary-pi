#!/bin/bash

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
}

warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "==========================================="
echo "    Ossuary Integrated Installation"
echo "==========================================="
echo ""
echo "Using raspi-captive-portal for AP management"
echo "Installation log: $LOG_FILE"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check for SSH
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    warning "Installing over SSH - be careful with network changes"
fi

# Initialize submodule
log "Initializing raspi-captive-portal submodule..."
cd "$REPO_DIR"
git submodule update --init --recursive >> "$LOG_FILE" 2>&1 || {
    error "Failed to initialize git submodule"
    exit 1
}

# Step 1: Install raspi-captive-portal
log "Installing raspi-captive-portal..."
cd "$REPO_DIR/captive-portal"

# Modify their config files before installation
log "Configuring captive portal settings..."

# Update hostapd.conf with our settings
cat > "$REPO_DIR/captive-portal/access-point/hostapd.conf" << EOF
interface=wlan0
driver=nl80211
ssid=Ossuary-Setup
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=ossuary123
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=US
EOF

# Update dhcpcd.conf
cat > "$REPO_DIR/captive-portal/access-point/dhcpcd.conf" << EOF
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

# Update dnsmasq.conf
cat > "$REPO_DIR/captive-portal/access-point/dnsmasq.conf" << EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.100,255.255.255.0,24h
domain=ossuary
address=/ossuary.local/192.168.4.1

# Captive portal detection
address=/captive.apple.com/192.168.4.1
address=/connectivitycheck.gstatic.com/192.168.4.1
address=/detectportal.firefox.com/192.168.4.1
address=/www.msftconnecttest.com/192.168.4.1
address=/clients3.google.com/192.168.4.1

# Redirect all domains to our server
address=/#/192.168.4.1
EOF

# Run their setup script
log "Running raspi-captive-portal setup..."
sudo python3 setup.py << EOF
y
EOF

# Step 2: Stop their Node.js server (we'll use our Python one)
log "Disabling default captive portal server..."
sudo systemctl stop access-point-server 2>/dev/null || true
sudo systemctl disable access-point-server 2>/dev/null || true

# Step 3: Install our Python dependencies
log "Installing Python dependencies..."
apt-get update >> "$LOG_FILE" 2>&1
apt-get install -y python3 python3-pip python3-flask python3-venv >> "$LOG_FILE" 2>&1

# Create virtual environment
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install flask werkzeug >> "$LOG_FILE" 2>&1

# Step 4: Copy our files
log "Installing Ossuary components..."
mkdir -p "$INSTALL_DIR"/{services,web/templates}
mkdir -p "$CONFIG_DIR"

cp -r "$REPO_DIR/src/services/"* "$INSTALL_DIR/services/"
cp -r "$REPO_DIR/src/web/"* "$INSTALL_DIR/web/"

# Step 5: Create wrapper to integrate with raspi-captive-portal
log "Creating integration wrapper..."
cat > "$INSTALL_DIR/services/portal_controller.sh" << 'EOF'
#!/bin/bash

# Controller for raspi-captive-portal integration

start_portal() {
    echo "Starting captive portal..."

    # Start raspi-captive-portal services
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq

    # Start our Flask app
    source /opt/ossuary/venv/bin/activate
    cd /opt/ossuary/web
    python3 app.py &
    echo $! > /var/run/ossuary-flask.pid

    echo "Portal started"
}

stop_portal() {
    echo "Stopping captive portal..."

    # Stop Flask app
    if [ -f /var/run/ossuary-flask.pid ]; then
        kill $(cat /var/run/ossuary-flask.pid) 2>/dev/null || true
        rm -f /var/run/ossuary-flask.pid
    fi

    # Stop raspi-captive-portal services
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq

    # Reset WiFi
    sudo systemctl restart wpa_supplicant

    echo "Portal stopped"
}

status_portal() {
    echo "Checking portal status..."
    systemctl is-active hostapd
    systemctl is-active dnsmasq

    if [ -f /var/run/ossuary-flask.pid ]; then
        if ps -p $(cat /var/run/ossuary-flask.pid) > /dev/null; then
            echo "Flask app: active"
        else
            echo "Flask app: inactive"
        fi
    else
        echo "Flask app: inactive"
    fi
}

case "$1" in
    start)
        start_portal
        ;;
    stop)
        stop_portal
        ;;
    status)
        status_portal
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
EOF

chmod +x "$INSTALL_DIR/services/portal_controller.sh"

# Step 6: Create monitoring service
log "Creating monitoring service..."
cat > "$INSTALL_DIR/services/wifi_monitor_integrated.py" << 'EOF'
#!/usr/bin/env python3

import subprocess
import time
import logging
import os
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('wifi_monitor')

PORTAL_CONTROLLER = '/opt/ossuary/services/portal_controller.sh'
CHECK_INTERVAL = 30
TIMEOUT = 60

def check_connectivity():
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
    """Check WiFi connection"""
    try:
        result = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True)
        return bool(result.stdout.strip())
    except:
        return False

def is_portal_active():
    """Check if captive portal is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'hostapd'],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == 'active'
    except:
        return False

def main():
    logger.info("WiFi Monitor started")
    portal_active = False
    lost_time = None

    while True:
        try:
            wifi_connected = check_wifi()
            internet_ok = check_connectivity() if wifi_connected else False

            if wifi_connected and internet_ok:
                lost_time = None
                if portal_active:
                    logger.info("Connection restored, stopping portal")
                    subprocess.run([PORTAL_CONTROLLER, 'stop'])
                    portal_active = False

            else:
                if lost_time is None:
                    lost_time = time.time()
                    logger.info("Connection lost")

                if time.time() - lost_time > TIMEOUT and not portal_active:
                    logger.info("Starting captive portal")
                    subprocess.run([PORTAL_CONTROLLER, 'start'])
                    portal_active = True

        except Exception as e:
            logger.error(f"Error: {e}")

        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
EOF

chmod +x "$INSTALL_DIR/services/wifi_monitor_integrated.py"

# Step 7: Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/ossuary-monitor.service << EOF
[Unit]
Description=Ossuary WiFi Monitor (Integrated)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/services/wifi_monitor_integrated.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Step 8: Configure iptables for our Flask app
log "Configuring firewall rules..."
iptables -A INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT
iptables-save > /etc/iptables/rules.v4

# Step 9: Create config file
log "Creating configuration..."
cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": [],
  "portal": {
    "ssid": "Ossuary-Setup",
    "password": "ossuary123"
  }
}
EOF

# Step 10: Enable and start
systemctl daemon-reload
systemctl enable ossuary-monitor

if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    systemctl start ossuary-monitor
else
    warning "Not starting services over SSH - reboot to activate"
fi

echo ""
echo "==========================================="
echo "    Installation Complete!"
echo "==========================================="
echo ""
echo "Integrated with raspi-captive-portal for AP management"
echo ""
echo "Access Point: Ossuary-Setup (password: ossuary123)"
echo "Configuration portal: http://192.168.4.1:8080"
echo ""
echo "Commands:"
echo "  Start portal: sudo $INSTALL_DIR/services/portal_controller.sh start"
echo "  Stop portal: sudo $INSTALL_DIR/services/portal_controller.sh stop"
echo "  Check status: sudo systemctl status ossuary-monitor"
echo ""
echo "The raspi-captive-portal handles all the complex AP setup!"