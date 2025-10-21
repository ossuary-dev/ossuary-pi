# Hardware Compatibility Guide - Ossuary Pi 2025

**Last Updated**: October 2025
**Version**: 1.0
**Status**: Comprehensive Testing Matrix

---

## 🎯 Quick Compatibility Check

| Model | Status | Performance | Recommended Use | Notes |
|-------|---------|-------------|-----------------|--------|
| **Raspberry Pi 5** | ✅ Full | ⭐⭐⭐⭐⭐ | Production, 4K displays | Best choice |
| **Raspberry Pi 4B (8GB)** | ✅ Full | ⭐⭐⭐⭐ | Production deployments | Excellent |
| **Raspberry Pi 4B (4GB)** | ✅ Full | ⭐⭐⭐⭐ | Budget production | Very good |
| **Raspberry Pi 4B (2GB)** | ✅ Limited | ⭐⭐⭐ | Light use only | Marginal |
| **Raspberry Pi 3B+** | ⚠️ Legacy | ⭐⭐ | Legacy support only | Not recommended |
| **Raspberry Pi Zero 2W** | ✅ Basic | ⭐⭐ | Compact installations | Limited display |
| **Raspberry Pi 3B** | ❌ EOL | ⭐ | Not supported | Too slow |
| **Raspberry Pi Zero/1/2** | ❌ No | - | Not supported | Incompatible |

---

## 🔬 Detailed Hardware Analysis

### Raspberry Pi 5 (2023+)
**Best Choice for New Deployments**

#### Specifications
- **CPU**: Quad-core Cortex-A76 @ 2.4GHz
- **GPU**: VideoCore VII with hardware decode
- **RAM**: 4GB or 8GB LPDDR4X
- **WiFi**: 802.11ac dual-band, Bluetooth 5.0/BLE
- **Display**: Dual 4K@60Hz via micro HDMI
- **USB**: 2× USB 3.0, 2× USB 2.0
- **Storage**: microSD + optional NVMe via HAT

#### Ossuary Pi Performance
```
✅ WebGL Acceleration: Excellent (VC4 V3D driver)
✅ Captive Portal: Fast network switching (<3s)
✅ Kiosk Performance: Smooth 4K video, complex dashboards
✅ Multi-display: Dual screen support
✅ Boot Time: ~45 seconds to portal ready
✅ WiFi Range: Excellent with external antenna
```

#### Configuration Requirements
```bash
# /boot/firmware/config.txt optimizations
gpu_mem=128
dtoverlay=vc4-kms-v3d
hdmi_force_hotplug=1
disable_overscan=1
max_usb_current=1

# For dual displays
hdmi_group:0=1
hdmi_mode:0=16
hdmi_group:1=1
hdmi_mode:1=16
```

#### Known Issues & Solutions
- **Power Requirements**: Needs 5V/5A PSU (27W)
  - Solution: Use official Pi 5 PSU or equivalent
- **Heat Management**: Can throttle under sustained load
  - Solution: Active cooling recommended for kiosk use
- **NVMe Compatibility**: Some drives require firmware updates
  - Solution: Use official Pi NVMe HAT

---

### Raspberry Pi 4B (2019-2023)
**Proven Production Choice**

#### Model Variants

| RAM | Production Use | Kiosk Performance | Network Load |
|-----|----------------|-------------------|--------------|
| **8GB** | ✅ Excellent | 4K + complex UI | High traffic |
| **4GB** | ✅ Good | 1080p + dashboards | Medium traffic |
| **2GB** | ⚠️ Limited | Simple displays only | Low traffic |
| **1GB** | ❌ Not viable | Too constrained | Not suitable |

#### Performance Characteristics
```
✅ WebGL Acceleration: Good (requires tuning)
✅ Captive Portal: Reliable network management
✅ Kiosk Performance: 1080p smooth, 4K possible
✅ Single Display: HDMI 0 or 1
✅ Boot Time: ~60 seconds to portal ready
✅ WiFi Range: Good with dual-band antenna
```

#### GPU Driver Optimization
```bash
# Check current driver
cat /proc/device-tree/soc/firmwarekms@7e600000/status
# Should return: okay

# Optimal config.txt settings
gpu_mem=128
dtoverlay=vc4-fkms-v3d  # Use fake KMS for stability
hdmi_force_hotplug=1
hdmi_drive=2
disable_overscan=1

# If WebGL issues persist, fallback to:
# dtoverlay=vc4-kms-v3d  # Full KMS (may have right-click issues)
```

#### Common Issues & Solutions

**Issue**: WebGL performance poor
```bash
# Solution: Check GPU driver status
glxinfo | grep -i opengl
# Expected: Mesa DRI VC4

# If software rendering detected:
sudo raspi-config
# Advanced Options > GL Driver > G2 GL (Fake KMS)
```

