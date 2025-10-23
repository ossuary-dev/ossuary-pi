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
    warning "Installing over SSH detected!"
    echo ""
    echo "IMPORTANT: The captive portal setup may disconnect your SSH session"
    echo "when it restarts the network services (dhcpcd restart)."
    echo ""
    echo "Recommendations:"
    echo "  • Use Ethernet for SSH if possible"
    echo "  • Have physical access as backup"
    echo "  • Run in screen/tmux session"
    echo ""
    echo "Continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 0
    fi

    # Try to make it safer
    warning "Will skip network restart during install"
    SKIP_NETWORK_RESTART=1
else
    SKIP_NETWORK_RESTART=0
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

# Configure iptables rules (empty - we'll configure after their setup)
cat > "$REPO_DIR/captive-portal/access-point/iptables-rules-dhcpcd.sh" << 'EOF'
#!/bin/bash
# Rules will be added after setup
EOF

chmod +x "$REPO_DIR/captive-portal/access-point/iptables-rules-dhcpcd.sh"

# Run raspi-captive-portal setup (only the access point part, not Node.js)
log "Running raspi-captive-portal access point setup..."
cd "$REPO_DIR/captive-portal"

# Handle SSH safety for raspi-captive-portal setup
if [ "$SKIP_NETWORK_RESTART" -eq 1 ]; then
    log "SSH session detected - using safe installation method"

    # Run the critical parts manually
    log "Running captive portal setup in SSH-safe mode..."

    # 1. Install required packages (safe)
    apt-get install -y dhcpcd dnsmasq hostapd >> "$LOG_FILE" 2>&1
    apt-get install -y netfilter-persistent iptables-persistent >> "$LOG_FILE" 2>&1

    # 2. Stop services (safe)
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl stop hostapd 2>/dev/null || true

    # 3. Configure dhcpcd WITHOUT restarting it
    cat ./access-point/dhcpcd.conf >> /etc/dhcpcd.conf
    log "dhcpcd configured but NOT restarted (SSH safety)"

    # 4. Configure dnsmasq (safe)
    [ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
    cp ./access-point/dnsmasq.conf /etc/dnsmasq.conf
    echo "DNSMASQ_EXCEPT=lo" >> /etc/default/dnsmasq

    # 5. Configure hostapd (safe)
    cp ./access-point/hostapd.conf /etc/hostapd/hostapd.conf

    # 6. Set up IP forwarding (safe)
    if [ -f /etc/sysctl.conf ]; then
        sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ossuary.conf
    fi

    # 7. Configure iptables - redirect port 80 to 3000 for Flask
    iptables -t nat -I PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.4.1:3000
    netfilter-persistent save >> "$LOG_FILE" 2>&1

    # 8. Enable services but don't start them
    systemctl unmask dnsmasq hostapd
    systemctl enable dnsmasq hostapd

    warning "Network services configured but not started - reboot required"
else
    # Normal installation - run only the access point setup part
    log "Running standard raspi-captive-portal access point setup..."

    # Make sure the setup script is executable
    chmod +x ./access-point/setup-access-point.sh >> "$LOG_FILE" 2>&1

    # Run just the access point setup (skip Node.js parts)
    if bash ./access-point/setup-access-point.sh >> "$LOG_FILE" 2>&1; then
        log "raspi-captive-portal access point setup completed successfully"
    else
        warning "Access point setup had issues. Recent log output:"
        echo "----------------------------------------"
        tail -20 "$LOG_FILE"
        echo "----------------------------------------"
        echo "Full log available at: $LOG_FILE"
        warning "Continuing with installation despite errors..."
    fi
fi

# Stop and disable their Node.js server (if it exists)
log "Disabling default captive portal server..."
systemctl stop access-point-server 2>/dev/null || true
systemctl disable access-point-server 2>/dev/null || true

# Note: We keep their iptables redirect (80->3000) since Flask now runs on port 3000

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

# Note: monitor.py is created directly below, not copied

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
FLASK_PID_FILE = '/var/run/ossuary-flask.pid'

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

def is_flask_running():
    """Check if Flask app is running"""
    try:
        if os.path.exists(FLASK_PID_FILE):
            with open(FLASK_PID_FILE, 'r') as f:
                pid = int(f.read().strip())
                # Check if process exists
                os.kill(pid, 0)
                return True
    except:
        pass
    return False

def start_flask():
    """Start Flask web interface"""
    if not is_flask_running():
        logger.info("Starting Flask web interface...")
        proc = subprocess.Popen([
            '/opt/ossuary/venv/bin/python3',
            '/opt/ossuary/web/app.py'
        ])
        with open(FLASK_PID_FILE, 'w') as f:
            f.write(str(proc.pid))
        logger.info(f"Flask started with PID {proc.pid}")

def stop_flask():
    """Stop Flask web interface"""
    try:
        if os.path.exists(FLASK_PID_FILE):
            with open(FLASK_PID_FILE, 'r') as f:
                pid = int(f.read().strip())
                os.kill(pid, signal.SIGTERM)
                os.remove(FLASK_PID_FILE)
                logger.info("Flask stopped")
    except:
        subprocess.run(['pkill', '-f', 'app.py'], check=False)

def start_ap():
    """Start access point mode"""
    logger.info("Starting access point mode...")

    # Start AP services
    subprocess.run(['systemctl', 'start', 'hostapd'], check=False)
    subprocess.run(['systemctl', 'start', 'dnsmasq'], check=False)

    logger.info("Access point started")

def stop_ap():
    """Stop access point mode"""
    logger.info("Stopping access point mode...")

    # Stop AP services
    subprocess.run(['systemctl', 'stop', 'hostapd'], check=False)
    subprocess.run(['systemctl', 'stop', 'dnsmasq'], check=False)

    # Restart normal WiFi
    subprocess.run(['systemctl', 'restart', 'wpa_supplicant'], check=False)

    logger.info("Access point stopped")

def get_ip_address():
    """Get current IP address"""
    try:
        result = subprocess.run(
            ['hostname', '-I'],
            capture_output=True,
            text=True
        )
        ips = result.stdout.strip().split()
        return ips[0] if ips else None
    except:
        return None

def signal_handler(sig, frame):
    logger.info("Shutting down...")
    stop_flask()
    stop_ap()
    sys.exit(0)

def main():
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("Ossuary Monitor started")

    # Always start Flask web interface
    start_flask()
    time.sleep(2)  # Give Flask time to start

    # Log access information
    ip = get_ip_address()
    if ip:
        logger.info(f"Web interface available at http://{ip}")
    logger.info("Direct Flask access at http://localhost:3000")

    ap_active = False
    fail_time = None

    while True:
        # Ensure Flask stays running
        if not is_flask_running():
            logger.warning("Flask not running, restarting...")
            start_flask()

        has_wifi = check_wifi()
        has_internet = check_internet() if has_wifi else False

        if has_wifi and has_internet:
            fail_time = None
            if ap_active:
                stop_ap()
                ap_active = False
                # Log new IP after reconnection
                time.sleep(5)
                ip = get_ip_address()
                if ip:
                    logger.info(f"Connected to WiFi. Web interface at http://{ip}")
        else:
            if fail_time is None:
                fail_time = time.time()
                logger.warning("Connection lost")

            if time.time() - fail_time > FAIL_THRESHOLD and not ap_active:
                start_ap()
                ap_active = True
                logger.info("AP mode active. Connect to 'Ossuary-Setup' and visit http://192.168.4.1")

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
echo "Web Interface Access:"
echo "  • When on WiFi: http://<pi-ip-address>"
echo "  • In AP mode: http://192.168.4.1"
echo "  • Direct Flask: http://localhost:3000"
echo ""
echo "To find your Pi's IP address: hostname -I"
echo ""
echo "Access Point (when WiFi fails):"
echo "  • SSID: Ossuary-Setup (open network)"
echo "  • URL: http://192.168.4.1"
echo ""
echo "Commands:"
echo "  • Status: systemctl status ossuary-monitor"
echo "  • Logs: journalctl -fu ossuary-monitor"
echo "  • IP Address: hostname -I"
echo ""
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "==========================================="
    echo "    SSH Installation - Action Required"
    echo "==========================================="
    echo ""
    echo "Since you installed over SSH, network services were not restarted."
    echo ""
    echo "To complete installation, either:"
    echo "  1. Reboot: sudo reboot"
    echo "  2. Or manually restart: sudo systemctl restart dhcpcd"
    echo ""
    echo "WARNING: Option 2 may disconnect your SSH session!"
fi