#!/bin/bash

# Debug script for WiFi AP mode connection issues
# When devices can't connect to the hotspot at all

echo "=== WiFi AP Mode Connection Debug ==="
echo

echo "1. Current WiFi Interface Status"
echo "==============================="
echo "WiFi interfaces:"
ip link show | grep wlan

echo
echo "Interface details:"
iwconfig 2>/dev/null | grep -A10 wlan || echo "No wireless found"

echo
echo "Interface IP addresses:"
ip addr show | grep -A5 wlan

echo
echo "2. NetworkManager Hotspot Status"
echo "================================"
echo "Active connections:"
nmcli connection show --active

echo
echo "Available connections:"
nmcli connection show | grep -i hotspot

echo
echo "WiFi device status:"
nmcli device status | grep wifi

echo
echo "Current hotspot state:"
nmcli device wifi hotspot 2>/dev/null || echo "No hotspot active or command failed"

echo
echo "3. Hostapd Status"
echo "================"
systemctl status hostapd --no-pager -l || echo "hostapd not running/installed"

echo
echo "4. DHCP Server Status"
echo "===================="
echo "dnsmasq status:"
systemctl status dnsmasq --no-pager -l

echo
echo "NetworkManager internal DHCP:"
ps aux | grep dnsmasq

echo
echo "5. WiFi Hardware Capabilities"
echo "============================="
echo "Supported modes:"
iw list 2>/dev/null | grep -A10 "Supported interface modes" || echo "iw command failed"

echo
echo "Current mode:"
iw dev 2>/dev/null | grep -E "Interface|type" || echo "iw dev failed"

echo
echo "6. RF Kill Status"
echo "================="
rfkill list all 2>/dev/null || echo "rfkill not available"

echo
echo "7. Kernel Modules"
echo "================"
echo "WiFi modules loaded:"
lsmod | grep -E "brcm|cfg80211|mac80211"

echo
echo "8. Network Configuration Files"
echo "=============================="
echo "NetworkManager main config:"
if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
    cat /etc/NetworkManager/NetworkManager.conf
else
    echo "NetworkManager.conf not found"
fi

echo
echo "9. Test Manual Hotspot Creation"
echo "==============================="
echo "Attempting to create test hotspot..."

# First, turn off any existing hotspot
nmcli connection down ossuary-ap 2>/dev/null || true
nmcli connection delete ossuary-ap 2>/dev/null || true

# Try to create a simple hotspot
echo "Creating basic hotspot..."
if nmcli device wifi hotspot ifname wlan0 ssid "test-ossuary" password "testpass123"; then
    echo "✓ Test hotspot created successfully"

    sleep 3
    echo "Hotspot status:"
    nmcli connection show --active | grep hotspot

    echo "Interface status after hotspot:"
    ip addr show wlan0

    # Clean up test hotspot
    nmcli device disconnect wlan0
    echo "Test hotspot cleaned up"
else
    echo "✗ Failed to create test hotspot"
    echo "This indicates a fundamental AP mode issue"
fi

echo
echo "=== Diagnostic Complete ==="
echo
echo "Common issues and solutions:"
echo "1. 'Operation not supported' = WiFi hardware doesn't support AP mode"
echo "2. 'Device busy' = Another service using WiFi interface"
echo "3. 'RF-kill' = WiFi disabled in hardware/software"
echo "4. No hostapd/dnsmasq = Missing AP mode software"
echo "5. NetworkManager conflicts = Need to configure properly"