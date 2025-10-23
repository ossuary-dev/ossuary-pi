#!/bin/bash

# Ossuary Test Script - Verify installation

echo "==========================================="
echo "    Ossuary Installation Test"
echo "==========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

ERRORS=0

# Must run as root
if [[ $EUID -ne 0 ]]; then
   echo "Run with sudo for full tests"
   exit 1
fi

echo "1. CHECKING INSTALLATION"
echo "------------------------"

# Check directories
if [ -d "/opt/ossuary" ]; then
    pass "/opt/ossuary exists"
else
    fail "/opt/ossuary missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "/etc/ossuary/config.json" ]; then
    pass "Config file exists"
else
    fail "Config file missing"
    ERRORS=$((ERRORS + 1))
fi

# Check Python venv
if [ -d "/opt/ossuary/venv" ]; then
    pass "Python venv exists"
    if /opt/ossuary/venv/bin/python3 -c "import flask" 2>/dev/null; then
        pass "Flask installed"
    else
        fail "Flask not installed"
        ERRORS=$((ERRORS + 1))
    fi
else
    fail "Python venv missing"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "2. CHECKING SERVICES"
echo "--------------------"

# Check raspi-captive-portal components
for service in hostapd dnsmasq; do
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        pass "$service installed"
    else
        fail "$service not installed"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check our monitor
if systemctl list-unit-files | grep -q "^ossuary-monitor.service"; then
    pass "ossuary-monitor installed"
    if systemctl is-active --quiet ossuary-monitor; then
        pass "ossuary-monitor running"
    else
        warn "ossuary-monitor not running"
    fi
else
    fail "ossuary-monitor not installed"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "3. CHECKING NETWORK"
echo "-------------------"

# Check WiFi interface
if ip link show wlan0 &>/dev/null; then
    pass "wlan0 interface found"
else
    fail "wlan0 not found"
    ERRORS=$((ERRORS + 1))
fi

# Check current connectivity
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    pass "Internet connectivity OK"
else
    warn "No internet (might be in AP mode)"
fi

echo ""
echo "4. CHECKING WEB APP"
echo "-------------------"

# Check Flask app
if [ -f "/opt/ossuary/web/app.py" ]; then
    pass "Flask app exists"
    if python3 -m py_compile /opt/ossuary/web/app.py 2>/dev/null; then
        pass "Flask app syntax OK"
    else
        fail "Flask app has errors"
        ERRORS=$((ERRORS + 1))
    fi
else
    fail "Flask app missing"
    ERRORS=$((ERRORS + 1))
fi

# Check if web interface is accessible
if curl -s -f http://localhost:3000 &>/dev/null; then
    pass "Flask responding on port 3000"
elif curl -s -f http://localhost &>/dev/null; then
    pass "Web interface responding via iptables redirect"
elif curl -s -f http://192.168.4.1 &>/dev/null; then
    pass "Web interface responding (AP mode)"
else
    warn "Web interface not responding"
fi

echo ""
echo "==========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}$ERRORS test(s) failed${NC}"
fi
echo ""
echo "Monitor logs: journalctl -fu ossuary-monitor"
echo "Force AP mode: systemctl stop wpa_supplicant"