# Ossuary Service Interactions & Data Flow

## Service Dependency Graph

```
┌─────────────────┐
│ ossuary-config  │ (Port: N/A, File-based)
│ Configuration   │
│ Manager         │
└────────┬────────┘
         │ reads config.json
         ▼
┌─────────────────┐     ┌─────────────────┐
│ ossuary-netd    │────▶│ ossuary-api     │ (Port: 8080)
│ Network Manager │     │ API Gateway     │
│                 │     │ + WebSocket     │
└─────────────────┘     └────────┬────────┘
                                 │ HTTP API calls
                                 ▼
                        ┌─────────────────┐
                        │ ossuary-portal  │ (Port: 80)
                        │ Web Portal      │
                        │ Captive Portal  │
                        └─────────────────┘

                        ┌─────────────────┐
                        │ ossuary-kiosk   │ (No network port)
                        │ Browser Manager │
                        │ Chromium Kiosk  │
                        └─────────────────┘
```

## Detailed Service Analysis

### 1. ossuary-config (Configuration Manager)
**Role**: Central configuration authority
**Dependencies**: None (base service)
**Dependents**: All other services

**Responsibilities**:
- Load/validate configuration from `/etc/ossuary/config.json`
- File watching with asyncio integration
- Configuration backup management (10 backups retained)
- Schema validation via Pydantic
- Change notification system

**Key Methods**:
```python
async def load_config() -> Config
async def save_config(config: Config) -> bool
async def update_config(updates: Dict[str, Any]) -> bool
async def get_config_value(key: str, default: Any = None) -> Any
```

**File Operations**:
- **Config File**: `/etc/ossuary/config.json` (primary)
- **Backups**: `/etc/ossuary/backups/config_YYYYMMDD_HHMMSS.json`
- **Default**: `/opt/ossuary/config/default.json` (template)

**Startup Sequence**:
1. Initialize directory structure
2. Load configuration (create from default if missing)
3. Start file watcher (watchdog + asyncio)
4. Begin serving other services

---

### 2. ossuary-netd (Network Manager)
**Role**: WiFi and network management
**Dependencies**: ossuary-config
**Dependents**: ossuary-api

**Responsibilities**:
- NetworkManager D-Bus interface (via GI bindings)
- WiFi scanning and connection management
- Access Point mode fallback
- Network state monitoring
- Connection history logging

**Key Methods**:
```python
async def scan_networks() -> List[WiFiNetwork]
async def connect_to_network(ssid: str, password: str) -> bool
async def start_access_point() -> bool
async def get_status() -> NetworkStatus
```

**NetworkManager Integration**:
- **Primary**: GI (gobject-introspection) bindings
- **Fallback**: Python-sdbus (if available)
- **Interface**: D-Bus communication with NetworkManager daemon
- **Monitoring**: 5-second polling loop (replaced unreliable signals)

**Network States**:
```python
class NetworkState(Enum):
    UNKNOWN = "unknown"
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    FAILED = "failed"
    AP_MODE = "ap_mode"
```

**Database Integration**:
- **Network Storage**: SQLite `/var/lib/ossuary/networks.db`
- **Connection History**: Timestamp, success/failure, signal strength
- **Credential Caching**: SHA256 hashed passwords (SECURITY ISSUE)

---

### 3. ossuary-api (API Gateway)
**Role**: Unified API and WebSocket server
**Dependencies**: ossuary-config, ossuary-netd
**Dependents**: ossuary-portal, ossuary-kiosk

**Responsibilities**:
- RESTful API for all system operations
- WebSocket real-time communication
- Authentication and authorization
- Rate limiting and security headers
- Service orchestration

**Network Configuration**:
- **Bind Address**: `0.0.0.0:8080` (all interfaces)
- **Protocol**: HTTP/WebSocket
- **CORS**: Wildcard `*` (SECURITY ISSUE)
- **Auth**: Optional bearer token (disabled by default)

**API Endpoints**:

**Health & System**:
```
GET  /health                     # Service health check
GET  /api/v1/system/info         # System information (CPU, memory, temp)
POST /api/v1/system/restart      # System reboot
POST /api/v1/system/shutdown     # System shutdown
```

