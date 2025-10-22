"""Unified API Gateway for system control."""

import asyncio
import logging
import signal
import sys
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime

from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

from .websocket import WebSocketManager
from .middleware import AuthMiddleware, RateLimitMiddleware
from config import ConfigManager
from netd import NetworkManager as NetManager
from kiosk import KioskManager
from portal.models import (
    NetworkScanRequest, NetworkConnectRequest, KioskConfigRequest,
    APIResponse, ErrorResponse, SystemInfo
)


class APIGateway:
    """Unified API gateway for all system services."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize API gateway."""
        self.config_path = Path(config_path)
        self.config_manager = ConfigManager(str(config_path))
        self.logger = logging.getLogger(__name__)

        # Service managers
        self.network_manager: Optional[NetManager] = None
        self.kiosk_manager: Optional[KioskManager] = None

        # API components
        self.app: Optional[FastAPI] = None
        self.websocket_manager: Optional[WebSocketManager] = None
        self.server: Optional[uvicorn.Server] = None

        # State
        self.running = False
        self.services_initialized = False

    async def initialize(self) -> None:
        """Initialize API gateway and all services."""
        try:
            self.logger.info("Initializing API Gateway")

            # Load configuration
            config = await self.config_manager.load_config()

            # Initialize service managers
            await self._initialize_services(config)

            # Create FastAPI app
            self.app = self._create_app(config)

            # Initialize WebSocket manager
            self.websocket_manager = WebSocketManager()

            # Set up routes
            self._setup_routes()

            self.services_initialized = True
            self.logger.info("API Gateway initialized successfully")

        except Exception as e:
            self.logger.error(f"Failed to initialize API gateway: {e}")
            raise

    async def _initialize_services(self, config) -> None:
        """Initialize all service managers."""
        try:
            # Initialize network manager
            network_config = config.network.dict()
            self.network_manager = NetManager(network_config)
            await self.network_manager.initialize()

            # Initialize kiosk manager
            kiosk_config = config.kiosk.dict()
            self.kiosk_manager = KioskManager(kiosk_config)
            await self.kiosk_manager.initialize()

            # Set up service callbacks
            self.network_manager.add_state_change_callback(self._on_network_state_change)
            self.kiosk_manager.add_url_change_callback(self._on_kiosk_url_change)

            self.logger.info("All services initialized")

        except Exception as e:
            self.logger.error(f"Failed to initialize services: {e}")
            raise

    def _create_app(self, config) -> FastAPI:
        """Create FastAPI application."""
        app = FastAPI(
            title="Ossuary API",
            description="Unified API for Ossuary Pi system control",
            version="1.0.0",
            docs_url="/docs" if config.api.enabled else None,
            redoc_url="/redoc" if config.api.enabled else None
        )

        # CORS middleware
        if config.api.cors_enabled:
            app.add_middleware(
                CORSMiddleware,
                allow_origins=["*"],
                allow_credentials=True,
                allow_methods=["*"],
                allow_headers=["*"],
            )

        # Rate limiting middleware
        if config.api.rate_limit.enabled:
            app.add_middleware(
                RateLimitMiddleware,
                requests_per_minute=config.api.rate_limit.requests_per_minute
            )

        # Authentication middleware
        if config.api.auth_required:
            app.add_middleware(
                AuthMiddleware,
                auth_token=config.api.auth_token
            )

        return app

    def _setup_routes(self) -> None:
        """Set up API routes."""

        # Health check
        @self.app.get("/health")
        async def health_check():
            """Health check endpoint."""
            return {
                "status": "healthy",
                "services": {
                    "network": self.network_manager is not None,
                    "kiosk": self.kiosk_manager is not None,
                    "config": self.config_manager is not None,
                },
                "timestamp": datetime.now()
            }

        # WebSocket endpoint
        @self.app.websocket("/ws")
        async def websocket_endpoint(websocket: WebSocket):
            """WebSocket connection endpoint."""
            await self.websocket_manager.connect(websocket)
            try:
                while True:
                    data = await websocket.receive_text()
                    await self.websocket_manager.handle_message(websocket, data)
            except WebSocketDisconnect:
                self.websocket_manager.disconnect(websocket)

        # Network API endpoints
        @self.app.get("/api/v1/network/status")
        async def get_network_status():
            """Get current network status."""
            try:
                status = await self.network_manager.get_status()
                return status.to_dict()
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/network/scan")
        async def scan_networks(request: NetworkScanRequest):
            """Scan for WiFi networks."""
            try:
                networks = await self.network_manager.scan_networks()
                return {
                    "networks": [network.to_dict() for network in networks],
                    "scan_time": datetime.now(),
                    "total_found": len(networks)
                }
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/network/connect")
        async def connect_network(request: NetworkConnectRequest):
            """Connect to a WiFi network."""
            try:
                success = await self.network_manager.connect_to_network(
                    request.ssid, request.password
                )

                if success:
                    # Notify WebSocket clients
                    await self.websocket_manager.broadcast({
                        "type": "network_connected",
                        "ssid": request.ssid,
                        "timestamp": datetime.now()
                    })

                    return APIResponse(
                        success=True,
                        message=f"Connected to {request.ssid}",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Connection failed")

            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/api/v1/network/known")
        async def get_known_networks():
            """Get known networks."""
            try:
                networks = await self.network_manager.get_known_networks()
                return {
                    "networks": networks,
                    "total_count": len(networks)
                }
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.delete("/api/v1/network/known/{ssid}")
        async def forget_network(ssid: str):
            """Forget a network."""
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
                raise HTTPException(status_code=500, detail=str(e))

        # Kiosk API endpoints
        @self.app.get("/api/v1/kiosk/status")
        async def get_kiosk_status():
            """Get kiosk status."""
            try:
                status = await self.kiosk_manager.get_status()
                return status
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/kiosk/navigate")
        async def navigate_kiosk(url: str):
            """Navigate kiosk to URL."""
            try:
                success = await self.kiosk_manager.navigate_to(url)
                if success:
                    # Notify WebSocket clients
                    await self.websocket_manager.broadcast({
                        "type": "kiosk_navigated",
                        "url": url,
                        "timestamp": datetime.now()
                    })

                    return APIResponse(
                        success=True,
                        message=f"Navigated to {url}",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Navigation failed")
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/kiosk/refresh")
        async def refresh_kiosk():
            """Refresh kiosk browser."""
            try:
                success = await self.kiosk_manager.refresh()
                if success:
                    return APIResponse(
                        success=True,
                        message="Kiosk refreshed",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Refresh failed")
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/kiosk/restart")
        async def restart_kiosk():
            """Restart kiosk browser."""
            try:
                success = await self.kiosk_manager.restart()
                if success:
                    return APIResponse(
                        success=True,
                        message="Kiosk restarted",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Restart failed")
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/api/v1/kiosk/compatibility")
        async def check_kiosk_compatibility():
            """Check kiosk system compatibility."""
            try:
                compatibility = await self.kiosk_manager.check_system_compatibility()
                return compatibility
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/api/v1/kiosk/performance")
        async def get_kiosk_performance():
            """Get kiosk performance metrics."""
            try:
                metrics = await self.kiosk_manager.get_performance_metrics()
                return metrics
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        # Configuration API endpoints
        @self.app.get("/api/v1/config")
        async def get_config():
            """Get current configuration."""
            try:
                config = await self.config_manager.get_config()
                return config.dict()
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.put("/api/v1/config")
        async def update_config(updates: Dict[str, Any]):
            """Update configuration."""
            try:
                success = await self.config_manager.update_config(updates)
                if success:
                    # Notify WebSocket clients
                    await self.websocket_manager.broadcast({
                        "type": "config_updated",
                        "updates": updates,
                        "timestamp": datetime.now()
                    })

                    return APIResponse(
                        success=True,
                        message="Configuration updated",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Update failed")
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/api/v1/config/{key:path}")
        async def get_config_value(key: str):
            """Get specific configuration value."""
            try:
                value = await self.config_manager.get_config_value(key)
                return {"key": key, "value": value}
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.put("/api/v1/config/{key:path}")
        async def set_config_value(key: str, value: Any):
            """Set specific configuration value."""
            try:
                success = await self.config_manager.set_config_value(key, value)
                if success:
                    return APIResponse(
                        success=True,
                        message=f"Set {key} = {value}",
                        timestamp=datetime.now()
                    )
                else:
                    raise HTTPException(status_code=400, detail="Update failed")
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        # System API endpoints
        @self.app.get("/api/v1/system/info")
        async def get_system_info():
            """Get system information."""
            try:
                import psutil
                import subprocess

                # CPU and memory
                cpu_percent = psutil.cpu_percent(interval=1)
                memory = psutil.virtual_memory()

                # Uptime
                uptime = int(psutil.boot_time())

                # Temperature
                try:
                    with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                        temp = float(f.read().strip()) / 1000.0
                except Exception:
                    temp = 0.0

                # Hostname
                hostname = subprocess.run(
                    ["hostname"], capture_output=True, text=True
                ).stdout.strip()

                # Version
                try:
                    version = subprocess.run(
                        ["git", "describe", "--tags", "--always"],
                        capture_output=True, text=True,
                        cwd=Path(__file__).parent.parent.parent
                    ).stdout.strip()
                except Exception:
                    version = "unknown"

                return SystemInfo(
                    hostname=hostname,
                    uptime=uptime,
                    cpu_percent=cpu_percent,
                    memory_percent=memory.percent,
                    temperature=temp,
                    version=version,
                    timestamp=datetime.now()
                )

            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/system/restart")
        async def restart_system():
            """Restart system."""
            try:
                # Notify WebSocket clients
                await self.websocket_manager.broadcast({
                    "type": "system_restarting",
                    "timestamp": datetime.now()
                })

                # Schedule restart
                asyncio.create_task(self._restart_system())

                return APIResponse(
                    success=True,
                    message="System restart initiated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/v1/system/shutdown")
        async def shutdown_system():
            """Shutdown system."""
            try:
                # Notify WebSocket clients
                await self.websocket_manager.broadcast({
                    "type": "system_shutting_down",
                    "timestamp": datetime.now()
                })

                # Schedule shutdown
                asyncio.create_task(self._shutdown_system())

                return APIResponse(
                    success=True,
                    message="System shutdown initiated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        # Service control endpoints
        @self.app.post("/api/v1/services/restart")
        async def restart_services():
            """Restart all services."""
            try:
                await self._restart_services()

                return APIResponse(
                    success=True,
                    message="Services restart initiated",
                    timestamp=datetime.now()
                )
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/api/v1/services/status")
        async def get_services_status():
            """Get status of all services."""
            try:
                status = {
                    "api": {"running": self.running, "initialized": self.services_initialized},
                    "network": await self._get_service_status("network"),
                    "kiosk": await self._get_service_status("kiosk"),
                    "portal": await self._get_service_status("portal"),
                    "timestamp": datetime.now()
                }
                return status
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

    async def _on_network_state_change(self, old_state, new_state, status) -> None:
        """Handle network state changes."""
        await self.websocket_manager.broadcast({
            "type": "network_state_changed",
            "old_state": old_state.name,
            "new_state": new_state.name,
            "status": status.to_dict(),
            "timestamp": datetime.now()
        })

    async def _on_kiosk_url_change(self, old_url: str, new_url: str) -> None:
        """Handle kiosk URL changes."""
        await self.websocket_manager.broadcast({
            "type": "kiosk_url_changed",
            "old_url": old_url,
            "new_url": new_url,
            "timestamp": datetime.now()
        })

    async def _restart_system(self) -> None:
        """Restart the system."""
        try:
            await asyncio.sleep(2)
            import subprocess
            subprocess.run(["sudo", "reboot"], check=True)
        except Exception as e:
            self.logger.error(f"Failed to restart system: {e}")

    async def _shutdown_system(self) -> None:
        """Shutdown the system."""
        try:
            await asyncio.sleep(2)
            import subprocess
            subprocess.run(["sudo", "shutdown", "-h", "now"], check=True)
        except Exception as e:
            self.logger.error(f"Failed to shutdown system: {e}")

    async def _restart_services(self) -> None:
        """Restart all Ossuary services."""
        try:
            import subprocess
            services = ["ossuary-netd", "ossuary-portal", "ossuary-kiosk"]

            for service in services:
                subprocess.run(
                    ["sudo", "systemctl", "restart", service],
                    check=True, timeout=30
                )

        except Exception as e:
            self.logger.error(f"Failed to restart services: {e}")

    async def _get_service_status(self, service_name: str) -> Dict[str, Any]:
        """Get status of a specific service."""
        try:
            if service_name == "network" and self.network_manager:
                status = await self.network_manager.get_status()
                return {"running": True, "status": status.to_dict()}
            elif service_name == "kiosk" and self.kiosk_manager:
                status = await self.kiosk_manager.get_status()
                return {"running": True, "status": status}
            else:
                return {"running": False, "status": None}

        except Exception as e:
            return {"running": False, "error": str(e)}

    async def start(self, host: str = "127.0.0.1", port: int = 8080) -> None:
        """Start the API gateway server."""
        try:
            if not self.services_initialized:
                await self.initialize()

            self.logger.info(f"Starting API gateway on {host}:{port}")

            # Load config for server settings
            config = await self.config_manager.get_config()
            host = config.api.bind_address
            port = config.api.bind_port

            # Create server config
            server_config = uvicorn.Config(
                app=self.app,
                host=host,
                port=port,
                log_level="info",
                access_log=True
            )

            # Create and start server
            self.server = uvicorn.Server(server_config)
            self.running = True

            await self.server.serve()

        except Exception as e:
            self.logger.error(f"Failed to start API gateway: {e}")
            raise

    async def stop(self) -> None:
        """Stop the API gateway."""
        try:
            self.logger.info("Stopping API gateway")
            self.running = False

            if self.server:
                self.server.should_exit = True

            # Shutdown services
            if self.network_manager:
                await self.network_manager.shutdown()

            if self.kiosk_manager:
                await self.kiosk_manager.shutdown()

            if self.websocket_manager:
                await self.websocket_manager.shutdown()

        except Exception as e:
            self.logger.error(f"Failed to stop API gateway: {e}")

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        self.logger.info(f"Received signal {signum}")
        asyncio.create_task(self.stop())