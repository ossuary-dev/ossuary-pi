# Ossuary Pi - Clean Installation Guide

**For Fresh Raspberry Pi OS Installation**

## What This Does

Creates a working WiFi access point that:
1. Shows up as "ossuary-setup" (no password) when Pi has no internet
2. When you connect with phone/laptop, opens captive portal automatically
3. Portal lets you scan and connect to WiFi networks
4. Remembers networks and auto-reconnects
5. Displays kiosk webpage once connected

## Installation Steps

### 1. Flash Fresh Raspberry Pi OS
- Use Raspberry Pi Imager
- Flash latest Raspberry Pi OS (Bookworm recommended)
- Enable SSH in imager settings
- Boot Pi and connect via SSH or keyboard

### 2. Install Ossuary
```bash
# Download and run simple installer
curl -fsSL https://raw.githubusercontent.com/your-repo/ossuary-pi/main/install-simple.sh | sudo bash

# OR if you have the files locally:
sudo ./install-simple.sh
```

### 3. Reboot
```bash
sudo reboot
```

### 4. Test Access Point
After reboot, the Pi should automatically create an access point:

```bash
# Check if AP is running
nmcli connection show --active

# Should see something like:
# NAME         UUID                   TYPE   DEVICE
# Hotspot      abc123...              wifi   wlan0

# Test AP manually if needed
sudo /usr/local/bin/test-ap
```

### 5. Connect with Phone/Laptop
1. Look for WiFi network "ossuary-setup"
2. Connect (no password required)
3. Open any webpage - should redirect to portal
4. Use portal to scan and connect to your WiFi

## Troubleshooting

### AP Not Showing Up
```bash
# Check NetworkManager status
systemctl status NetworkManager

# Check WiFi device
nmcli device

# Manually create AP
sudo nmcli device wifi hotspot ifname wlan0 ssid ossuary-setup
```

### Portal Not Opening
```bash
# Check portal service
systemctl status ossuary-portal

# Test portal directly
curl http://192.168.42.1

# Check logs
journalctl -u ossuary-portal -f
```

### Can't Connect to AP
```bash
# Check if device supports AP mode
iw list | grep -A 10 "Supported interface modes"

# Should show "AP" in the list
```

### WiFi Connection Fails
```bash
# Check network manager logs
journalctl -u NetworkManager -f

# Check saved connections
nmcli connection show
```

## Manual Testing Commands

```bash
# Create AP manually
sudo nmcli device wifi hotspot ifname wlan0 ssid test-ap

# Stop AP
sudo nmcli device disconnect wlan0

# Connect to WiFi manually
sudo nmcli device wifi connect "YourWiFi" password "yourpassword"

# Check connection status
nmcli device status
```

## What Files Were Changed

### Added:
- `/opt/ossuary/` - All application files
- `/etc/ossuary/config.json` - Configuration
- `/etc/NetworkManager/conf.d/99-ossuary.conf` - NetworkManager config
- `/usr/local/bin/test-ap` - AP test script
- SystemD services in `/etc/systemd/system/`

### Modified:
- NetworkManager configuration only

## Rollback

To completely remove:
```bash
sudo ./uninstall.sh
```

Or manually:
```bash
sudo systemctl disable ossuary-*
sudo rm -rf /opt/ossuary
sudo rm -rf /etc/ossuary
sudo rm /etc/NetworkManager/conf.d/99-ossuary.conf
sudo rm /usr/local/bin/test-ap
sudo systemctl daemon-reload
```

## Architecture

The system uses:
- **NetworkManager** for WiFi management (modern approach)
- **Python FastAPI** for captive portal web server
- **SystemD** for service management
- **SQLite** for remembering networks

No hostapd, dnsmasq, or other conflicting services.

## Expected Behavior

1. **Fresh boot with no WiFi configured**: Creates AP "ossuary-setup"
2. **Known WiFi available**: Connects automatically
3. **Known WiFi lost**: Falls back to AP mode after 2 minutes
4. **Portal access**: Any HTTP request redirects to configuration page
5. **WiFi configuration**: Scan, connect, and remember networks
6. **Kiosk mode**: Display configured URL once connected

This is a minimal, working implementation focused on reliability over features.