# Ossuary Pi - Simplified Captive Portal System

A lightweight Raspberry Pi configuration system that provides WiFi setup via captive portal and manages a user-defined startup command with automatic restart on failure.

## Features

- **Automatic WiFi Management**: Monitors WiFi connectivity and falls back to captive portal when disconnected
- **Web-Based Configuration**: Simple web interface for WiFi setup and startup command configuration
- **Auto-Restart Service**: User-defined command runs at startup with automatic restart on failure
- **Captive Portal**: Based on [raspi-captive-portal](https://github.com/Splines/raspi-captive-portal) for reliable AP mode

## How It Works

1. **WiFi Monitor Service**: Continuously checks network connectivity
2. **Fallback Logic**: If WiFi connection fails:
   - Attempts to reconnect to known networks
   - Launches captive portal if no known networks available
3. **Configuration Portal**: Accessible at `http://192.168.4.1:8080` when in AP mode
4. **Startup Command**: Runs user-defined command as a systemd service with auto-restart

## Installation

1. **Check Requirements** (optional but recommended):
```bash
./check-requirements.sh
```

2. **Install Ossuary**:
```bash
sudo ./install.sh
```

3. **Verify Installation** (optional):
```bash
sudo ./test-installation.sh
```

## Uninstallation

To completely remove Ossuary from your system:
```bash
sudo ./uninstall.sh
```

## Configuration

### Via Captive Portal

1. When no WiFi is available, connect to the `Ossuary-Setup` network
2. Navigate to `http://192.168.4.1:8080`
3. Configure:
   - WiFi networks (scan and connect)
   - Startup command (any command to run at boot)

### Manual Configuration

Configuration is stored in `/etc/ossuary/config.json`:

```json
{
  "startup_command": "chromium-browser --kiosk https://example.com",
  "wifi_networks": [
    {"ssid": "NetworkName", "password": "password123"}
  ]
}
```

## Services

- **ossuary-wifi-monitor**: Monitors WiFi and manages captive portal
- **ossuary-captive-portal**: Web configuration interface
- **ossuary-startup**: Runs user-defined startup command

## System Requirements

- Raspberry Pi with WiFi capability
- Raspberry Pi OS (Bullseye or newer)
- Python 3.7+

## File Structure

```
/opt/ossuary/
├── services/
│   └── wifi_monitor.py     # WiFi monitoring service
└── web/
    ├── app.py              # Flask web application
    └── templates/          # HTML templates

/etc/ossuary/
└── config.json             # System configuration

/etc/systemd/system/
├── ossuary-wifi-monitor.service
├── ossuary-captive-portal.service
└── ossuary-startup.service
```

## Startup Command Examples

- **Kiosk Mode**: `chromium-browser --kiosk --noerrdialogs https://example.com`
- **Python Script**: `python3 /home/pi/my_application.py`
- **Shell Script**: `/home/pi/scripts/startup.sh`
- **Node Application**: `node /home/pi/app/server.js`

## Troubleshooting

### Check Service Status

```bash
sudo systemctl status ossuary-wifi-monitor
sudo systemctl status ossuary-captive-portal
sudo systemctl status ossuary-startup
```

### View Logs

```bash
sudo journalctl -u ossuary-wifi-monitor -f
sudo journalctl -u ossuary-captive-portal -f
sudo journalctl -u ossuary-startup -f
```

### Manual Control

```bash
# Start/stop captive portal
sudo systemctl start ossuary-captive-portal
sudo systemctl stop ossuary-captive-portal

# Restart WiFi monitor
sudo systemctl restart ossuary-wifi-monitor

# Restart startup command
sudo systemctl restart ossuary-startup
```

## License

MIT License