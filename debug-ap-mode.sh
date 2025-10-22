#!/bin/bash

# Debug script for AP mode and captive portal issues
# Run this to diagnose why captive portal isn't opening

echo "=== AP Mode & Captive Portal Debug ==="
echo

echo "1. AP Mode Status"
echo "================="
echo "Active connections:"
nmcli connection show --active

echo
echo "WiFi hotspot status:"
nmcli device wifi hotspot

echo
echo "Network interfaces:"
ip addr show | grep -E "wlan|inet"

echo
echo "2. DNS Configuration"
echo "==================="
echo "Current DNS servers:"
cat /etc/resolv.conf

echo
echo "dnsmasq status:"
systemctl status dnsmasq --no-pager -l

echo
echo "dnsmasq config for AP:"
if [[ -f /etc/dnsmasq.d/ossuary-ap.conf ]]; then
    cat /etc/dnsmasq.d/ossuary-ap.conf
else
    echo "dnsmasq AP config not found!"
fi

echo
echo "3. NetworkManager Configuration"
echo "==============================="
echo "NetworkManager DNS config:"
if [[ -f /etc/NetworkManager/conf.d/99-ossuary-dns.conf ]]; then
    cat /etc/NetworkManager/conf.d/99-ossuary-dns.conf
else
    echo "NetworkManager DNS config not found!"
fi

echo
echo "4. Web Server Status"
echo "==================="
echo "Portal service:"
systemctl status ossuary-portal --no-pager -l

echo
echo "Portal listening ports:"
netstat -tlnp | grep -E ":80|:443|:8080"

echo
echo "5. Firewall Status"
echo "=================="
ufw status verbose

echo
echo "6. Test DNS Resolution"
echo "====================="
echo "Testing captive portal domains:"
for domain in connectivitycheck.gstatic.com clients3.google.com captive.apple.com; do
    echo -n "$domain: "
    nslookup $domain | grep -A1 "Name:" | tail -1 || echo "FAILED"
done

echo
echo "7. AP Interface Status"
echo "====================="
echo "WiFi interface details:"
iwconfig 2>/dev/null | grep -A10 wlan || echo "No wireless interfaces found"

echo
echo "8. DHCP Leases"
echo "=============="
if [[ -f /var/lib/dhcp/dhcpd.leases ]]; then
    echo "DHCP leases:"
    tail -20 /var/lib/dhcp/dhcpd.leases
elif [[ -f /var/lib/NetworkManager/dnsmasq.leases ]]; then
    echo "NetworkManager DHCP leases:"
    cat /var/lib/NetworkManager/dnsmasq.leases
else
    echo "No DHCP lease file found"
fi

echo
echo "=== Debugging Complete ==="
echo
echo "Common issues and solutions:"
echo "1. No DHCP leases = WiFi not actually in AP mode"
echo "2. DNS not resolving to 192.168.42.1 = dnsmasq not configured"
echo "3. Portal service not running = web server down"
echo "4. Firewall blocking = need to allow ports 80/443"