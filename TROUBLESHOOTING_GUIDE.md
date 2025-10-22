# Ossuary Troubleshooting Guide

## Overview
This guide provides comprehensive troubleshooting information for diagnosing and resolving issues with the Ossuary system. Issues are organized by service and symptom for quick resolution.

---

## Quick Diagnostic Commands

### System Status Check
```bash
# Check all service status
sudo systemctl status ossuary-*

# View recent logs
sudo journalctl -u ossuary-* --since "10 minutes ago" -f

# Check configuration
python3 -c "
from src.config.manager import ConfigManager
cm = ConfigManager()
config = cm.load_config()
print('Config loaded successfully')
"

# Network connectivity
ping -c 3 8.8.8.8
nmcli device wifi list
```

### Quick Health Check
```bash
# API Gateway health
curl -s http://localhost:8080/health

# Portal health
curl -s http://localhost:80/ | head -n 10

# Check processes
ps aux | grep -E "(ossuary|chromium|NetworkManager)"
```

---

## Service-Specific Troubleshooting

## 1. ossuary-config (Configuration Manager)

### Symptoms
- Services fail to start with configuration errors
- File watcher not detecting config changes
- Configuration validation failures

### Diagnostic Commands
```bash
# Check service status
sudo systemctl status ossuary-config

# View configuration logs
sudo journalctl -u ossuary-config --since "1 hour ago"

# Validate configuration manually
python3 -c "
from src.config.schema import Config
import json
with open('/etc/ossuary/config.json') as f:
    config = Config(**json.load(f))
print('Configuration is valid')
"

# Check file permissions
ls -la /etc/ossuary/config.json
```

### Common Issues

#### Issue: "Configuration file not found"
**Symptoms**: Service fails to start, "No such file or directory" errors
**Solution**:
```bash
# Create default configuration
sudo mkdir -p /etc/ossuary
sudo cp config/default.json /etc/ossuary/config.json
sudo chmod 644 /etc/ossuary/config.json
sudo systemctl restart ossuary-config
```

#### Issue: "AsyncIO Event Loop Error"
**Symptoms**: "RuntimeError: no running event loop" in logs
**Status**: ✅ FIXED - Thread-safe event loop handling implemented
**Verification**:
```bash
# Should not see event loop errors after fix
sudo journalctl -u ossuary-config | grep -i "event loop"
```

#### Issue: Configuration validation errors
**Symptoms**: "ValidationError" in logs, services using default values
**Solution**:
```bash
# Check configuration syntax
python3 -c "
import json
with open('/etc/ossuary/config.json') as f:
    json.load(f)
print('JSON syntax valid')
"

# Restore from backup if available
ls /etc/ossuary/backups/
sudo cp /etc/ossuary/backups/config_LATEST.json /etc/ossuary/config.json
```

---

## 2. ossuary-netd (Network Manager)

### Symptoms
- WiFi scanning fails
- Cannot connect to networks
- NetworkManager signal errors
- Access point mode not working

### Diagnostic Commands
```bash
# Check NetworkManager status
sudo systemctl status NetworkManager
nmcli general status

# Check WiFi device
nmcli device show
nmcli device wifi list

# Check service logs
sudo journalctl -u ossuary-netd --since "30 minutes ago"

# Test NetworkManager connection
nmcli device wifi connect "SSID" password "password"
```

### Common Issues

#### Issue: "Failed to connect device state signal"
**Symptoms**: WARNING messages about NetworkManager signal connections
**Status**: ✅ FIXED - Replaced with polling-based monitoring
**Verification**:
```bash
# Should not see signal connection warnings after fix
sudo journalctl -u ossuary-netd | grep -i "signal"
```

#### Issue: "No WiFi device found"
**Symptoms**: Cannot scan networks, "No WiFi device available"
**Solution**:
```bash
# Check WiFi hardware
lsusb | grep -i wireless
lshw -C network

# Check driver status
lsmod | grep -E "(brcm|rtl|ath|iwl)"

# Restart NetworkManager
sudo systemctl restart NetworkManager
sleep 5
sudo systemctl restart ossuary-netd
```

#### Issue: Access point mode fails
**Symptoms**: Cannot create hotspot, "Failed to start AP" errors
**Solution**:
```bash
# Check if device supports AP mode
iw list | grep -A 5 "Supported interface modes"

# Check for conflicting connections
nmcli connection show --active
nmcli connection down "connection-name"

# Manually test AP creation
nmcli device wifi hotspot ifname wlan0 ssid test password test123
```

#### Issue: Connection timeout
**Symptoms**: "Connection timed out" after 30 seconds
**Configuration Fix**:
```json
{
  "network": {
    "connection_timeout": 60,
    "fallback_timeout": 900
  }
}
```

