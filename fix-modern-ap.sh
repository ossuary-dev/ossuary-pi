#!/bin/bash

# Modern WiFi AP Configuration Fix for Raspberry Pi (2025)
# This script implements modern NetworkManager-based AP mode with proper captive portal

set -e

echo "=== Modern WiFi AP Configuration (2025) ==="
echo "Implementing NetworkManager-based approach for reliable AP mode"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# 1. Clean up old configuration
echo "🧹 Cleaning up old configuration..."

# Stop conflicting services
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

# Remove old configs
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.d/ossuary-ap.conf

echo "✅ Old configuration cleaned"

# 2. Configure NetworkManager for modern AP mode
echo "⚙️  Configuring NetworkManager for optimal AP mode..."

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/99-ossuary-wifi.conf << 'EOF'
[main]
# Use keyfile plugin for connection management
plugins=keyfile
# Do NOT use dnsmasq - NetworkManager handles DHCP in shared mode
dns=default

[device]
# Disable MAC randomization for AP mode stability
wifi.scan-rand-mac-address=no
# Use stable backend
wifi.backend=wpa_supplicant
# Ensure WiFi is managed
match-device=interface-name:wlan0
managed=true

[connection]
# Optimize for hotspot usage
wifi.powersave=2
# Disable IPv6 for simplicity
ipv6.method=disabled

[logging]
# Increase logging for debugging
level=INFO
domains=WIFI,DEVICE,DHCP,DNS
EOF

echo "✅ NetworkManager configured"

# 3. Create modern AP startup script
echo "📝 Creating modern AP management scripts..."

cat > /usr/local/bin/ossuary-ap-start << 'EOF'
#!/bin/bash
# Modern AP startup script using NetworkManager (2025)

set -e

SSID="ossuary-setup"
PASSWORD="ossuarypi"
DEVICE="wlan0"

echo "Starting modern WiFi AP: $SSID"

# Clean up any existing hotspot connections
nmcli connection show | grep -i hotspot | awk '{print $1}' | while read conn; do
    echo "Removing old hotspot: $conn"
    nmcli connection delete "$conn" 2>/dev/null || true
done

# Disconnect from any current WiFi
nmcli device disconnect "$DEVICE" 2>/dev/null || true

# Create hotspot using modern nmcli method
echo "Creating hotspot with NetworkManager..."
nmcli device wifi hotspot \
    ifname "$DEVICE" \
    ssid "$SSID" \
    password "$PASSWORD" \
    band bg

# Get the connection name created by nmcli
HOTSPOT_CONN=$(nmcli connection show | grep -i hotspot | awk '{print $1}' | head -1)

if [[ -n "$HOTSPOT_CONN" ]]; then
    echo "Configuring hotspot connection: $HOTSPOT_CONN"

    # Configure for proper captive portal operation
    nmcli connection modify "$HOTSPOT_CONN" \
        ipv4.method shared \
        ipv4.address "192.168.42.1/24" \
        ipv4.dns "192.168.42.1" \
        ipv6.method disabled \
        connection.autoconnect false \
        802-11-wireless.channel 6

    echo "✅ AP started successfully!"
    echo "   SSID: $SSID"
    echo "   Password: $PASSWORD"
    echo "   Gateway: 192.168.42.1"
    echo "   Connection: $HOTSPOT_CONN"
else
    echo "❌ Failed to create hotspot"
    exit 1
fi
EOF

cat > /usr/local/bin/ossuary-ap-stop << 'EOF'
#!/bin/bash
# Modern AP stop script using NetworkManager (2025)

echo "Stopping WiFi AP..."

# Find and stop all hotspot connections
nmcli connection show --active | grep -i hotspot | awk '{print $1}' | while read conn; do
    echo "Stopping hotspot: $conn"
    nmcli connection down "$conn"
    nmcli connection delete "$conn"
done

