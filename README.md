# Ossuary Pi - Robust Kiosk & Captive Portal System

**The complete solution for Raspberry Pi kiosk deployments with WiFi configuration via captive portal.**

![Version](https://img.shields.io/badge/version-1.0-green) ![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red) ![OS](https://img.shields.io/badge/OS-Bookworm-blue) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## What is Ossuary Pi?

Ossuary Pi transforms any Raspberry Pi into a **professional kiosk system** with **zero-configuration WiFi setup**. Perfect for digital signage, dashboards, information displays, and IoT applications.

### Key Features

- **Mobile WiFi Setup**: Configure WiFi networks via captive portal using your phone
- **Hardware-Accelerated Kiosk**: WebGL/WebGPU support for smooth graphics
- **Network Memory**: Automatically reconnects to saved networks
- **Production Ready**: Robust error handling, monitoring, and recovery
- **Easy Deployment**: Balena Cloud integration or simple install script
- **REST API**: Programmatic control and monitoring
- **Auto-Fallback**: Returns to setup mode when no networks available

---

## Quick Start (5 Minutes)

### Option 1: Balena Cloud (Recommended)
```bash
# 1. Create Balena app
balena app create my-kiosk --type raspberrypi4-64

# 2. Deploy code
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi
balena push my-kiosk

# 3. Flash SD card
balena os download raspberrypi4-64 --version latest
balena os configure image.img --app my-kiosk
balena os flash image.img --drive /dev/sdX

# 4. Configure environment
balena env add OSSUARY_KIOSK_URL "https://your-dashboard.com"
```

### Option 2: Direct Install
```bash
# 1. Flash Raspberry Pi OS Bookworm Lite to SD card
# 2. Boot Pi and SSH in
ssh pi@raspberrypi.local

# 3. Install Ossuary Pi
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi
sudo ./install.sh

# 4. Configure URL
sudo nano /etc/ossuary/config.json
# Set "url": "https://your-dashboard.com"
```

### Setup Workflow
1. **Power on** your Pi
2. **Connect** to "ossuary-setup" WiFi network on your phone
3. **Configure** your WiFi and display URL via the captive portal
4. **Done!** Pi automatically switches to kiosk mode

---

## Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **Model** | Pi 3B+ | Pi 4B 4GB+ or Pi 5 | Pi 5 for best performance |
| **RAM** | 1GB | 4GB+ | More RAM = better dashboards |
| **Storage** | 8GB Class 10 | 32GB A2 | A2 cards much faster |
| **Power** | Official PSU | Official PSU + UPS | Stable power critical |
| **Cooling** | Passive (Pi 3) | Active (Pi 4/5) | Prevents throttling |

### Supported Models
- **Raspberry Pi 5** (Best performance, 4K displays)
- **Raspberry Pi 4B** (Production ready, great performance)
- **Raspberry Pi Zero 2W** (Compact installations)
- **Raspberry Pi 3B+** (Legacy support, limited performance)

---

## Deployment Matrix

| Method | Difficulty | Time | Best For | Management |
|--------|------------|------|----------|------------|
| **Balena Cloud** | Easy | 20 min | Production, fleets | Remote, automatic updates |
| **Direct Install** | Medium | 45 min | Single device | SSH, manual updates |
| **Docker** | Advanced | 60 min | Development | Container tools |

---

## Use Cases

### Business Applications
- **Reception Displays**: Company information, visitor check-in
- **Conference Rooms**: Meeting schedules, resource booking
- **Retail Signage**: Product information, promotional content
- **Restaurant Menus**: Digital menu boards, daily specials

### Industrial & IoT
- **Factory Dashboards**: Production metrics, KPIs
- **Warehouse Management**: Inventory, shipping status
- **Security Monitoring**: Camera feeds, alerts
- **Environmental Monitoring**: Sensor data, air quality

### Educational & Public
- **Classroom Displays**: Schedules, announcements
- **Library Information**: Events, catalog search
- **Museum Exhibits**: Interactive content, information
- **Transit Information**: Schedules, delays, maps

---

## Feature Comparison

| Feature | Ossuary Pi | Alternatives |
|---------|------------|--------------|
| **Mobile WiFi Setup** | Built-in captive portal | Manual config |
| **WebGL Acceleration** | Hardware-optimized | Hit or miss |
| **Network Memory** | Automatic reconnection | Forgets networks |
| **Fleet Management** | Balena integration | DIY solutions |
| **Production Ready** | Error handling, recovery | Basic scripts |
| **API Control** | Full REST API | No remote control |

---

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Mobile Device │    │  Raspberry Pi   │    │   Dashboard     │
│                 │    │                 │    │                 │
│  Captive Portal │    │  WiFi AP Portal │    │  Your Content   │
│                 │◄──►│                 │    │                 │
│  Configure WiFi │    │  Chromium Kiosk │◄──►│  Live Data      │
│  Set URL        │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Core Components
- **Network Manager**: WiFi handling, AP mode, captive portal
- **Kiosk Browser**: Hardware-accelerated Chromium with WebGL
- **Configuration System**: Persistent settings, network memory
- **REST API**: Remote control and monitoring
- **Web Portal**: Mobile-friendly configuration interface

---

## Configuration Examples

### Basic Kiosk Configuration
```json
{
    "kiosk": {
        "url": "https://dashboard.company.com",
        "enable_webgl": true,
        "refresh_interval": 3600
    },
    "network": {
        "ap_ssid": "company-setup",
        "ap_passphrase": "setup123"
    }
}
```

### High-Performance Setup
```json
{
    "kiosk": {
        "url": "https://analytics.company.com",
        "enable_webgl": true,
        "enable_webgpu": true,
        "disable_screensaver": true
    },
    "display": {
        "resolution": "1920x1080",
        "rotation": 0
    }
}
```

### Secure Production Setup
```json
{
    "api": {
        "auth_required": true,
        "auth_token": "your-secure-token"
    },
    "network": {
        "ap_ssid": "secure-setup",
        "ap_passphrase": "complex-password-123"
    },
    "system": {
        "log_level": "INFO",
        "auto_update": true
    }
}
```

---

## Complete Documentation

| Document | Description | When to Use |
|----------|-------------|-------------|
| **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** | Complete installation instructions | Setting up new systems |
| **[Hardware Compatibility](docs/HARDWARE_COMPATIBILITY.md)** | Detailed hardware requirements | Choosing Pi model |
| **[Troubleshooting](docs/TROUBLESHOOTING.md)** | Problem diagnosis and solutions | When things go wrong |
| **[Security Audit 2025](SECURITY_AUDIT_2025.md)** | Security analysis and fixes | Production security |
| **[Critical Fixes Applied](CRITICAL_FIXES_APPLIED.md)** | 2025 compatibility updates | Understanding recent changes |

---

## Security Features

### Built-in Security
- **Environment-Aware Sandboxing**: Secure by default, container-compatible
- **API Authentication**: Optional token-based API access
- **Network Isolation**: Captive portal isolated from main network
- **Input Validation**: All configuration inputs validated and sanitized

### Security Best Practices
```bash
# Change default passwords
sudo passwd pi

# Enable firewall
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443

# Use API authentication
echo 'OSSUARY_API_AUTH_TOKEN=your-secure-token' | sudo tee -a /etc/ossuary/.env
```

---

## Performance Optimization

### Pi 5 Optimization (2025 Recommended)
```bash
# /boot/firmware/config.txt
gpu_mem=128
dtoverlay=vc4-kms-v3d
hdmi_force_hotplug=1
disable_overscan=1
```

### Pi 4 Optimization
```bash
# Stable WebGL configuration
gpu_mem=128
dtoverlay=vc4-fkms-v3d  # More stable than kms
hdmi_force_hotplug=1
hdmi_drive=2
```

### Network Performance
```bash
# Faster WiFi scanning
{
    "network": {
        "scan_timeout": 10,
        "connection_timeout": 30
    }
}
```

---

## Fleet Management

### Balena Cloud Integration
- **Remote Access**: SSH into devices anywhere
- **Live Monitoring**: Real-time logs and metrics
- **OTA Updates**: Zero-downtime deployments
- **Environment Sync**: Update configuration across fleet
- **Health Dashboard**: Device status at a glance

### Scaling Recommendations
- **1-5 devices**: Manual management
- **6-20 devices**: Balena Cloud dashboard
- **20+ devices**: Full telemetry and monitoring

---

## Testing & Validation

### Automated Tests
```bash
# Run complete system validation
python3 tests/test_system.py

# Check hardware compatibility
python3 tests/hardware_test.py

# Validate configuration
python3 -m json.tool /etc/ossuary/config.json
```

### Manual Testing Checklist
- [ ] Pi boots to captive portal mode
- [ ] Mobile device connects and portal opens
- [ ] WiFi configuration saves and connects
- [ ] Kiosk launches with correct URL
- [ ] WebGL acceleration working (if enabled)
- [ ] System recovers after power loss
- [ ] API endpoints respond correctly

---

## 2025 Compatibility Updates

### Critical Issues Resolved
- **NetworkManager Library**: Updated to python-sdbus-networkmanager
- **WebGL Hardware Acceleration**: GPU driver detection and optimization
- **Security Vulnerabilities**: Environment-aware sandbox control
- **Raspberry Pi OS Bookworm**: Full compatibility with latest OS

### What's New in v1.0
- Modern NetworkManager integration with fallback support
- Intelligent GPU driver detection for optimal WebGL performance
- Container-aware security configuration
- Comprehensive hardware compatibility matrix
- Production-ready deployment documentation

---

## Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch
3. **Make** your changes
4. **Test** thoroughly (see testing section)
5. **Submit** a pull request

### Development Setup
```bash
git clone https://github.com/ossuary-dev/ossuary-pi.git
cd ossuary-pi
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
```

---

## Support

### Getting Help
1. **Check Documentation**: Start with the troubleshooting guide
2. **Search Issues**: Look through existing GitHub issues
3. **Community Forum**: Ask questions and share solutions
4. **Report Bugs**: Create detailed issue reports
5. **Emergency Support**: For critical production issues

### Useful Commands
```bash
# System health check
sudo systemctl status ossuary-*

# View logs
sudo journalctl -u ossuary-* -f

# Test network
nmcli device wifi list

# Check display
DISPLAY=:0 xdpyinfo | head -5
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- **Raspberry Pi Foundation** for creating amazing hardware
- **Balena** for excellent IoT deployment platform
- **NetworkManager Team** for robust network management
- **Chromium Project** for the browser engine
- **Community Contributors** for testing and feedback

---

## Get Started Today

Ready to deploy your first kiosk? Choose your path:

### New to Raspberry Pi?
Start with our **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** for step-by-step instructions.

### Hardware Questions?
Check the **[Hardware Compatibility Guide](docs/HARDWARE_COMPATIBILITY.md)** for detailed requirements.

### Production Deployment?
Review the **[Security Features](#security-features)** and **[Fleet Management](#fleet-management)** sections.

### Need Customization?
Explore the **[Configuration Examples](#configuration-examples)** and **API Reference**.

---

**Made with care for the Raspberry Pi community**

*Transform your Pi into a professional kiosk in minutes, not hours.*