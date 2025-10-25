# Ossuary Pi Usage Guide

Detailed usage instructions for the captive portal and configuration interface.

## Overview

Ossuary Pi provides two main interfaces:
1. **Captive Portal** - Appears when no WiFi connection exists
2. **Configuration Interface** - Always available when connected to WiFi

## Captive Portal

### When It Appears

The captive portal activates automatically when:
- No WiFi networks are configured
- Configured WiFi networks are unavailable
- WiFi connection is lost for more than 60 seconds

### Accessing the Portal

1. **Automatic Mode**: Connect to "Ossuary-Setup" WiFi network
   - Network appears in WiFi list
   - No password required
   - Browser should open portal automatically

2. **Manual Mode**: If portal doesn't open automatically
   - Ensure connected to "Ossuary-Setup" network
   - Open browser and navigate to `http://192.168.4.1`
   - Clear browser cache if page doesn't load

### Portal Interface

#### WiFi Configuration Tab

**Available Networks Section:**
- Shows all detected WiFi networks
- Networks sorted by signal strength
- Click any network to auto-populate SSID field
- Refresh button to rescan for networks

**Network Connection:**
- SSID field auto-populated when network selected
- Manual SSID entry for hidden networks
- Password field with show/hide toggle
- Connect button initiates connection

**Connection Process:**
1. Select network or enter SSID manually
2. Enter network password
3. Click "Connect to Network"
4. Device attempts connection
5. If successful, portal closes and device joins network
6. If failed, error message displays

#### Startup Command Tab

- Configure command to run after network connection
- Test command execution before saving
- Commands execute as root with network available

## Configuration Interface

### Accessing the Interface

**When connected to WiFi, access via:**
- `http://[hostname].local:8080`
- `http://[ip-address]:8080`

**Finding your device:**
```bash
# On the Pi
hostname -I

# From another device on same network
ping ossuary-pi.local
nmap -sn 192.168.1.0/24 | grep ossuary
```

### Interface Sections

#### Available Networks

**Network Cards Display:**
- SSID name prominently displayed
- Signal strength when available
- Security type (Open/Secured)
- Connection status indicators

**Status Indicators:**
- **Available** - Network detected and ready to connect
- **Connected** - Currently connected to this network
- **Saved** - Previously connected, credentials stored

**Actions:**
- Click network card to select for connection
- Auto-populates connection form
- Shows network metadata

#### Saved Networks

**Persistent Network List:**
- Networks you've previously connected to
- Shows even when networks not in range
- Stored in browser localStorage as fallback
- Retrieved from NetworkManager when available

**Network Information:**
- Last connection timestamp
- Network type and security
- Connection history

#### Connection Form

**SSID Field:**
- Auto-populated when network selected
- Manual entry for hidden networks
- Real-time validation

**Password Field:**
- Masked by default for security
- Toggle visibility with Show/Hide button
- Remembers setting in session

**Connect Button:**
- Dynamic text shows selected network
- Disabled during connection process
- Shows connection progress

#### Startup Command Management

**Command Configuration:**
- Large text area for command entry
- Syntax highlighting for shell commands
- Save button with immediate validation

**Process Control:**
- Start/Stop/Restart buttons
- Real-time process status
- Process ID display when running

**Command Testing:**
- Test button runs command temporarily
- Output displayed in real-time
- Stop test button to terminate
- Test results help debug before saving

#### System Status

**WiFi Status Display:**
- Current SSID and connection state
- IP address information
- Signal strength when available

**Service Health:**
- Status of all Ossuary Pi services
- Color-coded indicators
- Quick restart buttons

**Log Viewer:**
- Real-time log streaming
- Multiple log sources
- Searchable and filterable

## Usage Scenarios

### Initial Setup

1. **First Boot**:
   - Pi creates "Ossuary-Setup" network
   - Connect with phone/laptop
   - Portal opens automatically
   - Configure WiFi and startup command

