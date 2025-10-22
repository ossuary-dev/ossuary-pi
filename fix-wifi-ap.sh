#!/bin/bash

# Fix script for WiFi AP mode connection issues (2025)
# Based on current best practices for Raspberry Pi and NetworkManager

echo "=== Fixing WiFi AP Mode Issues (2025) ==="

# 1. Check if hardware supports AP mode
echo "1. Checking WiFi hardware compatibility..."
if command -v iw >/dev/null; then
    echo "Checking AP mode support:"
    if iw list | grep -A 10 "Supported interface modes" | grep -q "AP"; then
        echo "✓ WiFi hardware supports AP mode"
    else
        echo "✗ WiFi hardware does NOT support AP mode"
        echo "Your WiFi adapter cannot create hotspots"
        exit 1
    fi
else
    echo "⚠ iw command not available, installing..."
    apt-get update >/dev/null && apt-get install -y iw
fi

# 2. Ensure WiFi is not blocked
echo "2. Checking RF-Kill status..."
if command -v rfkill >/dev/null; then
    rfkill unblock wifi
    rfkill unblock all
    echo "✓ WiFi unblocked"
else
    echo "⚠ rfkill not available"
fi

# 2. Restart WiFi interface
echo "2. Resetting WiFi interface..."
ip link set wlan0 down 2>/dev/null || true
sleep 2
ip link set wlan0 up 2>/dev/null || true
echo "✓ WiFi interface reset"

# 3. Stop any conflicting services
echo "3. Stopping conflicting services..."
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl stop hostapd 2>/dev/null || true
echo "✓ Conflicting services stopped"

# 4. Clean up any existing hotspot connections
echo "4. Cleaning up existing hotspot connections..."
nmcli connection down ossuary-ap 2>/dev/null || true
nmcli connection delete ossuary-ap 2>/dev/null || true
nmcli device disconnect wlan0 2>/dev/null || true
echo "✓ Existing connections cleaned"

# 5. Configure NetworkManager for optimal AP mode (2025)
echo "5. Configuring NetworkManager for AP mode..."
mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/99-ossuary-wifi.conf << 'EOF'
[main]
# Use keyfile plugin for connection management
plugins=keyfile

[device]
# Disable MAC randomization for AP mode stability
wifi.scan-rand-mac-address=no

# Use stable backend
wifi.backend=wpa_supplicant

# Allow unmanaged devices for hotspot
match-device=interface-name:wlan0;type:wifi
managed=true

[connection]
# Optimize for hotspot usage
wifi.powersave=2
ipv6.method=ignore

[logging]
# Increase logging for debugging
level=INFO
domains=WIFI,DEVICE
EOF

# 6. Install required packages if missing
echo "6. Checking required packages..."
for pkg in hostapd dnsmasq; do
    if ! dpkg -l | grep -q "^ii.*$pkg "; then
        echo "Installing $pkg..."
        apt-get update >/dev/null 2>&1
        apt-get install -y $pkg
    else
        echo "✓ $pkg already installed"
    fi
done

# 7. Configure hostapd for AP mode
echo "7. Configuring hostapd..."
cat > /etc/hostapd/hostapd.conf << 'EOF'
# Ossuary AP Mode Configuration
interface=wlan0
driver=nl80211
ssid=ossuary-setup
hw_mode=g
channel=6
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=ossuarypi
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# 8. Configure dnsmasq for DHCP
echo "8. Configuring DHCP..."
cat > /etc/dnsmasq.d/ossuary-ap.conf << 'EOF'
# DHCP configuration for AP mode
interface=wlan0
dhcp-range=192.168.42.10,192.168.42.100,12h
dhcp-option=option:router,192.168.42.1
dhcp-option=option:dns-server,192.168.42.1
EOF

# 9. Create AP startup script
echo "9. Creating AP startup script..."
cat > /usr/local/bin/start-ossuary-ap << 'EOF'
#!/bin/bash
# Script to start Ossuary AP mode

set -e

# Configure interface
ip link set wlan0 down
ip addr flush dev wlan0
ip addr add 192.168.42.1/24 dev wlan0
ip link set wlan0 up

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Start hostapd
hostapd -B /etc/hostapd/hostapd.conf

# Start dnsmasq
dnsmasq --interface=wlan0 --bind-interfaces

echo "AP mode started successfully"
echo "SSID: ossuary-setup"
echo "Password: ossuarypi"
echo "Gateway: 192.168.42.1"
EOF

chmod +x /usr/local/bin/start-ossuary-ap

# 10. Create AP stop script
cat > /usr/local/bin/stop-ossuary-ap << 'EOF'
#!/bin/bash
# Script to stop Ossuary AP mode

# Kill hostapd and dnsmasq
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true

# Reset interface
ip addr flush dev wlan0
ip link set wlan0 down
ip link set wlan0 up

echo "AP mode stopped"
EOF

chmod +x /usr/local/bin/stop-ossuary-ap

# 11. Restart NetworkManager
echo "10. Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 3

# 12. Test simple hotspot creation
echo "11. Testing hotspot creation..."
if timeout 10 nmcli device wifi hotspot ifname wlan0 ssid "ossuary-setup" password "ossuarypi"; then
    echo "✓ Hotspot created successfully!"

    sleep 3
    echo "Connection status:"
    nmcli connection show --active | grep -E "NAME|hotspot" || echo "No active hotspot shown"

    echo "Interface status:"
    ip addr show wlan0 | grep inet || echo "No IP assigned"

else
    echo "✗ NetworkManager hotspot failed, trying manual method..."

    # Try manual method
    echo "Attempting manual AP setup..."
    if /usr/local/bin/start-ossuary-ap; then
        echo "✓ Manual AP setup successful"
    else
        echo "✗ Manual AP setup also failed"
        echo "Your WiFi hardware may not support AP mode"
    fi
fi

echo
echo "=== WiFi AP Fix Complete ==="
echo
echo "Test commands:"
echo "  Start AP: nmcli device wifi hotspot ifname wlan0 ssid ossuary-setup password ossuarypi"
echo "  Manual start: sudo /usr/local/bin/start-ossuary-ap"
echo "  Stop AP: nmcli device disconnect wlan0"
echo "  Manual stop: sudo /usr/local/bin/stop-ossuary-ap"
echo "  Debug: sudo ./debug-wifi-ap.sh"