**Network Management**:
```
GET  /api/v1/network/status      # Current network status
POST /api/v1/network/scan        # Scan for WiFi networks
POST /api/v1/network/connect     # Connect to WiFi network
GET  /api/v1/network/known       # List saved networks
DELETE /api/v1/network/known/{ssid} # Forget network
```

**Kiosk Control**:
```
GET  /api/v1/kiosk/status        # Browser status
POST /api/v1/kiosk/navigate      # Navigate to URL
POST /api/v1/kiosk/refresh       # Refresh browser
POST /api/v1/kiosk/restart       # Restart browser
```

**Configuration**:
```
GET  /api/v1/config              # Get full configuration
PUT  /api/v1/config              # Update configuration
GET  /api/v1/config/{key:path}   # Get specific config value
PUT  /api/v1/config/{key:path}   # Set specific config value
```

**WebSocket Communication**:
- **Endpoint**: `/ws`
- **Protocol**: JSON message-based
- **Features**: Subscriptions, topics, ping/pong
- **Message Types**:
  ```json
  {
    "type": "network_state_changed",
    "old_state": "disconnected",
    "new_state": "connected",
    "status": { ... }
  }
  ```

**Middleware Stack**:
1. **CORS**: Cross-origin request handling
2. **Rate Limiting**: Per-IP request throttling (60/min default)
3. **Authentication**: Bearer token validation
4. **Security Headers**: XSS, CSRF, content-type protection
5. **Request Logging**: Access log with timing

---

### 4. ossuary-portal (Web Portal)
**Role**: Captive portal and web interface
**Dependencies**: ossuary-api (for backend data)
**Dependents**: None

**Responsibilities**:
- Captive portal detection and redirection
- WiFi setup web interface
- System status dashboard
- Kiosk configuration interface
- Static asset serving

**Network Configuration**:
- **Bind Address**: `0.0.0.0:80` (all interfaces)
- **Protocol**: HTTP (HTTPS optional)
- **Templates**: Jinja2-based HTML rendering
- **Static Assets**: `/assets/*` paths

**Captive Portal Flow**:
```
Device connects to AP
    ↓
OS detects captive portal via test endpoints:
    - Android: GET /generate_204
    - iOS: GET /hotspot-detect.html
    - Windows: GET /connecttest.txt
    ↓
Redirect to portal interface (/)
    ↓
User selects WiFi network
    ↓
POST /api/v1/network/connect
    ↓
Success: Device moves to production network
```

**Frontend Communication**:
- **API Calls**: Direct HTTP to portal service (port 80)
- **WebSocket**: Connects to API gateway (port 8080) - FIXED
- **Real-time Updates**: Network status, scan results, system events

---

### 5. ossuary-kiosk (Browser Manager)
**Role**: Full-screen Chromium browser management
**Dependencies**: ossuary-api (for configuration and control)
**Dependents**: None

**Responsibilities**:
- Chromium process lifecycle management
- Hardware-optimized browser configuration
- Display and X11 session management
- Auto-restart and monitoring
- Performance optimization

**Browser Configuration**:
- **Process Management**: subprocess.Popen with process groups
- **Monitoring**: 5-second health check loop
- **Restart Policy**: Automatic restart on crash (max 5 attempts)
- **Resource Limits**: 512MB memory limit

**Hardware Detection**:
```python
def _detect_pi_model() -> str:
    # Reads /proc/cpuinfo for BCM chip identification
    # Returns: 'Pi3', 'Pi4', 'Pi5', 'Unknown'

def _detect_display_system() -> bool:
    # Checks XDG_SESSION_TYPE and WAYLAND_DISPLAY
    # Returns: True for Wayland, False for X11
```

**X11 Session Detection** (FIXED):
```python
def _detect_xauthority() -> Optional[str]:
    # 1. Check environment XAUTHORITY
    # 2. Find X server process owner via ps aux
    # 3. Try common paths for detected user
    # 4. Fallback to who command for logged-in users
    # 5. Last resort: common user paths (pi, user, root)
```

**Browser Flags by Pi Model**:

**Pi 5 (VideoCore VII)**:
```bash
--enable-features=VaapiVideoDecoder,CanvasOopRasterization,Vulkan
--enable-unsafe-webgpu  # WebGPU support
--ignore-gpu-blocklist
--use-gl=egl  # X11 mode
--ozone-platform=wayland  # Wayland mode
```