2. **Network Change**:
   - Access config interface via WiFi
   - Add new network credentials
   - Switch between saved networks

### Daily Operations

**Checking Status:**
- Access config interface
- Review system status section
- Monitor service health

**Changing Commands:**
- Access startup command section
- Test new commands before saving
- Monitor process execution

**Network Management:**
- View saved networks
- Connect to different networks
- Remove unused network credentials

### Troubleshooting

**Connection Issues:**
- Use portal to reconfigure WiFi
- Check saved networks list
- Force portal mode if needed

**Command Problems:**
- Use test command feature
- Review real-time logs
- Adjust command syntax

## Advanced Features

### Command Examples

**Basic Web Kiosk:**
```bash
DISPLAY=:0 chromium --kiosk --start-fullscreen http://example.com
```

**Hardware Accelerated Display:**
```bash
DISPLAY=:0 chromium --kiosk --start-fullscreen --noerrdialogs --disable-infobars --enable-features=Vulkan --enable-unsafe-webgpu --ignore-gpu-blocklist --enable-features=VaapiVideoDecoder,CanvasOopRasterization --password-store=basic https://lumencanvas.studio/projector/proj_j8sfRItFzUOE8ZGlyIE2T/user_33kWBuQgLbKnC84z1dLcCMe2nWY?nb
```

**Python Application:**
```bash
cd /home/pi/app && python3 main.py
```

**Multiple Commands:**
```bash
cd /home/pi && python3 setup.py && python3 app.py
```

### Browser Compatibility

**Portal Access:**
- Works with all modern browsers
- Mobile browsers on phones/tablets
- Desktop browsers on laptops
- No JavaScript required for basic function

**Config Interface:**
- Requires JavaScript for full functionality
- Modern browser recommended
- Responsive design for mobile access

### Network Requirements

**Portal Network:**
- Creates isolated AP on 192.168.4.0/24
- DHCP server provides IP addresses
- No internet access until WiFi configured

**Configuration Access:**
- Requires device on same network as Pi
- Standard TCP/IP connectivity
- Port 8080 must be accessible

## Security Considerations

### Access Control

**Portal Security:**
- Open WiFi network (no password)
- Isolated from internet until configured
- Automatic timeout after 10 minutes idle

**Config Interface:**
- No authentication by default
- Network-level security only
- Consider firewall rules for public networks

### Data Protection

**Credentials:**
- WiFi passwords stored in NetworkManager
- Encrypted by system
- Not visible in web interface

**Commands:**
- Stored in plain text in config file
- Accessible to root user only
- Consider security implications of commands

## Limitations

### Portal Limitations

- Single device configuration at a time
- No concurrent connections to portal
- Limited to WiFi networks only
- Cannot configure enterprise networks

### Interface Limitations

- No user authentication
- Single command execution only
- No command scheduling
- No remote access controls

### Network Limitations

- WiFi only (no Ethernet configuration)
- Basic network types only
- No VPN configuration
- No static IP configuration through interface

## Troubleshooting Guide

### Portal Issues

**Portal doesn't appear:**
```bash
sudo systemctl status wifi-connect
sudo systemctl restart wifi-connect-manager
```

**Can't connect to portal network:**
- Check WiFi adapter is working
- Restart device WiFi
- Try different device

**Portal page won't load:**
- Clear browser cache
- Try incognito/private mode
- Navigate manually to 192.168.4.1

### Config Interface Issues

**Can't access config page:**
- Verify Pi IP address: `hostname -I`
- Check port 8080 access
- Restart ossuary-web service

**Interface not responding:**
- Check browser JavaScript enabled
- Try different browser
- Clear browser cache

**Commands not executing:**
- Use test command feature
- Check command syntax
- Review service logs

### Network Issues

**WiFi won't connect:**
- Verify password correct
- Check network compatibility
- Use debug script for diagnosis

**Frequent disconnections:**
- Check signal strength
- Verify router stability
- Update Pi firmware