---

## 3. ossuary-api (API Gateway)

### Symptoms
- API endpoints not responding
- WebSocket connection failures
- Authentication errors
- CORS issues

### Diagnostic Commands
```bash
# Check API service
sudo systemctl status ossuary-api
curl -v http://localhost:8080/health

# Check port binding
netstat -tlnp | grep 8080
ss -tlnp | grep 8080

# Test specific endpoints
curl http://localhost:8080/api/v1/system/info
curl http://localhost:8080/api/v1/network/status

# Check logs
sudo journalctl -u ossuary-api --since "15 minutes ago"
```

### Common Issues

#### Issue: "Address already in use"
**Symptoms**: Service fails to start, port 8080 already bound
**Solution**:
```bash
# Find process using port
sudo lsof -i :8080
sudo netstat -tlnp | grep :8080

# Kill conflicting process
sudo kill -9 <PID>

# Or change port in configuration
{
  "api": {
    "bind_port": 8081
  }
}
```

#### Issue: API returns 500 errors
**Symptoms**: Internal server errors, failed API calls
**Diagnostic**:
```bash
# Check detailed logs
sudo journalctl -u ossuary-api --since "1 hour ago" | grep ERROR

# Test dependency services
curl http://localhost:8080/api/v1/network/status
sudo systemctl status ossuary-netd
```

#### Issue: CORS errors in browser
**Symptoms**: Browser console shows CORS policy errors
**Solution**:
```json
{
  "api": {
    "cors_enabled": true
  }
}
```

#### Issue: WebSocket connections fail with 403
**Symptoms**: "WebSocket connection rejected (403 Forbidden)"
**Status**: ✅ FIXED - WebSocket authentication bypass implemented
**Verification**:
```bash
# Test WebSocket connection
websocat ws://localhost:8080/ws
# Should connect successfully
```

---

## 4. ossuary-portal (Web Portal)

### Symptoms
- Portal webpage not loading
- Captive portal not redirecting
- Static assets not found
- Template rendering errors

### Diagnostic Commands
```bash
# Check portal service
sudo systemctl status ossuary-portal
curl -v http://localhost:80/

# Check port binding
sudo netstat -tlnp | grep :80

# Test captive portal endpoints
curl http://localhost/generate_204
curl http://localhost/hotspot-detect.html

# Check static assets
curl http://localhost/assets/app.js
curl http://localhost/assets/style.css
```

### Common Issues

#### Issue: Permission denied on port 80
**Symptoms**: "Permission denied" when binding to port 80
**Solution**:
```bash
# Run as root (current approach)
sudo systemctl restart ossuary-portal

# Or use non-privileged port
{
  "portal": {
    "bind_port": 8080
  }
}

# Or grant capability
sudo setcap CAP_NET_BIND_SERVICE=+eip /opt/ossuary/venv/bin/python
```

#### Issue: Template not found errors
**Symptoms**: "TemplateNotFound" errors in logs
**Solution**:
```bash
# Check template files exist
ls -la web/templates/
ls -la web/assets/

# Check service working directory
sudo systemctl show ossuary-portal | grep WorkingDirectory

# Fix paths in service
sudo systemctl edit ossuary-portal
# Add:
# [Service]
# WorkingDirectory=/opt/ossuary
```

#### Issue: Static assets return 404
**Symptoms**: CSS/JS files not loading, broken styling
**Solution**:
```bash
# Check static file mounting
curl -I http://localhost/assets/app.js

# Verify file permissions
ls -la web/assets/
sudo chmod -R 644 web/assets/

# Check FastAPI static mounting configuration
```

---

## 5. ossuary-kiosk (Browser Manager)

### Symptoms
- Chromium fails to start
- Black screen or display issues
- Browser crashes repeatedly
- X11 authorization errors

### Diagnostic Commands
```bash
# Check kiosk service
sudo systemctl status ossuary-kiosk

# Check display environment
echo $DISPLAY
echo $XAUTHORITY
xauth list

# Test browser manually
sudo -u root chromium-browser --version
sudo -u root chromium-browser --headless --dump-dom http://google.com

# Check X11 session
who
ps aux | grep -E "(X|Xorg|startx)"
```

### Common Issues

#### Issue: "Authorization required, but no authorization protocol specified"
**Symptoms**: Browser fails to start, X11 authorization errors
**Status**: ✅ FIXED - Dynamic XAUTHORITY detection implemented
**Verification**:
```bash
# Check X session detection
sudo python3 -c "
from src.kiosk.browser import BrowserController
bc = BrowserController({})
print('DISPLAY:', bc._detect_display())
print('XAUTHORITY:', bc._detect_xauthority())
"
```

