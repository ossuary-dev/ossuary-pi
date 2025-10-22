#!/bin/bash

# Quick fix script for captive portal issues

echo "=== Fixing Captive Portal Configuration ==="

# 1. Ensure dnsmasq is configured for captive portal
echo "Setting up dnsmasq for captive portal..."
mkdir -p /etc/dnsmasq.d

cat > /etc/dnsmasq.d/ossuary-ap.conf << 'EOF'
# Ossuary AP mode DNS configuration
interface=wlan0
dhcp-range=192.168.42.10,192.168.42.100,12h
dhcp-option=option:router,192.168.42.1
dhcp-option=option:dns-server,192.168.42.1

# Captive portal detection domains - redirect to our portal
address=/connectivitycheck.gstatic.com/192.168.42.1
address=/www.gstatic.com/192.168.42.1
address=/clients3.google.com/192.168.42.1
address=/captive.apple.com/192.168.42.1
address=/www.apple.com/192.168.42.1
address=/www.appleiphonecell.com/192.168.42.1
address=/msftconnecttest.com/192.168.42.1
address=/www.msftconnecttest.com/192.168.42.1

# Redirect everything else to our portal too
address=/#/192.168.42.1

# Ensure fast responses
cache-size=1000
min-cache-ttl=60
EOF

# 2. Configure NetworkManager to use dnsmasq for AP mode
echo "Configuring NetworkManager DNS..."
mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/99-ossuary-dns.conf << 'EOF'
[main]
dns=dnsmasq

[logging]
level=INFO
EOF

# 3. Create NetworkManager dispatcher for AP mode
mkdir -p /etc/NetworkManager/dispatcher.d

cat > /etc/NetworkManager/dispatcher.d/99-ossuary-dns << 'EOF'
#!/bin/bash
# DNS configuration for AP mode

if [[ "$1" =~ wlan.*|.*hotspot.* ]] && [[ "$2" == "up" ]]; then
    # AP mode activated - ensure DNS points to us
    echo "nameserver 192.168.42.1" > /etc/resolv.conf
    echo "search ossuary.local" >> /etc/resolv.conf

    # Restart dnsmasq to pick up new config
    systemctl restart dnsmasq || true
fi
EOF

chmod +x /etc/NetworkManager/dispatcher.d/99-ossuary-dns

# 4. Ensure web server responds on all interfaces
echo "Checking portal service configuration..."
if systemctl is-active ossuary-portal &>/dev/null; then
    echo "Portal service is running"
else
    echo "Starting portal service..."
    systemctl start ossuary-portal
fi

# 5. Configure firewall for captive portal
echo "Configuring firewall..."
ufw allow 53/udp  # DNS
ufw allow 67/udp  # DHCP
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS

# 6. Restart services
echo "Restarting services..."
systemctl restart dnsmasq
systemctl restart NetworkManager

echo "=== Captive Portal Fix Complete ==="
echo
echo "Now try:"
echo "1. Turn AP mode off and on again"
echo "2. Connect with your phone"
echo "3. Check if captive portal appears"
echo
echo "If still not working, run: ./debug-ap-mode.sh"