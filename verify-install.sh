#!/bin/bash

# Comprehensive verification script for Ossuary Pi installation
# Ensures ALL critical fixes have been properly applied

echo "=== Ossuary Pi Installation Verification ==="
echo "Checking that all critical fixes are properly installed..."
echo

ERRORS=0
WARNINGS=0

error() {
    echo "✗ ERROR: $1"
    ((ERRORS++))
}

warning() {
    echo "⚠ WARNING: $1"
    ((WARNINGS++))
}

success() {
    echo "✓ $1"
}

check_file() {
    local file="$1"
    local description="$2"

    if [[ -f "$file" ]]; then
        success "$description exists: $file"
        return 0
    else
        error "$description MISSING: $file"
        return 1
    fi
}

check_service() {
    local service="$1"

    if systemctl list-unit-files | grep -q "${service}.service"; then
        success "Service exists: $service"

        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            success "Service enabled: $service"
        else
            warning "Service not enabled: $service"
        fi

        return 0
    else
        error "Service MISSING: $service"
        return 1
    fi
}

echo "1. Critical Service Files"
echo "========================"
check_file "/opt/ossuary/bin/ossuary-display" "Display service binary"
check_file "/opt/ossuary/bin/ossuary-kiosk" "Kiosk service binary"
check_file "/usr/local/bin/ossuaryctl" "Service control script"

echo
echo "2. SystemD Service Files"
echo "======================="
check_service "ossuary-config"
check_service "ossuary-display"
check_service "ossuary-netd"
check_service "ossuary-api"
check_service "ossuary-portal"
check_service "ossuary-kiosk"

echo
echo "3. Display Service Fixes"
echo "======================="

# Check display service binary has proper imports
if [[ -f "/opt/ossuary/bin/ossuary-display" ]]; then
    if grep -q "from common.logging import" "/opt/ossuary/bin/ossuary-display"; then
        error "Display service still has BAD import 'from common.logging'"
    else
        success "Display service imports fixed (no common.logging)"
    fi

    if grep -q "logging.basicConfig" "/opt/ossuary/bin/ossuary-display"; then
        success "Display service uses proper logging.basicConfig"
    else
        warning "Display service may not have proper logging setup"
    fi
else
    error "Cannot check display service - binary missing"
fi

echo
echo "4. ossuaryctl Service List"
echo "========================"

if [[ -f "/usr/local/bin/ossuaryctl" ]]; then
    if grep -q "ossuary-display" "/usr/local/bin/ossuaryctl"; then
        success "ossuaryctl includes display service"
    else
        error "ossuaryctl MISSING display service in services list"
    fi

    # Check services array
    echo "Services in ossuaryctl:"
    grep -A 10 'SERVICES=(' "/usr/local/bin/ossuaryctl" | grep '"ossuary-' | while read line; do
        service=$(echo "$line" | grep -o 'ossuary-[^"]*')
        echo "  - $service"
    done
else
    error "ossuaryctl binary missing"
fi

echo
echo "5. Source Files"
echo "=============="
check_file "/opt/ossuary/src/display/service.py" "Display service source"
check_file "/opt/ossuary/src/kiosk/service.py" "Kiosk service source"

echo
echo "6. Configuration Files"
echo "====================="
check_file "/opt/ossuary/config/default.json" "Default configuration"

# Check AP password
if [[ -f "/opt/ossuary/config/default.json" ]]; then
    if grep -q '"ap_passphrase": "ossuarypi"' "/opt/ossuary/config/default.json"; then
        success "AP password set to 'ossuarypi'"
    else
        warning "AP password may not be set correctly"
    fi
fi

echo
echo "7. Virtual Environment"
echo "===================="
check_file "/opt/ossuary/venv/bin/python" "Python virtual environment"

if [[ -f "/opt/ossuary/venv/bin/python" ]]; then
    echo "Python version: $(/opt/ossuary/venv/bin/python --version)"
fi

echo
echo "8. Permissions Check"
echo "==================="

for file in "/opt/ossuary/bin/ossuary-display" "/opt/ossuary/bin/ossuary-kiosk" "/usr/local/bin/ossuaryctl"; do
    if [[ -f "$file" ]]; then
        if [[ -x "$file" ]]; then
            success "Executable: $(basename "$file")"
        else
            error "NOT executable: $file"
        fi
    fi
done

echo
echo "9. Service Dependencies"
echo "======================"

if systemctl list-dependencies ossuary-kiosk 2>/dev/null | grep -q ossuary-display; then
    success "Kiosk service depends on display service"
else
    error "Kiosk service MISSING display service dependency"
fi

echo
echo "10. Test Service Control"
echo "======================="

if command -v ossuaryctl >/dev/null; then
    success "ossuaryctl command available"

    echo "Testing ossuaryctl status..."
    if ossuaryctl status >/dev/null 2>&1; then
        success "ossuaryctl status command works"
    else
        warning "ossuaryctl status command failed"
    fi
else
    error "ossuaryctl command not found in PATH"
fi

echo
echo "=== Verification Summary ==="
if [[ $ERRORS -eq 0 ]]; then
    echo -e "\033[0;32m✓ ALL CHECKS PASSED\033[0m"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "\033[1;33m⚠ $WARNINGS warnings (non-critical)\033[0m"
    fi
    echo
    echo "Installation appears to be correct!"
    echo "You can now test with: sudo ossuaryctl status"
else
    echo -e "\033[0;31m✗ $ERRORS CRITICAL ERRORS FOUND\033[0m"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "\033[1;33m⚠ $WARNINGS warnings\033[0m"
    fi
    echo
    echo "INSTALLATION IS INCOMPLETE OR BROKEN!"
    echo "Re-run the installer to fix these issues."
    exit 1
fi