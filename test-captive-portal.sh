#!/bin/bash

# Comprehensive test script for Ossuary captive portal

echo "==========================================="
echo "    Ossuary Captive Portal Test Suite"
echo "==========================================="
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${YELLOW}ℹ${NC} $1"; }

echo "TEST 1: System Detection"
echo "------------------------"

# Check Pi model
if grep -q "Raspberry Pi 5" /proc/cpuinfo; then
    pass "Raspberry Pi 5 detected"
else
    info "Not Pi 5 - $(grep Model /proc/cpuinfo | cut -d: -f2)"
fi

# Check OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$VERSION_CODENAME" == "trixie" ]]; then
        pass "Debian Trixie detected"
    else
        info "OS Version: $PRETTY_NAME ($VERSION_CODENAME)"
    fi
fi

# Check network manager
if systemctl is-active --quiet NetworkManager; then
    pass "NetworkManager is active (recommended for 2025)"
elif systemctl is-active --quiet dhcpcd; then
    info "dhcpcd is active (legacy mode)"
else
    fail "No network manager detected"
fi

echo ""
echo "TEST 2: Required Services"
echo "-------------------------"

# Check dnsmasq
if command -v dnsmasq &> /dev/null; then
    pass "dnsmasq installed"
    if systemctl is-enabled --quiet dnsmasq; then
        pass "dnsmasq enabled"
    else
        info "dnsmasq not enabled"
    fi
else
    fail "dnsmasq not installed"
fi

# Check hostapd (if using traditional method)
if command -v hostapd &> /dev/null; then
    pass "hostapd installed"
else
    info "hostapd not installed (OK if using NetworkManager)"
fi

# Check Python and Flask
if [ -d /opt/ossuary/venv ]; then
    pass "Python venv exists"
    if /opt/ossuary/venv/bin/python3 -c "import flask" 2>/dev/null; then
        pass "Flask installed in venv"
    else
        fail "Flask not found in venv"
    fi
else
    info "No venv found - checking system Python"
    if python3 -c "import flask" 2>/dev/null; then
        pass "Flask installed system-wide"
    else
        fail "Flask not installed"
    fi
fi

echo ""
echo "TEST 3: Network Configuration"
echo "-----------------------------"

# Check WiFi interface
if ip link show wlan0 &>/dev/null; then
    pass "wlan0 interface exists"

    # Check if it supports AP mode
    if iw list | grep -q "AP"; then
        pass "wlan0 supports AP mode"
    else
        fail "wlan0 doesn't support AP mode"
    fi
else
    fail "wlan0 interface not found"
fi

# Check IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]; then
    pass "IP forwarding enabled"
else
    fail "IP forwarding disabled"
fi

echo ""
echo "TEST 4: Captive Portal Functionality"
echo "------------------------------------"

# Test if we can create an AP with NetworkManager
info "Testing NetworkManager AP creation..."
nmcli con add type wifi ifname wlan0 con-name test-ap \
    autoconnect no ssid "TEST-AP" mode ap \
    ipv4.method shared ipv4.addresses 192.168.99.1/24 \
    ipv6.method disabled &>/dev/null

if [ $? -eq 0 ]; then
    pass "Can create AP connection with NetworkManager"
    nmcli con delete test-ap &>/dev/null
else
    fail "Cannot create AP with NetworkManager"
fi

echo ""
echo "TEST 5: DNS and DHCP Configuration"
echo "-----------------------------------"

# Check dnsmasq configuration
if [ -d /etc/dnsmasq.d ]; then
    pass "/etc/dnsmasq.d directory exists"
else
    fail "/etc/dnsmasq.d directory missing"
fi

# Test dnsmasq syntax
dnsmasq --test 2>/dev/null
if [ $? -eq 0 ]; then
    pass "dnsmasq configuration valid"
else
    fail "dnsmasq configuration has errors"
fi

echo ""
echo "TEST 6: Firewall Rules"
echo "----------------------"

# Check if iptables is available
if command -v iptables &> /dev/null; then
    pass "iptables available"

    # Check for iptables-persistent
    if systemctl list-unit-files | grep -q iptables-persistent; then
        pass "iptables-persistent installed"
    else
        info "iptables-persistent not installed (rules won't persist)"
    fi
else
    fail "iptables not available"
fi

# Check nftables (modern alternative)
if command -v nft &> /dev/null; then
    info "nftables available (modern firewall)"
else
    info "nftables not available"
fi

echo ""
echo "TEST 7: Web Interface"
echo "---------------------"

# Test Flask app syntax
if [ -f /opt/ossuary/web/app.py ]; then
    python3 -m py_compile /opt/ossuary/web/app.py 2>/dev/null
    if [ $? -eq 0 ]; then
        pass "Flask app syntax valid"
    else
        fail "Flask app has syntax errors"
    fi
else
    fail "Flask app not found"
fi

# Test if port 8080 is available
if ! netstat -tlpn | grep -q ":8080"; then
    pass "Port 8080 available"
else
    info "Port 8080 already in use"
fi

echo ""
echo "TEST 8: Service Status"
echo "----------------------"

# Check Ossuary services
for service in ossuary-nm-monitor ossuary-wifi-monitor ossuary-captive-portal; do
    if systemctl list-unit-files | grep -q "$service"; then
        if systemctl is-active --quiet "$service"; then
            pass "$service is running"
        else
            info "$service exists but not running"
        fi
    else
        info "$service not installed"
    fi
done

echo ""
echo "TEST 9: Connectivity Check"
echo "--------------------------"

# Check current network state
CONNECTIVITY=$(nmcli networking connectivity check 2>/dev/null)
case "$CONNECTIVITY" in
    full)
        pass "Full network connectivity"
        ;;
    limited)
        info "Limited connectivity (captive portal?)"
        ;;
    portal)
        info "Behind captive portal"
        ;;
    none)
        fail "No network connectivity"
        ;;
    *)
        info "Unknown connectivity state: $CONNECTIVITY"
        ;;
esac

echo ""
echo "TEST 10: Quick AP Test (Non-Destructive)"
echo "----------------------------------------"

info "Checking if we can query NetworkManager for AP capabilities..."
nmcli device wifi list &>/dev/null
if [ $? -eq 0 ]; then
    pass "Can scan for WiFi networks"
else
    fail "Cannot scan WiFi networks"
fi

echo ""
echo "==========================================="
echo "    Test Suite Complete"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. If all core tests pass, try: sudo systemctl start ossuary-nm-monitor"
echo "2. Monitor logs: sudo journalctl -fu ossuary-nm-monitor"
echo "3. Check portal at: http://192.168.4.1:8080 when AP is active"
echo ""
echo "To force AP mode for testing:"
echo "  sudo nmcli device disconnect wlan0"
echo "  Wait 60 seconds for captive portal to activate"