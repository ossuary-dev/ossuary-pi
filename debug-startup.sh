#!/bin/bash

# Debug script for startup command issues

echo "================================"
echo "  Startup Service Diagnostics"
echo "================================"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "Run with sudo for full diagnostics"
   exit 1
fi

echo "1. Service Status:"
echo "-----------------"
systemctl status ossuary-startup.service --no-pager

echo ""
echo "2. Service File:"
echo "---------------"
if [ -f /etc/systemd/system/ossuary-startup.service ]; then
    cat /etc/systemd/system/ossuary-startup.service
else
    echo "Service file not found!"
fi

echo ""
echo "3. Recent Logs:"
echo "--------------"
journalctl -u ossuary-startup.service -n 20 --no-pager

echo ""
echo "4. Config File:"
echo "--------------"
if [ -f /etc/ossuary/config.json ]; then
    cat /etc/ossuary/config.json
else
    echo "Config file not found!"
fi

echo ""
echo "5. User Check:"
echo "-------------"
echo "Users with UID >= 1000:"
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1 " (UID: " $3 ")"}'

echo ""
echo "6. Test Command:"
echo "---------------"
echo "To test a command manually:"
echo "  sudo -u <username> /bin/bash -c 'your command here'"
echo ""
echo "To restart the service:"
echo "  sudo systemctl restart ossuary-startup"
echo ""
echo "To see live logs:"
echo "  sudo journalctl -fu ossuary-startup"