# Ossuary System - Complete Deep Analysis & Architecture Documentation

## Project Overview
Ossuary is a comprehensive IoT/embedded system designed for Raspberry Pi that provides:
- Captive portal for WiFi setup
- Kiosk browser mode for full-screen applications
- Network management and fallback AP
- RESTful API and WebSocket communication
- Configuration management system

## File Structure Analysis (43 total files)

### Core Services (5 systemd services)
1. **ossuary-config** - Configuration manager (first to start)
2. **ossuary-netd** - Network manager (depends on config)
3. **ossuary-api** - API Gateway (depends on config, netd)
4. **ossuary-portal** - Web portal server (depends on api)
5. **ossuary-kiosk** - Browser kiosk (depends on api, graphical target)

### Source Code Structure
```
src/
├── __init__.py
├── api/           (4 files) - API Gateway & WebSocket
├── config/        (4 files) - Configuration & Database
├── kiosk/         (4 files) - Browser Management
├── netd/          (4 files) - Network Management
└── portal/        (4 files) - Web Portal
```

### Supporting Files
- **web/** - Frontend assets (JS, CSS, HTML templates)
- **systemd/** - Service definitions
- **config/** - Default configuration
- **docs/** - Documentation
- **tests/** - Test suite

---

## Service Architecture Deep Dive

### 1. Configuration Service (ossuary-config)
**Purpose**: Centralized configuration management with file watching
**Files**: `src/config/`
- `manager.py` - Main configuration manager with file watching
- `schema.py` - Pydantic schemas for validation
- `network_db.py` - SQLite database for network storage
- `__init__.py` - Module exports

**Key Features**:
- Reactive file watching with asyncio integration (FIXED: thread-safe event loop)
- JSON-based configuration with validation
- Automatic backup system (keeps 10 backups)
- Schema migration support
- Network credentials database with encryption

**Configuration Schema**:
```json
{
  "system": { "hostname", "timezone", "log_level" },
  "network": { "ap_ssid", "ap_passphrase", "connection_timeout", "fallback_timeout" },
  "kiosk": { "url", "enable_webgl", "enable_webgpu", "refresh_interval" },
  "portal": { "bind_address", "bind_port", "ssl_enabled" },
  "api": { "bind_address", "bind_port", "auth_required", "cors_enabled" }
}
```

### 2. Network Service (ossuary-netd)
**Purpose**: WiFi management with NetworkManager integration
**Files**: `src/netd/`
- `manager.py` - NetworkManager interface (GI bindings)
- `service.py` - Service wrapper
- `states.py` - Network state enums and classes
- `exceptions.py` - Custom exceptions

**Key Features**:
- NetworkManager D-Bus integration via GI (gobject-introspection)
- WiFi scanning and connection management
- Access Point mode fallback
- Signal monitoring via polling (FIXED: removed unreliable signal handlers)
- State machine for connection lifecycle

**Network States**:
- `UNKNOWN`, `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `FAILED`, `AP_MODE`

**FIXED Issues**:
- Replaced unreliable NetworkManager signal handlers with polling
- Added proper error handling for missing WiFi devices
- Improved compatibility across different Pi models

### 3. API Gateway (ossuary-api)
**Purpose**: Unified REST API and WebSocket server
**Files**: `src/api/`
- `gateway.py` - FastAPI application with all endpoints
- `websocket.py` - WebSocket manager for real-time communication
- `middleware.py` - Authentication, rate limiting, security headers
- `service.py` - Service wrapper

**Key Features**:
- RESTful API for all system operations
- WebSocket support for real-time updates
- Middleware stack (auth, rate limiting, CORS, security headers)
- System control endpoints (restart, shutdown)
- Network management API
- Kiosk control API

**API Endpoints**:
```
GET  /health
GET  /api/v1/network/status
POST /api/v1/network/scan
POST /api/v1/network/connect
GET  /api/v1/kiosk/status
POST /api/v1/kiosk/navigate
GET  /api/v1/system/info
POST /api/v1/system/restart
WebSocket /ws
```

**FIXED Issues**:
- WebSocket authentication bypass for `/ws*` paths
- API Gateway now binds to all interfaces (0.0.0.0) instead of localhost only
- Fixed CORS policy (still uses wildcard - SECURITY CONCERN)

### 4. Portal Service (ossuary-portal)
**Purpose**: Captive portal web interface
**Files**: `src/portal/`
- `server.py` - FastAPI web server
- `api.py` - Portal-specific API endpoints
- `models.py` - Pydantic models for requests/responses
- `__init__.py` - Module exports

**Key Features**:
- Captive portal detection endpoints (Android, iOS, Windows)
- Web-based WiFi setup interface
- System status dashboard
- Kiosk configuration interface
- Template-based rendering with Jinja2

**Captive Portal Endpoints**:
```
GET /generate_204          (Android)
GET /hotspot-detect.html   (iOS)
GET /connecttest.txt       (Windows)
GET /{path:path}           (Catch-all redirect)
```

### 5. Kiosk Service (ossuary-kiosk)
**Purpose**: Full-screen Chromium browser management
**Files**: `src/kiosk/`
- `browser.py` - Chromium process management with hardware detection
- `manager.py` - High-level kiosk management
- `display.py` - Display configuration
- `service.py` - Service wrapper

**Key Features**:
- Chromium kiosk mode with hardware-optimized flags
- Pi model detection (Pi3, Pi4, Pi5) with specific GPU settings
- WebGL/WebGPU support based on hardware
- X11 session detection (FIXED: dynamic user detection)
- Process monitoring and auto-restart
- Display management (screensaver disable, cursor hiding)

**FIXED Issues**:
- Dynamic X11 XAUTHORITY detection instead of hardcoded /home/pi
- Proper X session user detection via ps/who commands
- Container vs host detection for security flags

---

## Communication Patterns

### Service Dependencies
```
ossuary-config (base)
    ↓
ossuary-netd (depends on config)
    ↓
ossuary-api (depends on config, netd)
    ↓
ossuary-portal (depends on api)
ossuary-kiosk (depends on api, graphical.target)
```

### Data Flow
1. **Configuration Changes**: File → config service → API → WebSocket broadcast
2. **Network Events**: NetworkManager → netd → API → WebSocket broadcast
3. **User Actions**: Portal Web UI → Portal API → Network/Kiosk services
4. **Real-time Updates**: Services → API Gateway → WebSocket → Frontend

### Inter-Service Communication
- **Configuration**: Shared JSON file `/etc/ossuary/config.json`
- **Network Database**: SQLite `/var/lib/ossuary/networks.db`
- **API Communication**: HTTP REST calls between services
- **Real-time Events**: WebSocket broadcasts from API Gateway

---

## Security Implementation

### Authentication & Authorization
- **API Gateway**: Optional token-based auth (disabled by default - SECURITY ISSUE)
- **Portal**: No authentication (captive portal design)
- **Middleware**: JWT-like bearer token validation
- **Rate Limiting**: Per-IP request throttling

### Security Headers
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'
```

### CORS Policy
- **Current**: Wildcard `*` (SECURITY VULNERABILITY)
- **Recommendation**: Restrict to specific origins

### Identified Security Issues
1. **Command Injection**: Unsafe subprocess calls in system control
2. **Root Privileges**: All services run as root (MAJOR RISK)
3. **SQL Injection**: String formatting in database queries
4. **Weak Passwords**: SHA256 without salt
5. **Default Config**: Auth disabled, empty tokens

---

## Hardware Compatibility

### Raspberry Pi Support
- **Pi 3**: VideoCore IV, basic WebGL support
- **Pi 4**: VideoCore VI with V3D, hardware decode
- **Pi 5**: VideoCore VII with Vulkan, WebGPU support (TESTED)

### Display Systems
- **X11**: EGL acceleration, traditional setup
- **Wayland**: Ozone platform, modern compositor
- **Auto-detection**: Based on environment variables

### Browser Optimization
- **Memory limits**: 512MB max old space size
- **Hardware acceleration**: Model-specific GPU flags
- **Security**: Conditional sandbox (disabled for containers/root)

---

## Configuration Deep Dive

### Default Configuration Analysis
```json
{
  "system": {
    "hostname": "ossuary",
    "timezone": "UTC",
    "log_level": "INFO"
  },
  "network": {
    "ap_ssid": "ossuary-setup",
    "ap_passphrase": null,          // Open AP by default
    "connection_timeout": 30,
    "fallback_timeout": 300         // 5 minutes to AP fallback
  },
  "api": {
    "bind_address": "0.0.0.0",      // FIXED: was 127.0.0.1
    "auth_required": false,         // SECURITY ISSUE
    "cors_enabled": true
  }
}
```

### Network Database Schema
```sql
CREATE TABLE networks (
    ssid TEXT NOT NULL,
    bssid TEXT,
    security_type TEXT,
    password_hash TEXT,             // SHA256 - WEAK
    auto_connect BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0,
    connect_count INTEGER,
    failed_attempts INTEGER
);

CREATE TABLE connection_history (
    network_id INTEGER,
    connected_at TIMESTAMP,
    success BOOLEAN,
    signal_strength INTEGER
);
```

---

## Deployment Architecture

### Systemd Integration
All services are managed by systemd with:
- **Dependencies**: Proper startup ordering
- **Restart policies**: Always restart on failure
- **Logging**: Journald integration
- **Capabilities**: Network management permissions for netd
- **User context**: All run as root (SECURITY CONCERN)

### File Locations
```
/etc/ossuary/config.json          # Main configuration
/var/lib/ossuary/networks.db      # Network database
/opt/ossuary/                     # Installation directory
/home/{user}/.Xauthority          # X11 auth (dynamic detection)
```

### Web Assets
```
web/
├── templates/
│   ├── index.html               # Main portal interface
│   └── error.html               # Error page template
└── assets/
    ├── app.js                   # Frontend JavaScript
    └── style.css                # Styling
```

---

## Critical Issues Identified

### HIGH PRIORITY
1. **Services running as root** - Major security vulnerability
2. **Command injection in system control APIs**
3. **SQL injection in network database queries**
4. **Weak password hashing (SHA256 without salt)**

### MEDIUM PRIORITY
5. **CORS wildcard policy**
6. **No input validation on many endpoints**
7. **Default insecure configuration**
8. **Browser sandbox disabled when running as root**

### FIXED ISSUES
- ✅ WebSocket authentication bypass
- ✅ API Gateway localhost-only binding
- ✅ NetworkManager signal handler failures
- ✅ Hardcoded X11 user assumptions
- ✅ Asyncio event loop errors in config watcher

---

## Testing & Quality Assurance

### Test Coverage
- **Unit Tests**: Basic system test file
- **Integration Tests**: None found
- **Security Tests**: None found
- **Browser Compatibility**: Pi 5 WebGPU tested

### Logging Strategy
- **Structured Logging**: Python logging with levels
- **Centralized**: All services log to journald
- **Debug Information**: Extensive browser startup logging
- **Error Handling**: Try/catch with proper error messages

---

## Performance Considerations

### Resource Usage
- **Memory**: Chromium limited to 512MB
- **CPU**: Polling-based network monitoring (every 5 seconds)
- **Disk**: SQLite database with cleanup policies
- **Network**: Minimal overhead, WebSocket for real-time updates

### Optimization Strategies
- **Hardware-specific browser flags**
- **Conditional feature enabling (WebGL/WebGPU)**
- **Connection pooling for database**
- **Background task management**

---

## Future Architecture Recommendations

### Security Hardening
1. Create dedicated service users instead of root
2. Implement proper input validation and sanitization
3. Use secure password hashing (bcrypt/Argon2)
4. Restrict CORS to specific origins
5. Enable authentication by default

### Performance Improvements
1. Replace polling with proper event handling where possible
2. Implement caching for frequent API calls
3. Add connection pooling
4. Optimize browser memory usage

### Monitoring & Observability
1. Add health check endpoints for all services
2. Implement metrics collection
3. Add structured logging with correlation IDs
4. Create system dashboard for monitoring

This analysis reveals a well-architected but security-vulnerable system that needs immediate hardening before production deployment.