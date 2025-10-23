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

# Check if we're running over SSH
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    warning "You appear to be installing over SSH"
    echo ""
    echo "NOTE: This installation modifies network settings but should NOT"
    echo "disconnect your current SSH session. The WiFi monitor service"
    echo "will only activate AP mode when WiFi is disconnected."
    echo ""
    echo "However, if you're connected via WiFi (not Ethernet), there is"
    echo "a small risk of disconnection during network service restart."
    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
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

# Core packages that must be installed
CORE_PACKAGES="python3 python3-pip hostapd dnsmasq wireless-tools wpasupplicant net-tools git"

# Python packages - try to install via apt first
PYTHON_PACKAGES="python3-flask"

# Optional packages - nice to have but not critical
OPTIONAL_PACKAGES="python3-werkzeug"

# Install core packages
apt-get install -y $CORE_PACKAGES >> "$LOG_FILE" 2>&1 || {
    error "Failed to install core packages"
    exit 1
}

# Install Python packages via apt
apt-get install -y $PYTHON_PACKAGES >> "$LOG_FILE" 2>&1 || {
    warning "Some Python packages not available via apt, will use pip"
}

# Try to install optional packages (don't fail if unavailable)
for pkg in $OPTIONAL_PACKAGES; do
    apt-get install -y $pkg >> "$LOG_FILE" 2>&1 || {
        log "Optional package $pkg not available via apt"
    }
done

# Check if additional Python packages are needed
log "Checking Python dependencies..."

# Try to import Flask and Werkzeug to verify they're installed
if ! python3 -c "import flask; import werkzeug" 2>/dev/null; then
    log "Installing additional Python dependencies..."
    # For newer Debian/RPi OS with PEP 668, we need to use --break-system-packages
    # since we're creating a system service that needs these packages
    pip3 install --break-system-packages -r "$REPO_DIR/requirements.txt" >> "$LOG_FILE" 2>&1 || {
        # If that fails, try without the flag for older systems
        pip3 install -r "$REPO_DIR/requirements.txt" >> "$LOG_FILE" 2>&1 || {
            warning "Could not install Python packages via pip, relying on apt packages"
        }
    }
else
    log "All Python dependencies satisfied via apt"
fi

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

# Check which network manager is in use
log "Detecting network management system..."
NETWORK_MANAGER=""

if systemctl is-active --quiet NetworkManager; then
    NETWORK_MANAGER="NetworkManager"
    log "NetworkManager detected"
elif systemctl is-active --quiet dhcpcd; then
    NETWORK_MANAGER="dhcpcd"
    log "dhcpcd detected"
else
    NETWORK_MANAGER="dhcpcd"  # Default to dhcpcd
    log "No active network manager detected, defaulting to dhcpcd configuration"
fi

# Configure network interfaces for AP mode
log "Configuring network interfaces..."

if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
    # For NetworkManager, we need to tell it to ignore wlan0 when in AP mode
    log "Configuring NetworkManager to ignore wlan0 in AP mode..."
    cat > /etc/NetworkManager/conf.d/99-ossuary.conf << EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    systemctl reload NetworkManager >> "$LOG_FILE" 2>&1 || true
fi

# Configure dhcpcd (even if using NetworkManager, as fallback)
if [ -f /etc/dhcpcd.conf ] || [ "$NETWORK_MANAGER" = "dhcpcd" ]; then
    log "Configuring dhcpcd..."
    # NOTE: The static IP configuration for wlan0 will only take effect
    # when the captive portal service explicitly configures AP mode.
    # Normal WiFi connections will continue to work through wpa_supplicant.

    # Append to existing dhcpcd.conf or create new one
    if [ -f /etc/dhcpcd.conf ]; then
        # Remove any existing Ossuary wlan0 configuration
        sed -i '/^# Ossuary AP mode configuration/,/^$/d' /etc/dhcpcd.conf 2>/dev/null || true
    fi

    # Add configuration but it won't activate until AP mode is triggered
    cat >> /etc/dhcpcd.conf << EOF

# Ossuary AP mode configuration
# This is only activated when captive portal starts
#interface wlan0
#    nohook wpa_supplicant
#    static ip_address=192.168.4.1/24
EOF

    log "dhcpcd configuration prepared (commented out for safety)"
fi

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

# Modern systems use /etc/sysctl.d/ for configuration
if [ -d /etc/sysctl.d ]; then
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ossuary.conf
    sysctl --system >> "$LOG_FILE" 2>&1
elif [ -f /etc/sysctl.conf ]; then
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p >> "$LOG_FILE" 2>&1
else
    # Create sysctl.conf if it doesn't exist
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
    sysctl -p >> "$LOG_FILE" 2>&1
fi

# Enable immediately
echo 1 > /proc/sys/net/ipv4/ip_forward

# Configure iptables for NAT
log "Configuring iptables..."
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save iptables rules
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Create systemd service for iptables persistence (modern approach)
log "Creating iptables persistence service..."
cat > /etc/systemd/system/ossuary-iptables.service << 'EOF'
[Unit]
Description=Ossuary IPTables Rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecReload=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ossuary-iptables.service >> "$LOG_FILE" 2>&1

# Reload systemd
log "Reloading systemd..."
systemctl daemon-reload

# Enable services
log "Enabling services..."
systemctl enable ossuary-wifi-monitor.service >> "$LOG_FILE" 2>&1
# Note: captive-portal is started on-demand by wifi-monitor

# Start services
log "Starting services..."

# Check if we're on SSH before starting services that might affect network
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    warning "Services will start after reboot to preserve SSH connection"
    log "Services configured to start on next boot"
else
    systemctl start ossuary-wifi-monitor.service >> "$LOG_FILE" 2>&1 || {
        warning "Failed to start WiFi monitor service. Check logs with: journalctl -u ossuary-wifi-monitor"
    }
fi

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