**Issue**: Right-click breaks WebGL
```bash
# Solution: Disable context menu in kiosk
# This is handled automatically in browser flags
```

**Issue**: 4K display choppy
```bash
# Solution: Optimize HDMI settings
hdmi_enable_4kp60=1  # Pi 4 only
hdmi_group=2
hdmi_mode=82         # 1920x1080 60Hz
# Or reduce to 1080p for better performance
```

---

### Raspberry Pi 3B+ (2018)
**Legacy Support Only**

#### Why Not Recommended for New Deployments
- **CPU Limitations**: Cortex-A53 struggles with modern web content
- **RAM Constraints**: 1GB insufficient for complex dashboards
- **GPU Performance**: Limited WebGL capabilities
- **Network Performance**: Single-band WiFi, slower throughput

#### If You Must Use Pi 3B+
```bash
# Minimal configuration for basic functionality
gpu_mem=64  # Conserve RAM
dtoverlay=vc4-fkms-v3d
arm_freq=1400  # Overclock if cooling adequate

# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable hciuart
```

#### Performance Expectations
```
⚠️ WebGL Acceleration: Basic only
⚠️ Captive Portal: Slower network switching (5-10s)
⚠️ Kiosk Performance: 720p max, simple content
❌ Multi-display: Not supported
⚠️ Boot Time: ~90 seconds to portal ready
⚠️ WiFi Range: Limited to 2.4GHz
```

---

### Raspberry Pi Zero 2W (2021)
**Compact Installations**

#### Specifications
- **CPU**: Quad-core Cortex-A53 @ 1GHz
- **RAM**: 512MB LPDDR2
- **WiFi**: 802.11n single-band, Bluetooth 4.2/BLE
- **Display**: Single micro HDMI
- **Form Factor**: Minimal footprint

#### Best Use Cases
- Digital signage with static content
- Simple information displays
- Embedded kiosk applications
- Space-constrained installations

#### Performance Profile
```
✅ Captive Portal: Functional but slow (10-15s)
⚠️ Kiosk Performance: 720p max, static content
❌ WebGL Acceleration: Software rendering only
✅ Power Efficiency: Excellent (5V/1A)
⚠️ Boot Time: ~120 seconds to portal ready
⚠️ WiFi Range: 2.4GHz only, limited range
```

#### Optimization for Zero 2W
```bash
# Aggressive memory conservation
gpu_mem=16
disable_overscan=1
hdmi_force_hotplug=1

# CPU governor for consistent performance
echo 'performance' | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable hardware acceleration
OSSUARY_KIOSK_WEBGL=false
OSSUARY_KIOSK_WEBGPU=false
```

---

## 🔌 Power Requirements & Supply Compatibility

### Power Supply Matrix

| Model | Voltage | Current | Power | Connector | Official PSU |
|-------|---------|---------|-------|-----------|--------------|
| **Pi 5** | 5V | 5A | 25W | USB-C | Required |
| **Pi 4B** | 5V | 3A | 15W | USB-C | Recommended |
| **Pi 3B+** | 5V | 2.5A | 12.5W | Micro-USB | Optional |
| **Zero 2W** | 5V | 1A | 5W | Micro-USB | Any quality PSU |

### Power Supply Recommendations

**Production Deployments:**
- Use official Raspberry Pi power supplies
- Avoid cheap USB chargers (cause instability)
- Consider UPS for critical installations
- Monitor `vcgencmd get_throttled` for power issues

**Signs of Inadequate Power:**
```bash
# Check for power throttling
vcgencmd get_throttled
# 0x0 = No issues
# 0x50000 = Under-voltage detected
# 0x50005 = Currently under-voltage + previously under-voltage
```

---

## 📺 Display Compatibility & Performance

### Supported Display Interfaces

| Interface | Pi 5 | Pi 4B | Pi 3B+ | Zero 2W | Max Resolution |
|-----------|------|-------|---------|---------|----------------|
| **HDMI 0** | ✅ | ✅ | ✅ | ✅ | 4K@60Hz* |
| **HDMI 1** | ✅ | ✅ | ❌ | ❌ | 4K@60Hz* |
| **DSI** | ✅ | ✅ | ✅ | ✅ | 1920x1080 |
| **Composite** | ❌ | ✅ | ✅ | ✅ | 480i |

*4K@60Hz requires Pi 5 or Pi 4 with proper config

### Display Resolution Recommendations

| Model | Optimal Resolution | Max Tested | WebGL Performance |
|-------|-------------------|------------|-------------------|
| **Pi 5** | 4K (3840x2160) | 4K@60Hz | Excellent |
| **Pi 4B 8GB** | 4K (3840x2160) | 4K@30Hz | Good |
| **Pi 4B 4GB** | 1080p (1920x1080) | 4K@30Hz | Good |
| **Pi 3B+** | 720p (1280x720) | 1080p@30Hz | Basic |
| **Zero 2W** | 720p (1280x720) | 1080p@30Hz | Software only |

