"""Portal server implementation with FastAPI."""

import asyncio
import logging
import logging.handlers
import signal
import sys
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from fastapi import FastAPI, Request, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from .api import APIRouter
from .models import ErrorResponse
from netd import NetworkManager as NetManager
from config import ConfigManager


class PortalServer:
    """Captive portal web server."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize portal server."""
        self.config_path = Path(config_path)
        self.config_manager = ConfigManager(str(config_path))
        self.network_manager = None
        self.app = None
        self.server = None
        self.running = False
        self.logger = self._setup_logging()

        # Template and static file paths
        self.web_dir = Path(__file__).parent.parent.parent / "web"
        self.templates_dir = self.web_dir / "templates"
        self.static_dir = self.web_dir / "assets"

    def _setup_logging(self) -> logging.Logger:
        """Set up logging."""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(sys.stdout),
                logging.handlers.SysLogHandler(address='/dev/log')
            ]
        )
        return logging.getLogger(__name__)

    async def initialize(self) -> None:
        """Initialize the portal server."""
        try:
            self.logger.info("Initializing Portal Server")

            # Load configuration
            config = await self.config_manager.load_config()

            # Initialize network manager
            network_config = config.network.dict()
            self.network_manager = NetManager(network_config)
            await self.network_manager.initialize()

            # Create FastAPI app
            self.app = self._create_app(config)

            self.logger.info("Portal server initialized successfully")

        except Exception as e:
            self.logger.error(f"Failed to initialize portal server: {e}")
            raise

    def _create_app(self, config) -> FastAPI:
        """Create FastAPI application."""
        app = FastAPI(
            title="Ossuary Portal",
            description="Captive Portal and Kiosk Configuration",
            version="1.0.0",
            docs_url="/docs" if config.api.enabled else None,
            redoc_url="/redoc" if config.api.enabled else None
        )

        # CORS middleware
        # Enable CORS by default (no cors_enabled field in PortalConfig)
        cors_enabled = True  # Default to enabled
        if cors_enabled:
            app.add_middleware(
                CORSMiddleware,
                allow_origins=["*"],
                allow_credentials=True,
                allow_methods=["*"],
                allow_headers=["*"],
            )

        # Set up API router
        if self.network_manager:
            api_router = APIRouter(self.network_manager, self.config_manager)
            app.include_router(api_router.get_router())

        # Set up templates
        templates = Jinja2Templates(directory=str(self.templates_dir))

        # Static files
        app.mount("/assets", StaticFiles(directory=str(self.static_dir)), name="assets")

        # Main routes
        @app.get("/", response_class=HTMLResponse)
        async def index(request: Request):
            """Serve main portal page."""
            try:
                # Try to serve the simple portal first
                if (self.templates_dir / "simple-portal.html").exists():
                    return templates.TemplateResponse(
                        "simple-portal.html",
                        {"request": request}
                    )
                else:
                    # Fallback to basic HTML if template missing
                    return HTMLResponse("""
                    <!DOCTYPE html>
                    <html><head><title>Ossuary Setup</title>
                    <meta name="viewport" content="width=device-width,initial-scale=1">
                    <style>body{font-family:Arial;padding:20px;text-align:center;}
                    .container{max-width:400px;margin:0 auto;background:#f5f5f5;padding:30px;border-radius:10px;}
                    input,button{width:100%;padding:10px;margin:10px 0;font-size:16px;}
                    button{background:#007AFF;color:white;border:none;border-radius:5px;cursor:pointer;}
                    </style></head><body>
                    <div class="container">
                    <h1>🏺 Ossuary Setup</h1>
                    <p>WiFi configuration portal</p>
                    <input type="text" placeholder="WiFi Name" id="ssid">
                    <input type="password" placeholder="WiFi Password" id="password">
                    <button onclick="connect()">Connect</button>
                    <script>
                    function connect(){
                        const ssid=document.getElementById('ssid').value;
                        const password=document.getElementById('password').value;
                        if(!ssid) {alert('Enter WiFi name'); return;}
                        fetch('/api/v1/network/connect',{
                            method:'POST',
                            headers:{'Content-Type':'application/json'},
                            body:JSON.stringify({ssid,password})
                        }).then(r=>r.json()).then(d=>{
                            if(d.success) alert('Connected!'); else alert('Failed: '+d.message);
                        });
                    }
                    </script>
                    </div></body></html>
                    """)
            except Exception as e:
                self.logger.error(f"Failed to serve index: {e}")
                # Return ultra-basic HTML that always works
                return HTMLResponse("""
                <html><body style="font-family:Arial;text-align:center;padding:50px;">
                <h1>Ossuary Setup</h1>
                <p>Portal is running but templates not found</p>
                <p>Connect to configure WiFi</p>
                </body></html>
                """)

        @app.get("/starter", response_class=HTMLResponse)
        async def starter_page(request: Request):
            """Serve starter page with system information."""
            try:
                # Get system information
                hostname = self._get_hostname()
                ip_address = self._get_ip_address()
                mac_address = self._get_mac_address()
                model = self._get_model()
                os_version = self._get_os_version()
                uptime = self._get_uptime()

                return templates.TemplateResponse(
                    "starter.html",
                    {
                        "request": request,
                        "hostname": hostname,
                        "ip_address": ip_address,
                        "mac_address": mac_address,
                        "model": model,
                        "os_version": os_version,
                        "uptime": uptime
                    }
                )
            except Exception as e:
                self.logger.error(f"Failed to serve starter page: {e}")
                raise HTTPException(status_code=500, detail="Internal server error")

        # Captive portal detection endpoints - MORE COMPREHENSIVE
        @app.get("/generate_204")
        @app.get("/gen_204")
        @app.head("/generate_204")
        @app.head("/gen_204")
        async def captive_portal_android():
            """Handle captive portal detection (Android)."""
            # Android expects 204 No Content for internet, redirect for captive portal
            return RedirectResponse(url="/", status_code=302)

        @app.get("/hotspot-detect.html")
        @app.get("/library/test/success.html")
        @app.get("/captive-portal-detect")
        async def captive_portal_apple():
            """Handle captive portal detection (Apple)."""
            return RedirectResponse(url="/", status_code=302)

        @app.get("/connecttest.txt")
        @app.get("/redirect")
        @app.get("/msftconnecttest/connecttest.txt")
        @app.get("/ncsi.txt")
        async def captive_portal_windows():
            """Handle captive portal detection (Windows/Microsoft)."""
            return RedirectResponse(url="/", status_code=302)

        @app.get("/success.txt")
        @app.get("/kindle-wifi/wifiredirect.html")
        @app.get("/sony-wifi/")
        async def captive_portal_others():
            """Handle other device captive portal detection."""
            return RedirectResponse(url="/", status_code=302)

        # Catch-all route for captive portal
        @app.get("/{path:path}")
        async def catch_all(request: Request, path: str):
            """Catch-all route to redirect to portal."""
            # Check if it's an API request
            if path.startswith("api/"):
                raise HTTPException(status_code=404, detail="Not found")

            # Check if it's a static asset
            if path.startswith("assets/"):
                raise HTTPException(status_code=404, detail="Not found")

            # Redirect to main portal page
            self.logger.debug(f"Redirecting {path} to portal")
            return RedirectResponse(url="/", status_code=302)

        # Error handlers
        @app.exception_handler(404)
        async def not_found_handler(request: Request, exc):
            """Handle 404 errors."""
            # For API requests, return JSON
            if request.url.path.startswith("/api/"):
                return ErrorResponse(
                    error="Not Found",
                    detail="The requested endpoint was not found",
                    code="404",
                    timestamp=datetime.now()
                )

            # For web requests, redirect to portal
            return RedirectResponse(url="/", status_code=302)

        @app.exception_handler(500)
        async def internal_error_handler(request: Request, exc):
            """Handle 500 errors."""
            self.logger.error(f"Internal server error: {exc}")

            if request.url.path.startswith("/api/"):
                return ErrorResponse(
                    error="Internal Server Error",
                    detail="An internal server error occurred",
                    code="500",
                    timestamp=datetime.now()
                )

            # For web requests, show error page
            return templates.TemplateResponse(
                "error.html",
                {"request": request, "error": "Internal server error"},
                status_code=500
            )

        return app

    async def start(self, host: str = "0.0.0.0", port: int = 80) -> None:
        """Start the portal server."""
        try:
            self.logger.info(f"Starting portal server on {host}:{port}")

            # Load config for server settings
            config = await self.config_manager.load_config()
            host = config.portal.bind_address
            port = config.portal.bind_port

            # Create server config
            server_config = uvicorn.Config(
                app=self.app,
                host=host,
                port=port,
                log_level="info",
                access_log=True,
                server_header=False,
                date_header=False
            )

            # Create and start server
            self.server = uvicorn.Server(server_config)
            self.running = True

            await self.server.serve()

        except Exception as e:
            self.logger.error(f"Failed to start portal server: {e}")
            raise

    async def stop(self) -> None:
        """Stop the portal server."""
        self.logger.info("Stopping portal server")
        self.running = False

        if self.server:
            self.server.should_exit = True

        if self.network_manager:
            await self.network_manager.shutdown()

    def _get_hostname(self) -> str:
        """Get system hostname."""
        try:
            import socket
            return socket.gethostname()
        except Exception:
            return "ossuary-pi"

    def _get_ip_address(self) -> str:
        """Get primary IP address."""
        try:
            import socket
            # Connect to a remote address to determine local IP
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except Exception:
            try:
                # Fallback: get from hostname
                import socket
                return socket.gethostbyname(socket.gethostname())
            except Exception:
                return "192.168.0.1"

    def _get_mac_address(self) -> str:
        """Get MAC address of primary interface."""
        try:
            import uuid
            mac = uuid.getnode()
            return ':'.join(f'{mac:012x}'[i:i+2] for i in range(0, 12, 2))
        except Exception:
            return "00:00:00:00:00:00"

    def _get_model(self) -> str:
        """Get Pi model."""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Model'):
                        return line.split(':', 1)[1].strip()
                    elif 'BCM2711' in line:
                        return 'Raspberry Pi 4'
                    elif 'BCM2712' in line:
                        return 'Raspberry Pi 5'
                    elif 'BCM2837' in line:
                        return 'Raspberry Pi 3'
            return 'Raspberry Pi'
        except Exception:
            return 'Unknown'

    def _get_os_version(self) -> str:
        """Get OS version."""
        try:
            with open('/etc/os-release', 'r') as f:
                for line in f:
                    if line.startswith('PRETTY_NAME'):
                        return line.split('=', 1)[1].strip().strip('"')
            return 'Linux'
        except Exception:
            return 'Unknown'

    def _get_uptime(self) -> str:
        """Get system uptime."""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])

            days = int(uptime_seconds // 86400)
            hours = int((uptime_seconds % 86400) // 3600)
            minutes = int((uptime_seconds % 3600) // 60)

            if days > 0:
                return f"{days}d {hours}h {minutes}m"
            elif hours > 0:
                return f"{hours}h {minutes}m"
            else:
                return f"{minutes}m"
        except Exception:
            return "Unknown"

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        self.logger.info(f"Received signal {signum}")
        asyncio.create_task(self.stop())


class PortalService:
    """Portal service wrapper."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize service."""
        self.portal_server = PortalServer(config_path)

    async def run(self) -> None:
        """Run the portal service."""
        # Set up signal handlers
        signal.signal(signal.SIGTERM, self.portal_server._signal_handler)
        signal.signal(signal.SIGINT, self.portal_server._signal_handler)

        try:
            await self.portal_server.initialize()
            await self.portal_server.start()
        except KeyboardInterrupt:
            pass
        except Exception as e:
            logging.error(f"Portal service error: {e}")
            sys.exit(1)
        finally:
            await self.portal_server.stop()


async def main():
    """Main entry point."""
    service = PortalService()
    await service.run()


if __name__ == "__main__":
    asyncio.run(main())