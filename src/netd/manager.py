"""Network Manager implementation using NetworkManager D-Bus interface."""

import asyncio
import logging
import subprocess
import ipaddress
from typing import Optional, List, Dict, Any, Callable
from datetime import datetime, timedelta

# Try sdbus NetworkManager bindings (may not be available on all systems)
try:
    from sdbus_async.networkmanager import NetworkManager as NMAsyncClient
    from sdbus_async.networkmanager.enums import DeviceType, DeviceState, ConnectivityState
    SDBUS_AVAILABLE = True
except ImportError:
    SDBUS_AVAILABLE = False

# Fallback to legacy GI bindings (deprecated but may be needed)
try:
    import gi
    gi.require_version('NM', '1.0')
    from gi.repository import NM, GLib
    GI_AVAILABLE = True
except ImportError:
    GI_AVAILABLE = False

if not SDBUS_AVAILABLE and not GI_AVAILABLE:
    logging.error("No NetworkManager bindings available. Install python3-gi and gir1.2-nm-1.0")
    raise ImportError("NetworkManager bindings not found")

if SDBUS_AVAILABLE:
    logging.info("Using sdbus NetworkManager bindings")
else:
    logging.warning("Using GI bindings for NetworkManager")

from .states import (
    NetworkState, ConnectionState, APState, WiFiNetwork,
    NetworkStatus, NetworkConfiguration, APConfiguration
)
from .exceptions import (
    NetworkError, ConnectionError, AccessPointError, ScanError,
    NetworkManagerError, TimeoutError, InterfaceError
)


