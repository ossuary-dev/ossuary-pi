# Ossuary Pi - Actual System Architecture (2025)

**Audit Date**: 2025-10-22
**Based On**: Complete codebase analysis (8,405 lines of Python across 27 files)

## What Ossuary Pi Actually Is

A modern, production-ready **Raspberry Pi kiosk system** with **WiFi access point management** and **captive portal configuration**. The system automatically switches between AP mode (for configuration) and client mode (for internet access) while maintaining a persistent full-screen browser display.

## Verified Technology Stack

- **Python 3.9+** with AsyncIO for all services
- **FastAPI** for web services and REST API
- **NetworkManager** for modern WiFi management (2025 best practices)
- **Chromium** for kiosk browser with hardware acceleration
- **SQLite** for network persistence
- **SystemD** for service orchestration
- **X11** for display management

## Actual Service Architecture

### Service Dependency Chain (VERIFIED)
```
ossuary-config (Configuration Management)
    ↓
ossuary-netd (Network Management)
    ↓
ossuary-api (API Gateway) + ossuary-portal (Web Portal)
    ↓
ossuary-kiosk (Browser) + ossuary-display (X Server)
```

### 1. Configuration Service (`ossuary-config`)
**File**: `src/config/manager.py` (466 lines)
**Purpose**: Centralized configuration with hot-reload

**Actual Implementation**:
- Pydantic schema validation for all settings
- File system watching for `/etc/ossuary/config.json`
- Thread-safe async configuration loading
- SQLite database for network persistence
- IP address and subnet validation

**Configuration Schema** (VERIFIED):
```python
Config:
  - system: SystemConfig (hostname, timezone, log_level)
  - network: NetworkConfig (AP settings, timeouts, IP ranges)
  - kiosk: KioskConfig (URL, fullscreen, hardware acceleration)
  - portal: PortalConfig (bind address/port)
  - api: APIConfig (authentication, rate limiting)
  - plugins: PluginConfig (plugin system - skeleton only)
```

### 2. Network Management Service (`ossuary-netd`)
**File**: `src/netd/manager.py` (1,292 lines) + service wrapper
**Purpose**: WiFi state management and NetworkManager integration

**Actual Features**:
- NetworkManager D-Bus interface with fallback to GI bindings
- Modern `nmcli device wifi hotspot` command usage
- State machine: DISCONNECTED → AP_MODE → CONNECTING → CONNECTED
- Automatic fallback to AP mode after connection timeout (300s default)
- WiFi network scanning and connection management
- Network persistence (remembers and auto-reconnects)
- Captive portal DNS configuration via iptables

**Network State Management**:
```python
NetworkState.DISCONNECTED  # No connection
NetworkState.CONNECTING    # Attempting connection
NetworkState.CONNECTED     # Connected to WiFi
NetworkState.AP_MODE       # Access point active
NetworkState.FAILED        # Connection failed
```

### 3. Portal Service (`ossuary-portal`)
**File**: `src/portal/server.py` (389 lines) + API routes
**Purpose**: Captive portal web interface and configuration API

**Actual Implementation**:
- FastAPI web server on port 80
- Captive portal detection endpoints for Android/iOS/Windows
- WiFi scanning and connection API
- System information display
- Responsive web interface
- CORS enabled for cross-origin requests

**Captive Portal Endpoints** (VERIFIED):
```
GET  /                    # Main portal page
GET  /starter             # System information
GET  /generate_204        # Android detection
GET  /hotspot-detect.html # Apple detection
GET  /connecttest.txt     # Windows detection
POST /api/network/scan    # WiFi scanning
POST /api/network/connect # WiFi connection
```

### 4. API Gateway Service (`ossuary-api`)
**File**: `src/api/gateway.py` (628 lines) + middleware
**Purpose**: Unified REST API with authentication and monitoring

**Actual Features**:
- JWT-based authentication
- Redis-powered rate limiting
- WebSocket support for real-time updates
- Request logging and security headers
- Service health monitoring
- System metrics (CPU, memory, temperature)

**Security Implementation**:
- `AuthMiddleware`: JWT token validation
- `RateLimitMiddleware`: Redis-based rate limiting
- `SecurityHeadersMiddleware`: Security headers
- `RequestLoggingMiddleware`: Comprehensive logging

### 5. Kiosk Service (`ossuary-kiosk`)
**Files**: `src/kiosk/browser.py` (823 lines) + display management
**Purpose**: Full-screen Chromium browser management

