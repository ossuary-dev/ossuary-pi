# Balena Deployment Guide

This guide explains how to deploy Ossuary Pi using Balena Cloud for easy management and updates.

## Prerequisites

1. **Balena Account**: Sign up at [balena.io](https://balena.io)
2. **Balena CLI**: Install the [Balena CLI](https://github.com/balena-io/balena-cli)
3. **Raspberry Pi**: Compatible with Pi 3B+, Pi 4, Pi Zero 2W

## Quick Deployment

### 1. Create Balena Application

```bash
# Login to Balena
balena login

# Create a new application
balena app create ossuary-pi --type raspberrypi4-64

# Clone the repository
git clone https://github.com/yourusername/ossuary-pi.git
cd ossuary-pi

# Add Balena remote
balena app ossuary-pi
git remote add balena <your-git-remote-url>
```

### 2. Deploy Application

```bash
# Push to Balena (builds and deploys)
git push balena main

# Or use Balena CLI
balena push ossuary-pi
```

### 3. Flash Device

```bash
# Download OS image
balena os download raspberrypi4-64 --version latest

# Configure and flash to SD card
balena os configure downloaded-image.img --app ossuary-pi
balena os flash downloaded-image.img --drive /dev/sdX
```

### 4. Boot and Configure

1. Insert SD card into Raspberry Pi and power on
2. Wait for first boot and application deployment (5-10 minutes)
3. Connect to "ossuary-setup" WiFi network
4. Configure your WiFi and display URL via captive portal

## Configuration

### Environment Variables

Configure your deployment through Balena Cloud dashboard or CLI:

```bash
# Set WiFi AP name
balena env add OSSUARY_AP_SSID "my-setup-network"

# Set kiosk URL
balena env add OSSUARY_KIOSK_URL "https://my-dashboard.com"

# Enable WebGL
balena env add OSSUARY_KIOSK_WEBGL "true"

# Set log level
balena env add OSSUARY_LOG_LEVEL "INFO"
```

### Device Configuration

Set device configuration variables for hardware optimization:

```bash
# GPU memory split
balena config write BALENA_HOST_CONFIG_gpu_mem 128

# Enable V3D driver for hardware acceleration
balena config write BALENA_HOST_CONFIG_dtoverlay vc4-kms-v3d

# Force HDMI output
balena config write BALENA_HOST_CONFIG_hdmi_force_hotplug 1

# Disable overscan
balena config write BALENA_HOST_CONFIG_disable_overscan 1
```

## Data Persistence

Ossuary Pi uses persistent volumes for:

- **Configuration**: `/data/ossuary/config`
- **Application Data**: `/data/ossuary/data`
- **Logs**: `/data/ossuary/logs`
- **Network Settings**: `/data/ossuary/network`

Data persists across application updates and device reboots.

## Monitoring

### Health Checks

The application includes built-in health checks:

- Portal health: `http://device-ip/health`
- API health: `http://device-ip:8080/health`

### Logs

View logs through Balena dashboard or CLI:

```bash
# View live logs
balena logs <device-uuid> --follow

# View service-specific logs
balena logs <device-uuid> --service ossuary-pi
```

### Device Management

```bash
# List devices
balena devices

# Restart application
balena device restart <device-uuid>

# Reboot device
balena device reboot <device-uuid>

# Open device terminal
balena ssh <device-uuid>
```

## Updates

### Automatic Updates

Balena automatically updates devices when you push new code:

```bash
# Deploy update
git push balena main

# Or using CLI
balena push ossuary-pi
```

### Manual Updates

Control update timing:

```bash
# Pin to specific release
balena device pin <device-uuid> <commit-or-release>

# Unpin for automatic updates
balena device pin <device-uuid> --remove
```

## Troubleshooting

### Common Issues

1. **Display not working**
   - Check HDMI connection
   - Verify GPU memory split: `BALENA_HOST_CONFIG_gpu_mem=128`
   - Enable HDMI force: `BALENA_HOST_CONFIG_hdmi_force_hotplug=1`

2. **WiFi not detected**
   - Ensure NetworkManager is running
   - Check device WiFi capabilities
   - Verify container has host network access

3. **Kiosk not starting**
   - Check X server logs: `balena logs <device> --service ossuary-pi`
   - Verify display environment variables
   - Check GPU driver configuration

### Debug Mode

Enable debug mode for detailed logging:

```bash
balena env add OSSUARY_DEBUG "true"
balena env add OSSUARY_LOG_LEVEL "DEBUG"
```

### SSH Access

Access device for debugging:

```bash
# SSH into device
balena ssh <device-uuid>

# SSH into application container
balena ssh <device-uuid> ossuary-pi

# Run commands in container
balena ssh <device-uuid> ossuary-pi "ossuaryctl status"
```

## Scaling

### Fleet Management

Deploy to multiple devices:

```bash
# Create fleet
balena fleet create my-kiosks --type raspberrypi4-64

# Move devices to fleet
balena device move <device-uuid> my-kiosks

# Set fleet-wide configuration
balena env add OSSUARY_KIOSK_URL "https://dashboard.company.com" --fleet my-kiosks
```

### Configuration Templates

Use device tags for different configurations:

```bash
# Tag devices by location
balena tag set location "office-lobby" <device-uuid>
balena tag set location "reception" <device-uuid>

# Set location-specific URLs
balena env add OSSUARY_KIOSK_URL "https://lobby.company.com" --device <lobby-device>
balena env add OSSUARY_KIOSK_URL "https://reception.company.com" --device <reception-device>
```

## Security

### Best Practices

1. **Change default credentials**: Set `OSSUARY_API_AUTH_TOKEN`
2. **Enable HTTPS**: Configure SSL certificates
3. **Network isolation**: Use VPN or private networks
4. **Regular updates**: Keep Balena OS and applications updated

### VPN Configuration

For secure remote access:

```bash
# Enable Balena VPN
balena tunnel <device-uuid> --port 8080:8080

# Access via tunnel
curl http://localhost:8080/api/v1/system/info
```

## Support

- **Documentation**: [GitHub Repository](https://github.com/yourusername/ossuary-pi)
- **Issues**: [GitHub Issues](https://github.com/yourusername/ossuary-pi/issues)
- **Balena Support**: [Balena Forums](https://forums.balena.io)
- **Community**: [Discord/Slack Channel]