#### Issue: "Missing X server or $DISPLAY"
**Symptoms**: Browser cannot connect to display
**Solution**:
```bash
# Check X11 is running
ps aux | grep -E "(X|Xorg)"

# Check DISPLAY variable
echo $DISPLAY
export DISPLAY=:0

# Test X11 connection
xdpyinfo
xwininfo -root

# For SSH sessions, enable X forwarding
ssh -X user@hostname
```

#### Issue: Browser process keeps crashing
**Symptoms**: Repeated restart attempts, crash logs
**Diagnostic**:
```bash
# Check browser logs
sudo journalctl -u ossuary-kiosk | grep -E "(ERROR|STDERR)"

# Test browser with minimal flags
chromium-browser --no-sandbox --disable-dev-shm-usage --headless --dump-dom http://google.com

# Check memory usage
free -h
cat /proc/meminfo | grep Available

# Check GPU acceleration
glxinfo | head -20
```

#### Issue: GPU acceleration not working
**Symptoms**: Poor performance, software rendering warnings
**Solution**:
```bash
# Check GPU driver
lsmod | grep -E "(vc4|v3d)"
cat /boot/config.txt | grep gpu

# Enable GPU acceleration
echo 'dtoverlay=vc4-kms-v3d' | sudo tee -a /boot/config.txt
echo 'gpu_mem=128' | sudo tee -a /boot/config.txt
sudo reboot

# Test WebGL
chromium-browser --enable-webgl --ignore-gpu-blocklist
```

---

## Network Connectivity Issues

### Symptoms
- Cannot reach external websites
- DNS resolution fails
- Network configuration conflicts
- IP address conflicts

### Diagnostic Commands
```bash
# Basic connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com

# DNS resolution
nslookup google.com
dig google.com

# Network configuration
ip addr show
ip route show
cat /etc/resolv.conf

# NetworkManager status
nmcli general status
nmcli device show
nmcli connection show
```

### Common Issues

#### Issue: No internet connectivity
**Solution**:
```bash
# Check default route
ip route show default

# Add default route if missing
sudo ip route add default via 192.168.1.1

# Check DNS
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

# Restart networking
sudo systemctl restart NetworkManager
```

#### Issue: AP mode conflicts with client mode
**Solution**:
```bash
# Check active connections
nmcli connection show --active

# Disable conflicting connections
nmcli connection down "connection-name"

# Use separate interface for AP if available
nmcli device wifi hotspot ifname wlan1 ssid "ossuary-setup"
```

---

## Performance Issues

### Symptoms
- Slow response times
- High CPU/memory usage
- Browser lag or freezing
- Service timeouts

### Diagnostic Commands
```bash
# System resources
top
htop
free -h
df -h

# Service-specific usage
systemctl status ossuary-*
ps aux | grep -E "ossuary|chromium"

# Network performance
iperf3 -c speedtest.net

# Browser performance
chromium-browser --enable-logging --log-level=0
```

### Common Issues

#### Issue: High memory usage
**Solution**:
```bash
# Check memory consumers
ps aux --sort=-%mem | head -10

# Optimize browser memory
{
  "kiosk": {
    "enable_webgl": false,
    "refresh_interval": 3600
  }
}

# Add swap if needed
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

#### Issue: Slow API responses
**Solution**:
```bash
# Check database size
ls -lh /var/lib/ossuary/networks.db

# Clean old history
python3 -c "
from src.config.network_db import NetworkDatabase
import asyncio
async def cleanup():
    db = NetworkDatabase()
    await db.initialize()
    removed = await db.cleanup_old_history(30)
    print(f'Removed {removed} old records')
asyncio.run(cleanup())
"

# Optimize database
sqlite3 /var/lib/ossuary/networks.db "VACUUM;"
```

---

## Configuration Issues

### Symptoms
- Invalid configuration errors
- Services using wrong settings
- Configuration not persisting
- Backup/restore failures

### Diagnostic Commands
```bash
# Validate configuration
python3 -c "
from src.config.schema import Config
import json
with open('/etc/ossuary/config.json') as f:
    Config(**json.load(f))
print('Valid')
"

# Check configuration history
ls -la /etc/ossuary/backups/

# Compare configurations
diff /etc/ossuary/config.json /etc/ossuary/backups/config_20231122_143022.json
```

### Common Issues

#### Issue: Configuration changes not taking effect
**Solution**:
```bash
# Restart dependent services
sudo systemctl restart ossuary-config
sudo systemctl restart ossuary-netd
sudo systemctl restart ossuary-api

# Force configuration reload
curl -X POST http://localhost:8080/api/v1/config/reload
```

#### Issue: Configuration file corruption
**Solution**:
```bash
# Restore from backup
sudo cp /etc/ossuary/backups/config_LATEST.json /etc/ossuary/config.json

