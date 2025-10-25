# Ossuary Pi Setup Guide

Complete setup instructions for transforming a Raspberry Pi into a kiosk device.

## Prerequisites

### Hardware Requirements
- Raspberry Pi 3, 4, 5, or Zero 2 W
- MicroSD card (16GB+ recommended)
- WiFi capability (built-in or USB adapter)
- Internet connection for setup

### Software Requirements
- Raspberry Pi OS Desktop (Bullseye, Bookworm, or Trixie)
- SSH access (recommended for headless setup)

## Step 1: Flash Pi OS

### Using Raspberry Pi Imager (Recommended)

1. Download and install [Raspberry Pi Imager](https://www.raspberrypi.org/software/)
2. Select Pi OS Desktop as the operating system
3. Click gear icon to configure settings:
   - Enable SSH with password authentication
   - Set username and password
   - Configure WiFi network and password
   - Set hostname (e.g., "ossuary-pi")
4. Flash to SD card
5. Insert SD card and boot Pi

### First Boot Setup

```bash
# SSH into the Pi (replace hostname/IP as needed)
ssh pi@ossuary-pi.local
# or
ssh pi@192.168.1.xxx

# Update system packages
sudo apt update && sudo apt upgrade -y

# Expand filesystem to use full SD card
sudo raspi-config --expand-rootfs

# Reboot to apply changes
sudo reboot
```

## Step 2: Install Ossuary Pi

### Download and Install

```bash
# Clone the repository
git clone https://github.com/your-username/ossuary-pi.git
cd ossuary-pi

# Run installer with sudo
sudo ./install.sh
```

### Installation Process

The installer will:
1. Check system compatibility
2. Download WiFi Connect binary for your Pi architecture
3. Install required packages
4. Copy scripts to `/opt/ossuary/`
5. Install captive portal UI to `/opt/ossuary/custom-ui/`
6. Create systemd services
7. Configure automatic startup

Installation takes 2-5 minutes depending on internet speed.

## Step 3: Configure Services

### Automatic Configuration

After installation, three services run automatically:

1. **wifi-connect-manager** - Monitors WiFi connection
2. **ossuary-startup** - Manages user startup command
3. **ossuary-web** - Configuration server on port 8080

### Verify Installation

```bash
# Check service status
sudo systemctl status wifi-connect-manager
sudo systemctl status ossuary-startup
sudo systemctl status ossuary-web

# View real-time logs
sudo journalctl -u wifi-connect-manager -f
```

## Step 4: Access Configuration

### If Pi is Connected to WiFi

Access the configuration interface:
- `http://[hostname].local:8080`
- `http://[pi-ip-address]:8080`

Example: `http://ossuary-pi.local:8080`

### If Pi is Not Connected to WiFi

The system will create a captive portal:

1. Look for "Ossuary-Setup" WiFi network
2. Connect with any device (no password required)
3. Browser should automatically open portal
4. If not, navigate to `http://192.168.4.1`

## Step 5: Configure Startup Command

### Web Interface

1. Access configuration page (see Step 4)
2. Navigate to "Startup Command" section
3. Enter your command
4. Click "Save Command"
5. Use "Test Command" to verify it works
6. Use "Start Process" to run immediately

### Example Commands

**Web Kiosk with Hardware Acceleration:**
```bash
DISPLAY=:0 chromium --kiosk --start-fullscreen --noerrdialogs --disable-infobars --enable-features=Vulkan --enable-unsafe-webgpu --ignore-gpu-blocklist --enable-features=VaapiVideoDecoder,CanvasOopRasterization --password-store=basic https://lumencanvas.studio/projector/proj_j8sfRItFzUOE8ZGlyIE2T/user_33kWBuQgLbKnC84z1dLcCMe2nWY?nb
```

**Python Application:**
```bash
cd /home/pi/myapp && python3 app.py
```

**Node.js Application:**
```bash
cd /home/pi/webapp && node server.js
```

### Command Requirements

- Commands run as root by default
- Use full paths for executables
- Set working directory with `cd` if needed
- Environment variables can be set inline

## Configuration Interface Details

### WiFi Section
- **Available Networks**: Shows scannable WiFi networks
- **Saved Networks**: Displays previously connected networks
- **Network Selection**: Click to auto-populate SSID field
- **Password Field**: Toggle visibility with Show/Hide button

### Startup Command Section
- **Command Field**: Enter shell command to run on startup
- **Test Command**: Execute command temporarily to verify it works
- **Process Control**: Start, stop, restart the managed process
- **Status Display**: Shows current process state

### System Status
- **WiFi Status**: Current connection state and SSID
- **Service Status**: Health of all Ossuary Pi services
- **Log Viewer**: Real-time logs from services

## Advanced Configuration

### Manual Configuration File

Configuration is stored in `/etc/ossuary/config.json`:

```json
{
  "startup_command": "your command here"
}
```

Edit manually if needed:
```bash
sudo nano /etc/ossuary/config.json
sudo systemctl reload ossuary-startup
```

### Service Management

```bash
# Restart services
sudo systemctl restart wifi-connect-manager
sudo systemctl restart ossuary-startup
sudo systemctl restart ossuary-web

# Enable/disable auto-start
sudo systemctl enable ossuary-startup
sudo systemctl disable ossuary-startup

# View service logs
sudo journalctl -u ossuary-startup -n 50
sudo journalctl -u wifi-connect-manager -n 50
sudo journalctl -u ossuary-web -n 50
```

### Network Management

```bash
# Force captive portal mode (for testing)
sudo nmcli device disconnect wlan0
sudo systemctl restart wifi-connect-manager

# Connect to WiFi manually
sudo nmcli device wifi connect "Network Name" password "password"

# List saved WiFi connections
nmcli connection show

# Show current WiFi status
iwgetid
nmcli device status
```

## Troubleshooting

### Captive Portal Issues

**Problem**: Ossuary-Setup network doesn't appear
```bash
# Check WiFi Connect service
sudo systemctl status wifi-connect
sudo journalctl -u wifi-connect -n 20

# Restart services
sudo systemctl restart wifi-connect-manager
```

**Problem**: Portal doesn't open automatically
- Navigate manually to `http://192.168.4.1`
- Check device is connected to Ossuary-Setup network
- Try different browser or clear cache

### Startup Command Issues

**Problem**: Command doesn't run on boot
```bash
# Check service status
sudo systemctl status ossuary-startup

# View logs
sudo journalctl -u ossuary-startup -n 20

# Check configuration
cat /etc/ossuary/config.json
```

**Problem**: Command runs but fails
- Use "Test Command" in web interface to debug
- Check that all dependencies are installed
- Verify file paths and permissions
- Check if command needs X11 display (add `DISPLAY=:0`)

### WiFi Connection Issues

**Problem**: Can't connect to WiFi
```bash
# Run emergency WiFi fix
sudo systemctl stop wifi-connect wifi-connect-manager
sudo systemctl restart NetworkManager
sudo nmcli radio wifi on
sudo nmcli device set wlan0 managed yes
sudo nmcli device wifi rescan
sudo nmcli device connect wlan0
sudo systemctl start wifi-connect-manager
```

**Problem**: Connection drops frequently
- Check WiFi signal strength
- Verify router settings
- Update Pi firmware: `sudo rpi-update`

### Configuration Interface Issues

**Problem**: Can't access http://hostname:8080
```bash
# Check web service
sudo systemctl status ossuary-web
sudo systemctl restart ossuary-web

# Check port is listening
sudo netstat -tlnp | grep :8080

# Try IP address instead of hostname
hostname -I
```

### Debug Tools

**Run comprehensive debug:**
```bash
./debug-wifi-connect.sh
```

**Check all service status:**
```bash
sudo systemctl status wifi-connect-manager ossuary-startup ossuary-web
```

**Monitor all logs live:**
```bash
sudo journalctl -u wifi-connect-manager -u ossuary-startup -u ossuary-web -f
```

## Common Use Cases

### Digital Signage
```bash
DISPLAY=:0 chromium --kiosk --start-fullscreen http://your-signage-url.com
```

### IoT Dashboard
```bash
cd /home/pi/dashboard && python3 -m http.server 8000 &
DISPLAY=:0 chromium --kiosk --start-fullscreen http://localhost:8000
```

### Security Camera
```bash
cd /home/pi && python3 camera_stream.py
```

### Industrial HMI
```bash
cd /home/pi/hmi && ./start_hmi.sh
```

## Maintenance

### Updates
```bash
cd ossuary-pi
git pull
sudo ./install.sh --update
```

### Backup Configuration
```bash
# Backup config
sudo cp /etc/ossuary/config.json ~/config-backup.json

# Restore config
sudo cp ~/config-backup.json /etc/ossuary/config.json
sudo systemctl reload ossuary-startup
```

### Complete Removal
```bash
sudo ./uninstall.sh
```

## Support

For issues and troubleshooting:
1. Check this guide first
2. Run `./debug-wifi-connect.sh` for diagnostic info
3. Check system logs with `journalctl`
4. Review GitHub issues for similar problems