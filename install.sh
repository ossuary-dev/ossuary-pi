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

# Logging function
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
echo "    Ossuary Simplified Installation"
echo "==========================================="
echo ""
echo "Installation log: $LOG_FILE"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check system requirements
log "Checking system requirements..."

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    warning "This system doesn't appear to be a Raspberry Pi"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for required commands
for cmd in python3 pip3 systemctl ip iwlist wpa_cli; do
    if ! command -v $cmd &> /dev/null; then
        error "Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [[ $PYTHON_MAJOR -lt 3 ]] || [[ $PYTHON_MAJOR -eq 3 && $PYTHON_MINOR -lt 7 ]]; then
    error "Python 3.7 or higher is required (found $PYTHON_VERSION)"
    exit 1
fi

log "System requirements check passed"

# Check for existing installation
if [ -d "$INSTALL_DIR" ]; then
    warning "Existing installation found at $INSTALL_DIR"
    read -p "Remove existing installation? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing existing installation..."
        systemctl stop ossuary-* 2>/dev/null || true
        rm -rf "$INSTALL_DIR"
        rm -rf "$CONFIG_DIR"
    else
        error "Installation aborted"
        exit 1
    fi
fi

# Update system
log "Updating system packages..."
apt-get update >> "$LOG_FILE" 2>&1 || {
    error "Failed to update package lists"
    exit 1
}

# Install required packages
log "Installing required packages..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-flask \
    hostapd \
    dnsmasq \
    wireless-tools \
    wpasupplicant \
    net-tools \
    git

# Install Python packages
log "Installing Python dependencies..."
pip3 install -r "$REPO_DIR/requirements.txt" >> "$LOG_FILE" 2>&1 || {
    error "Failed to install Python dependencies"
    exit 1
}

# Create installation directories
log "Creating directories..."
mkdir -p "$INSTALL_DIR"/{services,web/templates,web/static,captive-portal}
mkdir -p "$CONFIG_DIR"

# Copy files
log "Copying files..."
cp -r "$REPO_DIR/src/services/"* "$INSTALL_DIR/services/" || {
    error "Failed to copy service files"
    exit 1
}
cp -r "$REPO_DIR/src/web/"* "$INSTALL_DIR/web/" || {
    error "Failed to copy web files"
    exit 1
}

# Make scripts executable
chmod +x "$INSTALL_DIR/services/wifi_monitor.py"
chmod +x "$INSTALL_DIR/services/captive_portal_wrapper.sh"
chmod +x "$INSTALL_DIR/web/app.py"

# Initialize the captive portal submodule
echo "Setting up raspi-captive-portal..."
cd "$REPO_DIR"
git submodule update --init --recursive

# Configure the captive portal
if [ -d "$REPO_DIR/captive-portal" ]; then
    echo "Configuring captive portal..."
    cd "$REPO_DIR/captive-portal"

    # Run their installation if they have one
    if [ -f "install.sh" ]; then
        bash install.sh
    fi
fi

# Update service files with correct paths
log "Updating service files..."
sed -i "s|/opt/ossuary/services/captive_portal_wrapper.sh|$INSTALL_DIR/services/captive_portal_wrapper.sh|g" "$REPO_DIR/systemd/ossuary-captive-portal.service"

# Copy systemd service files
log "Installing systemd services..."
cp "$REPO_DIR/systemd/"*.service /etc/systemd/system/ || {
    error "Failed to install systemd services"
    exit 1
}

# Create default configuration
echo "Creating default configuration..."
cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF

# Set proper permissions
chown -R root:root "$INSTALL_DIR"
chown -R root:root "$CONFIG_DIR"

# Backup existing network configurations
log "Backing up network configurations..."
[ -f /etc/dhcpcd.conf ] && cp /etc/dhcpcd.conf /etc/dhcpcd.conf.ossuary-backup
[ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.ossuary-backup
[ -f /etc/hostapd/hostapd.conf ] && cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.ossuary-backup

# Configure network interfaces for AP mode
log "Configuring network interfaces..."
cat > /etc/dhcpcd.conf << EOF
interface wlan0
    nohook wpa_supplicant
    static ip_address=192.168.4.1/24
EOF

# Configure dnsmasq for DHCP
echo "Configuring dnsmasq..."
cat > /etc/dnsmasq.conf << EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.100,255.255.255.0,24h
domain=local
address=/ossuary.local/192.168.4.1
EOF

# Configure hostapd
echo "Configuring hostapd..."
cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=Ossuary-Setup
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

# Enable IP forwarding
log "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p >> "$LOG_FILE" 2>&1

# Configure iptables for NAT
echo "Configuring iptables..."
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables.ipv4.nat

# Add iptables restore to rc.local
if ! grep -q "iptables-restore" /etc/rc.local; then
    sed -i 's/^exit 0/iptables-restore < \/etc\/iptables.ipv4.nat\nexit 0/' /etc/rc.local
fi

# Reload systemd
log "Reloading systemd..."
systemctl daemon-reload

# Enable services
log "Enabling services..."
systemctl enable ossuary-wifi-monitor.service >> "$LOG_FILE" 2>&1
# Note: captive-portal is started on-demand by wifi-monitor

# Start services
log "Starting services..."
systemctl start ossuary-wifi-monitor.service >> "$LOG_FILE" 2>&1 || {
    warning "Failed to start WiFi monitor service. Check logs with: journalctl -u ossuary-wifi-monitor"
}

echo ""
echo "==========================================="
echo "    Installation Complete!"
echo "==========================================="
echo ""
echo "The system will monitor WiFi connectivity and start"
echo "a captive portal if no known networks are available."
echo ""
echo "Default access point SSID: Ossuary-Setup"
echo "Portal URL: http://192.168.4.1:8080"
echo ""
echo "To configure:"
echo "1. Connect to 'Ossuary-Setup' WiFi network"
echo "2. Navigate to http://192.168.4.1:8080"
echo "3. Configure WiFi and startup command"
echo ""
echo "Services:"
echo "  - ossuary-wifi-monitor: Monitors WiFi connection"
echo "  - ossuary-captive-portal: Web configuration portal"
echo "  - ossuary-startup: Runs user-defined startup command"
echo ""
echo "Reboot recommended to ensure all services start correctly."
echo ""
echo "Installation log saved to: $LOG_FILE"