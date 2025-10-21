# Ossuary Pi - Complete Deployment Guide 2025

**Version**: 1.0
**Updated**: October 2025
**Status**: Production Ready

## 🎯 Quick Reference

| Deployment Method | Difficulty | Time | Best For |
|-------------------|------------|------|-----------|
| **Balena Cloud** | ⭐⭐ Easy | 20 min | Production, Multiple devices |
| **Direct Install** | ⭐⭐⭐ Medium | 45 min | Single device, Customization |
| **Container** | ⭐⭐⭐⭐ Advanced | 60 min | Development, Testing |

---

## 🔧 Hardware Requirements

### Minimum Requirements
- **CPU**: ARM Cortex-A53 (Pi 3) or better
- **RAM**: 1GB minimum, 2GB+ recommended
- **Storage**: 8GB+ microSD (Class 10)
- **WiFi**: 2.4GHz/5GHz capability
- **Display**: HDMI output capability

### Recommended Hardware Matrix

| Model | Best Use Case | Performance | Power | Notes |
|-------|---------------|-------------|-------|-------|
| **Pi 5** | High-traffic kiosks, 4K displays | ⭐⭐⭐⭐⭐ | 5V/5A | Best performance, dual 4K |
| **Pi 4B (8GB)** | General production use | ⭐⭐⭐⭐ | 5V/3A | Excellent balance |
| **Pi 4B (4GB)** | Budget production | ⭐⭐⭐ | 5V/3A | Good for most use cases |
| **Pi Zero 2W** | Compact installations | ⭐⭐ | 5V/1A | Limited display options |
| **Pi 3B+** | Legacy support only | ⭐⭐ | 5V/2.5A | Not recommended for new deployments |

### ⚠️ Hardware Incompatibilities
- **Pi 1/2**: Not supported (32-bit ARM only)
- **Pi Zero (original)**: Not supported (single-core, no WiFi)
- **Compute Modules**: Possible but not tested

---

## 💿 Operating System Recommendations

### **RECOMMENDED: Raspberry Pi OS Bookworm (2025)**

**Why Bookworm?**
- ✅ Modern NetworkManager (required for our system)
- ✅ Wayland display system (better performance)
- ✅ Python 3.11+ (modern libraries)
- ✅ Active security updates
- ✅ **Required for Pi 5**

**Download Options:**
```bash
# 64-bit (Recommended for Pi 4/5)
https://downloads.raspberrypi.org/raspios_lite_arm64/

# 32-bit (Pi 3/Zero 2W only if needed)
https://downloads.raspberrypi.org/raspios_lite_armhf/
```

### Legacy Support: Bullseye
- ⚠️ **Use only if absolutely necessary**
- ⚠️ Limited to security updates
- ⚠️ Requires legacy NetworkManager workarounds
- ⚠️ No Pi 5 support

### Version Selection Guide

| Hardware | Recommended OS | Notes |
|----------|----------------|-------|
| **Pi 5** | Bookworm 64-bit | Only supported option |
| **Pi 4B** | Bookworm 64-bit | Best performance |
| **Pi 3B+** | Bookworm 64-bit | Or 32-bit if memory constrained |
| **Pi Zero 2W** | Bookworm 32-bit | 64-bit possible but slower |

---

## 🚀 Deployment Method 1: Balena Cloud (RECOMMENDED)

**Perfect for**: Production deployments, fleet management, remote updates

