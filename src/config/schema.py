"""Configuration schema definitions using Pydantic."""

from typing import Optional
from pydantic import BaseModel, Field, field_validator
import ipaddress


class SystemConfig(BaseModel):
    """System-level configuration."""
    hostname: str = Field(default="ossuary", min_length=1, max_length=63)
    timezone: str = Field(default="UTC")
    log_level: str = Field(default="INFO", regex="^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$")


class NetworkConfig(BaseModel):
    """Network configuration settings."""
    ap_ssid: str = Field(default="ossuary-setup", min_length=1, max_length=32)
    ap_passphrase: Optional[str] = Field(default=None, min_length=8, max_length=63)
    ap_channel: int = Field(default=6, ge=1, le=13)
    ap_ip: str = Field(default="192.168.42.1")
    ap_subnet: str = Field(default="192.168.42.0/24")
    connection_timeout: int = Field(default=30, ge=5, le=300)
    fallback_timeout: int = Field(default=300, ge=60, le=3600)
    scan_interval: int = Field(default=10, ge=5, le=60)

    @field_validator("ap_ip")
    @classmethod
    def validate_ap_ip(cls, v):
        """Validate AP IP address."""
        try:
            ipaddress.IPv4Address(v)
            return v
        except ipaddress.AddressValueError:
            raise ValueError("Invalid IPv4 address")

    @field_validator("ap_subnet")
    @classmethod
    def validate_ap_subnet(cls, v):
        """Validate AP subnet."""
        try:
            ipaddress.IPv4Network(v, strict=False)
            return v
        except ipaddress.AddressValueError:
            raise ValueError("Invalid IPv4 subnet")


class KioskConfig(BaseModel):
    """Kiosk browser configuration."""
    url: str = Field(default="")
    default_url: str = Field(default="http://ossuary.local")
    refresh_interval: int = Field(default=0, ge=0)
    enable_webgl: bool = Field(default=True)
    enable_webgpu: bool = Field(default=False)
    disable_screensaver: bool = Field(default=True)
    hide_cursor: bool = Field(default=True)
    autostart_delay: int = Field(default=5, ge=0, le=60)

    @field_validator("url", "default_url")
    @classmethod
    def validate_url(cls, v):
        """Basic URL validation."""
        if v and not (v.startswith("http://") or v.startswith("https://") or v.startswith("file://")):
            raise ValueError("URL must start with http://, https://, or file://")
        return v


class PortalConfig(BaseModel):
    """Portal server configuration."""
    bind_address: str = Field(default="0.0.0.0")
    bind_port: int = Field(default=80, ge=1, le=65535)
    ssl_port: int = Field(default=443, ge=1, le=65535)
    ssl_enabled: bool = Field(default=False)
    ssl_cert_path: str = Field(default="/etc/ossuary/ssl/cert.pem")
    ssl_key_path: str = Field(default="/etc/ossuary/ssl/key.pem")
    title: str = Field(default="Ossuary Setup", min_length=1, max_length=100)
    theme: str = Field(default="dark", regex="^(light|dark)$")


class RateLimitConfig(BaseModel):
    """Rate limiting configuration."""
    enabled: bool = Field(default=False)
    requests_per_minute: int = Field(default=60, ge=1, le=1000)


class APIConfig(BaseModel):
    """API server configuration."""
    enabled: bool = Field(default=True)
    bind_address: str = Field(default="127.0.0.1")
    bind_port: int = Field(default=8080, ge=1, le=65535)
    auth_required: bool = Field(default=False)
    auth_token: str = Field(default="")
    cors_enabled: bool = Field(default=True)
    rate_limit: RateLimitConfig = Field(default_factory=RateLimitConfig)


class PluginConfig(BaseModel):
    """Plugin system configuration."""
    enabled: bool = Field(default=True)
    auto_load: bool = Field(default=True)
    plugin_dir: str = Field(default="/opt/ossuary/plugins")


class Config(BaseModel):
    """Main configuration container."""
    system: SystemConfig = Field(default_factory=SystemConfig)
    network: NetworkConfig = Field(default_factory=NetworkConfig)
    kiosk: KioskConfig = Field(default_factory=KioskConfig)
    portal: PortalConfig = Field(default_factory=PortalConfig)
    api: APIConfig = Field(default_factory=APIConfig)
    plugins: PluginConfig = Field(default_factory=PluginConfig)

    class Config:
        """Pydantic configuration."""
        validate_assignment = True
        extra = "forbid"