# Troubleshooting Guide - Ossuary Pi 2025

**Last Updated**: October 2025
**Version**: 1.0
**Coverage**: Complete diagnostic procedures

---

## 🚨 Emergency Quick Fixes

| Problem | Quick Solution | Time | Risk |
|---------|----------------|------|------|
| **No WiFi AP** | `sudo systemctl restart ossuary-netd` | 30s | Low |
| **Portal not opening** | Check mobile data off, clear browser cache | 1min | None |
| **Service crashed** | `sudo systemctl restart ossuary-*` | 1min | Low |
| **System frozen** | Power cycle, check logs after reboot | 2min | Medium |
| **Can't connect** | `sudo nmcli device disconnect wlan0 && sleep 5 && sudo systemctl restart ossuary-netd` | 1min | Low |

---

## 🔍 Diagnostic Workflow

### Step 1: Basic System Health
```bash
# Check if system is responsive
ping localhost
uptime
free -h

# Check for obvious errors
dmesg | tail -20
journalctl --priority=err --since="1 hour ago"
```

### Step 2: Service Status Check
```bash
# Check all Ossuary services
sudo systemctl status ossuary-*

# Quick service health overview
systemctl is-active ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-kiosk
```

### Step 3: Network Connectivity
```bash
# Check network interfaces
ip addr show
nmcli device status

# Check WiFi functionality
nmcli device wifi list
iwconfig wlan0
```

### Step 4: Application-Specific Tests
```bash
# Test web endpoints
curl -f http://localhost/health || echo "Portal not responding"
curl -f http://localhost:8080/api/v1/system/info || echo "API not responding"

# Check kiosk display
ps aux | grep chromium
DISPLAY=:0 xwininfo -root -tree | head -10
```

---

## 🌐 Network & WiFi Issues

### No WiFi Access Point Visible

**Symptoms:**
- Setup network not appearing on mobile devices
- Cannot connect to configure WiFi

**Diagnosis:**
```bash
# Check if network interface is managed by NetworkManager
nmcli device status
# wlan0 should show "managed" or "disconnected", not "unmanaged"

# Check if access point is configured
nmcli connection show | grep -i ap

# Check for interface conflicts
sudo systemctl status dhcpcd
sudo systemctl status wpa_supplicant
```

**Solutions:**

1. **Interface Management Issue:**
```bash
# Ensure NetworkManager manages WiFi
sudo systemctl stop dhcpcd
sudo systemctl disable dhcpcd
sudo systemctl enable NetworkManager
sudo systemctl restart NetworkManager
```

2. **Service Restart:**
```bash
# Restart network service
sudo systemctl stop ossuary-netd
sudo nmcli device disconnect wlan0
sleep 5
sudo systemctl start ossuary-netd

# Monitor logs
sudo journalctl -u ossuary-netd -f
```

3. **Manual AP Creation:**
```bash
# Emergency AP setup
sudo nmcli device wifi hotspot \
    ssid "ossuary-emergency" \
    password "emergency123" \
    ifname wlan0
```

### Captive Portal Not Opening

**Symptoms:**
- Device connects to WiFi but no browser page opens
- Portal accessible via direct IP but not auto-opening

**Diagnosis:**
```bash
# Check if portal web server is running
curl http://192.168.42.1/
netstat -tlnp | grep :80

# Check DNS configuration
nslookup google.com 192.168.42.1
dig @192.168.42.1 captive.apple.com

# Check iptables rules
sudo iptables -L -n | grep -A5 -B5 REDIRECT
```

**Solutions:**

1. **Portal Service Issue:**
```bash
# Restart portal service
sudo systemctl restart ossuary-portal

# Check portal logs
sudo journalctl -u ossuary-portal -f
```

2. **DNS/DHCP Configuration:**
```bash
# Check dnsmasq configuration
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq --since "5 minutes ago"

# Restart DNS/DHCP
sudo systemctl restart dnsmasq
```

3. **Captive Portal Detection URLs:**
```bash
# Test common detection URLs
curl -I http://clients3.google.com/generate_204  # Should return 204
curl -I http://detectportal.firefox.com/success_page.txt  # Should redirect
curl -I http://captive.apple.com/hotspot-detect.html  # Should redirect
```

4. **Firewall/iptables Issue:**
```bash
# Reset captive portal rules
sudo iptables -t nat -F
sudo /opt/ossuary/scripts/setup-captive-portal.sh
```

