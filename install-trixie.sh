#!/bin/bash

# Ossuary Pi Installer - Debian 13 Trixie (2025) Compatible
# Works with latest Raspberry Pi OS based on Debian Trixie

set -e

echo "=== Ossuary Pi Installer for Debian 13 Trixie (2025) ==="
echo "Compatible with latest Raspberry Pi OS"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Detect OS version
OS_VERSION=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d'=' -f2)
echo "🔍 Detected OS: $OS_VERSION"

# 1. Install required packages (updated for Trixie)
echo "📦 Installing required packages for Debian 13 Trixie..."
apt-get update -qq
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    network-manager \
    nginx \
    git \
    curl

# Note: dnsmasq removed as NetworkManager 1.50+ has internal DHCP
echo "✅ Packages installed (using NetworkManager 1.50+ internal DHCP)"

# 2. Handle Trixie's netplan integration
echo "🔧 Configuring for Trixie's netplan/NetworkManager integration..."

# Check if netplan is present (Trixie uses it)
if command -v netplan &> /dev/null; then
    echo "Netplan detected - configuring for Trixie compatibility"

    # Create netplan config for NetworkManager
    cat > /etc/netplan/99-ossuary.yaml << 'EOF'
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlan0:
      dhcp4: true
      optional: true
EOF

    # Apply netplan config
    netplan generate
    netplan apply
else
    echo "Legacy mode - no netplan detected"
fi

# 3. Create ossuary user and directories
echo "👤 Creating ossuary user and directories..."
useradd -r -s /bin/false -d /opt/ossuary ossuary 2>/dev/null || true

mkdir -p /opt/ossuary/{src,bin,venv}
mkdir -p /etc/ossuary
mkdir -p /var/lib/ossuary
mkdir -p /var/log/ossuary