### Touchscreen Compatibility
```bash
# Official 7" touchscreen (DSI)
✅ Pi 5: Full support with auto-rotate
✅ Pi 4B: Full support
✅ Pi 3B+: Basic support
✅ Zero 2W: Basic support (may be slow)

# USB touchscreens
✅ Most HID-compliant screens work
⚠️ May require additional drivers
⚠️ Check power requirements
```

---

## 📡 Network Hardware Compatibility

### WiFi Chipset Support

| Model | Built-in WiFi | Supported Standards | Range | External Antenna |
|-------|---------------|-------------------|-------|-------------------|
| **Pi 5** | CYW43455 | 802.11ac dual-band | Excellent | Connector included |
| **Pi 4B** | CYW43455 | 802.11ac dual-band | Good | Soldering required |
| **Pi 3B+** | CYW43455 | 802.11n single-band | Fair | Soldering required |
| **Zero 2W** | CYW43438 | 802.11n single-band | Limited | Not practical |

### WiFi Performance Testing
```bash
# Test WiFi performance
iperf3 -c speedtest.net -p 5201

# Expected throughput:
# Pi 5: 50-80 Mbps (dual-band)
# Pi 4B: 40-60 Mbps (dual-band)
# Pi 3B+: 20-30 Mbps (single-band)
# Zero 2W: 10-20 Mbps (single-band)
```

### External WiFi Dongles
**Recommended dongles** (if built-in WiFi insufficient):
```
✅ Panda PAU09 (Ralink RT5372)
✅ Edimax EW-7811Un (RTL8188CUS)
✅ TP-Link AC600 T2U Plus (Realtek RTL8811AU)

❌ Avoid: Generic no-name dongles
❌ Avoid: RTL8188EUS chipsets (driver issues)
```

---

## 💾 Storage Compatibility & Performance

### microSD Card Recommendations

| Class | Min Speed | Use Case | Reliability | Cost |
|-------|-----------|----------|-------------|------|
| **A2/V30** | 30MB/s write | Production | High | $$$ |
| **Class 10/U3** | 10MB/s write | Development | Medium | $$ |
| **Class 10/U1** | 6MB/s write | Testing only | Low | $ |

**Recommended Brands:**
- Samsung EVO Select (A2)
- SanDisk Extreme (A2)
- Kingston Canvas React (A2)

**Avoid:**
- Generic/no-name cards
- Counterfeit cards (common on marketplace sites)
- Class 4 or lower

### Storage Performance Impact
```bash
# Test SD card performance
sudo hdparm -tT /dev/mmcblk0

# Expected results:
# A2 cards: 40-50 MB/s read
# Class 10: 20-30 MB/s read
# Slow cards: <15 MB/s read

# Poor storage causes:
# - Slow boot times (>5 minutes)
# - Application timeouts
# - Database corruption
# - General system sluggishness
```

### SSD Upgrades (Pi 4/5 only)
```bash
# USB 3.0 SSD setup
✅ Significantly faster than microSD
✅ Better reliability for production
✅ Easy setup with USB-to-SATA adapter

# NVMe SSD (Pi 5 only)
✅ Fastest storage option
✅ Official NVMe HAT available
⚠️ Requires additional power consideration
```

---

## 🌡️ Thermal Management

### Operating Temperature Ranges

| Model | Normal | Warning | Throttle | Shutdown | Cooling Required |
|-------|---------|---------|----------|----------|------------------|
| **Pi 5** | <60°C | 60-75°C | 80°C | 85°C | Yes (active) |
| **Pi 4B** | <65°C | 65-80°C | 80°C | 85°C | Recommended |
| **Pi 3B+** | <70°C | 70-80°C | 82°C | 85°C | Optional |
| **Zero 2W** | <70°C | 70-80°C | 82°C | 85°C | Rarely needed |

### Cooling Solutions

**Pi 5 Cooling (Essential):**
```
✅ Official Active Cooler (recommended)
✅ Third-party fan HATs
✅ Case with integrated cooling
❌ Passive heatsinks insufficient for kiosk use
```

**Pi 4B Cooling (Recommended):**
```
✅ FLIRC case (passive cooling)
✅ Argon ONE case (active cooling)
✅ Ice Tower CPU cooler
⚠️ Basic heatsinks (marginal for extended use)
```

### Thermal Monitoring
```bash
# Check current temperature
vcgencmd measure_temp

# Monitor throttling
watch -n 1 vcgencmd get_throttled

# Throttle status meanings:
# 0x0: No throttling
# 0x1: Under-voltage
# 0x2: ARM frequency capped
# 0x4: Currently throttled
# 0x8: Soft temperature limit active
```

---

## 🔧 Peripheral Compatibility

