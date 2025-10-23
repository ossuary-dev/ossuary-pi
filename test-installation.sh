#!/bin/bash

# Test script to verify Ossuary installation

echo "==========================================="
echo "    Ossuary Installation Test"
echo "==========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}✗${NC} $1: $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Testing installation..."
echo ""

# Test 1: Check directories
echo "Checking directories:"
if [ -d "/opt/ossuary" ]; then
    test_pass "/opt/ossuary exists"
else
    test_fail "/opt/ossuary" "Directory not found"
fi

if [ -d "/etc/ossuary" ]; then
    test_pass "/etc/ossuary exists"
else
    test_fail "/etc/ossuary" "Directory not found"
fi

# Test 2: Check configuration file
echo ""
echo "Checking configuration:"
if [ -f "/etc/ossuary/config.json" ]; then
    test_pass "config.json exists"

    # Validate JSON
    if python3 -c "import json; json.load(open('/etc/ossuary/config.json'))" 2>/dev/null; then
        test_pass "config.json is valid JSON"
    else
        test_fail "config.json" "Invalid JSON format"
    fi
else
    test_fail "config.json" "File not found"
fi

# Test 3: Check Python scripts
echo ""
echo "Checking Python scripts:"

for script in "/opt/ossuary/services/wifi_monitor.py" "/opt/ossuary/web/app.py"; do
    if [ -f "$script" ]; then
        if python3 -m py_compile "$script" 2>/dev/null; then
            test_pass "$(basename $script) syntax OK"
        else
            test_fail "$(basename $script)" "Syntax error"
        fi
    else
        test_fail "$(basename $script)" "File not found"
    fi
done

# Test 4: Check systemd services
echo ""
echo "Checking systemd services:"

for service in ossuary-wifi-monitor ossuary-captive-portal ossuary-startup; do
    if [ -f "/etc/systemd/system/${service}.service" ]; then
        test_pass "${service}.service installed"

        # Check if service is loaded
        if systemctl list-unit-files | grep -q "${service}.service"; then
            test_pass "${service}.service loaded"
        else
            test_fail "${service}.service" "Not loaded by systemd"
        fi
    else
        test_fail "${service}.service" "Service file not found"
    fi
done

# Test 5: Check service status
echo ""
echo "Checking service status:"

if systemctl is-active --quiet ossuary-wifi-monitor; then
    test_pass "WiFi monitor service is running"
else
    test_warn "WiFi monitor service is not running"
fi

# Test 6: Check network configuration
echo ""
echo "Checking network configuration:"

if [ -f "/etc/hostapd/hostapd.conf" ]; then
    test_pass "hostapd configuration exists"
else
    test_fail "hostapd.conf" "File not found"
fi

if [ -f "/etc/dnsmasq.conf" ]; then
    test_pass "dnsmasq configuration exists"
else
    test_fail "dnsmasq.conf" "File not found"
fi

# Test 7: Check Python dependencies
echo ""
echo "Checking Python dependencies:"

if python3 -c "import flask" 2>/dev/null; then
    test_pass "Flask is installed"
else
    test_fail "Flask" "Module not found"
fi

# Test 8: Test web interface
echo ""
echo "Testing web interface:"

# Try to connect to the web interface
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q "200\|302"; then
    test_pass "Web interface is responsive"
else
    test_warn "Web interface not responding (may not be running)"
fi

# Test 9: Check permissions
echo ""
echo "Checking permissions:"

if [ -x "/opt/ossuary/services/wifi_monitor.py" ]; then
    test_pass "wifi_monitor.py is executable"
else
    test_fail "wifi_monitor.py" "Not executable"
fi

if [ -x "/opt/ossuary/services/captive_portal_wrapper.sh" ]; then
    test_pass "captive_portal_wrapper.sh is executable"
else
    test_fail "captive_portal_wrapper.sh" "Not executable"
fi

# Test 10: Check IP forwarding
echo ""
echo "Checking system configuration:"

if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    test_pass "IP forwarding configured"
else
    test_warn "IP forwarding not configured"
fi

# Summary
echo ""
echo "==========================================="
echo "Test Results:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo "Ossuary is properly installed."
    exit 0
else
    echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
    echo "Please review the errors above."
    exit 1
fi