### Network Connection Failures

**Symptoms:**
- Can't connect to saved networks
- Connection attempts timeout
- Connects but no internet access

**Diagnosis:**
```bash
# Check saved connections
nmcli connection show

# Test network scanning
nmcli device wifi rescan
nmcli device wifi list

# Check connection status
nmcli connection show --active
```

**Solutions:**

1. **Network Profile Corruption:**
```bash
# Remove and recreate connection
sudo nmcli connection delete "YourNetworkName"
# Reconfigure via portal
```

2. **Authentication Issues:**
```bash
# Check for authentication failures
sudo journalctl -u NetworkManager | grep -i "auth\|fail\|error"

# Test manual connection
sudo nmcli device wifi connect "SSID" password "password"
```

3. **DNS Resolution Problems:**
```bash
# Test DNS
nslookup google.com
dig google.com

# Reset DNS configuration
sudo systemctl restart systemd-resolved
```

---

## 🖥️ Display & Kiosk Issues

### No Display Output

**Symptoms:**
- HDMI display shows no signal
- Display works with other devices
- System appears to boot (activity LED blinks)

**Diagnosis:**
```bash
# Check HDMI detection
vcgencmd get_config hdmi_force_hotplug
tvservice -s

# Check GPU configuration
vcgencmd get_config gpu_mem
vcgencmd measure_temp

# Check X server status
ps aux | grep X
journalctl -u lightdm --since "5 minutes ago"
```

**Solutions:**

1. **Force HDMI Output:**
```bash
# Edit boot configuration
sudo nano /boot/firmware/config.txt
# Add or modify:
hdmi_force_hotplug=1
hdmi_drive=2
hdmi_group=1
hdmi_mode=16
disable_overscan=1

# Reboot
sudo reboot
```

2. **GPU Memory Configuration:**
```bash
# Increase GPU memory
echo 'gpu_mem=128' | sudo tee -a /boot/firmware/config.txt
sudo reboot
```

3. **Display Driver Issues:**
```bash
# Check for VC4 driver
lsmod | grep vc4

# Reset to legacy driver if needed
sudo nano /boot/firmware/config.txt
# Change: dtoverlay=vc4-kms-v3d
# To: dtoverlay=vc4-fkms-v3d
sudo reboot
```

### Kiosk Browser Not Starting

**Symptoms:**
- Display works but no browser content
- Browser process not running
- Blank screen or desktop visible

**Diagnosis:**
```bash
# Check browser process
ps aux | grep chromium
pgrep -f chromium

# Check kiosk service
sudo systemctl status ossuary-kiosk
sudo journalctl -u ossuary-kiosk --since "5 minutes ago"

# Check X server access
DISPLAY=:0 xdpyinfo | head -10
```

**Solutions:**

1. **Browser Launch Issues:**
```bash
# Manual browser test
DISPLAY=:0 chromium-browser --version
DISPLAY=:0 chromium-browser --no-sandbox --kiosk http://google.com &

# Check for missing dependencies
sudo apt install -y chromium-browser xorg
```

2. **X Server Permission:**
```bash
# Fix X server access
sudo usermod -a -G video ossuary
sudo usermod -a -G audio ossuary

# Update Xauthority
sudo touch /home/ossuary/.Xauthority
sudo chown ossuary:ossuary /home/ossuary/.Xauthority
```

3. **WebGL/GPU Issues:**
```bash
# Test GPU acceleration
DISPLAY=:0 glxinfo | grep -i opengl

# Disable hardware acceleration if problematic
sudo nano /etc/ossuary/config.json
# Set: "enable_webgl": false
sudo systemctl restart ossuary-kiosk
```

### Poor WebGL Performance

**Symptoms:**
- Slow graphics rendering
- Choppy animations
- High CPU usage

**Diagnosis:**
```bash
# Check GPU driver status
glxinfo | grep -E "(OpenGL vendor|OpenGL renderer|OpenGL version)"
vcgencmd get_config gpu_mem

# Check browser GPU status
# In Chromium: go to chrome://gpu/
```

**Solutions:**

1. **GPU Driver Optimization:**
```bash
# Try different VC4 drivers
sudo nano /boot/firmware/config.txt

# Option 1: Full KMS (better performance, may have issues)
dtoverlay=vc4-kms-v3d

# Option 2: Fake KMS (more stable)
dtoverlay=vc4-fkms-v3d

# Option 3: Legacy driver (fallback)
# Comment out vc4 overlay entirely

sudo reboot
```

