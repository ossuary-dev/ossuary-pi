"""Portal API router implementation."""

import asyncio
import logging
import psutil
import subprocess
from typing import List, Dict, Any, Optional
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, HTTPException, BackgroundTasks, Depends
from fastapi.responses import JSONResponse

from .models import (
    NetworkScanRequest, NetworkConnectRequest, NetworkForgetRequest,
    KioskConfigRequest, SystemAction,
    NetworkInfo, NetworkStatus, NetworkScanResponse, NetworkListResponse,
    KioskConfig, SystemInfo, APIResponse, ErrorResponse
)
from netd import NetworkManager as NetManager
from config import ConfigManager


class APIRouter:
    """API router for portal endpoints."""

    def __init__(self, network_manager: NetManager, config_manager: ConfigManager):
        """Initialize API router."""
        self.network_manager = network_manager
        self.config_manager = config_manager
        self.logger = logging.getLogger(__name__)
        # Import here to avoid name conflict
        from fastapi import APIRouter as FastAPIRouter
        # Create router (prefix parameter added in newer FastAPI versions)
        try:
            self.router = FastAPIRouter(prefix="/api/v1")
        except TypeError:
            # Fallback for older FastAPI versions
            self.router = FastAPIRouter()
            self.prefix = "/api/v1"
        self._setup_routes()

    def _setup_routes(self):
        """Set up API routes."""

        # Network endpoints
        @self.router.get("/network/status", response_model=NetworkStatus)
        async def get_network_status():
            """Get current network status."""
            try:
                status = await self.network_manager.get_status()
                return status.to_dict()
            except Exception as e:
                self.logger.error(f"Failed to get network status: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.post("/network/scan", response_model=NetworkScanResponse)
        async def scan_networks(request: NetworkScanRequest):
            """Scan for available WiFi networks."""
            try:
                networks = await self.network_manager.scan_networks()
                network_info = [NetworkInfo(**network.to_dict()) for network in networks]

                return NetworkScanResponse(
                    networks=network_info,
                    scan_time=datetime.now(),
                    total_found=len(networks)
                )
            except Exception as e:
                self.logger.error(f"Failed to scan networks: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.post("/network/connect", response_model=APIResponse)
        async def connect_network(request: NetworkConnectRequest, background_tasks: BackgroundTasks):
            """Connect to a WiFi network."""
            try:
                # Start connection in background
                background_tasks.add_task(
                    self._connect_to_network,
                    request.ssid,
                    request.password
                )

                return APIResponse(
                    success=True,
                    message=f"Connecting to {request.ssid}...",
                    timestamp=datetime.now()
                )
            except Exception as e:
                self.logger.error(f"Failed to connect to network: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.get("/network/networks", response_model=NetworkListResponse)
        async def get_known_networks():
            """Get list of known/saved networks."""
            try:
                networks = await self.network_manager.get_known_networks()
                return NetworkListResponse(
                    networks=networks,
                    total_count=len(networks)
                )
            except Exception as e:
                self.logger.error(f"Failed to get known networks: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.delete("/network/networks/{ssid}", response_model=APIResponse)
        async def forget_network(ssid: str):
            """Forget a saved network."""
            try:
                success = await self.network_manager.forget_network(ssid)
                if success:
                    return APIResponse(
                        success=True,
                        message=f"Forgot network {ssid}",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=404, detail="Network not found")
            except Exception as e:
                self.logger.error(f"Failed to forget network: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        # Kiosk endpoints
        @self.router.get("/kiosk/config", response_model=KioskConfig)
        async def get_kiosk_config():
            """Get current kiosk configuration."""
            try:
                config = await self.config_manager.load_config()
                return KioskConfig(**config.kiosk.dict())
            except Exception as e:
                self.logger.error(f"Failed to get kiosk config: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.put("/kiosk/config", response_model=APIResponse)
        async def update_kiosk_config(request: KioskConfigRequest):
            """Update kiosk configuration."""
            try:
                config = await self.config_manager.load_config()

                # Update only provided fields
                if request.url is not None:
                    config.kiosk.url = request.url
                if request.enable_webgl is not None:
                    config.kiosk.enable_webgl = request.enable_webgl
                if request.enable_webgpu is not None:
                    config.kiosk.enable_webgpu = request.enable_webgpu
                if request.refresh_interval is not None:
                    config.kiosk.refresh_interval = request.refresh_interval

                await self.config_manager.save_config(config)

                return APIResponse(
                    success=True,
                    message="Kiosk configuration updated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                self.logger.error(f"Failed to update kiosk config: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.post("/kiosk/refresh", response_model=APIResponse)
        async def refresh_kiosk():
            """Refresh the kiosk browser."""
            try:
                # Send refresh signal to kiosk service
                await self._refresh_kiosk_browser()

                return APIResponse(
                    success=True,
                    message="Kiosk refresh initiated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                self.logger.error(f"Failed to refresh kiosk: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        # System endpoints
        @self.router.get("/system/status", response_model=SystemInfo)
        async def get_system_status():
            """Get system information."""
            try:
                info = await self._get_system_info()
                return SystemInfo(**info)
            except Exception as e:
                self.logger.error(f"Failed to get system status: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.post("/system/restart", response_model=APIResponse)
        async def restart_system(background_tasks: BackgroundTasks):
            """Restart the system."""
            try:
                background_tasks.add_task(self._restart_system)

                return APIResponse(
                    success=True,
                    message="System restart initiated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                self.logger.error(f"Failed to restart system: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.router.post("/system/action", response_model=APIResponse)
        async def system_action(request: SystemAction, background_tasks: BackgroundTasks):
            """Perform system action."""
            try:
                if request.action == "restart":
                    background_tasks.add_task(self._restart_system)
                    message = "System restart initiated"
                elif request.action == "shutdown":
                    background_tasks.add_task(self._shutdown_system)
                    message = "System shutdown initiated"
                elif request.action == "reload":
                    background_tasks.add_task(self._reload_services)
                    message = "Service reload initiated"
                else:
                    raise HTTPException(status_code=400, detail="Invalid action")

                return APIResponse(
                    success=True,
                    message=message,
                    timestamp=datetime.now()
                )
            except Exception as e:
                self.logger.error(f"Failed to perform system action: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        # Health check
        @self.router.get("/health")
        async def health_check():
            """Health check endpoint."""
            return {"status": "healthy", "timestamp": datetime.now()}

    async def _connect_to_network(self, ssid: str, password: Optional[str]):
        """Connect to network in background."""
        try:
            await self.network_manager.connect_to_network(ssid, password)
        except Exception as e:
            self.logger.error(f"Background connection failed: {e}")

    async def _refresh_kiosk_browser(self):
        """Refresh the kiosk browser."""
        try:
            # Send USR1 signal to kiosk service to refresh
            result = subprocess.run(
                ["pkill", "-USR1", "-f", "ossuary-kiosk"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                self.logger.info("Kiosk refresh signal sent")
            else:
                self.logger.warning("Failed to send refresh signal")
        except Exception as e:
            self.logger.error(f"Failed to refresh kiosk: {e}")

    async def _get_system_info(self) -> Dict[str, Any]:
        """Get system information."""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)

            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent

            # Uptime
            uptime = int(psutil.boot_time())

            # Temperature (Pi specific)
            temperature = await self._get_cpu_temperature()

            # Hostname
            hostname = subprocess.run(
                ["hostname"], capture_output=True, text=True
            ).stdout.strip()

            # Version (from git or package)
            version = await self._get_version()

            return {
                "hostname": hostname,
                "uptime": uptime,
                "cpu_percent": cpu_percent,
                "memory_percent": memory_percent,
                "temperature": temperature,
                "version": version,
                "timestamp": datetime.now()
            }
        except Exception as e:
            self.logger.error(f"Failed to get system info: {e}")
            raise

    async def _get_cpu_temperature(self) -> float:
        """Get CPU temperature (Raspberry Pi)."""
        try:
            temp_file = Path("/sys/class/thermal/thermal_zone0/temp")
            if temp_file.exists():
                temp_raw = temp_file.read_text().strip()
                return float(temp_raw) / 1000.0
        except Exception as e:
            self.logger.debug(f"Failed to get temperature: {e}")

        return 0.0

    async def _get_version(self) -> str:
        """Get application version."""
        try:
            # Try to get git version
            result = subprocess.run(
                ["git", "describe", "--tags", "--always", "--dirty"],
                capture_output=True, text=True, cwd=Path(__file__).parent.parent.parent
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass

        return "unknown"

    async def _restart_system(self):
        """Restart the system."""
        try:
            await asyncio.sleep(2)  # Give time for response
            subprocess.run(["sudo", "reboot"], check=True)
        except Exception as e:
            self.logger.error(f"Failed to restart system: {e}")

    async def _shutdown_system(self):
        """Shutdown the system."""
        try:
            await asyncio.sleep(2)  # Give time for response
            subprocess.run(["sudo", "shutdown", "-h", "now"], check=True)
        except Exception as e:
            self.logger.error(f"Failed to shutdown system: {e}")

    async def _reload_services(self):
        """Reload ossuary services."""
        try:
            await asyncio.sleep(1)  # Give time for response

            services = [
                "ossuary-netd",
                "ossuary-portal",
                "ossuary-kiosk",
                "ossuary-api"
            ]

            for service in services:
                try:
                    subprocess.run(
                        ["sudo", "systemctl", "reload-or-restart", service],
                        check=True, timeout=10
                    )
                    self.logger.info(f"Reloaded service: {service}")
                except subprocess.CalledProcessError as e:
                    self.logger.warning(f"Failed to reload {service}: {e}")

        except Exception as e:
            self.logger.error(f"Failed to reload services: {e}")

    def get_router(self) -> APIRouter:
        """Get the FastAPI router."""
        return self.router