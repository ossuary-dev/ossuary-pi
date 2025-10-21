# Ossuary-Pi

A robust, self-configuring kiosk and captive portal system for Raspberry Pi that provides seamless WiFi onboarding and persistent display management.

## Features

- **Auto WiFi Configuration**: Automatic captive portal when disconnected
- **Network Memory**: Remembers multiple WiFi networks across locations
- **Kiosk Mode**: Full-screen Chromium browser with WebGL acceleration
- **REST API**: Complete programmatic control over all functions
- **Easy Installation**: Single script deployment or Balena container
- **Self-Healing**: Automatic fallback to configuration mode when disconnected

## Quick Start

### Installation Script
```bash
curl -sSL https://raw.githubusercontent.com/yourusername/ossuary-pi/main/install.sh | sudo bash
```

### Balena Deployment
```bash
git clone https://github.com/yourusername/ossuary-pi.git
cd ossuary-pi
balena push myapp
```

## How It Works

1. **First Boot**: Pi creates "ossuary-setup" WiFi hotspot
2. **Configuration**: Connect to hotspot, configure WiFi and display URL
3. **Operation**: Pi connects to WiFi and displays configured content
4. **Mobility**: Automatically falls back to setup mode in new locations

## Usage

### Initial Setup
1. Power on Pi with Ossuary-Pi installed
2. Connect to "ossuary-setup" WiFi network on your phone
3. Your phone will automatically show the setup portal
4. Select your WiFi network and enter password
5. Configure the display URL (optional)
6. Submit - Pi will connect and display your content

### Reconfiguration
- Visit `http://ossuary.local` or Pi's IP address
- Access the same interface to change WiFi or display settings
- Changes take effect immediately

## Configuration

Main configuration file: `/etc/ossuary/config.json`

```json
{
  "network": {
    "ap_ssid": "ossuary-setup",
    "connection_timeout": 30
  },
  "kiosk": {
    "url": "https://your-dashboard.com",
    "enable_webgl": true
  }
}
```

## API Reference

### Network Management
- `GET /api/v1/network/status` - Current network status
- `GET /api/v1/network/scan` - Scan for WiFi networks
- `POST /api/v1/network/connect` - Connect to WiFi network

### Kiosk Control
- `GET /api/v1/kiosk/url` - Get current display URL
- `PUT /api/v1/kiosk/url` - Set new display URL
- `POST /api/v1/kiosk/refresh` - Refresh browser

### System Information
- `GET /api/v1/system/status` - System health and info
- `POST /api/v1/system/reboot` - Restart system

## Hardware Requirements

- Raspberry Pi 3B+ or newer (Pi Zero 2W minimum)
- 8GB+ SD card
- WiFi capability (built-in or USB adapter)
- HDMI display (optional for headless operation)

## Software Requirements

- Raspberry Pi OS Bookworm (12) or newer
- NetworkManager (included in modern Pi OS)
- Python 3.9+

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed system design.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on actual Pi hardware
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- [Issues](https://github.com/yourusername/ossuary-pi/issues) for bug reports
- [Discussions](https://github.com/yourusername/ossuary-pi/discussions) for questions

## Credits

Inspired by projects like Balena WiFi Connect and RaspAP, built with modern tools and practices for reliability and ease of use.