#!/usr/bin/env python3
"""Ossuary Kiosk Service.

This service manages the kiosk browser display, handling Chromium
in full-screen mode with hardware acceleration support.
"""

import asyncio
import logging
import signal
import sys
import os
from pathlib import Path
from typing import Dict, Any

from .manager import KioskManager
from config import ConfigManager


class KioskService:
    """Kiosk management service."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize service."""
        self.config_path = Path(config_path)
        self.config_manager = ConfigManager(config_path)
        self.kiosk_manager = None
        self.running = False
        self.logger = self._setup_logging()

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

    async def start(self) -> None:
        """Start the kiosk service."""
        try:
            self.logger.info("Starting Ossuary Kiosk Service")

            # Ensure we're running as the correct user
            await self._check_user_permissions()

            # Load configuration
            config = await self.config_manager.load_config()
            kiosk_config = config.kiosk.dict()

            # Initialize kiosk manager
            self.kiosk_manager = KioskManager(kiosk_config)

            # Add configuration change callback
            self.kiosk_manager.add_url_change_callback(self._on_url_change)

            # Check system compatibility
            compatibility = await self.kiosk_manager.check_system_compatibility()
            self._log_compatibility_check(compatibility)

            # Initialize and start kiosk
            if await self.kiosk_manager.initialize():
                # Determine initial URL
                initial_url = await self._determine_initial_url(config)

                if await self.kiosk_manager.start(initial_url):
                    self.running = True
                    await self._run_main_loop()
                else:
                    self.logger.error("Failed to start kiosk")
                    sys.exit(1)
            else:
                self.logger.error("Failed to initialize kiosk")
                sys.exit(1)

        except Exception as e:
            self.logger.error(f"Failed to start service: {e}")
            raise

    async def _check_user_permissions(self) -> None:
        """Check user permissions and environment."""
        # Check if we have access to display
        display = os.environ.get("DISPLAY", ":0")
        if not display:
            self.logger.warning("DISPLAY environment variable not set, using :0")
            os.environ["DISPLAY"] = ":0"

        # Check X authority
        xauth = os.environ.get("XAUTHORITY")
        if not xauth:
            # Try common locations
            user_home = Path.home()
            xauth_file = user_home / ".Xauthority"
            if xauth_file.exists():
                os.environ["XAUTHORITY"] = str(xauth_file)

        # Log user and environment info
        user = os.getenv("USER", "unknown")
        self.logger.info(f"Running as user: {user}")
        self.logger.info(f"DISPLAY: {os.environ.get('DISPLAY')}")
        self.logger.info(f"XAUTHORITY: {os.environ.get('XAUTHORITY', 'not set')}")

    def _log_compatibility_check(self, compatibility: Dict[str, Any]) -> None:
        """Log system compatibility check results."""
        if compatibility.get("error"):
            self.logger.error(f"Compatibility check failed: {compatibility['error']}")
            return

        self.logger.info("System Compatibility Check:")
        self.logger.info(f"  Display available: {compatibility.get('display_available', False)}")
        self.logger.info(f"  Chromium available: {compatibility.get('chromium_available', False)}")

        gpu_support = compatibility.get("gpu_support", {})
        self.logger.info(f"  Hardware acceleration: {gpu_support.get('hardware_accelerated', False)}")
        self.logger.info(f"  WebGL support: {gpu_support.get('webgl_supported', False)}")
        self.logger.info(f"  WebGL2 support: {gpu_support.get('webgl2_supported', False)}")
        self.logger.info(f"  WebGPU support: {gpu_support.get('webgpu_supported', False)}")

        recommendations = compatibility.get("recommendations", [])
        if recommendations:
            self.logger.warning("Recommendations:")
            for rec in recommendations:
                self.logger.warning(f"  - {rec}")

    async def _determine_initial_url(self, config) -> str:
        """Determine the initial URL to display."""
        # Check if we have a configured URL
        if config.kiosk.url:
            return config.kiosk.url

        # Check network connectivity to determine if we should show portal
        try:
            # Simple connectivity check
            import aiohttp
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as session:
                async with session.get("http://connectivitycheck.gstatic.com/generate_204") as response:
                    if response.status == 204:
                        # We have internet, show default URL or portal
                        return config.kiosk.default_url
        except Exception:
            pass

        # No internet or connectivity issues, show local portal
        return config.kiosk.default_url

    async def _run_main_loop(self) -> None:
        """Main service loop."""
        self.logger.info("Kiosk service started")

        # Monitor configuration changes
        config_check_interval = 30  # Check every 30 seconds
        last_config_check = 0

        while self.running:
            try:
                current_time = asyncio.get_event_loop().time()

                # Periodically check for configuration changes
                if current_time - last_config_check > config_check_interval:
                    await self._check_config_changes()
                    last_config_check = current_time

                # Check kiosk status
                status = await self.kiosk_manager.get_status()
                if not status.get("running", False):
                    self.logger.warning("Kiosk not running, attempting restart")
                    await self._restart_kiosk()

                await asyncio.sleep(10)  # Main loop interval

            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Main loop error: {e}")
                await asyncio.sleep(5)

    async def _check_config_changes(self) -> None:
        """Check for configuration changes and apply them."""
        try:
            config = await self.config_manager.load_config()
            current_config = config.kiosk.dict()

            # Compare with current kiosk config
            if current_config != self.kiosk_manager.config:
                self.logger.info("Configuration changed, updating kiosk")
                await self.kiosk_manager.update_config(current_config)

        except Exception as e:
            self.logger.error(f"Failed to check config changes: {e}")

    async def _restart_kiosk(self) -> None:
        """Restart the kiosk system."""
        try:
            self.logger.info("Restarting kiosk system")

            # Get current config
            config = await self.config_manager.load_config()
            url = await self._determine_initial_url(config)

            # Restart kiosk
            if not await self.kiosk_manager.restart(url):
                self.logger.error("Failed to restart kiosk")

        except Exception as e:
            self.logger.error(f"Failed to restart kiosk: {e}")

    async def _on_url_change(self, old_url: str, new_url: str) -> None:
        """Handle URL changes."""
        self.logger.info(f"URL changed: {old_url} -> {new_url}")

        # Update configuration if needed
        try:
            config = await self.config_manager.load_config()
            if config.kiosk.url != new_url:
                config.kiosk.url = new_url
                await self.config_manager.save_config(config)

        except Exception as e:
            self.logger.error(f"Failed to save URL change: {e}")

    async def stop(self) -> None:
        """Stop the kiosk service."""
        self.logger.info("Stopping Ossuary Kiosk Service")
        self.running = False

        if self.kiosk_manager:
            await self.kiosk_manager.shutdown()

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        signal_names = {
            signal.SIGTERM: "SIGTERM",
            signal.SIGINT: "SIGINT",
            signal.SIGUSR1: "SIGUSR1",
            signal.SIGUSR2: "SIGUSR2"
        }

        signal_name = signal_names.get(signum, f"Signal {signum}")
        self.logger.info(f"Received {signal_name}")

        if signum in (signal.SIGTERM, signal.SIGINT):
            asyncio.create_task(self.stop())
        elif signum == signal.SIGUSR1:
            # Refresh signal
            if self.kiosk_manager:
                asyncio.create_task(self.kiosk_manager.refresh())
        elif signum == signal.SIGUSR2:
            # Reload signal
            if self.kiosk_manager:
                asyncio.create_task(self.kiosk_manager.reload_browser())


async def main():
    """Main entry point."""
    service = KioskService()

    # Set up signal handlers
    signal.signal(signal.SIGTERM, service._signal_handler)
    signal.signal(signal.SIGINT, service._signal_handler)
    signal.signal(signal.SIGUSR1, service._signal_handler)
    signal.signal(signal.SIGUSR2, service._signal_handler)

    try:
        await service.start()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.error(f"Service error: {e}")
        sys.exit(1)
    finally:
        await service.stop()


if __name__ == "__main__":
    # Ensure proper environment for GUI applications
    if "DISPLAY" not in os.environ:
        os.environ["DISPLAY"] = ":0"

    asyncio.run(main())