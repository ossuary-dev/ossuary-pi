#!/bin/bash

# Fix ossuary services startup issues
# Quick script to diagnose and fix the display service dependency problem

set -e

echo "=== Ossuary Service Diagnostic and Fix ==="
echo

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "1. Checking service files..."
for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-display ossuary-kiosk; do
    if [[ -f "/etc/systemd/system/${service}.service" ]]; then
        echo "✓ ${service}.service exists"
    else
        echo "✗ ${service}.service MISSING"
    fi
done

echo
echo "2. Checking service enablement status..."
for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-display ossuary-kiosk; do
    if systemctl is-enabled "$service" &>/dev/null; then
        echo "✓ $service is enabled"
    else
        echo "✗ $service is NOT enabled - fixing..."
        systemctl enable "$service"
    fi
done

echo
echo "3. Reloading systemd daemon..."
systemctl daemon-reload

echo
echo "4. Checking service status and starting in correct order..."

# Start services in dependency order
services_order=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-display" "ossuary-kiosk")

for service in "${services_order[@]}"; do
    echo "Starting $service..."
    if systemctl start "$service"; then
        echo "✓ $service started successfully"
        # Give it a moment to settle
        sleep 2
    else
        echo "✗ $service failed to start - checking logs..."
        echo "Last 5 lines from $service:"
        journalctl -u "$service" -n 5 --no-pager || echo "No logs available"
        echo
    fi
done

echo
echo "5. Final status check..."
for service in "${services_order[@]}"; do
    if systemctl is-active "$service" &>/dev/null; then
        echo "✓ $service is running"
    else
        echo "✗ $service is NOT running"
    fi
done

echo
echo "=== Fix Complete ==="
echo "If any services are still failing, check logs with:"
echo "  sudo journalctl -u [service-name] -f"
echo
echo "Or use: sudo ossuaryctl logs"