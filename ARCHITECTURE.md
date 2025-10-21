# Ossuary-Pi System Architecture

## Overview

Ossuary-pi is a robust, self-configuring kiosk and captive portal system for Raspberry Pi that automatically switches between AP mode (for WiFi configuration) and client mode (for internet access), while providing a persistent kiosk interface.

## Core Design Principles

1. **Separation of Concerns**: Each service handles a specific domain
2. **Fail-Safe Operation**: System always provides a way to reconfigure
3. **NetworkManager Integration**: Use modern Pi OS networking stack
4. **API-First Design**: All functionality accessible via REST API
5. **Service Independence**: Services can restart independently
6. **Configuration Persistence**: Remember networks and settings across reboots

## System Components

### 1. Network Manager Service (`ossuary-netd`)
**Purpose**: WiFi state management and mode switching
- **Technology**: Python 3.9+ with NetworkManager D-Bus integration
- **Responsibilities**:
  - Monitor WiFi connection status
  - Switch between AP mode and client mode
  - Manage NetworkManager hotspot profiles
  - Handle connection timeouts and fallbacks
  - Trigger captive portal activation
- **Configuration**: `/etc/ossuary/network.json`
- **State Machine**:
  - DISCONNECTED → AP_MODE → CONNECTING → CONNECTED
  - Auto-fallback to AP_MODE after connection timeout

### 2. Portal Server (`ossuary-portal`)
**Purpose**: Captive portal web interface and API backend
- **Technology**: FastAPI (Python) with uvicorn ASGI server
- **Responsibilities**:
  - Serve captive portal web interface
  - Provide WiFi scanning API
  - Handle network connection requests
  - Manage kiosk URL configuration
  - Handle both HTTP (port 80) and HTTPS (port 443) for modern devices
- **Features**:
  - Mobile-first responsive design
  - Real-time network scanning
  - QR code generation for easy access
  - Configuration export/import

### 3. Kiosk Service (`ossuary-kiosk`)
**Purpose**: Browser management and display control
- **Technology**: Chromium with hardware acceleration
- **Responsibilities**:
  - Launch and manage Chromium in kiosk mode
  - Handle WebGL/WebGPU acceleration
  - Monitor and restart browser on crashes
  - Switch content based on connectivity state
- **Features**:
  - Hardware-accelerated graphics (WebGL)
  - Auto-recovery from crashes
  - Configurable timeout and refresh policies
  - Support for local and remote content

### 4. API Gateway (`ossuary-api`)
**Purpose**: Unified REST API and WebSocket interface
- **Technology**: FastAPI with WebSocket support
- **Responsibilities**:
  - Coordinate between all services
  - Provide unified REST API
  - WebSocket real-time updates
  - Authentication and rate limiting
  - Plugin hook management
- **Endpoints**:
  - `/api/v1/network/*` - Network management
  - `/api/v1/kiosk/*` - Kiosk control
  - `/api/v1/system/*` - System information
  - `/ws/events` - Real-time event stream

### 5. Configuration Manager (`ossuary-config`)
**Purpose**: Centralized configuration management
- **Technology**: Python with file watching
- **Responsibilities**:
  - Manage configuration files
  - Validate configuration changes
  - Notify services of config updates
  - Handle configuration backup/restore

## Network Architecture

### Access Point Mode
```
Phone/Laptop → [WiFi: ossuary-setup] → Raspberry Pi (192.168.42.1)
                                      ├─ HTTP: 80 → Portal
                                      ├─ HTTPS: 443 → Portal
                                      └─ DNS: * → 192.168.42.1
```

### Client Mode
```
Internet ←→ Router ←→ [WiFi] ←→ Raspberry Pi (DHCP)
                                ├─ Kiosk: Display Content
                                └─ API: Configuration Access
```

## Service Dependencies

