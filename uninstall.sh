#!/bin/bash

set -e

echo "==========================================="
echo "    Ossuary Uninstallation Script"
echo "==========================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo ""
echo "This will completely remove Ossuary from your system."
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Stopping services..."

# Stop services
systemctl stop ossuary-wifi-monitor.service 2>/dev/null || true
systemctl stop ossuary-captive-portal.service 2>/dev/null || true
systemctl stop ossuary-startup.service 2>/dev/null || true

echo "Disabling services..."

# Disable services
systemctl disable ossuary-wifi-monitor.service 2>/dev/null || true
systemctl disable ossuary-captive-portal.service 2>/dev/null || true
systemctl disable ossuary-startup.service 2>/dev/null || true

echo "Removing service files..."

# Remove service files
rm -f /etc/systemd/system/ossuary-wifi-monitor.service
rm -f /etc/systemd/system/ossuary-captive-portal.service
rm -f /etc/systemd/system/ossuary-startup.service

# Reload systemd
systemctl daemon-reload

echo "Removing installation directories..."

# Remove installation directories
rm -rf /opt/ossuary
rm -rf /etc/ossuary

echo "Restoring network configuration..."

# Restore dhcpcd configuration
if [ -f /etc/dhcpcd.conf.ossuary-backup ]; then
    mv /etc/dhcpcd.conf.ossuary-backup /etc/dhcpcd.conf
else
    # Remove our static IP configuration
    sed -i '/^interface wlan0$/,/^$/d' /etc/dhcpcd.conf 2>/dev/null || true
fi

# Restore dnsmasq configuration
if [ -f /etc/dnsmasq.conf.ossuary-backup ]; then
    mv /etc/dnsmasq.conf.ossuary-backup /etc/dnsmasq.conf
else
    # Remove our dnsmasq configuration
    > /etc/dnsmasq.conf
fi

# Restore hostapd configuration
if [ -f /etc/hostapd/hostapd.conf.ossuary-backup ]; then
    mv /etc/hostapd/hostapd.conf.ossuary-backup /etc/hostapd/hostapd.conf
else
    rm -f /etc/hostapd/hostapd.conf
fi

echo "Removing iptables rules..."

# Remove iptables rules
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wlan0 -o eth0 -j ACCEPT 2>/dev/null || true

# Save cleaned iptables
iptables-save > /etc/iptables.ipv4.nat

# Remove IP forwarding configuration
if [ -f /etc/sysctl.d/99-ossuary.conf ]; then
    rm -f /etc/sysctl.d/99-ossuary.conf
    sysctl --system > /dev/null 2>&1 || true
elif [ -f /etc/sysctl.conf ]; then
    sed -i '/^net.ipv4.ip_forward=1$/d' /etc/sysctl.conf 2>/dev/null || true
fi

# Remove iptables persistence service
if [ -f /etc/systemd/system/ossuary-iptables.service ]; then
    systemctl stop ossuary-iptables.service 2>/dev/null || true
    systemctl disable ossuary-iptables.service 2>/dev/null || true
    rm -f /etc/systemd/system/ossuary-iptables.service
fi

# Remove saved iptables rules
rm -f /etc/iptables/rules.v4

# Remove NetworkManager configuration if exists
rm -f /etc/NetworkManager/conf.d/99-ossuary.conf
systemctl reload NetworkManager 2>/dev/null || true

echo "Restarting network services..."

# Restart network services
systemctl restart dhcpcd 2>/dev/null || true
systemctl restart networking 2>/dev/null || true

echo ""
echo "==========================================="
echo "    Uninstallation Complete"
echo "==========================================="
echo ""
echo "Ossuary has been removed from your system."
echo "Your network configuration has been restored."
echo ""
echo "You may want to reboot to ensure all changes take effect."