"""Kiosk manager that coordinates browser and display."""

import asyncio
import logging
import signal
from typing import Dict, Any, Optional, Callable, List
from datetime import datetime

from .browser import BrowserController
from .display import DisplayManager
from config import ConfigManager


class KioskManager:
    """Manages kiosk display and browser functionality."""

    def __init__(self, config: Dict[str, Any]):
        """Initialize kiosk manager."""
        self.config = config
        self.logger = logging.getLogger(__name__)

        # Components
        self.display_manager = DisplayManager(config)
        self.browser_controller = BrowserController(config)

        # State
        self.is_initialized = False
        self.is_running = False
        self.current_url = config.get("url", "")
        self.default_url = config.get("default_url", "http://ossuary.local")

        # Callbacks
        self.url_change_callbacks: List[Callable] = []

        # Auto-start configuration
        self.autostart_delay = config.get("autostart_delay", 5)

    async def initialize(self) -> bool:
        """Initialize kiosk system."""
        try:
            self.logger.info("Initializing kiosk system")

            # Initialize display first (optional for headless operation)
            display_initialized = await self.display_manager.initialize()
            if not display_initialized:
                self.logger.warning("Failed to initialize display - running in headless mode")
                self.headless_mode = True
            else:
                self.headless_mode = False
                # Wait for display to stabilize
                await asyncio.sleep(2)

            self.is_initialized = True
            self.logger.info("Kiosk system initialized successfully")
            return True

        except Exception as e:
            self.logger.error(f"Failed to initialize kiosk: {e}")
            return False

    async def start(self, url: Optional[str] = None) -> bool:
        """Start kiosk mode."""
        if not self.is_initialized:
            if not await self.initialize():
                return False

        if self.is_running:
            self.logger.warning("Kiosk is already running")
            return True

        try:
            self.logger.info("Starting kiosk mode")

            # Determine URL to display
            target_url = url or self.current_url or self.default_url

            # Wait for autostart delay
            if self.autostart_delay > 0:
                self.logger.info(f"Waiting {self.autostart_delay}s before starting browser")
                await asyncio.sleep(self.autostart_delay)

            # Start browser (skip if in headless mode)
            if hasattr(self, 'headless_mode') and self.headless_mode:
                self.logger.info("Running in headless mode - browser not started")
                self.is_running = True
                self.current_url = target_url
                return True
            elif await self.browser_controller.start(target_url):
                self.is_running = True
                self.current_url = target_url

                # Set up signal handlers for browser control
                self._setup_signal_handlers()

                self.logger.info(f"Kiosk started with URL: {target_url}")
                return True
            else:
                self.logger.error("Failed to start browser")
                return False

        except Exception as e:
            self.logger.error(f"Failed to start kiosk: {e}")
            return False

    async def stop(self) -> bool:
        """Stop kiosk mode."""
        if not self.is_running:
            return True

        try:
            self.logger.info("Stopping kiosk mode")

            # Stop browser
            await self.browser_controller.stop()

            self.is_running = False
            self.logger.info("Kiosk stopped")
            return True

        except Exception as e:
            self.logger.error(f"Failed to stop kiosk: {e}")
            return False

    async def restart(self, url: Optional[str] = None) -> bool:
        """Restart kiosk mode."""
        self.logger.info("Restarting kiosk")
        await self.stop()
        await asyncio.sleep(2)
        return await self.start(url)

    async def navigate_to(self, url: str) -> bool:
        """Navigate to a new URL."""
        try:
            self.logger.info(f"Navigating to: {url}")

            if not self.is_running:
                # Start with the new URL
                return await self.start(url)
            else:
                # Navigate existing browser
                success = await self.browser_controller.navigate_to(url)
                if success:
                    old_url = self.current_url
                    self.current_url = url

                    # Notify callbacks
                    for callback in self.url_change_callbacks:
                        try:
                            await callback(old_url, url)
                        except Exception as e:
                            self.logger.error(f"URL change callback error: {e}")

                return success

        except Exception as e:
            self.logger.error(f"Failed to navigate to {url}: {e}")
            return False

    async def refresh(self) -> bool:
        """Refresh current page."""
        if not self.is_running:
            self.logger.warning("Cannot refresh: kiosk not running")
            return False

        return await self.browser_controller.refresh()

    async def reload_browser(self) -> bool:
        """Reload browser (restart with same URL)."""
        if not self.is_running:
            self.logger.warning("Cannot reload: kiosk not running")
            return False

        return await self.browser_controller.restart(self.current_url)

    def _setup_signal_handlers(self) -> None:
        """Set up signal handlers for browser control."""
        def refresh_handler(signum, frame):
            """Handle refresh signal."""
            asyncio.create_task(self.refresh())

        def reload_handler(signum, frame):
            """Handle reload signal."""
            asyncio.create_task(self.reload_browser())

        # USR1 for refresh, USR2 for reload
        signal.signal(signal.SIGUSR1, refresh_handler)
        signal.signal(signal.SIGUSR2, reload_handler)

    async def update_config(self, config_update: Dict[str, Any]) -> bool:
        """Update kiosk configuration."""
        try:
            self.logger.info("Updating kiosk configuration")

            # Update internal config
            self.config.update(config_update)

            # Handle URL changes
            new_url = config_update.get("url")
            if new_url and new_url != self.current_url:
                await self.navigate_to(new_url)

            # Handle browser settings
            browser_settings = ["enable_webgl", "enable_webgpu", "refresh_interval"]
            browser_config_changed = any(key in config_update for key in browser_settings)

            if browser_config_changed and self.is_running:
                # Update browser config and restart
                self.browser_controller.config.update(config_update)
                await self.reload_browser()

            # Handle display settings
            display_settings = ["rotation", "resolution", "brightness"]
            display_config_changed = any(key in config_update for key in display_settings)

            if display_config_changed:
                # Update display config
                self.display_manager.config.update(config_update)
                # Note: Display changes might require manual restart for full effect

            return True

        except Exception as e:
            self.logger.error(f"Failed to update config: {e}")
            return False

    async def get_status(self) -> Dict[str, Any]:
        """Get kiosk status."""
        try:
            browser_status = self.browser_controller.get_status()
            display_info = await self.display_manager.get_display_info()

            return {
                "initialized": self.is_initialized,
                "running": self.is_running,
                "current_url": self.current_url,
                "browser": browser_status,
                "display": display_info,
                "timestamp": datetime.now()
            }

        except Exception as e:
            self.logger.error(f"Failed to get status: {e}")
            return {
                "initialized": self.is_initialized,
                "running": self.is_running,
                "error": str(e),
                "timestamp": datetime.now()
            }

    async def check_system_compatibility(self) -> Dict[str, Any]:
        """Check system compatibility for kiosk mode."""
        try:
            compatibility = {
                "display_available": False,
                "chromium_available": False,
                "gpu_support": {},
                "recommendations": []
            }

            # Check display
            display_info = await self.display_manager.get_display_info()
            compatibility["display_available"] = display_info.get("x_server_running", False)

            # Check Chromium
            import shutil
            compatibility["chromium_available"] = shutil.which("chromium-browser") is not None

            # Check GPU support
            compatibility["gpu_support"] = await self.browser_controller.check_gpu_support()

            # Generate recommendations
            recommendations = []

            if not compatibility["display_available"]:
                recommendations.append("X server not running or accessible")

            if not compatibility["chromium_available"]:
                recommendations.append("Chromium browser not installed")

            if not compatibility["gpu_support"].get("hardware_accelerated", False):
                recommendations.append("GPU acceleration not available")

            if not compatibility["gpu_support"].get("webgl_supported", False):
                recommendations.append("WebGL not supported")

            compatibility["recommendations"] = recommendations

            return compatibility

        except Exception as e:
            self.logger.error(f"Failed to check compatibility: {e}")
            return {"error": str(e)}

    def add_url_change_callback(self, callback: Callable) -> None:
        """Add callback for URL changes."""
        self.url_change_callbacks.append(callback)

    def remove_url_change_callback(self, callback: Callable) -> None:
        """Remove URL change callback."""
        if callback in self.url_change_callbacks:
            self.url_change_callbacks.remove(callback)

    async def shutdown(self) -> None:
        """Shutdown kiosk system."""
        try:
            self.logger.info("Shutting down kiosk system")

            await self.stop()
            await self.browser_controller.cleanup()
            await self.display_manager.shutdown()

            self.is_initialized = False
            self.logger.info("Kiosk system shutdown complete")

        except Exception as e:
            self.logger.error(f"Failed to shutdown kiosk: {e}")

    async def get_performance_metrics(self) -> Dict[str, Any]:
        """Get performance metrics."""
        try:
            import psutil

            # Get system metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()

            # Get GPU temperature if available
            gpu_temp = None
            try:
                with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                    gpu_temp = float(f.read().strip()) / 1000.0
            except Exception:
                pass

            # Get browser process info
            browser_metrics = {}
            if self.browser_controller.pid:
                try:
                    process = psutil.Process(self.browser_controller.pid)
                    browser_metrics = {
                        "cpu_percent": process.cpu_percent(),
                        "memory_percent": process.memory_percent(),
                        "memory_mb": process.memory_info().rss / 1024 / 1024,
                        "num_threads": process.num_threads(),
                    }
                except psutil.NoSuchProcess:
                    pass

            return {
                "system": {
                    "cpu_percent": cpu_percent,
                    "memory_percent": memory.percent,
                    "memory_available_mb": memory.available / 1024 / 1024,
                    "gpu_temperature": gpu_temp
                },
                "browser": browser_metrics,
                "timestamp": datetime.now()
            }

        except Exception as e:
            self.logger.error(f"Failed to get performance metrics: {e}")
            return {"error": str(e)}