#!/bin/bash

# Debug script specifically for kiosk issues
# Provides comprehensive kiosk status and troubleshooting info

set -e

echo "=== Ossuary Kiosk Debug Tool ==="
echo

echo "1. Kiosk Service Status"
echo "========================"
systemctl status ossuary-kiosk --no-pager || echo "Kiosk service not found or failed"

echo
echo "2. Display Service Status"
echo "========================="
systemctl status ossuary-display --no-pager || echo "Display service not found or failed"

echo
echo "3. Recent Kiosk Logs (last 20 lines)"
echo "====================================="
journalctl -u ossuary-kiosk -n 20 --no-pager || echo "No kiosk logs available"

echo
echo "4. Recent Display Logs (last 10 lines)"
echo "======================================="
journalctl -u ossuary-display -n 10 --no-pager || echo "No display logs available"

echo
echo "5. Process Status"
echo "================="
echo "Kiosk processes:"
ps aux | grep ossuary-kiosk | grep -v grep || echo "No kiosk processes running"

echo
echo "Chromium processes:"
ps aux | grep chromium | grep -v grep || echo "No chromium processes running"

echo
echo "6. Display Environment"
echo "====================="
echo "DISPLAY variable: ${DISPLAY:-Not set}"
echo "Xorg processes:"
ps aux | grep Xorg | grep -v grep || echo "No Xorg processes running"

echo
echo "7. Screen/Monitor Detection"
echo "=========================="
if command -v xrandr >/dev/null && [[ -n "$DISPLAY" ]]; then
    echo "Connected displays:"
    xrandr --query 2>/dev/null || echo "Failed to query displays"
else
    echo "xrandr not available or DISPLAY not set"
fi

echo
echo "8. Kiosk Configuration"
echo "====================="
if [[ -f "/etc/ossuary/config.json" ]]; then
    echo "Kiosk config from /etc/ossuary/config.json:"
    python3 -c "
import json
try:
    with open('/etc/ossuary/config.json', 'r') as f:
        config = json.load(f)
    kiosk = config.get('kiosk', {})
    print(f'URL: {kiosk.get(\"url\", \"Not set\")}')
    print(f'Default URL: {kiosk.get(\"default_url\", \"Not set\")}')
    print(f'WebGL: {kiosk.get(\"enable_webgl\", \"Not set\")}')
    print(f'WebGPU: {kiosk.get(\"enable_webgpu\", \"Not set\")}')
    print(f'Refresh interval: {kiosk.get(\"refresh_interval\", \"Not set\")}')
except Exception as e:
    print(f'Error reading config: {e}')
"
else
    echo "Configuration file not found at /etc/ossuary/config.json"
fi

echo
echo "9. Service Dependencies"
echo "======================"
echo "ossuary-kiosk dependencies:"
systemctl list-dependencies ossuary-kiosk --no-pager 2>/dev/null || echo "Failed to list dependencies"

echo
echo "10. Network Status (for portal access)"
echo "======================================"
echo "Active network connections:"
nmcli connection show --active 2>/dev/null || echo "NetworkManager not available"

echo
echo "=== Debug Commands You Can Run ==="
echo
echo "Live kiosk logs:"
echo "  sudo journalctl -u ossuary-kiosk -f"
echo
echo "Live display logs:"
echo "  sudo journalctl -u ossuary-display -f"
echo
echo "Restart kiosk service:"
echo "  sudo systemctl restart ossuary-kiosk"
echo
echo "Restart display service:"
echo "  sudo systemctl restart ossuary-display"
echo
echo "Check all ossuary services:"
echo "  sudo ossuaryctl status"
echo
echo "Manual kiosk start (for debugging):"
echo "  sudo DISPLAY=:0 /opt/ossuary/venv/bin/python /opt/ossuary/bin/ossuary-kiosk"