2. **Chromium Flags Optimization:**
```bash
# Check current browser flags
sudo journalctl -u ossuary-kiosk | grep "chromium-browser"

# Update browser configuration
sudo nano /etc/ossuary/config.json
# Adjust WebGL settings based on GPU detection
```

3. **Performance vs Stability Trade-off:**
```bash
# For maximum stability (software rendering)
{
    "kiosk": {
        "enable_webgl": false,
        "enable_webgpu": false
    }
}

# For balanced performance
{
    "kiosk": {
        "enable_webgl": true,
        "enable_webgpu": false
    }
}
```

---

## ⚙️ Service & Configuration Issues

### Services Won't Start

**Symptoms:**
- systemctl status shows failed services
- Services immediately exit after start
- Dependency issues between services

**Diagnosis:**
```bash
# Check service dependencies
systemctl list-dependencies ossuary-api
systemd-analyze critical-chain ossuary-api

# Check for configuration errors
sudo journalctl -u ossuary-config --since "10 minutes ago"
sudo /opt/ossuary/bin/ossuary-config --validate
```

**Solutions:**

1. **Configuration File Issues:**
```bash
# Validate JSON configuration
python3 -m json.tool /etc/ossuary/config.json

# Reset to default configuration
sudo cp /etc/ossuary/default.json /etc/ossuary/config.json
sudo systemctl restart ossuary-config
```

2. **Permission Problems:**
```bash
# Fix file permissions
sudo chown -R ossuary:ossuary /etc/ossuary/
sudo chown -R ossuary:ossuary /var/lib/ossuary/
sudo chown -R ossuary:ossuary /var/log/ossuary/

# Fix service file permissions
sudo chmod 644 /etc/systemd/system/ossuary-*.service
sudo systemctl daemon-reload
```

3. **Service Start Order:**
```bash
# Restart services in correct order
sudo systemctl stop ossuary-*
sudo systemctl start ossuary-config
sleep 2
sudo systemctl start ossuary-netd
sleep 2
sudo systemctl start ossuary-api
sudo systemctl start ossuary-portal
sudo systemctl start ossuary-kiosk
```

### Configuration Not Persisting

**Symptoms:**
- Settings reset after reboot
- Changes made via portal don't stick
- Network memory not working

**Diagnosis:**
```bash
# Check configuration file timestamps
ls -la /etc/ossuary/config.json
ls -la /var/lib/ossuary/

# Check file system write permissions
touch /etc/ossuary/test.txt && rm /etc/ossuary/test.txt

# Check configuration service logs
sudo journalctl -u ossuary-config -f
```

**Solutions:**

1. **File System Issues:**
```bash
# Check for read-only filesystem
mount | grep " / "
touch /test.txt && rm /test.txt

# Remount filesystem read-write if needed
sudo mount -o remount,rw /
```

2. **Database Corruption:**
```bash
# Check network database
sqlite3 /var/lib/ossuary/network.db ".schema"
sqlite3 /var/lib/ossuary/network.db "SELECT * FROM networks;"

# Recreate database if corrupted
sudo rm /var/lib/ossuary/network.db
sudo systemctl restart ossuary-config
```

3. **Configuration Service Issues:**
```bash
# Reset configuration service
sudo systemctl stop ossuary-config
sudo rm -f /var/lib/ossuary/config.lock
sudo systemctl start ossuary-config
```

---

## 🔒 Security & Permission Issues

### API Access Denied

**Symptoms:**
- API returns 401/403 errors
- Can't access management endpoints
- Authentication failures

**Diagnosis:**
```bash
# Test API endpoints
curl -v http://localhost:8080/health
curl -v http://localhost:8080/api/v1/system/info

# Check authentication configuration
grep -i auth /etc/ossuary/config.json
```

**Solutions:**

1. **Authentication Configuration:**
```bash
# Disable authentication for testing
sudo nano /etc/ossuary/config.json
{
    "api": {
        "auth_required": false
    }
}

# Or set authentication token
{
    "api": {
        "auth_required": true,
        "auth_token": "your-secure-token"
    }
}

sudo systemctl restart ossuary-api
```

2. **Firewall Issues:**
```bash
# Check if ports are blocked
sudo ufw status
sudo iptables -L | grep -E "8080|80|443"

# Allow API access
sudo ufw allow 8080
sudo ufw allow 80
```

### File Permission Errors

**Symptoms:**
- Services can't write to log files
- Configuration updates fail
- Database access denied

**Solutions:**
```bash
# Reset all Ossuary permissions
sudo chown -R ossuary:ossuary /etc/ossuary/
sudo chown -R ossuary:ossuary /var/lib/ossuary/
sudo chown -R ossuary:ossuary /var/log/ossuary/
sudo chown -R ossuary:ossuary /opt/ossuary/

# Set correct file permissions
sudo find /etc/ossuary/ -type f -exec chmod 644 {} \;
sudo find /var/lib/ossuary/ -type f -exec chmod 644 {} \;
sudo find /var/log/ossuary/ -type f -exec chmod 644 {} \;

# Set directory permissions
sudo find /etc/ossuary/ -type d -exec chmod 755 {} \;
sudo find /var/lib/ossuary/ -type d -exec chmod 755 {} \;
sudo find /var/log/ossuary/ -type d -exec chmod 755 {} \;
```

---

## 🚀 Performance Issues

### High CPU Usage

**Symptoms:**
- System sluggish or unresponsive
- High load average
- Browser performance poor

**Diagnosis:**
```bash
# Check CPU usage
top -p $(pgrep -d',' chromium)
iostat 1 5
vcgencmd measure_temp

# Check for runaway processes
ps aux --sort=-%cpu | head -10
```

**Solutions:**

1. **Browser Optimization:**
```bash
# Reduce browser resource usage
sudo nano /etc/ossuary/config.json
{
    "kiosk": {
        "enable_webgl": false,
        "enable_webgpu": false,
        "refresh_interval": 3600
    }
}
```

2. **System Optimization:**
```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl stop bluetooth

# Reduce GPU memory if not needed
echo 'gpu_mem=64' | sudo tee -a /boot/firmware/config.txt
```

### Memory Issues

**Symptoms:**
- Out of memory errors
- System swapping heavily
- Services being killed by OOM killer

**Diagnosis:**
```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head -10
dmesg | grep -i "killed process"
```

**Solutions:**

1. **Memory Optimization:**
```bash
# Add swap space
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

2. **Service Memory Limits:**
```bash
# Limit browser memory usage
sudo systemctl edit ossuary-kiosk
# Add:
[Service]
MemoryLimit=512M
```

---

## 📊 Monitoring & Logging

### Enhanced Logging for Troubleshooting

**Enable Debug Logging:**
```bash
# Temporary debug mode
sudo nano /etc/ossuary/config.json
{
    "system": {
        "log_level": "DEBUG",
        "debug": true
    }
}

sudo systemctl restart ossuary-*
```

**Real-time Log Monitoring:**
```bash
# Monitor all Ossuary services
sudo journalctl -f -u ossuary-*

# Monitor specific service
sudo journalctl -f -u ossuary-netd

# Monitor system events
sudo journalctl -f --priority=warning

# Monitor network events
sudo journalctl -f -u NetworkManager
```

### Performance Monitoring

**System Resource Monitoring:**
```bash
# CPU and memory usage
watch -n 1 'free -h; echo ""; ps aux --sort=-%cpu | head -5'

# Network monitoring
watch -n 1 'nmcli device status; echo ""; iwconfig wlan0'

# Temperature monitoring
watch -n 1 'vcgencmd measure_temp; vcgencmd get_throttled'
```

**Automated Health Checks:**
```bash
# Create monitoring script
cat > /tmp/health_check.sh << 'EOF'
#!/bin/bash
echo "=== Ossuary Pi Health Check ==="
echo "Time: $(date)"
echo "Uptime: $(uptime)"
echo "Temperature: $(vcgencmd measure_temp)"
echo "Memory: $(free -h | grep Mem)"
echo "Services:"
systemctl is-active ossuary-* | while read status; do
    echo "  $status"
done
echo "Network:"
nmcli device status | grep wlan0
echo "=== End Health Check ==="
EOF

chmod +x /tmp/health_check.sh
watch -n 30 /tmp/health_check.sh
```

---

## 🛠️ Advanced Diagnostics

### Complete System Diagnosis Script

```bash
#!/bin/bash
# Ossuary Pi Diagnostic Script
echo "=== OSSUARY PI DIAGNOSTIC REPORT ==="
echo "Generated: $(date)"
echo "Hostname: $(hostname)"
echo

