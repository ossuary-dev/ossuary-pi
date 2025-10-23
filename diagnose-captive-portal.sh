#!/bin/bash

# Diagnostic script for captive portal issues

echo "==========================================="
echo "    Captive Portal Diagnostics"
echo "==========================================="
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "1. SERVICE STATUS"
echo "-----------------"
for service in ossuary-wifi-monitor ossuary-captive-portal ossuary-startup; do
    echo -n "$service: "
    if systemctl is-active --quiet $service; then
        echo "✓ Running"
    else
        echo "✗ Stopped"
    fi
done

echo ""
echo "2. NETWORK INTERFACES"
echo "---------------------"
ip addr show wlan0 2>/dev/null || echo "wlan0 not found"

echo ""
echo "3. ROUTING TABLE"
echo "----------------"
ip route

echo ""
echo "4. IPTABLES NAT RULES"
echo "---------------------"
iptables -t nat -L -n -v

echo ""
echo "5. IPTABLES FILTER RULES"
echo "------------------------"
iptables -L -n -v

echo ""
echo "6. PROCESSES"
echo "------------"
echo "hostapd: $(pgrep hostapd > /dev/null && echo '✓ Running' || echo '✗ Not running')"
echo "dnsmasq: $(pgrep dnsmasq > /dev/null && echo '✓ Running' || echo '✗ Not running')"
echo "Flask app: $(pgrep -f 'python.*app.py' > /dev/null && echo '✓ Running' || echo '✗ Not running')"

echo ""
echo "7. PORT LISTENING"
echo "-----------------"
netstat -tlpn | grep -E ':3000|:80|:53|:67' || echo "No relevant ports found"

echo ""
echo "8. DNSMASQ CONFIG"
echo "-----------------"
if [ -f /etc/dnsmasq.conf ]; then
    grep -v '^#' /etc/dnsmasq.conf | grep -v '^$'
else
    echo "No dnsmasq.conf found"
fi

echo ""
echo "9. HOSTAPD STATUS"
echo "-----------------"
if pgrep hostapd > /dev/null; then
    echo "hostapd is running"
    hostapd_cli status 2>/dev/null || echo "Could not get hostapd status"
else
    echo "hostapd is not running"
fi

echo ""
echo "10. CONNECTIVITY TEST"
echo "--------------------"
echo "Can reach gateway (192.168.4.1): $(ping -c 1 -W 1 192.168.4.1 > /dev/null 2>&1 && echo '✓ Yes' || echo '✗ No')"
echo "Can reach web interface (port 80): $(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1 2>/dev/null || echo 'Failed')"
echo "Can reach Flask directly (port 3000): $(curl -s -o /dev/null -w '%{http_code}' http://192.168.4.1:3000 2>/dev/null || echo 'Failed')"

echo ""
echo "11. DHCPCD CONFIG CHECK"
echo "-----------------------"
if [ -f /etc/dhcpcd.conf ]; then
    echo "Ossuary section in dhcpcd.conf:"
    sed -n '/# Ossuary AP mode configuration/,/^$/p' /etc/dhcpcd.conf
else
    echo "No dhcpcd.conf found"
fi

echo ""
echo "12. IP FORWARDING"
echo "-----------------"
echo "IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"

echo ""
echo "13. RECENT LOGS"
echo "---------------"
echo "WiFi Monitor logs:"
journalctl -u ossuary-wifi-monitor -n 10 --no-pager 2>/dev/null || echo "No logs available"
echo ""
echo "Captive Portal logs:"
journalctl -u ossuary-captive-portal -n 10 --no-pager 2>/dev/null || echo "No logs available"

echo ""
echo "==========================================="
echo "    Diagnostics Complete"
echo "==========================================="
echo ""
echo "Common issues:"
echo "1. If port 3000 is not listening -> Flask app not running"
echo "2. If no NAT rules -> iptables not configured properly"
echo "3. If hostapd not running -> AP mode failed to start"
echo "4. If dnsmasq not running -> DHCP/DNS not working"