### USB Devices

**Tested Compatible:**
```
✅ Logitech wireless keyboards/mice
✅ Basic USB keyboards/mice
✅ USB WiFi dongles (see WiFi section)
✅ USB storage devices (FAT32, exFAT, ext4)
✅ USB webcams (UVC compatible)
✅ USB audio devices (most USB Audio Class)

⚠️ May require additional power:
- External USB hubs with power supply
- USB hard drives (need powered hub)
- High-power USB devices
```

**Not Recommended:**
```
❌ USB devices requiring >500mA per port
❌ Proprietary wireless dongles
❌ USB 1.1 legacy devices
❌ Devices requiring Windows-specific drivers
```

### GPIO and HAT Compatibility
```bash
# GPIO access from kiosk applications
✅ Standard GPIO libraries work
✅ I2C devices supported
✅ SPI devices supported
⚠️ Requires running as root or gpio group

# Compatible HATs:
✅ Sense HAT (environmental sensors)
✅ Camera modules (if needed for kiosk apps)
✅ Audio HATs (for enhanced sound)
✅ Display HATs (touchscreen integration)
```

---

## 🧪 Compatibility Testing Tools

### Automated Hardware Detection
```bash
# Run built-in compatibility check
python3 /opt/ossuary/tests/hardware_test.py

# Manual checks
lscpu                    # CPU information
free -h                  # Memory information
lsusb                   # USB devices
lspci                   # PCI devices (Pi 5 only)
vcgencmd version        # Firmware version
vcgencmd get_config int # Boot configuration
```

### Performance Benchmarks
```bash
# CPU benchmark
sysbench cpu --cpu-max-prime=20000 run

# Memory benchmark
mbw 128

# Storage benchmark
sudo hdparm -tT /dev/mmcblk0

# GPU benchmark (if available)
glmark2-es2

# Network benchmark
iperf3 -c speedtest.net -p 5201
```

### WebGL Compatibility Test
```javascript
// Browser console test
const canvas = document.createElement('canvas');
const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
console.log('WebGL Support:', !!gl);
console.log('WebGL Vendor:', gl ? gl.getParameter(gl.VENDOR) : 'None');
console.log('WebGL Renderer:', gl ? gl.getParameter(gl.RENDERER) : 'None');
```

---

## 📋 Compatibility Checklist

### Pre-Deployment Verification
```
Hardware Requirements:
[ ] Raspberry Pi model supported (Pi 3B+ minimum)
[ ] Adequate RAM (1GB minimum, 2GB+ recommended)
[ ] Quality microSD card (Class 10 minimum, A2 preferred)
[ ] Proper power supply (official recommended)
[ ] Compatible display with HDMI
[ ] Built-in WiFi or compatible USB dongle

Performance Requirements:
[ ] CPU benchmark passes minimum thresholds
[ ] Memory usage under 80% during operation
[ ] Storage write speed >10MB/s
[ ] GPU acceleration functional (WebGL test passes)
[ ] WiFi throughput adequate for use case
[ ] Temperature stays below throttle threshold

Compatibility Testing:
[ ] Captive portal opens on mobile devices
[ ] Network switching works reliably
[ ] Kiosk content displays correctly
[ ] Touch input responsive (if applicable)
[ ] System stable under sustained load
[ ] Auto-recovery after power loss
```

---

## 🆘 Troubleshooting Hardware Issues

### Common Hardware Problems

**Issue**: Device won't boot
```bash
Possible causes:
- Inadequate power supply
- Corrupted SD card
- Hardware failure

Diagnosis:
1. Check power LED (should be solid red)
2. Check activity LED (should blink during boot)
3. Try different SD card
4. Test with known good power supply
```

**Issue**: Poor WiFi performance
```bash
Diagnosis:
1. Check signal strength: iwconfig wlan0
2. Test with different networks
3. Try USB WiFi dongle
4. Check for interference (2.4GHz crowded)

Solutions:
- Reposition device for better signal
- Use 5GHz network if available
- Add external antenna (Pi 5)
- Use wired connection if possible
```

**Issue**: Display problems
```bash
Common symptoms:
- No display output
- Wrong resolution
- Poor performance

Solutions:
1. Force HDMI output: hdmi_force_hotplug=1
2. Set specific resolution: hdmi_group/hdmi_mode
3. Increase GPU memory: gpu_mem=128
4. Check HDMI cable and connections
```

**Issue**: Overheating and throttling
```bash
Symptoms:
- Slow performance
- System instability
- vcgencmd shows throttling

Solutions:
1. Add cooling (heatsink/fan)
2. Improve ventilation
3. Reduce GPU memory if not needed
4. Lower overclocking settings
5. Monitor ambient temperature
```

This comprehensive hardware compatibility guide ensures successful Ossuary Pi deployments across all supported Raspberry Pi models.