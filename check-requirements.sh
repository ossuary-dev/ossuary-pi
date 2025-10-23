#!/bin/bash

# System requirements checker for Ossuary

echo "==========================================="
echo "    Ossuary System Requirements Check"
echo "==========================================="
echo ""

ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

echo "Checking system requirements..."
echo ""

# Check if running on Linux
echo -n "Operating System: "
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    check_pass "Linux detected"
else
    check_fail "Not running on Linux (found: $OSTYPE)"
fi

# Check if Raspberry Pi
echo -n "Hardware: "
if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    MODEL=$(grep "Model" /proc/cpuinfo | cut -d: -f2 | xargs)
    check_pass "Raspberry Pi detected ($MODEL)"
elif [ -f /proc/cpuinfo ]; then
    check_warn "Not a Raspberry Pi (generic Linux system)"
else
    check_fail "Unable to detect hardware"
fi

# Check for WiFi interface
echo -n "WiFi Interface: "
if ip link show wlan0 &>/dev/null; then
    check_pass "wlan0 interface found"
elif ip link | grep -q "wlan"; then
    WLAN=$(ip link | grep "wlan" | head -1 | cut -d: -f2 | xargs)
    check_warn "Found WiFi interface: $WLAN (expected wlan0)"
else
    check_fail "No WiFi interface found"
fi

# Check Python version
echo -n "Python 3: "
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

    if [[ $PYTHON_MAJOR -ge 3 ]] && [[ $PYTHON_MINOR -ge 7 ]]; then
        check_pass "Version $PYTHON_VERSION"
    else
        check_fail "Version $PYTHON_VERSION (requires 3.7+)"
    fi
else
    check_fail "Python 3 not installed"
fi

# Check for pip3
echo -n "pip3: "
if command -v pip3 &>/dev/null; then
    check_pass "Installed"
else
    check_fail "Not installed"
fi

# Check for systemd
echo -n "systemd: "
if command -v systemctl &>/dev/null; then
    check_pass "Available"
else
    check_fail "Not available (systemd required)"
fi

# Check for required network tools
echo ""
echo "Network tools:"

for tool in iwlist iwgetid wpa_cli hostapd dnsmasq; do
    echo -n "  $tool: "
    if command -v $tool &>/dev/null; then
        check_pass "Available"
    else
        check_warn "Not installed (will be installed during setup)"
    fi
done

# Check for git (for submodules)
echo -n "git: "
if command -v git &>/dev/null; then
    check_pass "Available"
else
    check_fail "Not installed (required for installation)"
fi

# Check disk space
echo ""
echo -n "Disk Space: "
AVAILABLE=$(df / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -gt 524288 ]; then # 512MB in KB
    check_pass "$(( AVAILABLE / 1024 ))MB available"
else
    check_fail "Only $(( AVAILABLE / 1024 ))MB available (need at least 512MB)"
fi

# Check if running as root
echo -n "Permissions: "
if [[ $EUID -eq 0 ]]; then
    check_warn "Running as root"
else
    check_pass "Not running as root (will need sudo for installation)"
fi

# Check for conflicting services
echo ""
echo "Checking for conflicts:"

for service in connman network-manager wicd; do
    echo -n "  $service: "
    if systemctl is-active --quiet $service 2>/dev/null; then
        check_warn "$service is running (may conflict with WiFi management)"
    else
        check_pass "Not running"
    fi
done

# Summary
echo ""
echo "==========================================="
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}All checks passed!${NC}"
        echo "Your system is ready for Ossuary installation."
    else
        echo -e "${YELLOW}Checks passed with $WARNINGS warning(s)${NC}"
        echo "Installation can proceed, but review warnings above."
    fi
    exit 0
else
    echo -e "${RED}$ERRORS error(s) found${NC}"
    echo "Please resolve the issues above before installing."
    exit 1
fi