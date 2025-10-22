#!/bin/bash

# Fix AP mode issues
# This script addresses common problems with AP mode on Raspberry Pi

set -e

echo "=== AP Mode Diagnostic and Fix ==="
echo

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "1. Checking required packages for AP mode..."

# Install missing packages that are commonly needed for AP mode
packages_needed=("hostapd" "dnsmasq" "iptables")
packages_to_install=()

for package in "${packages_needed[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        echo "✗ $package is missing"
        packages_to_install+=("$package")
    else
        echo "✓ $package is installed"
    fi
done

if [[ ${#packages_to_install[@]} -gt 0 ]]; then
    echo
    echo "Installing missing packages: ${packages_to_install[*]}"
    apt-get update
    apt-get install -y "${packages_to_install[@]}"
fi

echo
echo "2. Checking NetworkManager AP capabilities..."

# Check if NetworkManager supports AP mode
if nmcli device wifi hotspot --help &>/dev/null; then
    echo "✓ NetworkManager supports AP mode"
else
    echo "✗ NetworkManager AP support issue"
fi

# Check WiFi device capabilities
echo
echo "3. Checking WiFi device capabilities..."
wifi_device=$(nmcli device | grep wifi | head -1 | awk '{print $1}')

if [[ -n "$wifi_device" ]]; then
    echo "Found WiFi device: $wifi_device"

    # Check if device supports AP mode
    if iw list 2>/dev/null | grep -A 20 "Supported interface modes:" | grep -q "AP"; then
        echo "✓ WiFi device supports AP mode"
    else
        echo "✗ WiFi device may not support AP mode"
    fi
else
    echo "✗ No WiFi device found"
fi

echo
echo "4. Checking current network state..."
nmcli device status
echo
nmcli connection show

echo
echo "5. AP Test (Optional - WARNING: Will disconnect WiFi!)"

# Check if user is connected via SSH over WiFi
ssh_connection=""
if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
    ssh_ip=$(echo $SSH_CLIENT | awk '{print $1}' 2>/dev/null || echo "unknown")

    # Check if SSH IP is on WiFi network
    wifi_ip=$(ip route | grep "$wifi_device" | grep -E '192\.168\.|10\.|172\.' | head -1 | awk '{print $9}' 2>/dev/null || echo "")

    if [[ -n "$wifi_ip" ]]; then
        echo "⚠️  WARNING: You appear to be connected via SSH over WiFi"
        echo "⚠️  Testing AP mode will DISCONNECT your SSH session!"
        echo "⚠️  SSH from: $ssh_ip, WiFi IP: $wifi_ip"
        echo
        read -p "Do you want to test AP creation anyway? This will disconnect you! (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping AP test for safety (recommended when connected via SSH over WiFi)"
            echo "You can test AP mode later from the web interface"
        else
            ssh_connection="yes"
        fi
    fi
fi

if [[ -z "$ssh_connection" ]]; then
    echo "Testing simple AP creation..."

    # Try to create a simple test AP
    test_ssid="ossuary-test-$(date +%s)"
    echo "Creating test AP: $test_ssid"

    if nmcli device wifi hotspot ifname "$wifi_device" ssid "$test_ssid" password "" 2>/dev/null; then
        echo "✓ Test AP created successfully"

        # Wait a moment then clean up
        sleep 3

        # Stop the test AP
        nmcli connection down "$test_ssid" 2>/dev/null || true
        nmcli connection delete "$test_ssid" 2>/dev/null || true
        echo "✓ Test AP cleaned up"
    else
        echo "✗ Failed to create test AP"
        echo "Error details:"
        nmcli device wifi hotspot ifname "$wifi_device" ssid "$test_ssid" password "" 2>&1 || true
    fi
fi

echo
echo "6. Checking NetworkManager configuration..."

# Check if NetworkManager is managing the WiFi device
if nmcli device show "$wifi_device" | grep -q "GENERAL.STATE.*connected"; then
    echo "ℹ WiFi device is currently connected"
elif nmcli device show "$wifi_device" | grep -q "GENERAL.STATE.*disconnected"; then
    echo "ℹ WiFi device is disconnected (good for AP mode)"
else
    echo "ℹ WiFi device state unclear"
fi

echo
echo "7. Checking system logs for errors..."
echo "Recent NetworkManager logs:"
journalctl -u NetworkManager -n 10 --no-pager || echo "No NetworkManager logs available"

echo
echo "=== Recommendations ==="
echo

if [[ ${#packages_to_install[@]} -gt 0 ]]; then
    echo "• Required packages were installed. Restart ossuary services:"
    echo "  sudo systemctl restart ossuary-netd"
fi

echo "• Try AP mode again from the web interface"
echo "• If AP still fails, check that WiFi hardware supports AP mode"
echo "• For debugging, check logs with: sudo journalctl -u NetworkManager -f"

echo
echo "=== Manual AP Test Commands ==="
echo "You can test AP creation manually with:"
echo "  sudo nmcli device wifi hotspot ifname $wifi_device ssid ossuary-manual"
echo "  sudo nmcli connection down ossuary-manual"
echo "  sudo nmcli connection delete ossuary-manual"