**Actual Features**:
- Chromium in full-screen kiosk mode
- Hardware acceleration detection and enablement
- Touch screen support
- Auto-restart on browser crashes
- URL change detection and automatic reload
- Performance monitoring (memory, CPU usage)
- GPU acceleration with proper driver detection

**Chromium Configuration**:
- Optimized flags for Pi hardware
- Disabled security features for kiosk use
- Hardware acceleration when available
- Touch event handling
- Auto-reload on network changes

### 6. Display Service (`ossuary-display`)
**File**: `src/display/service.py` (490 lines)
**Purpose**: X server and display management

**Actual Features**:
- X11 server startup and configuration
- Display detection and resolution setting
- Touch screen calibration
- DPMS power management
- Hardware-specific display configuration
- Multi-monitor support

## Verified Network Flow

### Access Point Mode
1. **NetworkManager** creates hotspot using modern `nmcli device wifi hotspot`
2. **DHCP** managed by NetworkManager (shared mode) - range 192.168.42.10-100
3. **DNS redirection** via iptables to 192.168.42.1
4. **Portal server** serves captive portal on port 80
5. **Device detection** triggers portal display

### Client Mode
1. **Network scanning** via NetworkManager D-Bus
2. **Connection attempts** with timeout management
3. **Automatic reconnection** to known networks
4. **Fallback to AP** if disconnected > 300 seconds

## Configuration File Structure (ACTUAL)

**Location**: `/etc/ossuary/config.json` (NOT `/etc/ossuary/network.json` as claimed)

```json
{
  "system": {
    "hostname": "ossuary",
    "timezone": "UTC",
    "log_level": "INFO"
  },
  "network": {
    "ap_ssid": "ossuary-setup",
    "ap_passphrase": null,
    "ap_channel": 6,
    "ap_ip": "192.168.42.1",
    "ap_subnet": "192.168.42.0/24",
    "connection_timeout": 30,
    "fallback_timeout": 300
  },
  "kiosk": {
    "url": "http://localhost:8080",
    "fullscreen": true,
    "hardware_acceleration": true
  },
  "portal": {
    "bind_address": "0.0.0.0",
    "bind_port": 80
  },
  "api": {
    "enabled": true,
    "bind_address": "0.0.0.0",
    "bind_port": 8080,
    "auth_enabled": true,
    "rate_limit": {
      "requests_per_minute": 60
    }
  }
}
```

## Installation and Management

### SystemD Services (VERIFIED)
```
ossuary-config.service    # Configuration management
ossuary-netd.service      # Network management
ossuary-api.service       # API gateway
ossuary-portal.service    # Web portal
ossuary-kiosk.service     # Browser management
ossuary-display.service   # X server management
```

### Installation Scripts
- `install.sh` (1,930 lines) - Comprehensive system installer
- `post-install.sh` (168 lines) - SSH-breaking operations
- `uninstall.sh` (223 lines) - Complete system removal
- `verify-install.sh` (234 lines) - Installation verification

## What Actually Works

✅ **Modern WiFi management** using NetworkManager (2025 approach)
✅ **Automatic AP fallback** when WiFi connection lost
✅ **Captive portal** with device detection for Android/iOS/Windows
✅ **Full-screen kiosk browser** with Chromium
✅ **REST API** with JWT authentication and rate limiting
✅ **Real-time updates** via WebSocket
✅ **Network persistence** - remembers WiFi networks
✅ **Service monitoring** and health checks
✅ **Hardware acceleration** detection and setup

## What Doesn't Exist (Documentation Claims)

❌ **HTTPS support** (port 443) - Only HTTP port 80 implemented
❌ **QR code generation** - Not found in codebase
❌ **Configuration export/import** - API endpoints missing
❌ **Plugin system** - Only skeleton implementation

## Development Artifacts (Cruft to Remove)

The project contains **1,371 lines of development cruft** in fix/debug scripts:
- `debug-*.sh` (4 files, 484 lines) - Development debugging
- `fix-*.sh` (7 files, 887 lines) - Development fixes

**Recommendation**: Remove all debug/fix scripts except `fix-modern-ap.sh`

## Summary

Ossuary Pi is a **well-architected, production-ready system** with modern design patterns and 2025 best practices. The core functionality is solid and extensively implemented. Main issues are documentation inaccuracies and development cruft that should be cleaned up.

**Architecture Quality**: ⭐⭐⭐⭐⭐ (5/5)
**Code Quality**: ⭐⭐⭐⭐ (4/5) - Some large files need refactoring
**Documentation Accuracy**: ⭐⭐ (2/5) - Several inaccuracies found