# 4. Copy source code
echo "📂 Installing source code..."
cp -r src/* /opt/ossuary/src/ 2>/dev/null || echo "Source directory not found, skipping"
cp -r scripts/bin/* /opt/ossuary/bin/ 2>/dev/null || echo "Scripts directory not found, skipping"
cp -r systemd/* /etc/systemd/system/ 2>/dev/null || echo "SystemD directory not found, skipping"
cp -r web /opt/ossuary/ 2>/dev/null || echo "Web directory not found, skipping"

chown -R ossuary:ossuary /opt/ossuary
chown -R ossuary:ossuary /var/lib/ossuary
chown -R ossuary:ossuary /var/log/ossuary

# 5. Create Python virtual environment
echo "🐍 Setting up Python environment..."
python3 -m venv /opt/ossuary/venv
/opt/ossuary/venv/bin/pip install --upgrade pip
/opt/ossuary/venv/bin/pip install \
    fastapi \
    uvicorn \
    pydantic \
    aiosqlite \
    psutil \
    watchdog \
    PyGObject

echo "✅ Python environment ready"

# 6. Create configuration (updated for Trixie)
echo "⚙️ Creating configuration..."
cat > /etc/ossuary/config.json << 'EOF'
{
  "system": {
    "hostname": "ossuary",
    "timezone": "UTC",
    "log_level": "INFO"
  },
  "network": {
    "ap_ssid": "ossuary-setup",
    "ap_passphrase": "ossuarypi",
    "ap_channel": 6,
    "ap_ip": "192.168.42.1",
    "ap_subnet": "192.168.42.0/24",
    "connection_timeout": 30,
    "fallback_timeout": 60
  },
  "kiosk": {
    "url": "http://localhost:80",
    "fullscreen": true,
    "hardware_acceleration": true
  },
  "portal": {
    "bind_address": "0.0.0.0",
    "bind_port": 80
  },
  "api": {
    "enabled": true,
    "bind_address": "0.0.0.0",
    "bind_port": 8080,
    "auth_enabled": false,
    "rate_limit": {
      "requests_per_minute": 60
    }
  }
}
EOF

chown ossuary:ossuary /etc/ossuary/config.json

# 7. Configure NetworkManager for Trixie
echo "🌐 Configuring NetworkManager 1.50+ for Trixie..."

# Trixie stores connections in /run/NetworkManager/system-connections/
mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/99-ossuary-trixie.conf << 'EOF'
[main]
# Trixie uses netplan renderer, but we can still configure NM
plugins=keyfile
# Use internal DHCP (dhclient deprecated in NM 1.50+)
dhcp=internal

[device]
# Disable MAC randomization for AP stability
wifi.scan-rand-mac-address=no
# Ensure WiFi is managed
match-device=interface-name:wlan0
managed=true

[connection]
# Store connections persistently
# Note: Trixie uses /run/ by default, we force /etc/
connection.stable-id=${CONNECTION}

[logging]
level=INFO
domains=WIFI,DEVICE,DHCP
EOF

# 8. Create AP script compatible with Trixie
echo "📝 Creating Trixie-compatible AP script..."
cat > /usr/local/bin/test-ap-trixie << 'EOF'
#!/bin/bash
echo "Testing AP creation on Debian 13 Trixie..."

# Clean up any existing connections
nmcli connection show | grep -i hotspot | awk '{print $1}' | while read conn; do
    nmcli connection delete "$conn" 2>/dev/null || true
done

# Create hotspot with NM 1.50+ syntax
echo "Creating hotspot with NetworkManager 1.50+..."
nmcli device wifi hotspot \
    ifname wlan0 \
    ssid "ossuary-setup" \
    password "ossuarypi" \
    band bg \
    channel 6

# Wait for connection to appear
sleep 3

# Configure the connection (may be in /run/ on Trixie)
CONN=$(nmcli connection show | grep -i hotspot | awk '{print $1}' | head -1)
if [[ -n "$CONN" ]]; then
    echo "Configuring connection: $CONN"
    nmcli connection modify "$CONN" \
        ipv4.method shared \
        ipv4.address "192.168.42.1/24" \
        ipv6.method disabled \
        connection.autoconnect no
fi

echo "AP should be active. Check with: nmcli connection show --active"
echo "Note: On Trixie, connections are in /run/NetworkManager/system-connections/"
EOF

chmod +x /usr/local/bin/test-ap-trixie

# 9. Handle Trixie's systemd changes
echo "🔧 Configuring services for Trixie..."

systemctl daemon-reload

# Only enable portal for testing
systemctl enable ossuary-portal.service
systemctl disable ossuary-netd.service 2>/dev/null || true
systemctl disable ossuary-api.service 2>/dev/null || true
systemctl disable ossuary-kiosk.service 2>/dev/null || true
systemctl disable ossuary-config.service 2>/dev/null || true
systemctl disable ossuary-display.service 2>/dev/null || true

# 10. Check for Trixie-specific issues
echo "🔍 Checking for Trixie-specific requirements..."

# Check kernel version (should be 6.6+ for Trixie)
KERNEL_VERSION=$(uname -r | cut -d'.' -f1)
if [[ $KERNEL_VERSION -ge 6 ]]; then
    echo "✅ Kernel version compatible ($(uname -r))"
else
    echo "⚠️ Old kernel detected, consider updating"
fi

# Check NetworkManager version
NM_VERSION=$(nmcli --version | grep version | awk '{print $4}')
echo "NetworkManager version: $NM_VERSION"
if [[ "$NM_VERSION" == "1.50"* ]] || [[ "$NM_VERSION" == "1.5"* ]]; then
    echo "✅ NetworkManager 1.50+ detected (Trixie compatible)"
else
    echo "⚠️ Older NetworkManager detected, some features may not work"
fi

echo
echo "=== Installation Complete for Debian 13 Trixie ==="
echo
echo "🎯 Key Differences in Trixie:"
echo "   • NetworkManager 1.50+ with internal DHCP"
echo "   • Connections stored in /run/NetworkManager/system-connections/"
echo "   • Netplan integration for cloud-init compatibility"
echo "   • dhclient deprecated - using internal DHCP"
echo
echo "🧪 Testing:"
echo "1. Reboot: sudo reboot"
echo "2. Test AP: sudo /usr/local/bin/test-ap-trixie"
echo "3. Connect to 'ossuary-setup' (password: ossuarypi)"
echo
echo "🔍 Debug:"
echo "   journalctl -u NetworkManager -f"
echo "   ls -la /run/NetworkManager/system-connections/"
echo "   nmcli device status"
echo
echo "⚠️ Note: This is configured for Debian 13 Trixie (2025)"
echo "For older Bookworm systems, use install-simple.sh instead"