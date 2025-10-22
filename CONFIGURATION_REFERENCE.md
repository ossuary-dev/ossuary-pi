# Ossuary Configuration Reference

## Overview
The Ossuary system uses a centralized JSON configuration file located at `/etc/ossuary/config.json`. All configuration parameters are validated using Pydantic schemas and support both file-based updates and API modifications.

## Configuration File Structure

```json
{
  "system": { ... },
  "network": { ... },
  "kiosk": { ... },
  "portal": { ... },
  "api": { ... },
  "plugins": { ... }
}
```

---

## System Configuration

**Path**: `config.system`

| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `hostname` | string | `"ossuary"` | 1-63 chars | System hostname |
| `timezone` | string | `"UTC"` | Valid timezone | System timezone |
| `log_level` | string | `"INFO"` | DEBUG/INFO/WARNING/ERROR/CRITICAL | Logging level |

**Example**:
```json
{
  "system": {
    "hostname": "my-ossuary-pi",
    "timezone": "America/New_York",
    "log_level": "DEBUG"
  }
}
```

---

## Network Configuration

**Path**: `config.network`

### Access Point Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `ap_ssid` | string | `"ossuary-setup"` | 1-32 chars | AP network name |
| `ap_passphrase` | string? | `null` | 8-63 chars or null | AP password (null = open) |
| `ap_channel` | int | `6` | 1-13 | WiFi channel |
| `ap_ip` | string | `"192.168.42.1"` | Valid IP | AP gateway IP |
| `ap_subnet` | string | `"192.168.42.0/24"` | Valid CIDR | AP subnet |

### Connection Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `connection_timeout` | int | `30` | 5-300 seconds | WiFi connection timeout |
| `fallback_timeout` | int | `300` | 60-3600 seconds | Time before AP fallback |
| `scan_interval` | int | `10` | 5-60 seconds | Network scan interval |

**Example**:
```json
{
  "network": {
    "ap_ssid": "MyDevice-Setup",
    "ap_passphrase": "setup123",
    "ap_channel": 11,
    "connection_timeout": 45,
    "fallback_timeout": 600
  }
}
```

---

## Kiosk Configuration

**Path**: `config.kiosk`

### Display Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `url` | string | `""` | Any URL | Current display URL |
| `default_url` | string | `"http://ossuary.local"` | Any URL | Fallback URL |
| `refresh_interval` | int | `0` | ≥ 0 seconds | Auto-refresh interval (0 = disabled) |

### Browser Features
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `enable_webgl` | bool | `true` | true/false | Enable WebGL acceleration |
| `enable_webgpu` | bool | `false` | true/false | Enable WebGPU (Pi 5 only) |
| `disable_screensaver` | bool | `true` | true/false | Disable screen blanking |
| `hide_cursor` | bool | `true` | true/false | Hide mouse cursor |
| `autostart_delay` | int | `5` | 0-60 seconds | Delay before browser start |

### Advanced Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `display_preference` | string | `"auto"` | auto/wayland/x11 | Display system preference |
| `browser_binary` | string | `"auto"` | Path or "auto" | Custom browser binary |

**Example**:
```json
{
  "kiosk": {
    "url": "https://my-dashboard.com",
    "enable_webgl": true,
    "enable_webgpu": true,
    "refresh_interval": 3600,
    "display_preference": "wayland"
  }
}
```

### Kiosk Extended Configuration (Not in Schema)
These settings are read directly by the display and browser modules:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `rotation` | int | `0` | Display rotation (0, 90, 180, 270) |
| `resolution` | string | `"auto"` | Display resolution |
| `brightness` | int | `100` | Display brightness (0-100) |

---

## Portal Configuration

**Path**: `config.portal`

### Network Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `bind_address` | string | `"0.0.0.0"` | Valid IP | Interface to bind to |
| `bind_port` | int | `80` | 1-65535 | HTTP port |
| `ssl_port` | int | `443` | 1-65535 | HTTPS port |
| `ssl_enabled` | bool | `false` | true/false | Enable HTTPS |

