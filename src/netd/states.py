"""Network state definitions and management."""

from enum import Enum, auto
from dataclasses import dataclass
from typing import Optional, List, Dict, Any
from datetime import datetime


class NetworkState(Enum):
    """Network connection states."""
    UNKNOWN = auto()
    DISCONNECTED = auto()
    CONNECTING = auto()
    CONNECTED = auto()
    FAILED = auto()
    AP_MODE = auto()
    SCANNING = auto()


class ConnectionState(Enum):
    """WiFi connection states from NetworkManager."""
    UNKNOWN = 0
    ACTIVATING = 1
    ACTIVATED = 2
    DEACTIVATING = 3
    DEACTIVATED = 4
    FAILED = 5


class APState(Enum):
    """Access Point states."""
    INACTIVE = auto()
    STARTING = auto()
    ACTIVE = auto()
    STOPPING = auto()
    FAILED = auto()


@dataclass
class WiFiNetwork:
    """Represents a WiFi network."""
    ssid: str
    bssid: str
    frequency: int
    signal_strength: int
    security: bool
    security_type: str
    connected: bool = False
    known: bool = False
    last_connected: Optional[datetime] = None

    @property
    def signal_percentage(self) -> int:
        """Convert signal strength to percentage."""
        # Convert from dBm to percentage (rough approximation)
        if self.signal_strength >= -50:
            return 100
        elif self.signal_strength >= -60:
            return 80
        elif self.signal_strength >= -70:
            return 60
        elif self.signal_strength >= -80:
            return 40
        elif self.signal_strength >= -90:
            return 20
        else:
            return 10

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "ssid": self.ssid,
            "bssid": self.bssid,
            "frequency": self.frequency,
            "signal_strength": self.signal_percentage,
            "security": self.security,
            "security_type": self.security_type,
            "connected": self.connected,
            "known": self.known,
            "last_connected": self.last_connected.isoformat() if self.last_connected else None
        }


@dataclass
class NetworkStatus:
    """Current network status information."""
    state: NetworkState
    ssid: Optional[str] = None
    ip_address: Optional[str] = None
    signal_strength: Optional[int] = None
    interface: Optional[str] = None
    ap_active: bool = False
    ap_ssid: Optional[str] = None
    ap_clients: int = 0
    last_error: Optional[str] = None
    timestamp: datetime = None

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "state": self.state.name.lower(),
            "ssid": self.ssid,
            "ip_address": self.ip_address,
            "signal_strength": self.signal_strength,
            "interface": self.interface,
            "ap_active": self.ap_active,
            "ap_ssid": self.ap_ssid,
            "ap_clients": self.ap_clients,
            "last_error": self.last_error,
            "timestamp": self.timestamp.isoformat()
        }


@dataclass
class NetworkConfiguration:
    """Network configuration parameters."""
    ssid: str
    password: Optional[str] = None
    security_type: Optional[str] = None
    hidden: bool = False
    auto_connect: bool = True
    priority: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "ssid": self.ssid,
            "password": self.password,
            "security_type": self.security_type,
            "hidden": self.hidden,
            "auto_connect": self.auto_connect,
            "priority": self.priority
        }


@dataclass
class APConfiguration:
    """Access Point configuration."""
    ssid: str
    password: Optional[str] = None
    channel: int = 6
    ip_address: str = "192.168.42.1"
    subnet: str = "192.168.42.0/24"
    dhcp_range_start: str = "192.168.42.10"
    dhcp_range_end: str = "192.168.42.50"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "ssid": self.ssid,
            "password": self.password,
            "channel": self.channel,
            "ip_address": self.ip_address,
            "subnet": self.subnet,
            "dhcp_range_start": self.dhcp_range_start,
            "dhcp_range_end": self.dhcp_range_end
        }