### Prerequisites
1. [Balena account](https://dashboard.balena.io/signup)
2. [Balena CLI](https://github.com/balena-io/balena-cli) installed
3. Git repository access

### Step 1: Create Balena Application
```bash
# Login to Balena
balena login

# Create application (choose your Pi model)
balena app create ossuary-pi --type raspberrypi4-64    # Pi 4/5
# OR
balena app create ossuary-pi --type raspberrypi3-64    # Pi 3
# OR
balena app create ossuary-pi --type raspberrypi-zero-2-w-64  # Zero 2W
```

### Step 2: Deploy Code
```bash
# Clone repository
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi

# Deploy to Balena
balena push ossuary-pi

# Or add as git remote
git remote add balena $(balena app ossuary-pi | grep 'Git remote' | awk '{print $3}')
git push balena main
```

### Step 3: Flash Device
```bash
# Download OS image for your device
balena os download raspberrypi4-64 --version latest

# Configure image
balena os configure raspberrypi4-64-*.img --app ossuary-pi

# Flash to SD card
balena os flash raspberrypi4-64-*.img --drive /dev/sdX
```

### Step 4: Environment Configuration
Set these via Balena dashboard or CLI:

```bash
# Essential configuration
balena env add OSSUARY_KIOSK_URL "https://your-dashboard.com"
balena env add OSSUARY_AP_SSID "your-setup-network"

# Optional configuration
balena env add OSSUARY_LOG_LEVEL "INFO"
balena env add OSSUARY_KIOSK_WEBGL "true"
balena env add OSSUARY_DISPLAY_ROTATION "0"
```

### Step 5: Device Setup
1. Insert SD card and power on Pi
2. Wait 5-10 minutes for first boot and deployment
3. Connect to "your-setup-network" WiFi
4. Configure via captive portal

---

## 🔧 Deployment Method 2: Direct Installation

**Perfect for**: Single devices, full control, custom configurations

### Step 1: Prepare SD Card
```bash
# Flash Raspberry Pi OS Bookworm Lite
# Use Raspberry Pi Imager or dd command

# Enable SSH and configure user (via Imager advanced options)
# Or create files manually:
touch /boot/ssh
echo 'pi:$6$...' > /boot/userconf.txt  # Use bcrypt hash
```

### Step 2: Initial Boot Setup
```bash
# SSH into Pi
ssh pi@raspberrypi.local

# Update system
sudo apt update && sudo apt upgrade -y

# Install git
sudo apt install -y git
```

### Step 3: Download and Install
```bash
# Clone repository
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi

# Run installation script
sudo ./install.sh

# Follow prompts for configuration
```

### Step 4: Configuration
```bash
# Edit configuration
sudo nano /etc/ossuary/config.json

# Example configuration:
{
    "kiosk": {
        "url": "https://your-dashboard.com",
        "enable_webgl": true
    },
    "network": {
        "ap_ssid": "your-setup-network",
        "ap_passphrase": "optional-password"
    }
}

# Restart services
sudo systemctl restart ossuary-*
```

---

## 🐳 Deployment Method 3: Container/Docker

**Perfect for**: Development, testing, custom environments

### Prerequisites
```bash
# Install Docker on Pi
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker pi

# Install Docker Compose
sudo apt install -y docker-compose
```

### Step 1: Clone and Configure
```bash
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi

# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

### Step 2: Deploy with Docker Compose
```bash
# Deploy services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### Step 3: Network Configuration
```bash
# Container needs host network access for WiFi management
# This is configured in docker-compose.yml:
network_mode: host
privileged: true
```

---

## ⚙️ Configuration Guide

### Essential Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `config.json` | Main configuration | `/etc/ossuary/config.json` |
| `network.db` | Saved networks | `/var/lib/ossuary/network.db` |
| `app.log` | Application logs | `/var/log/ossuary/app.log` |

### Configuration Schema
```json
{
    "kiosk": {
        "url": "https://your-dashboard.com",
        "enable_webgl": true,
        "enable_webgpu": false,
        "refresh_interval": 0,
        "hide_cursor": true
    },
    "network": {
        "ap_ssid": "ossuary-setup",
        "ap_passphrase": null,
        "ap_channel": 6,
        "connection_timeout": 30,
        "fallback_timeout": 300
    },
    "portal": {
        "title": "Device Setup",
        "theme": "dark",
        "auto_redirect": true
    },
    "api": {
        "enabled": true,
        "auth_required": false,
        "auth_token": null
    },
    "system": {
        "log_level": "INFO",
        "auto_update": true,
        "debug": false
    }
}
```

### Environment Variables (Balena/Container)

| Variable | Default | Description |
|----------|---------|-------------|
| `OSSUARY_KIOSK_URL` | - | **Required**: Dashboard URL |
| `OSSUARY_AP_SSID` | "ossuary-setup" | Setup network name |
| `OSSUARY_AP_PASSPHRASE` | null | Setup network password |
| `OSSUARY_LOG_LEVEL` | "INFO" | Logging level |
| `OSSUARY_KIOSK_WEBGL` | "true" | Enable WebGL |
| `OSSUARY_DISPLAY_ROTATION` | "0" | Screen rotation (0,90,180,270) |
| `OSSUARY_API_AUTH_TOKEN` | null | API authentication |

---

## 🔍 Post-Deployment Verification

### Health Check Commands
```bash
# Check service status
sudo systemctl status ossuary-*

# Check logs
sudo journalctl -u ossuary-api -f

# Test web endpoints
curl http://localhost/health
curl http://localhost:8080/api/v1/system/info

# Check WiFi functionality
nmcli device wifi list
```

### Performance Validation
```bash
# Run system tests
python3 /opt/ossuary/tests/test_system.py

# Check GPU acceleration
DISPLAY=:0 glxinfo | grep -i opengl

# Monitor resources
htop
```

### Mobile Device Testing
1. Connect phone to setup network
2. Verify captive portal opens automatically
3. Test network configuration and URL setting
4. Confirm device reconnects after reboot

---

## 🚨 Troubleshooting Quick Reference

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **No WiFi AP** | Setup network not visible | Check `systemctl status ossuary-netd` |
| **Portal not opening** | Connects but no webpage | Verify captive portal detection URLs |
| **WebGL not working** | Slow/broken graphics | Check GPU driver with `glxinfo` |
| **Service crashes** | Restart loops | Check logs: `journalctl -u ossuary-*` |
| **Network memory lost** | Forgets WiFi networks | Check `/var/lib/ossuary/network.db` |

### Emergency Recovery
```bash
# Reset to AP mode
sudo systemctl stop ossuary-netd
sudo nmcli device disconnect wlan0
sudo systemctl start ossuary-netd

# Factory reset configuration
sudo rm /etc/ossuary/config.json
sudo systemctl restart ossuary-config

# View detailed logs
sudo journalctl -u ossuary-* --since "1 hour ago"
```

---

## 📊 Performance Optimization

### Pi 5 Optimizations
```bash
# Enable GPU acceleration
echo 'dtoverlay=vc4-kms-v3d' | sudo tee -a /boot/firmware/config.txt
echo 'gpu_mem=128' | sudo tee -a /boot/firmware/config.txt

# Enable hardware video decode
echo 'dtparam=audio=on' | sudo tee -a /boot/firmware/config.txt
```

### Pi 4 Optimizations
```bash
# GPU memory split
echo 'gpu_mem=128' | sudo tee -a /boot/config.txt

# Force HDMI output
echo 'hdmi_force_hotplug=1' | sudo tee -a /boot/config.txt
echo 'hdmi_drive=2' | sudo tee -a /boot/config.txt
```

### Network Performance
```bash
# Faster WiFi scanning
echo 'iwlist_scan_timeout=10' | sudo tee -a /etc/ossuary/config.json

# Connection retry optimization
echo 'connection_retry_interval=5' | sudo tee -a /etc/ossuary/config.json
```

---

## 🛡️ Security Hardening

### Essential Security Steps
```bash
# Change default password
sudo passwd pi

# Disable SSH password auth (use keys only)
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no

# Enable firewall
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443

# Set API authentication
echo 'OSSUARY_API_AUTH_TOKEN=your-secure-token' | sudo tee -a /etc/ossuary/.env
```

### Production Security Checklist
- [ ] Default passwords changed
- [ ] SSH key-only authentication
- [ ] Firewall configured
- [ ] API authentication enabled
- [ ] Regular updates scheduled
- [ ] Logs monitored
- [ ] Physical device secured

---

## 📈 Monitoring and Maintenance

### Log Locations
```bash
# Application logs
tail -f /var/log/ossuary/app.log

# System logs
sudo journalctl -u ossuary-* -f

# Network logs
sudo journalctl -u NetworkManager -f
```

### Update Procedures

**Balena Deployment:**
```bash
# Automatic updates via git push
git push balena main
```

**Direct Installation:**
```bash
# Manual update
cd ossuary-pi
git pull
sudo ./scripts/update.sh
```

### Backup Procedures
```bash
# Backup configuration
sudo tar -czf ossuary-backup-$(date +%Y%m%d).tar.gz \
    /etc/ossuary/ \
    /var/lib/ossuary/ \
    /var/log/ossuary/

# Restore configuration
sudo tar -xzf ossuary-backup.tar.gz -C /
```

---

## 🌐 Fleet Management

### Balena Fleet Features
- **Remote SSH**: Access devices anywhere
- **Live logs**: Real-time debugging
- **Environment sync**: Update all devices at once
- **Health monitoring**: Device status dashboard
- **OTA updates**: Zero-downtime deployments

### Scaling Recommendations

| Fleet Size | Management Method | Monitoring |
|------------|-------------------|------------|
| 1-5 devices | Manual/SSH | Basic logs |
| 6-20 devices | Balena Cloud | Dashboard |
| 20+ devices | Balena + External monitoring | Full telemetry |

---

## 📞 Support and Resources

### Getting Help
1. **Check logs**: Always start with system logs
2. **Test hardware**: Verify basic Pi functionality
3. **Documentation**: Review troubleshooting guide
4. **Community**: Search existing GitHub issues
5. **Support**: Create detailed issue report

### Useful Commands Reference
```bash
# System info
cat /etc/os-release
vcgencmd version

# Network debugging
nmcli general status
iwconfig
ip addr show

# GPU information
vcgencmd get_mem gpu
glxinfo | head -20

# Service management
sudo systemctl list-units ossuary*
sudo systemctl daemon-reload
```

This deployment guide covers all major installation methods and provides the foundation for reliable Ossuary Pi deployments in 2025.