# Or restore defaults
sudo cp config/default.json /etc/ossuary/config.json

# Validate and restart
python3 -c "import json; json.load(open('/etc/ossuary/config.json'))"
sudo systemctl restart ossuary-config
```

---

## Hardware-Specific Issues

### Raspberry Pi Model Detection Issues
```bash
# Check Pi model
cat /proc/cpuinfo | grep -E "(Revision|Model)"
cat /proc/device-tree/model

# Manual model override
{
  "kiosk": {
    "browser_binary": "chromium-browser",
    "enable_webgpu": false
  }
}
```

### Display Issues
```bash
# Check display configuration
tvservice -l
tvservice -s

# Check HDMI connection
/opt/vc/bin/tvservice -n

# Force HDMI output
echo 'hdmi_force_hotplug=1' | sudo tee -a /boot/config.txt
echo 'hdmi_drive=2' | sudo tee -a /boot/config.txt
```

### GPIO/Hardware Peripherals
```bash
# Check GPIO permissions
ls -la /dev/gpiomem
groups $USER | grep gpio

# Add user to gpio group
sudo usermod -a -G gpio ossuary
```

---

## Security Issue Resolution

### Authentication Problems
```bash
# Reset API token
python3 -c "
import secrets
token = secrets.token_urlsafe(32)
print(f'New token: {token}')
"

# Update configuration
{
  "api": {
    "auth_required": true,
    "auth_token": "new-token-here"
  }
}
```

### SSL/TLS Issues
```bash
# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout /etc/ossuary/ssl/key.pem -out /etc/ossuary/ssl/cert.pem -days 365 -nodes

# Check certificate
openssl x509 -in /etc/ossuary/ssl/cert.pem -text -noout
```

---

## Emergency Recovery Procedures

### Complete System Reset
```bash
# Stop all services
sudo systemctl stop ossuary-*

# Reset configuration
sudo cp config/default.json /etc/ossuary/config.json

# Clear database
sudo rm -f /var/lib/ossuary/networks.db

# Restart all services
sudo systemctl start ossuary-config
sudo systemctl start ossuary-netd
sudo systemctl start ossuary-api
sudo systemctl start ossuary-portal
sudo systemctl start ossuary-kiosk
```

### Factory Reset
```bash
# Complete reset script
#!/bin/bash
set -e

echo "WARNING: This will reset Ossuary to factory defaults"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Stop services
sudo systemctl stop ossuary-*

# Backup current config
sudo cp /etc/ossuary/config.json /tmp/ossuary-config-backup.json 2>/dev/null || true

# Reset configuration
sudo cp config/default.json /etc/ossuary/config.json

# Clear all data
sudo rm -rf /var/lib/ossuary/*
sudo rm -rf /etc/ossuary/backups/*

# Reset browser data
sudo rm -rf /var/lib/ossuary/chromium/*

# Restart services
sudo systemctl start ossuary-config
sleep 2
sudo systemctl start ossuary-netd
sleep 2
sudo systemctl start ossuary-api
sleep 2
sudo systemctl start ossuary-portal
sudo systemctl start ossuary-kiosk

echo "Factory reset complete"
echo "Backup saved to: /tmp/ossuary-config-backup.json"
```

---

## Monitoring and Maintenance

### Health Check Script
```bash
#!/bin/bash
# Ossuary health check

echo "=== Ossuary Health Check ==="

# Check services
for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-kiosk; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service: running"
    else
        echo "✗ $service: failed"
    fi
done

# Check endpoints
if curl -s http://localhost:8080/health > /dev/null; then
    echo "✓ API: responding"
else
    echo "✗ API: not responding"
fi

if curl -s http://localhost:80/ > /dev/null; then
    echo "✓ Portal: responding"
else
    echo "✗ Portal: not responding"
fi

# Check network
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "✓ Internet: connected"
else
    echo "✗ Internet: disconnected"
fi

# Check resources
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')

echo "📊 Memory usage: ${MEM_USAGE}%"
echo "📊 CPU usage: ${CPU_USAGE}%"

echo "=== End Health Check ==="
```

### Log Monitoring
```bash
# Real-time log monitoring
sudo journalctl -u ossuary-* -f

# Error pattern monitoring
sudo journalctl -u ossuary-* --since "1 hour ago" | grep -i error

# Performance monitoring
while true; do
    echo "$(date): $(ps aux | grep ossuary | wc -l) processes, $(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')% memory"
    sleep 60
done
```

This troubleshooting guide provides comprehensive diagnostic procedures for all common Ossuary system issues and their resolutions.