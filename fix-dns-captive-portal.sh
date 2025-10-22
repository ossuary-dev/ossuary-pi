#!/bin/bash

# Fix DNS configuration for captive portal functionality
# This ensures NetworkManager properly handles DNS for AP mode

set -e

echo "=== DNS Configuration Fix for Captive Portal ==="
echo

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "1. Configuring NetworkManager for proper DNS handling..."

# Create NetworkManager configuration directory if it doesn't exist
mkdir -p /etc/NetworkManager/conf.d

# Configure NetworkManager to use dnsmasq for better captive portal support
cat > /etc/NetworkManager/conf.d/99-ossuary-dns.conf << 'EOF'
[main]
dns=dnsmasq

[logging]
level=INFO
domains=CORE,DHCP,WIFI,IP4,IP6,AUTOIP4,DHCP6,PPP,WIFI_SCAN,RFC3484,AUDIT,VPN_PLUGIN,DBUS_PROPS,TEAM,CONCHECK,DCB,DISPATCH,AGENT_MANAGER,SETTINGS_PLUGIN,SUSPEND_RESUME,CORE,DEVICE,OLPC,INFINIBAND,FIREWALL,ADSL,BOND,VLAN,BRIDGE,DBUS_PROPS,WIFI_SCAN,SIM,CONCHECK,DISPATCHER,AUDIT,VPN_PLUGIN,OTHER

EOF

echo "✓ Created NetworkManager DNS configuration"

# Create dnsmasq configuration for NetworkManager
mkdir -p /etc/NetworkManager/dnsmasq-shared.d

cat > /etc/NetworkManager/dnsmasq-shared.d/99-ossuary-captive.conf << 'EOF'
# DNS configuration for captive portal
# Redirect all DNS queries to the captive portal when in AP mode

# Enable logging for debugging
log-queries
log-dhcp

# Set cache size
cache-size=1000

# Faster DNS responses
min-cache-ttl=60

# Domain handling for captive portal
# These domains are commonly used by devices to detect captive portals
address=/connectivitycheck.gstatic.com/192.168.42.1
address=/www.gstatic.com/192.168.42.1
address=/clients3.google.com/192.168.42.1
address=/captive.apple.com/192.168.42.1
address=/www.apple.com/192.168.42.1
address=/www.appleiphonecell.com/192.168.42.1
address=/msftconnecttest.com/192.168.42.1
address=/www.msftconnecttest.com/192.168.42.1

# Catch-all for unknown domains when in captive portal mode
# This will be managed by the ossuary portal service

EOF

echo "✓ Created dnsmasq captive portal configuration"

echo
echo "2. Checking if dnsmasq system service needs to be disabled..."

# Disable the system dnsmasq service if it's running
# NetworkManager will manage its own dnsmasq instance
if systemctl is-active dnsmasq &>/dev/null; then
    echo "Stopping system dnsmasq service (NetworkManager will manage its own)"
    systemctl stop dnsmasq
    systemctl disable dnsmasq
    echo "✓ System dnsmasq disabled"
else
    echo "✓ System dnsmasq not running (good)"
fi

echo
echo "3. Restarting NetworkManager to apply changes..."

systemctl restart NetworkManager

echo "✓ NetworkManager restarted"

echo
echo "4. Testing DNS configuration..."

# Wait for NetworkManager to fully restart
sleep 3

# Check if NetworkManager is running its own dnsmasq
if pgrep -f "dnsmasq.*NetworkManager" >/dev/null; then
    echo "✓ NetworkManager is running its own dnsmasq instance"
else
    echo "⚠  NetworkManager dnsmasq may not be running"
fi

echo
echo "=== DNS Configuration Complete ==="
echo
echo "DNS is now configured for proper captive portal functionality."
echo "When AP mode is enabled, devices should:"
echo "  • Get IP addresses via DHCP"
echo "  • Have DNS queries redirected to the portal"
echo "  • Detect the captive portal automatically"
echo
echo "You can now test AP mode from the web interface."