#!/usr/bin/env python3
"""Ossuary Network Management Service.

This service manages WiFi connections and access point functionality
using NetworkManager. It automatically switches between client mode
and AP mode based on connectivity.
"""

import asyncio
import logging
import logging.handlers
import signal
import sys
import json
from pathlib import Path
from typing import Dict, Any

from .manager import NetworkManager
from .states import NetworkState
from config import ConfigManager


class NetworkService:
    """Network management service."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize service."""
        self.config_path = Path(config_path)
        self.config_manager = ConfigManager(config_path)
        self.network_manager = None
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
        """Start the network service."""
        try:
            self.logger.info("Starting Ossuary Network Service")

            # Load configuration
            config = await self.config_manager.load_config()
            network_config = config.network.dict()

            # Initialize network manager
            self.network_manager = NetworkManager(network_config)
            await self.network_manager.initialize()

            # Add state change callback
            self.network_manager.add_state_change_callback(self._on_state_change)

            # Start main loop
            self.running = True
            await self._run_main_loop()

        except Exception as e:
            self.logger.error(f"Failed to start service: {e}")
            raise

    async def _run_main_loop(self) -> None:
        """Main service loop."""
        self.logger.info("Network service started")

        # Check initial state and start AP if needed
        status = await self.network_manager.get_status()
        if status.state == NetworkState.DISCONNECTED:
            self.logger.info("No network connection, starting access point")
            await self.network_manager.start_access_point()

        # Main event loop with active reconnection logic
        reconnect_attempt = 0
        last_reconnect_time = 0

        while self.running:
            try:
                # Get current status
                status = await self.network_manager.get_status()
                current_time = asyncio.get_event_loop().time()

                # Active reconnection logic (CRITICAL IMPROVEMENT)
                if (status.state == NetworkState.DISCONNECTED and
                    not status.ap_active and
                    current_time - last_reconnect_time > 30):  # Try every 30s

                    reconnect_attempt += 1
                    self.logger.info(f"Attempting reconnection #{reconnect_attempt}")

                    # Try to reconnect to known networks
                    try:
                        await self.network_manager._attempt_startup_connection()
                        last_reconnect_time = current_time

                        # Reset counter on any attempt
                        if reconnect_attempt >= 5:  # Give up after 5 attempts (2.5 minutes)
                            self.logger.warning("Max reconnection attempts reached, letting fallback timer handle")
                            reconnect_attempt = 0
                            last_reconnect_time = current_time + 120  # Don't try again for 2 minutes

                    except Exception as e:
                        self.logger.error(f"Reconnection attempt failed: {e}")

                # Reset attempt counter if connected
                elif status.state == NetworkState.CONNECTED:
                    reconnect_attempt = 0
                    last_reconnect_time = 0

                await asyncio.sleep(10)

            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Main loop error: {e}")
                await asyncio.sleep(5)

    async def _on_state_change(self, old_state: NetworkState, new_state: NetworkState, status) -> None:
        """Handle network state changes."""
        self.logger.info(f"Network state changed: {old_state.name} -> {new_state.name}")

        # Handle specific state transitions
        if new_state == NetworkState.CONNECTED:
            self.logger.info(f"Connected to network: {status.ssid}")
            # Stop AP if running
            if status.ap_active:
                await self.network_manager.stop_access_point()

        elif new_state == NetworkState.DISCONNECTED:
            self.logger.info("Disconnected from network")
            # Will automatically start fallback timer

        elif new_state == NetworkState.AP_MODE:
            self.logger.info(f"Access point started: {status.ap_ssid}")

        elif new_state == NetworkState.FAILED:
            self.logger.error("Network connection failed")

    async def stop(self) -> None:
        """Stop the network service."""
        self.logger.info("Stopping Ossuary Network Service")
        self.running = False

        if self.network_manager:
            await self.network_manager.shutdown()

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        self.logger.info(f"Received signal {signum}")
        asyncio.create_task(self.stop())


async def main():
    """Main entry point."""
    service = NetworkService()

    # Set up signal handlers
    signal.signal(signal.SIGTERM, service._signal_handler)
    signal.signal(signal.SIGINT, service._signal_handler)

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
    asyncio.run(main())