echo "=== HARDWARE INFORMATION ==="
cat /proc/cpuinfo | grep -E "(model name|Hardware|Revision)"
free -h
df -h /
vcgencmd measure_temp
vcgencmd get_throttled
echo

echo "=== SOFTWARE VERSIONS ==="
cat /etc/os-release | grep PRETTY_NAME
uname -a
vcgencmd version
python3 --version
echo

echo "=== NETWORK STATUS ==="
ip addr show wlan0
nmcli device status
nmcli connection show --active
iwconfig wlan0 2>/dev/null | grep -E "(ESSID|Quality|Signal)"
echo

echo "=== SERVICE STATUS ==="
systemctl is-active ossuary-* | paste <(echo -e "config\nnetd\napi\nportal\nkiosk") -
echo

echo "=== RECENT ERRORS ==="
journalctl --priority=err --since="1 hour ago" --no-pager | tail -10
echo

echo "=== CONFIGURATION ==="
echo "Config file exists: $(test -f /etc/ossuary/config.json && echo 'YES' || echo 'NO')"
echo "Database exists: $(test -f /var/lib/ossuary/network.db && echo 'YES' || echo 'NO')"
echo "Logs directory: $(ls -la /var/log/ossuary/ | wc -l) files"
echo

echo "=== PROCESS STATUS ==="
ps aux | grep -E "(chromium|ossuary)" | grep -v grep
echo

echo "=== GPU STATUS ==="
if command -v glxinfo >/dev/null 2>&1; then
    DISPLAY=:0 glxinfo | grep -E "(OpenGL vendor|OpenGL renderer|Direct rendering)"
else
    echo "glxinfo not available"
fi
echo

echo "=== END DIAGNOSTIC REPORT ==="
```

### Emergency Recovery Procedures

**Complete Service Reset:**
```bash
#!/bin/bash
# Emergency recovery script
echo "Starting emergency recovery..."

# Stop all services
sudo systemctl stop ossuary-*

# Reset configuration to defaults
sudo cp /etc/ossuary/default.json /etc/ossuary/config.json

# Clear any locks
sudo rm -f /var/lib/ossuary/*.lock

# Reset network connections
sudo nmcli connection delete $(nmcli -t -f NAME connection show | grep -v "lo")

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Wait for NetworkManager to stabilize
sleep 10

# Start services in order
sudo systemctl start ossuary-config
sleep 2
sudo systemctl start ossuary-netd
sleep 5
sudo systemctl start ossuary-api
sudo systemctl start ossuary-portal
sudo systemctl start ossuary-kiosk

echo "Recovery complete. Check service status:"
systemctl is-active ossuary-*
```

**Nuclear Option - Complete Reinstall:**
```bash
# Only use if all else fails
sudo systemctl stop ossuary-*
sudo systemctl disable ossuary-*
sudo rm -rf /etc/ossuary/
sudo rm -rf /var/lib/ossuary/
sudo rm -rf /var/log/ossuary/
sudo rm -rf /opt/ossuary/
sudo rm /etc/systemd/system/ossuary-*.service

# Then run installer again
git clone https://github.com/ossuary-dev/ossuary-pi.git && cd ossuary-pi && sudo ./install.sh
```

---

## 📞 Getting Support

### Information to Collect Before Reporting Issues

1. **System Information:**
```bash
# Run diagnostic script (see above)
./diagnostic_script.sh > ossuary_diagnostic.txt
```

2. **Specific Error Messages:**
```bash
# Collect recent logs
sudo journalctl --since "1 hour ago" > ossuary_logs.txt
```

3. **Configuration:**
```bash
# Sanitize and collect config (remove sensitive data)
cat /etc/ossuary/config.json | jq 'del(.api.auth_token, .network.saved_networks[].password)' > config_sanitized.json
```

### Support Channels

- **Documentation**: Check this troubleshooting guide first
- **GitHub Issues**: Search existing issues before creating new ones
- **Community Forum**: Ask questions and share solutions
- **Emergency Support**: For critical production issues

### Creating Effective Bug Reports

Include:
1. Hardware model and OS version
2. Deployment method (Balena, direct install, container)
3. Complete diagnostic output
4. Steps to reproduce the issue
5. Expected vs actual behavior
6. Any recent changes to the system

This troubleshooting guide covers the most common issues and provides systematic approaches to diagnosing and resolving problems with Ossuary Pi deployments.