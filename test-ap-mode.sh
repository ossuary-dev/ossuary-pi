#!/bin/bash

echo "==================================="
echo "  TEST AP Mode Diagnostic"
echo "==================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Run with sudo"
   exit 1
fi

echo "1. Creating manual flag..."
echo "$(date +%s)" > /tmp/ossuary_manual_ap
echo "Flag created: $(ls -la /tmp/ossuary_manual_ap)"

echo ""
echo "2. Stopping WiFi client..."
systemctl stop wpa_supplicant
sleep 2

echo ""
echo "3. Checking wlan0 status..."
ip addr show wlan0

echo ""
echo "4. Starting hostapd..."
systemctl start hostapd
sleep 2
systemctl status hostapd --no-pager | head -10

echo ""
echo "5. Starting dnsmasq..."
systemctl start dnsmasq
sleep 1
systemctl status dnsmasq --no-pager | head -10

echo ""
echo "6. Checking if AP is visible..."
iw dev wlan0 info

echo ""
echo "7. Checking hostapd config..."
grep -E "ssid=|wpa=|channel=" /etc/hostapd/hostapd.conf

echo ""
echo "8. Checking for errors..."
journalctl -u hostapd -n 20 --no-pager

echo ""
echo "9. Network interfaces:"
ip addr show

echo ""
echo "10. Checking iptables:"
iptables -t nat -L PREROUTING -n -v

echo ""
echo "==================================="
echo "To stop test mode and restore WiFi:"
echo "  rm /tmp/ossuary_manual_ap"
echo "  systemctl stop hostapd dnsmasq"
echo "  systemctl restart wpa_supplicant"
echo "==================================="