# Also clean up any connections with our SSID
nmcli connection show | grep "ossuary-setup" | awk '{print $1}' | while read conn; do
    echo "Cleaning up connection: $conn"
    nmcli connection delete "$conn" 2>/dev/null || true
done

echo "✅ AP stopped"
EOF

chmod +x /usr/local/bin/ossuary-ap-start
chmod +x /usr/local/bin/ossuary-ap-stop

echo "✅ AP management scripts created"

# 4. Create NetworkManager dispatcher for portal DNS
echo "🌐 Setting up captive portal DNS redirection..."

mkdir -p /etc/NetworkManager/dispatcher.d

cat > /etc/NetworkManager/dispatcher.d/99-ossuary-portal << 'EOF'
#!/bin/bash
# NetworkManager dispatcher for captive portal DNS

# Only act on hotspot connections
if [[ "$CONNECTION_ID" =~ [Hh]otspot ]] && [[ "$2" == "up" ]]; then
    echo "$(date): Hotspot activated, setting up captive portal DNS" >> /var/log/ossuary-ap.log

    # Configure iptables for DNS redirection
    # Redirect all DNS queries to our gateway
    iptables -t nat -A PREROUTING -i wlan0 -p udp --dport 53 -j DNAT --to 192.168.42.1:53
    iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 53 -j DNAT --to 192.168.42.1:53

    # Redirect HTTP traffic to portal
    iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to 192.168.42.1:80

    # Allow established connections
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

    echo "$(date): Captive portal iptables rules applied" >> /var/log/ossuary-ap.log

elif [[ "$CONNECTION_ID" =~ [Hh]otspot ]] && [[ "$2" == "down" ]]; then
    echo "$(date): Hotspot deactivated, cleaning up iptables" >> /var/log/ossuary-ap.log

    # Clean up iptables rules
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true
fi
EOF

chmod +x /etc/NetworkManager/dispatcher.d/99-ossuary-portal

echo "✅ Captive portal DNS redirection configured"

# 5. Update netd service to use modern approach
echo "🔧 Updating network daemon configuration..."

# Backup current manager.py
if [[ -f /opt/ossuary/src/netd/manager.py ]]; then
    cp /opt/ossuary/src/netd/manager.py /opt/ossuary/src/netd/manager.py.backup
    echo "✅ Backed up current network manager"
fi

# 6. Restart NetworkManager
echo "🔄 Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 3

# 7. Test AP creation
echo "🧪 Testing AP creation..."

if timeout 15 /usr/local/bin/ossuary-ap-start; then
    echo "✅ AP test successful!"

    # Show status
    echo
    echo "📊 AP Status:"
    nmcli connection show --active | grep -i hotspot || echo "No active hotspot shown"
    ip addr show wlan0 | grep inet || echo "No IP on wlan0"

    sleep 5

    # Stop test AP
    echo "🛑 Stopping test AP..."
    /usr/local/bin/ossuary-ap-stop

else
    echo "❌ AP test failed"
    echo "Check NetworkManager status: systemctl status NetworkManager"
    echo "Check WiFi device: nmcli device"
fi

echo
echo "=== Modern WiFi AP Configuration Complete ==="
echo
echo "🎯 Key Improvements:"
echo "   • Pure NetworkManager approach (no hostapd/dnsmasq conflicts)"
echo "   • Modern nmcli hotspot command (2025 best practice)"
echo "   • Automatic DHCP via NetworkManager shared mode"
echo "   • Proper captive portal DNS redirection"
echo "   • Simplified service management"
echo
echo "📋 Usage:"
echo "   Start AP:  sudo /usr/local/bin/ossuary-ap-start"
echo "   Stop AP:   sudo /usr/local/bin/ossuary-ap-stop"
echo "   Status:    nmcli connection show --active"
echo
echo "🔧 Troubleshooting:"
echo "   Logs: journalctl -u NetworkManager -f"
echo "   Debug: nmcli device wifi list"
echo "   Portal logs: tail -f /var/log/ossuary-ap.log"