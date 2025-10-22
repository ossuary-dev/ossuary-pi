#!/usr/bin/env python3
"""Ossuary API Service.

This service provides the unified REST API and WebSocket gateway
for controlling all Ossuary system components.
"""

import asyncio
import logging
import logging.handlers
import signal
import sys
from pathlib import Path

from .gateway import APIGateway


class APIService:
    """API gateway service wrapper."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize service."""
        self.config_path = Path(config_path)
        self.api_gateway = APIGateway(str(config_path))
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
        """Start the API service."""
        try:
            self.logger.info("Starting Ossuary API Service")

            # Set up signal handlers
            signal.signal(signal.SIGTERM, self._signal_handler)
            signal.signal(signal.SIGINT, self._signal_handler)

            # Start API gateway
            await self.api_gateway.start()

        except Exception as e:
            self.logger.error(f"Failed to start API service: {e}")
            raise

    async def stop(self) -> None:
        """Stop the API service."""
        self.logger.info("Stopping Ossuary API Service")
        await self.api_gateway.stop()

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        signal_names = {
            signal.SIGTERM: "SIGTERM",
            signal.SIGINT: "SIGINT"
        }

        signal_name = signal_names.get(signum, f"Signal {signum}")
        self.logger.info(f"Received {signal_name}")
        asyncio.create_task(self.stop())


async def main():
    """Main entry point."""
    service = APIService()

    try:
        await service.start()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.error(f"API service error: {e}")
        sys.exit(1)
    finally:
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())