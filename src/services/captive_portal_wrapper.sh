#!/bin/bash

# Wrapper script to properly integrate with raspi-captive-portal

PORTAL_DIR="/opt/ossuary/captive-portal"
WEB_DIR="/opt/ossuary/web"

# Function to setup access point
setup_ap() {
    echo "Setting up access point..."

    # First, enable the dhcpcd static IP configuration if it exists
    if [ -f /etc/dhcpcd.conf ]; then
        # Uncomment the Ossuary AP configuration
        sed -i '/^# Ossuary AP mode configuration/,/^$/{s/^#interface/interface/; s/^#    /    /}' /etc/dhcpcd.conf 2>/dev/null || true
    fi

    # Stop any existing WiFi connections
    wpa_cli terminate 2>/dev/null || true
    systemctl stop wpa_supplicant 2>/dev/null || true

    # Configure the interface manually for immediate effect
    ip link set wlan0 down
    ip addr flush dev wlan0
    ip addr add 192.168.4.1/24 dev wlan0
    ip link set wlan0 up

    # Start hostapd
    hostapd -B /etc/hostapd/hostapd.conf

    # Start dnsmasq
    systemctl restart dnsmasq

    # Enable NAT and routing
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

    # Allow access to the web interface
    iptables -A INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT
    iptables -A INPUT -i wlan0 -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -i wlan0 -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i wlan0 -p udp --dport 67 -j ACCEPT

    # Redirect HTTP traffic to our portal (captive portal behavior)
    iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to-destination 192.168.4.1:8080

    echo "Access point started successfully"
}

# Function to teardown access point
teardown_ap() {
    echo "Stopping access point..."

    # Re-comment the dhcpcd static IP configuration
    if [ -f /etc/dhcpcd.conf ]; then
        sed -i '/^# Ossuary AP mode configuration/,/^$/{s/^interface/#interface/; s/^    /#    /}' /etc/dhcpcd.conf 2>/dev/null || true
    fi

    # Kill hostapd
    killall hostapd 2>/dev/null || true

    # Stop dnsmasq
    systemctl stop dnsmasq

    # Remove firewall rules
    iptables -t nat -D PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to-destination 192.168.4.1:8080 2>/dev/null || true
    iptables -D INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i wlan0 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i wlan0 -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i wlan0 -p udp --dport 67 -j ACCEPT 2>/dev/null || true

    # Remove NAT rules
    iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i wlan0 -o eth0 -j ACCEPT 2>/dev/null || true

    # Reset interface
    ip link set wlan0 down
    ip addr flush dev wlan0

    # Restart wpa_supplicant for normal WiFi
    systemctl restart wpa_supplicant

    echo "Access point stopped"
}

# Check command
case "$1" in
    start)
        setup_ap
        # Start the web interface
        cd "$WEB_DIR"
        python3 app.py &
        echo $! > /var/run/ossuary-portal.pid
        ;;
    stop)
        teardown_ap
        # Stop the web interface
        if [ -f /var/run/ossuary-portal.pid ]; then
            kill $(cat /var/run/ossuary-portal.pid) 2>/dev/null || true
            rm -f /var/run/ossuary-portal.pid
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac