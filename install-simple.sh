#!/bin/bash

# Simple Ossuary Pi Installer - For Fresh Raspberry Pi OS
# This script creates a working AP + Captive Portal system

set -e

echo "=== Ossuary Pi Simple Installer ==="
echo "Installing on fresh Raspberry Pi OS..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# 1. Install required packages
echo "📦 Installing required packages..."
apt-get update -qq
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    network-manager \
    dnsmasq \
    nginx \
    git \
    curl

echo "✅ Packages installed"

# 2. Create ossuary user and directories
echo "👤 Creating ossuary user and directories..."
useradd -r -s /bin/false -d /opt/ossuary ossuary 2>/dev/null || true

# Create directories
mkdir -p /opt/ossuary/{src,bin,venv}
mkdir -p /etc/ossuary
mkdir -p /var/lib/ossuary
mkdir -p /var/log/ossuary

# 3. Copy source code
echo "📂 Installing source code..."
cp -r src/* /opt/ossuary/src/
cp -r scripts/bin/* /opt/ossuary/bin/
cp -r systemd/* /etc/systemd/system/
cp -r web /opt/ossuary/

# Set permissions
chown -R ossuary:ossuary /opt/ossuary
chown -R ossuary:ossuary /var/lib/ossuary
chown -R ossuary:ossuary /var/log/ossuary

# 4. Create Python virtual environment
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

# 5. Create simple configuration
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
    "fallback_timeout": 120
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

# 6. Configure NetworkManager
echo "🌐 Configuring NetworkManager..."
cat > /etc/NetworkManager/conf.d/99-ossuary.conf << 'EOF'
[main]
plugins=keyfile
dns=default

[device]
wifi.scan-rand-mac-address=no
match-device=interface-name:wlan0
managed=true

[logging]
level=INFO
domains=WIFI,DEVICE
EOF

# 7. Create simple AP start script for testing
echo "📝 Creating AP test script..."
cat > /usr/local/bin/test-ap << 'EOF'
#!/bin/bash
echo "Testing AP creation..."
nmcli device wifi hotspot ifname wlan0 ssid ossuary-setup
echo "AP should be active. Check with: nmcli connection show --active"
EOF

chmod +x /usr/local/bin/test-ap

# 8. Enable and start only essential services
echo "🔧 Configuring services..."

# Start with just the portal service for testing
systemctl daemon-reload
systemctl enable ossuary-portal.service
systemctl disable ossuary-netd.service ossuary-api.service ossuary-kiosk.service ossuary-config.service ossuary-display.service 2>/dev/null || true

echo "✅ Installation complete!"
echo
echo "🧪 Testing:"
echo "1. Reboot the Pi: sudo reboot"
echo "2. After reboot, test AP: sudo /usr/local/bin/test-ap"
echo "3. Connect with phone to 'ossuary-setup' (no password)"
echo "4. Open browser - should redirect to portal"
echo
echo "🔍 Debug commands:"
echo "   nmcli device"
echo "   nmcli connection show"
echo "   systemctl status ossuary-portal"
echo "   curl http://192.168.42.1"