# Ossuary Pi

Transforms Raspberry Pi into a kiosk device with WiFi captive portal setup and persistent process management.

## Features

- WiFi Connect captive portal for network configuration
- Process manager that keeps user commands running
- Web configuration interface on port 8080
- Automatic WiFi management and reconnection
- Works on Pi OS Bullseye through Trixie (Debian 11-13)

## Requirements

- Raspberry Pi 3/4/5 or Zero 2 W
- Pi OS Desktop (Bullseye/Bookworm/Trixie)
- Internet connection for initial setup

## Quick Setup

### 1. Flash Pi OS

Use Raspberry Pi Imager to flash Pi OS Desktop. Configure WiFi and SSH in the imager settings.

```bash
# Update system first
sudo apt update && sudo apt upgrade -y
sudo raspi-config --expand-rootfs
```

### 2. Install Ossuary Pi

```bash
git clone https://github.com/your-repo/ossuary-pi.git
cd ossuary-pi
sudo ./install.sh
```

### 3. Configure Startup Command

Access the configuration page at `http://[pi-ip]:8080` and set your startup command.

Example command for hardware-accelerated web display:
```bash
DISPLAY=:0 chromium --kiosk --start-fullscreen --noerrdialogs --disable-infobars --enable-features=Vulkan --enable-unsafe-webgpu --ignore-gpu-blocklist --enable-features=VaapiVideoDecoder,CanvasOopRasterization --password-store=basic https://lumencanvas.studio/projector/proj_j8sfRItFzUOE8ZGlyIE2T/user_33kWBuQgLbKnC84z1dLcCMe2nWY?nb
```

## Usage

### WiFi Configuration

If WiFi is not configured or connection fails:
1. Look for "Ossuary-Setup" WiFi network
2. Connect and browser should open captive portal automatically
3. If not, navigate to `http://192.168.4.1`
4. Select network and enter password

### Configuration Access

When connected to WiFi, access configuration at:
- `http://[hostname].local:8080`
- `http://[ip-address]:8080`

### Configuration Interface

The web interface provides:
- Startup command configuration
- Process control (start/stop/restart)
- System status monitoring
- Service log viewing
- Test command execution

## Commands

Check service status:
```bash
sudo systemctl status wifi-connect-manager
sudo systemctl status ossuary-startup
sudo systemctl status ossuary-web
```

View logs:
```bash
sudo journalctl -u wifi-connect-manager -f
sudo journalctl -u ossuary-startup -f
sudo journalctl -u ossuary-web -f
```

Force captive portal mode:
```bash
sudo nmcli device disconnect wlan0
sudo systemctl restart wifi-connect-manager
```

## Troubleshooting

### WiFi Issues

If WiFi connection fails:
```bash
# Stop services blocking connection
sudo systemctl stop wifi-connect
sudo systemctl stop wifi-connect-manager

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Enable WiFi and reconnect
sudo nmcli radio wifi on
sudo nmcli device set wlan0 managed yes
sudo nmcli device wifi rescan
sudo nmcli device connect wlan0

# Restart WiFi manager
sudo systemctl start wifi-connect-manager
```

### Process Issues

Check if startup command is running:
```bash
sudo systemctl status ossuary-startup
sudo journalctl -u ossuary-startup -n 20
```

### Debug Information

For detailed debugging:
```bash
./debug-wifi-connect.sh
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## File Structure

- `install.sh` - Main installation script
- `uninstall.sh` - Removal script
- `scripts/process-manager.sh` - Keeps user processes running
- `scripts/wifi-connect-manager.sh` - Manages captive portal
- `scripts/config-server-enhanced.py` - Configuration web server
- `custom-ui/` - Captive portal and configuration interfaces

## Technical Details

### Services

- `wifi-connect-manager` - Monitors WiFi and starts captive portal when needed
- `ossuary-startup` - Runs and monitors user startup command
- `ossuary-web` - Configuration server on port 8080

### Architecture Support

- ARM64 (Pi 4/5)
- ARMv7 (Pi 3/Zero 2 W)

Automatically detects architecture and downloads appropriate WiFi Connect binary.

## License

MIT License