class NetworkManager:
    """Manages WiFi connections and access point using NetworkManager."""

    def __init__(self, config: Dict[str, Any]):
        """Initialize NetworkManager.

        Args:
            config: Configuration dictionary
        """
        self.config = config
        self.logger = logging.getLogger(__name__)

        # NetworkManager client - prefer GI for better Pi compatibility
        self.use_sdbus = SDBUS_AVAILABLE and not GI_AVAILABLE
        self.nm_client = None
        self.wifi_device = None

        # Compatibility layer
        self._init_nm_client()

        # Current state
        self.current_state = NetworkState.UNKNOWN
        self.last_status = None
        self.ap_state = APState.INACTIVE

        # Event callbacks
        self.state_change_callbacks: List[Callable] = []

        # Connection management
        self.connection_timeout = config.get("connection_timeout", 30)
        self.fallback_timeout = config.get("fallback_timeout", 300)
        self.last_connection_attempt = None
        self.fallback_timer = None

        # AP configuration
        self.ap_config = APConfiguration(
            ssid=config.get("ap_ssid", "ossuary-setup"),
            password=config.get("ap_passphrase"),
            channel=config.get("ap_channel", 6),
            ip_address=config.get("ap_ip", "192.168.42.1"),
            subnet=config.get("ap_subnet", "192.168.42.0/24")
        )

    def _init_nm_client(self) -> None:
        """Initialize NetworkManager client with compatibility layer."""
        if self.use_sdbus:
            self.logger.info("Initializing modern python-sdbus-networkmanager")
            # Will be initialized async in initialize()
        else:
            self.logger.warning("Initializing legacy GI NetworkManager bindings")
            # Legacy initialization will be done in initialize()

    async def _init_sdbus_client(self) -> None:
        """Initialize python-sdbus NetworkManager client."""
        try:
            self.nm_client = NMAsyncClient()
            # Get WiFi device - devices might be a list of paths or objects
            devices = await self.nm_client.get_devices()

            for device_path in devices:
                try:
                    # Try to get device type directly if it's already an object
                    if hasattr(device_path, 'device_type'):
                        device_type = await device_path.device_type
                        if device_type == DeviceType.WIFI:
                            self.wifi_device = device_path
                            break
                    # If it's a path string, we need a different approach
                    elif isinstance(device_path, str):
                        # Skip for now - may need to create device object from path
                        continue
                except Exception as e:
                    self.logger.debug(f"Failed to check device {device_path}: {e}")
                    continue

            if not self.wifi_device:
                self.logger.warning("No WiFi device found via sdbus - running in wired-only mode")
                # Don't raise an error, continue without WiFi capability

        except Exception as e:
            self.logger.error(f"Failed to initialize sdbus client: {e}")
            raise NetworkManagerError(f"Failed to initialize NetworkManager: {e}")

    def _init_gi_client(self) -> None:
        """Initialize legacy GI NetworkManager client."""
        try:
            self.nm_client = NM.Client.new(None)
            self.wifi_device = self._get_wifi_device()

            if not self.wifi_device:
                self.logger.warning("No WiFi device found - running in wired-only mode")
                # Don't raise an error, just continue without WiFi capability
            else:
                self.logger.info(f"Found WiFi device: {self.wifi_device.get_iface()}")

        except Exception as e:
            self.logger.error(f"Failed to initialize GI client: {e}")
            raise NetworkManagerError(f"Failed to initialize NetworkManager: {e}")

    async def initialize(self) -> None:
        """Initialize NetworkManager connection."""
        if not SDBUS_AVAILABLE and not GI_AVAILABLE:
            raise NetworkManagerError("No NetworkManager bindings available")

        try:
            if self.use_sdbus:
                await self._init_sdbus_client()
            else:
                self._init_gi_client()

            # Set up signal handlers (if using GI) - optional
            if not self.use_sdbus:
                try:
                    self._setup_signal_handlers()
                    self.logger.debug("Signal handlers set up successfully")
                except Exception as e:
                    self.logger.warning(f"Failed to set up signal handlers: {e}")
                    self.logger.info("Continuing without signal handlers - functionality may be limited")

            # Check current state
            await self._update_network_state()

            self.logger.info(f"NetworkManager initialized successfully ({'sdbus' if self.use_sdbus else 'gi'})")

        except Exception as e:
            raise NetworkManagerError(f"Failed to initialize NetworkManager: {e}", e)

    def _get_wifi_device(self) -> Optional[NM.DeviceWifi]:
        """Get the first WiFi device."""
        wifi_devices = []
        for device in self.nm_client.get_devices():
            if device.get_device_type() == NM.DeviceType.WIFI:
                wifi_devices.append(device)
                self.logger.debug(f"Found WiFi device: {device.get_iface()}")

        if wifi_devices:
            self.logger.info(f"Found {len(wifi_devices)} WiFi device(s)")
            return wifi_devices[0]
        else:
            self.logger.debug("No WiFi devices found via NetworkManager")
            return None

    def _setup_signal_handlers(self) -> None:
        """Set up NetworkManager signal handlers."""
        try:
            # Try modern signal name first
            self.nm_client.connect('device-state-changed', self._on_device_state_changed)
        except Exception as e:
            self.logger.debug(f"Modern signal failed: {e}")
            try:
                # Try legacy signal name
                self.nm_client.connect('device_state_changed', self._on_device_state_changed)
            except Exception as e2:
                self.logger.warning(f"Failed to connect device state signal: {e2}")

        if self.wifi_device:
            try:
                self.wifi_device.connect('access-point-added', self._on_access_point_added)
                self.wifi_device.connect('access-point-removed', self._on_access_point_removed)
            except Exception as e:
                self.logger.debug(f"WiFi signal handlers failed: {e}")
                try:
                    # Try legacy signal names
                    self.wifi_device.connect('access_point_added', self._on_access_point_added)
                    self.wifi_device.connect('access_point_removed', self._on_access_point_removed)
                except Exception as e2:
                    self.logger.warning(f"Failed to connect WiFi signals: {e2}")
        else:
            self.logger.debug("No WiFi device available - skipping WiFi signal handlers")

    def _on_device_state_changed(self, client, device, new_state, old_state, reason):
        """Handle device state changes."""
        if self.wifi_device and device == self.wifi_device:
            asyncio.create_task(self._update_network_state())

    def _on_access_point_added(self, device, access_point):
        """Handle new access point discovered."""
        self.logger.debug(f"Access point added: {access_point.get_ssid()}")

    def _on_access_point_removed(self, device, access_point):
        """Handle access point removed."""
        self.logger.debug(f"Access point removed: {access_point.get_ssid()}")

    async def get_status(self) -> NetworkStatus:
        """Get current network status."""
        await self._update_network_state()
        return self.last_status

    async def _update_network_state(self) -> None:
        """Update internal network state."""
        try:
            if not self.wifi_device:
                # No WiFi device - set to disconnected state
                self.current_state = NetworkState.DISCONNECTED
                self.last_status = NetworkStatus(
                    state=NetworkState.DISCONNECTED,
                    ssid=None,
                    ip_address=None,
                    interface="wired-only",
                    signal_strength=0
                )
                return

            device_state = self.wifi_device.get_state()
            active_connection = self.wifi_device.get_active_connection()

            # Determine current state
            if device_state == NM.DeviceState.ACTIVATED and active_connection:
                connection = active_connection.get_connection()
                if self._is_ap_connection(connection):
                    state = NetworkState.AP_MODE
                    ssid = self.ap_config.ssid
                    ip_address = self.ap_config.ip_address
                else:
                    state = NetworkState.CONNECTED
                    ssid = self._get_connection_ssid(active_connection)
                    ip_address = self._get_device_ip(self.wifi_device)
            elif device_state == NM.DeviceState.PREPARE or device_state == NM.DeviceState.CONFIG:
                state = NetworkState.CONNECTING
                ssid = None
                ip_address = None
            elif device_state == NM.DeviceState.FAILED:
                state = NetworkState.FAILED
                ssid = None
                ip_address = None
            else:
                state = NetworkState.DISCONNECTED
                ssid = None
                ip_address = None

            # Get signal strength if connected
            signal_strength = None
            if state == NetworkState.CONNECTED and active_connection:
                signal_strength = self._get_signal_strength()

            # Check AP status
            ap_active = state == NetworkState.AP_MODE
            ap_clients = self._get_ap_client_count() if ap_active else 0

            # Create status
            self.last_status = NetworkStatus(
                state=state,
                ssid=ssid,
                ip_address=ip_address,
                signal_strength=signal_strength,
                interface=self.wifi_device.get_iface(),
                ap_active=ap_active,
                ap_ssid=self.ap_config.ssid if ap_active else None,
                ap_clients=ap_clients
            )

            # Handle state changes
            if state != self.current_state:
                old_state = self.current_state
                self.current_state = state
                self.logger.info(f"Network state changed: {old_state.name} -> {state.name}")

                # Notify callbacks
                for callback in self.state_change_callbacks:
                    try:
                        await callback(old_state, state, self.last_status)
                    except Exception as e:
                        self.logger.error(f"State change callback error: {e}")

                # Handle automatic fallback
                if state == NetworkState.DISCONNECTED:
                    await self._start_fallback_timer()
                elif state == NetworkState.CONNECTED:
                    await self._cancel_fallback_timer()

        except Exception as e:
            self.logger.error(f"Failed to update network state: {e}")

    def _is_ap_connection(self, connection: NM.Connection) -> bool:
        """Check if connection is an access point."""
        settings = connection.get_setting_wireless()
        if settings:
            mode = settings.get_mode()
            return mode == NM.SETTING_WIRELESS_MODE_AP
        return False

    def _get_connection_ssid(self, active_connection: NM.ActiveConnection) -> Optional[str]:
        """Get SSID from active connection."""
        try:
            connection = active_connection.get_connection()
            wireless_setting = connection.get_setting_wireless()
            if wireless_setting:
                ssid_bytes = wireless_setting.get_ssid()
                if ssid_bytes:
                    return ssid_bytes.get_data().decode('utf-8')
        except Exception as e:
            self.logger.error(f"Failed to get connection SSID: {e}")
        return None

    def _get_device_ip(self, device: NM.Device) -> Optional[str]:
        """Get IP address of device."""
        try:
            ip4_config = device.get_ip4_config()
            if ip4_config:
                addresses = ip4_config.get_addresses()
                if addresses:
                    return addresses[0].get_address()
        except Exception as e:
            self.logger.error(f"Failed to get device IP: {e}")
        return None

    def _get_signal_strength(self) -> Optional[int]:
        """Get current signal strength percentage."""
        try:
            active_ap = self.wifi_device.get_active_access_point()
            if active_ap:
                strength = active_ap.get_strength()
                return min(100, max(0, strength))
        except Exception as e:
            self.logger.error(f"Failed to get signal strength: {e}")
        return None

    def _get_ap_client_count(self) -> int:
        """Get number of clients connected to AP."""
        # This is a simplified implementation
        # In practice, you might need to parse hostapd logs or use other methods
        try:
            result = subprocess.run(
                ["iw", "dev", self.wifi_device.get_iface(), "station", "dump"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                # Count stations (rough implementation)
                return result.stdout.count("Station ")
        except Exception as e:
            self.logger.debug(f"Failed to get AP client count: {e}")
        return 0

    async def scan_networks(self) -> List[WiFiNetwork]:
        """Scan for available WiFi networks."""
        if not self.wifi_device:
            self.logger.warning("Cannot scan networks - no WiFi device available")
            return []

        try:
            self.logger.info("Scanning for WiFi networks")

            # Request scan
            self.wifi_device.request_scan_async(None, self._scan_callback, None)

            # Wait for scan to complete (with timeout)
            await asyncio.sleep(5)  # Give scan time to complete

            # Get access points
            access_points = self.wifi_device.get_access_points()
            networks = []

            # Get known connections
            known_connections = self._get_known_connections()

            for ap in access_points:
                ssid_bytes = ap.get_ssid()
                if not ssid_bytes:
                    continue

                ssid = ssid_bytes.get_data().decode('utf-8', errors='ignore')
                if not ssid:
                    continue

                bssid = ap.get_bssid()
                frequency = ap.get_frequency()
                strength = ap.get_strength()
                flags = ap.get_flags()
                wpa_flags = ap.get_wpa_flags()
                rsn_flags = ap.get_rsn_flags()

                # Determine security
                # Access 80211ApFlags safely (can't use direct attribute due to number prefix)
                NM80211ApFlags = getattr(NM, "80211ApFlags", None)
                privacy_flag = getattr(NM80211ApFlags, "PRIVACY", 1) if NM80211ApFlags else 1
                security = bool((flags & privacy_flag) or wpa_flags or rsn_flags)
                security_type = self._determine_security_type(flags, wpa_flags, rsn_flags)

                # Check if known
                known = ssid in known_connections

                # Check if currently connected
                connected = False
                active_ap = self.wifi_device.get_active_access_point()
                if active_ap and active_ap.get_bssid() == bssid:
                    connected = True

                network = WiFiNetwork(
                    ssid=ssid,
                    bssid=bssid,
                    frequency=frequency,
                    signal_strength=strength,
                    security=security,
                    security_type=security_type,
                    connected=connected,
                    known=known
                )

                networks.append(network)

            # Sort by signal strength
            networks.sort(key=lambda n: n.signal_strength, reverse=True)

            self.logger.info(f"Found {len(networks)} networks")
            return networks

        except Exception as e:
            raise ScanError(f"Failed to scan networks: {e}")

    def _scan_callback(self, device, result, user_data):
        """Callback for scan completion."""
        try:
            device.request_scan_finish(result)
        except Exception as e:
            self.logger.error(f"Scan callback error: {e}")

    def _get_known_connections(self) -> Dict[str, NM.Connection]:
        """Get known WiFi connections."""
        known = {}
        for connection in self.nm_client.get_connections():
            wireless_setting = connection.get_setting_wireless()
            if wireless_setting:
                ssid_bytes = wireless_setting.get_ssid()
                if ssid_bytes:
                    ssid = ssid_bytes.get_data().decode('utf-8', errors='ignore')
                    known[ssid] = connection
        return known

    def _determine_security_type(self, flags, wpa_flags, rsn_flags) -> str:
        """Determine security type from AP flags."""
        # Access 80211 flags safely (can't use direct attribute due to number prefix)
        NM80211ApSecurityFlags = getattr(NM, "80211ApSecurityFlags", None)
        NM80211ApFlags = getattr(NM, "80211ApFlags", None)

        # Define flag constants with fallbacks
        KEY_MGMT_PSK = getattr(NM80211ApSecurityFlags, "KEY_MGMT_PSK", 0x100) if NM80211ApSecurityFlags else 0x100
        KEY_MGMT_802_1X = getattr(NM80211ApSecurityFlags, "KEY_MGMT_802_1X", 0x200) if NM80211ApSecurityFlags else 0x200
        PRIVACY = getattr(NM80211ApFlags, "PRIVACY", 1) if NM80211ApFlags else 1

        if rsn_flags:
            if rsn_flags & KEY_MGMT_PSK:
                return "WPA2-PSK"
            elif rsn_flags & KEY_MGMT_802_1X:
                return "WPA2-Enterprise"
        elif wpa_flags:
            if wpa_flags & KEY_MGMT_PSK:
                return "WPA-PSK"
            elif wpa_flags & KEY_MGMT_802_1X:
                return "WPA-Enterprise"
        elif flags & PRIVACY:
            return "WEP"
        else:
            return "Open"

    async def connect_to_network(self, ssid: str, password: Optional[str] = None) -> bool:
        """Connect to a WiFi network."""
        if not self.wifi_device:
            self.logger.warning("Cannot connect to network - no WiFi device available")
            return False

        try:
            self.logger.info(f"Connecting to network: {ssid}")
            self.last_connection_attempt = datetime.now()

            # Check if connection already exists
            known_connections = self._get_known_connections()

            if ssid in known_connections:
                # Activate existing connection
                connection = known_connections[ssid]
                self.logger.info(f"Activating existing connection for {ssid}")
                self.nm_client.activate_connection_async(
                    connection, self.wifi_device, None, None,
                    self._activation_callback, None
                )
            else:
                # Create new connection
                self.logger.info(f"Creating new connection for {ssid}")
                connection = self._create_connection(ssid, password)
                self.nm_client.add_and_activate_connection_async(
                    connection, self.wifi_device, None, None,
                    self._activation_callback, None
                )

            # Wait for connection with timeout
            await self._wait_for_connection_state(
                [NetworkState.CONNECTED, NetworkState.FAILED],
                timeout=self.connection_timeout
            )

            if self.current_state == NetworkState.CONNECTED:
                self.logger.info(f"Successfully connected to {ssid}")
                return True
            else:
                self.logger.error(f"Failed to connect to {ssid}")
                return False

        except Exception as e:
            self.logger.error(f"Connection error: {e}")
            raise ConnectionError(f"Failed to connect to {ssid}: {e}")

    def _create_connection(self, ssid: str, password: Optional[str] = None) -> NM.Connection:
        """Create a new WiFi connection."""
        connection = NM.SimpleConnection.new()

        # Connection settings
        s_con = NM.SettingConnection.new()
        s_con.set_property(NM.SETTING_CONNECTION_ID, ssid)
        s_con.set_property(NM.SETTING_CONNECTION_TYPE, "802-11-wireless")
        s_con.set_property(NM.SETTING_CONNECTION_AUTOCONNECT, True)
        connection.add_setting(s_con)

        # Wireless settings
        s_wifi = NM.SettingWireless.new()
        s_wifi.set_property(NM.SETTING_WIRELESS_SSID, GLib.Bytes.new(ssid.encode('utf-8')))
        connection.add_setting(s_wifi)

        # Security settings
        if password:
            s_wifi_sec = NM.SettingWirelessSecurity.new()
            s_wifi_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "wpa-psk")
            s_wifi_sec.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, password)
            connection.add_setting(s_wifi_sec)

        # IP settings
        s_ip4 = NM.SettingIP4Config.new()
        s_ip4.set_property(NM.SETTING_IP_CONFIG_METHOD, NM.SETTING_IP4_CONFIG_METHOD_AUTO)
        connection.add_setting(s_ip4)

        s_ip6 = NM.SettingIP6Config.new()
        s_ip6.set_property(NM.SETTING_IP_CONFIG_METHOD, NM.SETTING_IP6_CONFIG_METHOD_AUTO)
        connection.add_setting(s_ip6)

        return connection

    def _activation_callback(self, client, result, user_data):
        """Callback for connection activation."""
        try:
            active_connection = client.activate_connection_finish(result)
            if active_connection:
                self.logger.info("Connection activation initiated")
            else:
                self.logger.error("Connection activation failed")
        except Exception as e:
            self.logger.error(f"Activation callback error: {e}")

    async def _wait_for_connection_state(self, target_states: List[NetworkState], timeout: int = 30) -> bool:
        """Wait for network to reach one of the target states."""
        start_time = datetime.now()

        while (datetime.now() - start_time).seconds < timeout:
            await self._update_network_state()
            if self.current_state in target_states:
                return True
            await asyncio.sleep(1)

        raise TimeoutError(f"Timeout waiting for network state {target_states}")

    async def start_access_point(self) -> bool:
        """Start access point mode."""
        try:
            self.logger.info(f"Starting access point: {self.ap_config.ssid}")

            # Create AP connection
            connection = self._create_ap_connection()

            # Activate AP connection
            self.nm_client.add_and_activate_connection_async(
                connection, self.wifi_device, None, None,
                self._ap_activation_callback, None
            )

            # Wait for AP to start
            await asyncio.sleep(5)  # Give AP time to start
            await self._update_network_state()

            if self.current_state == NetworkState.AP_MODE:
                self.logger.info("Access point started successfully")
                return True
            else:
                self.logger.error("Failed to start access point")
                return False

        except Exception as e:
            self.logger.error(f"AP start error: {e}")
            raise AccessPointError(f"Failed to start access point: {e}")

    def _create_ap_connection(self) -> NM.Connection:
        """Create access point connection."""
        connection = NM.SimpleConnection.new()

        # Connection settings
        s_con = NM.SettingConnection.new()
        s_con.set_property(NM.SETTING_CONNECTION_ID, f"{self.ap_config.ssid}-ap")
        s_con.set_property(NM.SETTING_CONNECTION_TYPE, "802-11-wireless")
        s_con.set_property(NM.SETTING_CONNECTION_AUTOCONNECT, False)
        connection.add_setting(s_con)

        # Wireless settings
        s_wifi = NM.SettingWireless.new()
        s_wifi.set_property(NM.SETTING_WIRELESS_SSID, GLib.Bytes.new(self.ap_config.ssid.encode('utf-8')))
        s_wifi.set_property(NM.SETTING_WIRELESS_MODE, NM.SETTING_WIRELESS_MODE_AP)
        s_wifi.set_property(NM.SETTING_WIRELESS_CHANNEL, self.ap_config.channel)
        connection.add_setting(s_wifi)

        # Security settings
        if self.ap_config.password:
            s_wifi_sec = NM.SettingWirelessSecurity.new()
            s_wifi_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "wpa-psk")
            s_wifi_sec.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, self.ap_config.password)
            connection.add_setting(s_wifi_sec)

        # IP settings
        s_ip4 = NM.SettingIP4Config.new()
        s_ip4.set_property(NM.SETTING_IP_CONFIG_METHOD, NM.SETTING_IP4_CONFIG_METHOD_SHARED)

        # Add static IP for the AP
        try:
            addr = NM.IPAddress.new(4, self.ap_config.ip_address, 24)
            if addr is None:
                self.logger.error(f"Failed to create IP address object for {self.ap_config.ip_address}")
                raise AccessPointError("Failed to create IP address configuration")
            s_ip4.add_address(addr)
        except Exception as e:
            self.logger.error(f"IP address configuration error: {e}")
            raise AccessPointError(f"Failed to configure IP address: {e}")

        connection.add_setting(s_ip4)

        return connection

    def _ap_activation_callback(self, client, result, user_data):
        """Callback for AP activation."""
        try:
            active_connection = client.add_and_activate_connection_finish(result)
            if active_connection:
                self.logger.info("AP activation initiated")
            else:
                self.logger.error("AP activation failed")
        except Exception as e:
            self.logger.error(f"AP activation callback error: {e}")

    async def stop_access_point(self) -> bool:
        """Stop access point mode."""
        try:
            self.logger.info("Stopping access point")

            # Find and deactivate AP connection
            for connection in self.nm_client.get_active_connections():
                nm_connection = connection.get_connection()
                if self._is_ap_connection(nm_connection):
                    self.nm_client.deactivate_connection_async(
                        connection, None, self._deactivation_callback, None
                    )
                    break

            await asyncio.sleep(3)  # Give time to stop
            await self._update_network_state()

            if self.current_state != NetworkState.AP_MODE:
                self.logger.info("Access point stopped successfully")
                return True
            else:
                self.logger.error("Failed to stop access point")
                return False

        except Exception as e:
            self.logger.error(f"AP stop error: {e}")
            raise AccessPointError(f"Failed to stop access point: {e}")

    def _deactivation_callback(self, client, result, user_data):
        """Callback for connection deactivation."""
        try:
            client.deactivate_connection_finish(result)
            self.logger.info("Connection deactivated")
        except Exception as e:
            self.logger.error(f"Deactivation callback error: {e}")

    async def _start_fallback_timer(self) -> None:
        """Start fallback timer to AP mode."""
        await self._cancel_fallback_timer()

        self.logger.info(f"Starting fallback timer ({self.fallback_timeout}s)")
        self.fallback_timer = asyncio.create_task(self._fallback_to_ap())

    async def _cancel_fallback_timer(self) -> None:
        """Cancel fallback timer."""
        if self.fallback_timer and not self.fallback_timer.done():
            self.fallback_timer.cancel()
            self.fallback_timer = None
            self.logger.info("Fallback timer cancelled")

    async def _fallback_to_ap(self) -> None:
        """Fallback to AP mode after timeout."""
        try:
            await asyncio.sleep(self.fallback_timeout)

            if self.current_state == NetworkState.DISCONNECTED:
                self.logger.info("Fallback timeout reached, starting AP mode")
                await self.start_access_point()

        except asyncio.CancelledError:
            self.logger.debug("Fallback timer cancelled")
        except Exception as e:
            self.logger.error(f"Fallback error: {e}")

    def add_state_change_callback(self, callback: Callable) -> None:
        """Add a callback for state changes."""
        self.state_change_callbacks.append(callback)

    def remove_state_change_callback(self, callback: Callable) -> None:
        """Remove a state change callback."""
        if callback in self.state_change_callbacks:
            self.state_change_callbacks.remove(callback)

    async def get_known_networks(self) -> List[Dict[str, Any]]:
        """Get list of known/saved networks."""
        known = []
        connections = self._get_known_connections()

        for ssid, connection in connections.items():
            # Skip AP connections
            if self._is_ap_connection(connection):
                continue

            # Get last used time if available
            settings = connection.get_settings()
            timestamp = settings.get('connection', {}).get('timestamp', 0)
            last_used = datetime.fromtimestamp(timestamp) if timestamp else None

            known.append({
                "ssid": ssid,
                "last_used": last_used.isoformat() if last_used else None,
                "auto_connect": True  # Simplified
            })

        return known

    async def forget_network(self, ssid: str) -> bool:
        """Remove a saved network."""
        try:
            known_connections = self._get_known_connections()

            if ssid not in known_connections:
                return False

            connection = known_connections[ssid]
            connection.delete_async(None, self._delete_callback, None)

            self.logger.info(f"Forgot network: {ssid}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to forget network {ssid}: {e}")
            return False

    def _delete_callback(self, connection, result, user_data):
        """Callback for connection deletion."""
        try:
            connection.delete_finish(result)
            self.logger.info("Connection deleted")
        except Exception as e:
            self.logger.error(f"Delete callback error: {e}")

    async def shutdown(self) -> None:
        """Shutdown network manager."""
        self.logger.info("Shutting down NetworkManager")
        await self._cancel_fallback_timer()

        # Clean up any resources
        if self.nm_client:
            self.nm_client = None