```
└─ ossuary-config.service (config management)
   └─ ossuary-netd.service (network manager)
      └─ ossuary-api.service (API gateway)
         ├─ ossuary-portal.service (portal server)
         └─ ossuary-kiosk.service (browser/kiosk)
```

## Data Flow

### Initial Setup Flow
1. `ossuary-netd` detects no known networks
2. `ossuary-netd` activates AP mode via NetworkManager
3. `ossuary-portal` starts serving captive portal
4. User connects and configures WiFi + kiosk URL
5. `ossuary-netd` connects to specified network
6. `ossuary-kiosk` launches browser with configured URL

### Reconfiguration Flow
1. User accesses http://ossuary.local or Pi's IP
2. `ossuary-portal` serves configuration interface
3. Configuration changes sent via API
4. `ossuary-config` validates and persists changes
5. Affected services receive update notifications
6. Services apply new configuration

### Fallback Flow
1. `ossuary-netd` detects network disconnection
2. Timeout period allows for temporary outages
3. After timeout, `ossuary-netd` activates AP mode
4. `ossuary-kiosk` switches to local portal URL
5. System ready for reconfiguration

## Security Considerations

### Network Security
- AP mode uses WPA2 with configurable passphrase
- Portal access requires physical proximity (WiFi range)
- Optional rate limiting on API endpoints

### System Security
- Services run with minimal privileges
- Configuration files have restricted permissions
- No SSH keys or credentials in public repos
- Optional basic authentication for API access

### Captive Portal Detection
- Support HTTP (port 80) for legacy devices
- Support HTTPS (port 443) for modern Android/iOS
- Handle common connectivity check endpoints:
  - Android: `connectivitycheck.gstatic.com/generate_204`
  - iOS: `captive.apple.com/hotspot-detect.html`
  - Windows: `msftconnecttest.com/connecttest.txt`

## File System Layout

```
/etc/ossuary/
├── config.json           # Main configuration
├── network.json          # Network-specific settings
├── kiosk.json            # Kiosk-specific settings
└── ssl/                  # SSL certificates (if used)

/opt/ossuary/
├── bin/                  # Service executables
├── web/                  # Portal web assets
├── plugins/              # Plugin directory
└── logs/                 # Application logs

/var/lib/ossuary/
├── networks.db           # Known networks database
└── state/                # Service state files
```

## Configuration Schema

### Main Configuration (`/etc/ossuary/config.json`)
```json
{
  "system": {
    "hostname": "ossuary",
    "timezone": "UTC"
  },
  "network": {
    "ap_ssid": "ossuary-setup",
    "ap_passphrase": null,
    "connection_timeout": 30,
    "fallback_timeout": 300
  },
  "kiosk": {
    "url": "",
    "refresh_interval": 0,
    "enable_webgl": true,
    "enable_webgpu": false
  },
  "portal": {
    "bind_port": 80,
    "ssl_port": 443,
    "ssl_enabled": false
  },
  "api": {
    "enabled": true,
    "bind_port": 8080,
    "auth_required": false
  }
}
```

## Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Network Management | NetworkManager + Python D-Bus | Modern Pi OS standard, reliable |
| API Backend | FastAPI + uvicorn | High performance, modern Python async |
| Portal Frontend | Vanilla JS + Tailwind CSS | Lightweight, no build dependencies |
| Kiosk Browser | Chromium | Hardware acceleration, WebGL support |
| Configuration | JSON files | Human readable, easy to backup |
| Services | systemd | Native Linux service management |
| Database | SQLite | Lightweight, embedded, reliable |

## Performance Considerations

- Services designed for Pi Zero 2W minimum specs
- Lazy loading of non-essential components
- Efficient event-driven architecture
- Minimal memory footprint through careful dependency selection
- Hardware acceleration utilized where available

## Future Extensibility

- Plugin architecture for custom functionality
- WebSocket API for real-time integrations
- Bluetooth integration hooks prepared
- Container deployment support (Balena)
- Custom image generation pipeline support