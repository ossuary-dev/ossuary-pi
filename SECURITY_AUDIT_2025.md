# Security & Compatibility Audit Report 2025

**Date**: October 2025
**System**: Ossuary Pi - Captive Portal & Kiosk System
**Status**: ⚠️ CRITICAL ISSUES IDENTIFIED - REQUIRES IMMEDIATE FIXES

## Executive Summary

Based on comprehensive research of 2025 Raspberry Pi ecosystem, **3 CRITICAL ISSUES** have been identified that will cause system failures on modern Raspberry Pi OS Bookworm. Additionally, several hardware acceleration optimizations are needed.

---

## 🚨 CRITICAL ISSUE #1: NetworkManager Python Library Deprecation

### Problem
Our current implementation uses GI (GObject Introspection) bindings for NetworkManager:
```python
import gi
gi.require_version('NM', '1.0')
from gi.repository import NM, GLib
```

### 2025 Reality Check
- **python-networkmanager is ABANDONED** (deprecated for >1 year)
- **NetworkManager 1.40.4+ breaks D-Bus API compatibility**
- **GI bindings are legacy** - community moving to python-sdbus
- **Raspberry Pi Bookworm** ships with incompatible NetworkManager version

### Impact
- WiFi management will FAIL on Bookworm
- Captive portal setup will be BROKEN
- No fallback to AP mode possible

### Required Fix
Replace with `python-sdbus-networkmanager`:
```python
# OLD (BROKEN)
import gi
gi.require_version('NM', '1.0')
from gi.repository import NM

# NEW (2025)
from sdbus_async.networkmanager import NetworkManager as NM
from sdbus_async.networkmanager.enums import DeviceType, DeviceState
```

---

## 🚨 CRITICAL ISSUE #2: WebGL Hardware Acceleration Failures

### Problems Identified
1. **VC4 V3D Driver Issues**: Right-clicking disables compositing and breaks WebGL
2. **Chromium Flag Conflicts**: `--use-gl=egl` may cause GPU blacklisting
3. **Mesa Driver Incompatibility**: WebGL returns errors despite hardware support

### 2025 Research Findings
- **Common Workaround**: Reverting to `dtoverlay=vc4-fkms-v3d` (fake driver)
- **Flag Requirements**: Must enable "Hardware-accelerated video decode" in chrome://flags
- **Performance Issues**: WebGL works but may not achieve 60fps

### Impact
- Kiosk dashboards will be UNUSABLY SLOW
- WebGL content completely broken
- Hardware acceleration disabled

### Required Fixes
1. **Boot Config Detection**:
```bash
# Check if both return "okay"
cat /proc/device-tree/soc/firmwarekms@7e600000/status
cat /proc/device-tree/v3dbus/v3d@7ec04000/status
```

2. **Fallback Strategy**:
```python
# Detect GPU driver and adjust flags accordingly
def _detect_gpu_driver(self):
    try:
        result = subprocess.run(['glxinfo'], capture_output=True, text=True)
        if 'VC4 V3D' in result.stdout:
            return 'vc4'
        elif 'Mesa' in result.stdout:
            return 'mesa'
    except:
        return 'software'
```

3. **Dynamic Flag Selection**:
```python
# Adjust flags based on hardware
if gpu_driver == 'vc4':
    cmd.extend(['--use-gl=desktop'])  # Not EGL
elif gpu_driver == 'software':
    cmd.extend(['--disable-gpu'])
```

---

## 🚨 CRITICAL ISSUE #3: Chromium Security Flag Vulnerabilities

### Problem
Our current flags include serious security risks:
```python
"--no-sandbox",
"--disable-setuid-sandbox",
"--disable-dev-shm-usage",
```

### 2025 Security Reality
- **Container environments** require these flags BUT expose system
- **Balena deployment** runs as privileged container
- **X11 access** combined with no-sandbox = full system access

### Impact
- Any malicious website has FULL SYSTEM ACCESS
- Can escape container and access host
- Complete compromise of Pi system

### Required Fix
Implement conditional sandboxing:
```python
def _get_security_flags(self):
    """Get security flags based on environment."""
    if self._is_container():
        # Container requires disabled sandbox
        return ["--no-sandbox", "--disable-setuid-sandbox"]
    else:
        # Host system - use sandbox
        return ["--enable-sandbox"]

def _is_container(self):
    """Detect if running in container."""
    return os.path.exists('/.dockerenv') or 'container' in os.environ
```

---

## ⚠️ Additional Compatibility Issues

### Raspberry Pi 5 Support
- **Network Manager fails to start** with symbol lookup errors
- **USB-C power issues** affect WiFi stability
- **PCIe conflicts** with WiFi chips

### Python Dependencies
- **Requires Python 3.8+** for sdbus-networkmanager
- **Bookworm compatibility** needs testing
- **Package conflicts** with legacy python-networkmanager

### SystemD Service Issues
- **NetworkManager dependency** may fail on boot
- **D-Bus socket permissions** in containers
- **X11 access** requires proper user permissions

---

## 🔧 IMMEDIATE ACTION REQUIRED

### Priority 1: Update NetworkManager Integration
1. Replace GI bindings with python-sdbus-networkmanager
2. Add fallback for older systems
3. Test on Bookworm before deployment

### Priority 2: Fix WebGL Hardware Acceleration
1. Implement GPU driver detection
2. Add fallback rendering strategies
3. Create hardware validation tests

### Priority 3: Secure Chromium Configuration
1. Implement conditional sandbox disabling
2. Add security warnings for no-sandbox mode
3. Test in both container and host environments

### Priority 4: Comprehensive Testing
1. Test on Pi 4, Pi 5, and Pi Zero 2W
2. Validate on Bookworm and Bullseye
3. Test both Balena and direct installation

---

## 📋 Validation Checklist

Before deployment, MUST verify:

- [ ] NetworkManager D-Bus API works on Bookworm
- [ ] WiFi AP mode functions correctly
- [ ] WebGL acceleration performs adequately
- [ ] Captive portal detection works on iOS/Android
- [ ] Security flags appropriate for deployment environment
- [ ] SystemD services start in correct order
- [ ] Container permissions allow hardware access
- [ ] Pi 5 compatibility confirmed

**DEPLOYMENT SHOULD BE BLOCKED** until these critical issues are resolved.

---

## Recommendations

1. **Immediate**: Do not deploy current version to production
2. **Short-term**: Implement fixes for critical issues 1-3
3. **Long-term**: Consider alternative architectures (hostapd + dnsmasq instead of NetworkManager)
4. **Testing**: Establish automated testing on real Pi hardware

**Bottom Line**: The current implementation will fail catastrophically on modern Raspberry Pi systems. Critical updates required before any deployment.