**Pi 4 (VideoCore VI)**:
```bash
--enable-gpu
--enable-gpu-rasterization
--enable-features=VaapiVideoDecoder
--ignore-gpu-blocklist
```

**Pi 3 (VideoCore IV)**:
```bash
--enable-gpu
--use-gl=egl
--ignore-gpu-blocklist
```

---

## Data Flow Patterns

### 1. Configuration Updates
```
User modifies config.json
    ↓
ossuary-config detects file change (watchdog)
    ↓
Config validation and reload
    ↓
Other services read updated config
    ↓
Services adjust behavior accordingly
```

### 2. Network Connection Flow
```
User selects WiFi in portal
    ↓
Frontend: POST /api/v1/network/connect
    ↓
API Gateway validates request
    ↓
API calls ossuary-netd.connect_to_network()
    ↓
NetworkManager D-Bus connection attempt
    ↓
Connection status monitoring
    ↓
WebSocket broadcast to all clients
    ↓
Frontend updates connection status
```

### 3. Real-time Event Distribution
```
Network state change in ossuary-netd
    ↓
Callback to API Gateway
    ↓
WebSocket broadcast to all connected clients
    ↓
Frontend receives event and updates UI
```

### 4. Kiosk URL Navigation
```
User enters URL in portal
    ↓
Frontend: POST /api/v1/kiosk/navigate
    ↓
API Gateway forwards to kiosk manager
    ↓
Kiosk manager restarts Chromium with new URL
    ↓
WebSocket notification of kiosk state change
```

---

## Inter-Service Communication

### Communication Methods
1. **Configuration**: Shared JSON file (read-only after service start)
2. **API Calls**: HTTP REST between services
3. **Database**: Shared SQLite database for network data
4. **WebSocket**: Real-time event broadcasting
5. **File System**: Logs via journald

### Service Discovery
- **Static Configuration**: Services know each other's endpoints
- **Local Network**: All services on same machine
- **Port Allocation**: Fixed port assignments

### Error Handling
- **Circuit Breaker**: Services handle downstream failures gracefully
- **Retry Logic**: Automatic retry for transient failures
- **Fallback Modes**: AP mode when network connection fails
- **Health Checks**: Regular service health validation

---

## Security Boundaries

### Service Isolation
- **User Context**: All services run as root (MAJOR SECURITY ISSUE)
- **Network Access**: All services can bind to network interfaces
- **File System**: Full file system access
- **Process Control**: Can execute system commands

### Attack Vectors
1. **Network**: External access to API endpoints
2. **Input Validation**: Malformed requests to APIs
3. **Command Injection**: System control endpoints
4. **File Access**: Configuration file manipulation
5. **Database**: SQL injection in network queries

### Trust Relationships
```
ossuary-config (trusted source of truth)
    ↓ config data
ossuary-netd (trusted network authority)
    ↓ network status
ossuary-api (trusted orchestrator)
    ↓ commands
ossuary-portal (user-facing, untrusted input)
ossuary-kiosk (trusted execution environment)
```

---

## Performance Characteristics

### Resource Usage Per Service
- **ossuary-config**: Minimal CPU, file I/O for config changes
- **ossuary-netd**: Moderate CPU for D-Bus calls, network I/O
- **ossuary-api**: High CPU for request processing, WebSocket management
- **ossuary-portal**: Moderate CPU for web serving, static assets
- **ossuary-kiosk**: High CPU/Memory for Chromium browser

### Bottlenecks
1. **NetworkManager D-Bus**: Can be slow for scan operations
2. **WebSocket Broadcasting**: Scales with number of connected clients
3. **Chromium Memory**: Limited to 512MB, can cause browser crashes
4. **SQLite Database**: Single writer limitation for network history

### Optimization Opportunities
1. **Caching**: API responses for frequently requested data
2. **Connection Pooling**: Database connections
3. **Event Batching**: Reduce WebSocket message frequency
4. **Background Tasks**: Offload heavy operations from request handlers

This detailed analysis shows a well-structured but security-vulnerable microservices architecture that needs immediate hardening for production use.