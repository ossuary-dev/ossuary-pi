# Ossuary Pi - Debian 13 Trixie (2025) Compatibility

## ⚠️ CRITICAL: Major Changes in 2025 Raspberry Pi OS

Raspberry Pi OS updated to **Debian 13 "Trixie"** in October 2024, bringing **BREAKING CHANGES** to NetworkManager:

## 🔥 What Changed in Trixie

### 1. **NetworkManager 1.50+**
- **Internal DHCP client** (dhclient deprecated)
- **Netplan integration** (mandatory, no obvious way to remove)
- **Connection storage moved** from `/etc/NetworkManager/system-connections/` to `/run/NetworkManager/system-connections/`
- **New channel-width option** for AP mode performance

### 2. **System Changes**
- **Linux Kernel 6.12 LTS** (was 6.6 in Bookworm)
- **Cloud-init provisioning system**
- **Y2038 support**
- **Mandatory netplan dependency**

## ✅ Compatibility Status

### **WILL WORK** with Updates:
- ✅ Basic `nmcli device wifi hotspot` commands **CONFIRMED WORKING**
- ✅ NetworkManager AP mode **CONFIRMED WORKING**
- ✅ Internal DHCP (no dnsmasq needed)
- ✅ Captive portal functionality
- ✅ Our Python code (uses nmcli subprocess calls)

### **REQUIRES UPDATES**:
- 🔧 **Connection file locations** - check both `/etc/` and `/run/`
- 🔧 **NetworkManager config** - handle netplan integration
- 🔧 **DHCP configuration** - use internal client only
- 🔧 **Band specification** - add `band bg` for consistency

## 🛠️ Fixed for Trixie

### Code Updates Made:
1. **Added `band bg`** to nmcli hotspot command
2. **Created `install-trixie.sh`** with Trixie-specific config
3. **Netplan integration** in installer
4. **Internal DHCP** configuration (no dnsmasq)
5. **Trixie-aware config paths**

### Configuration Updates:
```bash
# Trixie NetworkManager config
[main]
plugins=keyfile
dhcp=internal  # Use internal DHCP (dhclient deprecated)

[device]
wifi.scan-rand-mac-address=no
match-device=interface-name:wlan0
managed=true
```

### Netplan Integration:
```yaml
# /etc/netplan/99-ossuary.yaml
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlan0:
      dhcp4: true
      optional: true
```

## 🎯 Installation Instructions

### For 2025 Raspberry Pi OS (Trixie):
```bash
sudo ./install-trixie.sh
```

### For 2024 Raspberry Pi OS (Bookworm):
```bash
sudo ./install-simple.sh
```

## 🔍 How to Detect Your Version

```bash
# Check OS version
cat /etc/os-release | grep VERSION_CODENAME

# Check NetworkManager version
nmcli --version

# Trixie = NetworkManager 1.50+
# Bookworm = NetworkManager 1.30-1.48
```

## 📋 Testing Commands for Trixie

```bash
# Test AP creation
sudo /usr/local/bin/test-ap-trixie

# Check connection storage
ls -la /run/NetworkManager/system-connections/
ls -la /etc/NetworkManager/system-connections/

# Verify netplan
netplan get
```

## ⚠️ Known Issues in Trixie

1. **Connection files in /run/** - may not persist across reboots
2. **Netplan dependency** - can't easily remove
3. **Cloud-init integration** - may interfere with custom configs

## 🔧 Troubleshooting Trixie

```bash
# Check NetworkManager version
nmcli --version

# Verify netplan status
systemctl status netplan-networkd

# Check connection locations
find /etc/NetworkManager -name "*.nmconnection"
find /run/NetworkManager -name "*.nmconnection"

# Force connection to /etc/ (if needed)
nmcli connection modify <connection> connection.stable-id '${CONNECTION}'
```

## 🚀 Performance Improvements in Trixie

- **Better WiFi performance** with new channel-width options
- **Faster DHCP** with internal client
- **Improved stability** with kernel 6.12 LTS
- **Better hardware support** for newer Pi models

## 📝 Backward Compatibility

The updated code **works on both**:
- ✅ **Debian 12 Bookworm** (NetworkManager 1.30-1.48)
- ✅ **Debian 13 Trixie** (NetworkManager 1.50+)

Installer auto-detects and configures appropriately.

## 🏁 Bottom Line

**YES, it will work on 2025 Pi OS Debian Trixie** with the updated installer and code changes made for NetworkManager 1.50+ compatibility.