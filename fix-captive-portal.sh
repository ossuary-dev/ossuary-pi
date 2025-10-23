#!/bin/bash

# Emergency fix script for captive portal issues

echo "==========================================="
echo "    Ossuary Captive Portal Fix Script"
echo "==========================================="
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "This script will:"
echo "1. Stop the captive portal services"
echo "2. Restore normal WiFi functionality"
echo "3. Allow you to connect to your network"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo "Step 1: Stopping Ossuary services..."
systemctl stop ossuary-wifi-monitor 2>/dev/null || true
systemctl stop ossuary-captive-portal 2>/dev/null || true
systemctl stop ossuary-startup 2>/dev/null || true

echo "Step 2: Killing any remaining processes..."
killall -9 hostapd 2>/dev/null || true
killall -9 dnsmasq 2>/dev/null || true
killall -9 python3 2>/dev/null || true

echo "Step 3: Restoring network configuration..."

# Reset iptables
iptables -t nat -F
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Reset WiFi interface
ip link set wlan0 down
ip addr flush dev wlan0
ip link set wlan0 up

# Comment out the dhcpcd static config if it's active
if [ -f /etc/dhcpcd.conf ]; then
    sed -i '/^# Ossuary AP mode configuration/,/^$/{s/^interface/#interface/; s/^    /#    /}' /etc/dhcpcd.conf 2>/dev/null || true
fi

# Remove NetworkManager unmanaged device if exists
rm -f /etc/NetworkManager/conf.d/99-ossuary.conf
systemctl reload NetworkManager 2>/dev/null || true

echo "Step 4: Restarting normal network services..."
systemctl restart dhcpcd 2>/dev/null || true
systemctl restart wpa_supplicant 2>/dev/null || true
systemctl restart NetworkManager 2>/dev/null || true

echo "Step 5: Disabling Ossuary services temporarily..."
systemctl disable ossuary-wifi-monitor 2>/dev/null || true
systemctl disable ossuary-captive-portal 2>/dev/null || true

echo ""
echo "==========================================="
echo "    Network Restored!"
echo "==========================================="
echo ""
echo "Your normal WiFi should now work again."
echo ""
echo "To connect to WiFi manually:"
echo "  Using wpa_cli:"
echo "    sudo wpa_cli"
echo "    > scan"
echo "    > scan_results"
echo "    > add_network"
echo "    > set_network 0 ssid \"YourNetworkName\""
echo "    > set_network 0 psk \"YourPassword\""
echo "    > enable_network 0"
echo "    > save_config"
echo "    > quit"
echo ""
echo "  Or using nmcli (if NetworkManager is active):"
echo "    nmcli device wifi list"
echo "    nmcli device wifi connect \"YourNetworkName\" password \"YourPassword\""
echo ""
echo "Once connected, you can pull the latest fixes with:"
echo "    git pull"
echo ""
echo "To re-enable Ossuary after pulling fixes:"
echo "    sudo systemctl enable ossuary-wifi-monitor"
echo "    sudo systemctl start ossuary-wifi-monitor"