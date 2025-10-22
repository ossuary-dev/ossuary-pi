"""Pydantic models for portal API."""

from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator
from datetime import datetime


class NetworkScanRequest(BaseModel):
    """Request to scan for networks."""
    refresh: bool = Field(default=True, description="Force refresh scan")


class NetworkConnectRequest(BaseModel):
    """Request to connect to network."""
    ssid: str = Field(..., min_length=1, max_length=32, description="Network SSID")
    password: Optional[str] = Field(default=None, max_length=63, description="Network password")
    hidden: bool = Field(default=False, description="Hidden network")

    @field_validator("password")
    @classmethod
    def validate_password(cls, v):
        """Validate password requirements."""
        if v is not None and len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v


class NetworkForgetRequest(BaseModel):
    """Request to forget a network."""
    ssid: str = Field(..., min_length=1, max_length=32, description="Network SSID")


class APModeRequest(BaseModel):
    """Request to toggle AP mode."""
    enable: bool = Field(..., description="Enable or disable AP mode")


class APModeStatus(BaseModel):
    """AP mode status response."""
    ap_mode_active: bool = Field(..., description="Whether AP mode is currently active")
    ssid: Optional[str] = Field(default=None, description="AP mode SSID if active")
    ip_address: Optional[str] = Field(default=None, description="AP mode IP address if active")


class KioskConfigRequest(BaseModel):
    """Request to update kiosk configuration."""
    url: Optional[str] = Field(default=None, description="Display URL")
    enable_webgl: Optional[bool] = Field(default=None, description="Enable WebGL")
    enable_webgpu: Optional[bool] = Field(default=None, description="Enable WebGPU")
    refresh_interval: Optional[int] = Field(default=None, ge=0, description="Refresh interval in seconds")

    @field_validator("url")
    @classmethod
    def validate_url(cls, v):
        """Validate URL format."""
        if v and not (v.startswith("http://") or v.startswith("https://") or v.startswith("file://")):
            raise ValueError("URL must start with http://, https://, or file://")
        return v


class SystemAction(BaseModel):
    """System action request."""
    action: str = Field(..., pattern="^(restart|shutdown|reload)$", description="Action to perform")


# Response models

class NetworkInfo(BaseModel):
    """Network information."""
    ssid: str
    bssid: str
    frequency: int
    signal_strength: int
    security: bool
    security_type: str
    connected: bool
    known: bool
    last_connected: Optional[datetime] = None

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None
        }


class NetworkStatus(BaseModel):
    """Current network status."""
    state: str
    ssid: Optional[str] = None
    ip_address: Optional[str] = None
    signal_strength: Optional[int] = None
    interface: Optional[str] = None
    ap_active: bool = False
    ap_ssid: Optional[str] = None
    ap_clients: int = 0
    last_error: Optional[str] = None
    timestamp: datetime

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class NetworkScanResponse(BaseModel):
    """Network scan response."""
    networks: List[NetworkInfo]
    scan_time: datetime
    total_found: int

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class NetworkListResponse(BaseModel):
    """Known networks list response."""
    networks: List[Dict[str, Any]]
    total_count: int


class KioskConfig(BaseModel):
    """Kiosk configuration."""
    url: str
    default_url: str
    enable_webgl: bool
    enable_webgpu: bool
    refresh_interval: int
    disable_screensaver: bool
    hide_cursor: bool
    autostart_delay: int


class SystemInfo(BaseModel):
    """System information."""
    hostname: str
    uptime: int
    cpu_percent: float
    memory_percent: float
    temperature: float
    version: str
    timestamp: datetime

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class APIResponse(BaseModel):
    """Generic API response."""
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
    timestamp: datetime

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class ErrorResponse(BaseModel):
    """Error response."""
    error: str
    detail: Optional[str] = None
    code: Optional[str] = None
    timestamp: datetime

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }