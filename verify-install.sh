#!/bin/bash

# Quick verification script after installation

echo "================================"
echo "  Ossuary Installation Check"
echo "================================"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check() {
    if eval "$2" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1"
        return 1
    fi
}

echo "1. Core Services:"
check "ossuary-monitor service exists" "systemctl list-unit-files | grep -q ossuary-monitor"
check "ossuary-monitor is active" "systemctl is-active --quiet ossuary-monitor"
check "hostapd installed" "which hostapd"
check "dnsmasq installed" "which dnsmasq"

echo ""
echo "2. Flask Application:"
check "Flask app exists" "[ -f /opt/ossuary/web/app.py ]"
check "Flask on port 3000" "netstat -tln 2>/dev/null | grep -q :3000"

echo ""
echo "3. Network Status:"
if iwgetid -r &>/dev/null; then
    SSID=$(iwgetid -r)
    echo -e "${GREEN}✓${NC} Connected to WiFi: $SSID"
    IP=$(hostname -I | awk '{print $1}')
    echo "  Web interface: http://$IP"
else
    echo -e "No WiFi connection (AP mode may be active)"
    if systemctl is-active --quiet hostapd; then
        echo -e "${GREEN}✓${NC} Access Point is active"
        echo "  Connect to: Ossuary-Setup"
        echo "  Then visit: http://192.168.4.1"
    fi
fi

echo ""
echo "4. Quick Actions:"
echo "  • View logs: sudo journalctl -fu ossuary-monitor"
echo "  • Test page: curl -I http://localhost:3000"
echo "  • Force AP: sudo systemctl stop wpa_supplicant"
echo "  • Status: sudo systemctl status ossuary-monitor"