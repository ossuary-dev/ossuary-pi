# Ossuary Pi

A WiFi failover system for Raspberry Pi that automatically creates a configuration portal when network connection is lost.

## What It Does

- Monitors WiFi connectivity continuously
- When WiFi fails for 60+ seconds, launches a captive portal
- Provides web interface to configure new WiFi networks
- Manages a user-defined startup command with auto-restart
- Built on top of [raspi-captive-portal](https://github.com/Splines/raspi-captive-portal)

## Requirements

- Raspberry Pi with WiFi (tested on Pi 4 & 5)
- Raspberry Pi OS (Bullseye or newer)
- Python 3.7+
- Git

## Quick Start

```bash
# Clone with submodules
git clone --recursive https://github.com/yourusername/ossuary-pi.git
cd ossuary-pi

# Check requirements
./check-requirements.sh

# Install
sudo ./install.sh

# Test installation
sudo ./test.sh
```

## How It Works

1. **Normal Operation**: Device connects to known WiFi networks normally
2. **Connection Lost**: Monitor detects loss of internet connectivity
3. **Failover**: After 60 seconds, starts access point mode
4. **Configuration**: Users connect to "Ossuary-Setup" and configure WiFi
5. **Recovery**: Once configured, returns to normal WiFi mode

## Configuration Portal

When in AP mode:
- SSID: `Ossuary-Setup` (open network)
- URL: `http://192.168.4.1:8080`

Features:
- Scan for WiFi networks
- Connect to WPA/WPA2 networks
- Configure startup command
- View connection status

## File Structure

```
/opt/ossuary/
├── venv/                 # Python virtual environment
├── services/
│   └── monitor.py        # WiFi monitoring service
└── web/
    ├── app.py           # Flask web interface
    └── templates/       # HTML templates

/etc/ossuary/
└── config.json          # Configuration storage
```

## Commands

```bash
# Check service status
sudo systemctl status ossuary-monitor

# View logs
sudo journalctl -fu ossuary-monitor

# Force AP mode (for testing)
sudo systemctl stop wpa_supplicant

# Restart normal WiFi
sudo systemctl restart wpa_supplicant

# Run tests
sudo ./test.sh
```

## Troubleshooting

### Can't Connect to Portal

1. Check if AP is active:
```bash
sudo systemctl status hostapd
```

2. Check Flask app:
```bash
sudo journalctl -fu ossuary-monitor | grep app.py
```

3. Verify IP configuration:
```bash
ip addr show wlan0
```

### WiFi Won't Reconnect

```bash
# Restore normal operation
sudo ./fix-captive-portal.sh
```

### Installation Issues

- If installing over SSH, the script will warn you
- Services won't auto-start over SSH (reboot required)
- Check logs: `/tmp/ossuary-install.log`

## Uninstall

```bash
sudo ./uninstall.sh
```

This will:
- Stop all services
- Remove installed files
- Restore network configuration
- Clean up firewall rules

## How the Integration Works

This project uses [raspi-captive-portal](https://github.com/Splines/raspi-captive-portal) for the complex AP management:

1. Their setup handles hostapd, dnsmasq, dhcpcd configuration
2. We add our Flask interface for WiFi/startup configuration
3. Our monitor controls when to start/stop the AP
4. All the hard networking stuff is handled by their proven code

## License

MIT