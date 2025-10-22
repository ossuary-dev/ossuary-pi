#!/bin/bash

# Debug script specifically for display service issues
# This will diagnose why ossuary-display service is failing

set -e

echo "=== Ossuary Display Service Debug Tool ==="
echo

echo "1. Display Service File Check"
echo "============================"
if [[ -f "/etc/systemd/system/ossuary-display.service" ]]; then
    echo "✓ Service file exists"
    echo "Service file contents:"
    cat /etc/systemd/system/ossuary-display.service
else
    echo "✗ Service file MISSING at /etc/systemd/system/ossuary-display.service"
    echo "This is the problem - service file was not installed!"
    exit 1
fi

echo
echo "2. Display Service Binary Check"
echo "==============================="
if [[ -f "/opt/ossuary/bin/ossuary-display" ]]; then
    echo "✓ Binary exists"
    if [[ -x "/opt/ossuary/bin/ossuary-display" ]]; then
        echo "✓ Binary is executable"
    else
        echo "✗ Binary is NOT executable"
        echo "Fixing permissions..."
        sudo chmod +x "/opt/ossuary/bin/ossuary-display"
        echo "✓ Fixed permissions"
    fi
    echo "Binary contents (first 10 lines):"
    head -10 /opt/ossuary/bin/ossuary-display
else
    echo "✗ Binary MISSING at /opt/ossuary/bin/ossuary-display"
    echo "This is the problem - binary was not installed!"
    exit 1
fi

echo
echo "3. Display Service Source Check"
echo "==============================="
if [[ -f "/opt/ossuary/src/display/service.py" ]]; then
    echo "✓ Source exists"
    echo "Source file size: $(stat -c%s /opt/ossuary/src/display/service.py) bytes"
else
    echo "✗ Source MISSING at /opt/ossuary/src/display/service.py"
    echo "This is the problem - source was not installed!"
    exit 1
fi

echo
echo "4. Python Virtual Environment Check"
echo "==================================="
if [[ -f "/opt/ossuary/venv/bin/python" ]]; then
    echo "✓ Virtual environment exists"
    echo "Python version:"
    /opt/ossuary/venv/bin/python --version
else
    echo "✗ Virtual environment MISSING at /opt/ossuary/venv"
    echo "This is the problem - venv was not created!"
    exit 1
fi

echo
echo "5. Display Service Status"
echo "========================="
echo "Service enabled status:"
if systemctl is-enabled ossuary-display &>/dev/null; then
    echo "✓ Service is enabled"
else
    echo "✗ Service is NOT enabled"
    echo "Enabling service..."
    sudo systemctl enable ossuary-display
    echo "✓ Service enabled"
fi

echo
echo "Service active status:"
if systemctl is-active ossuary-display &>/dev/null; then
    echo "✓ Service is running"
else
    echo "✗ Service is NOT running"
fi

echo
echo "Service detailed status:"
systemctl status ossuary-display --no-pager || echo "Status command failed"

echo
echo "6. Display Service Dependencies"
echo "==============================="
echo "Service dependencies:"
systemctl list-dependencies ossuary-display --no-pager || echo "Failed to list dependencies"

echo
echo "7. Display Service Logs"
echo "======================="
echo "Recent logs:"
journalctl -u ossuary-display -n 20 --no-pager || echo "No logs available"

echo
echo "8. Manual Service Test"
echo "======================"
echo "Attempting to start service manually..."
if sudo systemctl start ossuary-display; then
    echo "✓ Service started successfully"
    sleep 3
    if systemctl is-active ossuary-display &>/dev/null; then
        echo "✓ Service is still running after 3 seconds"
    else
        echo "✗ Service stopped after starting"
        echo "Recent logs after start attempt:"
        journalctl -u ossuary-display -n 10 --no-pager
    fi
else
    echo "✗ Failed to start service"
    echo "Error logs:"
    journalctl -u ossuary-display -n 10 --no-pager
fi

echo
echo "9. System Prerequisites"
echo "======================="
echo "Checking system requirements..."

echo "X11 packages:"
if dpkg -l | grep -q xorg; then
    echo "✓ Xorg packages installed"
else
    echo "✗ Xorg packages may be missing"
fi

echo "Display environment:"
echo "DISPLAY: ${DISPLAY:-Not set}"
echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-Not set}"

echo "Running X servers:"
ps aux | grep -E '[X]org|[W]ayland' || echo "No display servers running"

echo
echo "=== Debug Complete ==="
echo
echo "If the service is still failing, the most common issues are:"
echo "1. Missing service file (check section 1)"
echo "2. Missing binary or wrong permissions (check section 2)"
echo "3. Missing Python dependencies (check section 4)"
echo "4. Missing display packages on Pi OS Lite (run install script)"
echo
echo "To fix missing files, re-run: sudo ./install.sh"