### SSL Configuration
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ssl_cert_path` | string | `"/etc/ossuary/ssl/cert.pem"` | SSL certificate file |
| `ssl_key_path` | string | `"/etc/ossuary/ssl/key.pem"` | SSL private key file |

### Interface Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `title` | string | `"Ossuary Setup"` | 1-100 chars | Portal page title |
| `theme` | string | `"dark"` | light/dark | UI theme |

**Example**:
```json
{
  "portal": {
    "bind_port": 8080,
    "ssl_enabled": true,
    "title": "My IoT Device Setup",
    "theme": "light"
  }
}
```

---

## API Configuration

**Path**: `config.api`

### Network Settings
| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `enabled` | bool | `true` | true/false | Enable API service |
| `bind_address` | string | `"0.0.0.0"` | Valid IP | Interface to bind to |
| `bind_port` | int | `8080` | 1-65535 | API port |

### Security Settings
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `auth_required` | bool | `false` | **SECURITY**: Enable authentication |
| `auth_token` | string | `""` | **SECURITY**: Bearer token |
| `cors_enabled` | bool | `true` | **SECURITY**: Enable CORS |

### Rate Limiting
**Path**: `config.api.rate_limit`

| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `enabled` | bool | `false` | true/false | Enable rate limiting |
| `requests_per_minute` | int | `60` | 1-1000 | Requests per minute per IP |

**Example**:
```json
{
  "api": {
    "bind_address": "127.0.0.1",
    "auth_required": true,
    "auth_token": "your-secure-token-here",
    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 120
    }
  }
}
```

---

## Plugin Configuration

**Path**: `config.plugins`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | bool | `true` | Enable plugin system |
| `auto_load` | bool | `true` | Auto-load plugins on startup |
| `plugin_dir` | string | `"/opt/ossuary/plugins"` | Plugin directory |

**Example**:
```json
{
  "plugins": {
    "enabled": true,
    "auto_load": false,
    "plugin_dir": "/custom/plugins"
  }
}
```

---

## Configuration Management

### File Operations
- **Location**: `/etc/ossuary/config.json`
- **Backup**: `/etc/ossuary/backups/config_YYYYMMDD_HHMMSS.json`
- **Validation**: Pydantic schema validation on load/save
- **Watching**: Automatic reload on file changes (asyncio + watchdog)

### API Operations
```bash
# Get full configuration
curl http://localhost:8080/api/v1/config

# Update specific value
curl -X PUT http://localhost:8080/api/v1/config/kiosk.url \
  -H "Content-Type: application/json" \
  -d '"https://new-url.com"'

# Bulk update
curl -X PUT http://localhost:8080/api/v1/config \
  -H "Content-Type: application/json" \
  -d '{"kiosk": {"url": "https://example.com", "enable_webgl": false}}'
```

### Environment Variables
Some configuration can be overridden via environment variables:

| Variable | Config Path | Description |
|----------|-------------|-------------|
| `OSSUARY_CONFIG_PATH` | N/A | Override config file location |
| `OSSUARY_LOG_LEVEL` | `system.log_level` | Override log level |
| `DISPLAY` | N/A | X11 display (auto-detected) |
| `XAUTHORITY` | N/A | X11 auth file (auto-detected) |

---

## Default Configuration File

**Complete `/etc/ossuary/config.json`**:
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
    "fallback_timeout": 300,
    "scan_interval": 10
  },
  "kiosk": {
    "url": "",
    "default_url": "http://ossuary.local",
    "refresh_interval": 0,
    "enable_webgl": true,
    "enable_webgpu": false,
    "disable_screensaver": true,
    "hide_cursor": true,
    "autostart_delay": 5,
    "display_preference": "auto",
    "browser_binary": "auto"
  },
  "portal": {
    "bind_address": "0.0.0.0",
    "bind_port": 80,
    "ssl_port": 443,
    "ssl_enabled": false,
    "ssl_cert_path": "/etc/ossuary/ssl/cert.pem",
    "ssl_key_path": "/etc/ossuary/ssl/key.pem",
    "title": "Ossuary Setup",
    "theme": "dark"
  },
  "api": {
    "enabled": true,
    "bind_address": "0.0.0.0",
    "bind_port": 8080,
    "auth_required": false,
    "auth_token": "",
    "cors_enabled": true,
    "rate_limit": {
      "enabled": false,
      "requests_per_minute": 60
    }
  },
  "plugins": {
    "enabled": true,
    "auto_load": true,
    "plugin_dir": "/opt/ossuary/plugins"
  }
}
```

---

## Configuration Validation

### Schema Validation
All configuration is validated using Pydantic schemas. Invalid configurations will:
1. Log validation errors
2. Fall back to previous valid configuration
3. Create backup of current config
4. Restore from backup if available
5. Generate default configuration as last resort

### Common Validation Errors
- **String length**: SSID too long (>32 chars)
- **Number ranges**: Port numbers outside 1-65535
- **Pattern matching**: Invalid log levels
- **Required fields**: Missing mandatory configuration
- **Type mismatches**: String where number expected

### Validation Tools
```bash
# Validate configuration file
python -c "
from src.config.schema import Config
import json
with open('/etc/ossuary/config.json') as f:
    config = Config(**json.load(f))
print('Configuration valid!')
"
```

---

## Security Considerations

### Sensitive Configuration
- **API tokens**: Should be randomly generated, 32+ characters
- **Passwords**: AP passphrases stored in plain text in config
- **File permissions**: Config file should be readable only by ossuary services

### Recommendations
1. **Enable API authentication**: Set `api.auth_required = true`
2. **Use secure tokens**: Generate random `api.auth_token`
3. **Restrict CORS**: Disable wildcard CORS in production
4. **Enable rate limiting**: Set `api.rate_limit.enabled = true`
5. **Use HTTPS**: Enable `portal.ssl_enabled` with valid certificates
6. **File permissions**: `chmod 600 /etc/ossuary/config.json`

### Example Secure Configuration
```json
{
  "api": {
    "auth_required": true,
    "auth_token": "randomly-generated-32-char-token-here",
    "cors_enabled": false,
    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 30
    }
  },
  "portal": {
    "ssl_enabled": true
  }
}
```

This configuration system provides comprehensive control over all Ossuary system behaviors while maintaining validation and backward compatibility.