"""Configuration manager for persistent settings."""

import asyncio
import json
import logging
import os
import shutil
from pathlib import Path
from typing import Dict, Any, Optional, List, Callable
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from .schema import Config


class ConfigFileHandler(FileSystemEventHandler):
    """Handles configuration file changes."""

    def __init__(self, config_manager):
        """Initialize file handler."""
        self.config_manager = config_manager
        self.logger = logging.getLogger(__name__)

    def on_modified(self, event):
        """Handle file modification events."""
        if not event.is_directory and event.src_path == str(self.config_manager.config_path):
            self.logger.info("Configuration file changed, reloading")
            asyncio.create_task(self.config_manager._handle_file_change())


class ConfigManager:
    """Manages configuration persistence and validation."""

    def __init__(self, config_path: str = "/etc/ossuary/config.json"):
        """Initialize configuration manager."""
        self.config_path = Path(config_path)
        self.config_dir = self.config_path.parent
        self.backup_dir = self.config_dir / "backups"
        self.logger = logging.getLogger(__name__)

        # Current configuration
        self.current_config: Optional[Config] = None

        # File watching
        self.observer: Optional[Observer] = None
        self.file_handler: Optional[ConfigFileHandler] = None

        # Change callbacks
        self.change_callbacks: List[Callable] = []

        # Default configuration path
        self.default_config_path = Path(__file__).parent.parent.parent / "config" / "default.json"

        # Ensure directories exist
        self._ensure_directories()

    def _ensure_directories(self) -> None:
        """Ensure configuration directories exist."""
        try:
            # Only try to create directories if we have permission
            if os.access(self.config_dir.parent, os.W_OK) or os.geteuid() == 0:
                self.config_dir.mkdir(parents=True, exist_ok=True)
                self.backup_dir.mkdir(parents=True, exist_ok=True)

                # Set proper permissions if we're root
                if os.geteuid() == 0:
                    os.chmod(self.config_dir, 0o755)
                    os.chmod(self.backup_dir, 0o755)
            else:
                # Directory should already exist, just check it
                if not self.config_dir.exists():
                    self.logger.warning(f"Config directory {self.config_dir} does not exist and cannot be created")

        except Exception as e:
            self.logger.error(f"Failed to create config directories: {e}")

    async def initialize(self) -> None:
        """Initialize configuration manager."""
        try:
            self.logger.info("Initializing configuration manager")

            # Load or create initial configuration
            await self.load_config()

            # Start file watching
            await self._start_file_watching()

            self.logger.info("Configuration manager initialized")

        except Exception as e:
            self.logger.error(f"Failed to initialize config manager: {e}")
            raise

    async def load_config(self) -> Config:
        """Load configuration from file."""
        try:
            if not self.config_path.exists():
                self.logger.info("Configuration file not found, creating from defaults")
                await self._create_default_config()

            # Read configuration file
            with open(self.config_path, 'r') as f:
                config_data = json.load(f)

            # Validate and create config object
            self.current_config = Config(**config_data)

            self.logger.info("Configuration loaded successfully")
            return self.current_config

        except json.JSONDecodeError as e:
            self.logger.error(f"Invalid JSON in configuration file: {e}")
            await self._restore_from_backup()
            return await self.load_config()

        except Exception as e:
            self.logger.error(f"Failed to load configuration: {e}")
            await self._create_default_config()
            return await self.load_config()

    async def save_config(self, config: Config) -> bool:
        """Save configuration to file."""
        try:
            # Validate configuration
            config.dict()  # This will raise validation errors if invalid

            # Create backup before saving
            await self._create_backup()

            # Write configuration
            config_data = config.dict()
            temp_path = self.config_path.with_suffix('.tmp')

            with open(temp_path, 'w') as f:
                json.dump(config_data, f, indent=2, default=str)

            # Atomic move
            temp_path.replace(self.config_path)

            # Set proper permissions
            os.chmod(self.config_path, 0o644)

            self.current_config = config
            self.logger.info("Configuration saved successfully")

            # Notify callbacks
            await self._notify_change_callbacks(config)

            return True

        except Exception as e:
            self.logger.error(f"Failed to save configuration: {e}")
            return False

    async def update_config(self, updates: Dict[str, Any]) -> bool:
        """Update specific configuration values."""
        try:
            if not self.current_config:
                await self.load_config()

            # Create updated config
            current_data = self.current_config.dict()

            # Apply updates using dot notation
            self._apply_nested_updates(current_data, updates)

            # Create new config object
            updated_config = Config(**current_data)

            # Save updated configuration
            return await self.save_config(updated_config)

        except Exception as e:
            self.logger.error(f"Failed to update configuration: {e}")
            return False

    def _apply_nested_updates(self, data: Dict[str, Any], updates: Dict[str, Any]) -> None:
        """Apply nested updates to configuration data."""
        for key, value in updates.items():
            if '.' in key:
                # Handle nested keys (e.g., "kiosk.url")
                keys = key.split('.')
                target = data
                for k in keys[:-1]:
                    if k not in target:
                        target[k] = {}
                    target = target[k]
                target[keys[-1]] = value
            else:
                # Direct key
                if isinstance(value, dict) and key in data and isinstance(data[key], dict):
                    # Merge dictionaries
                    data[key].update(value)
                else:
                    data[key] = value

    async def get_config(self) -> Config:
        """Get current configuration."""
        if not self.current_config:
            await self.load_config()
        return self.current_config

    async def get_config_value(self, key: str, default: Any = None) -> Any:
        """Get specific configuration value using dot notation."""
        try:
            config = await self.get_config()
            data = config.dict()

            # Navigate nested keys
            keys = key.split('.')
            value = data
            for k in keys:
                if isinstance(value, dict) and k in value:
                    value = value[k]
                else:
                    return default

            return value

        except Exception as e:
            self.logger.error(f"Failed to get config value {key}: {e}")
            return default

    async def set_config_value(self, key: str, value: Any) -> bool:
        """Set specific configuration value using dot notation."""
        return await self.update_config({key: value})

    async def _create_default_config(self) -> None:
        """Create default configuration file."""
        try:
            self.logger.info("Creating default configuration")

            # Load default configuration
            if self.default_config_path.exists():
                with open(self.default_config_path, 'r') as f:
                    default_data = json.load(f)
            else:
                # Fallback to minimal default
                default_data = Config().dict()

            # Create config object and save
            default_config = Config(**default_data)
            await self.save_config(default_config)

        except Exception as e:
            self.logger.error(f"Failed to create default config: {e}")
            # Create minimal working config
            minimal_config = Config()
            await self.save_config(minimal_config)

    async def _create_backup(self) -> None:
        """Create backup of current configuration."""
        try:
            if not self.config_path.exists():
                return

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_name = f"config_{timestamp}.json"
            backup_path = self.backup_dir / backup_name

            shutil.copy2(self.config_path, backup_path)

            # Keep only last 10 backups
            await self._cleanup_old_backups()

        except Exception as e:
            self.logger.debug(f"Failed to create backup: {e}")

    async def _cleanup_old_backups(self) -> None:
        """Clean up old backup files."""
        try:
            backups = sorted(
                self.backup_dir.glob("config_*.json"),
                key=lambda x: x.stat().st_mtime,
                reverse=True
            )

            # Keep only the 10 most recent backups
            for backup in backups[10:]:
                backup.unlink()

        except Exception as e:
            self.logger.debug(f"Failed to cleanup old backups: {e}")

    async def _restore_from_backup(self) -> None:
        """Restore configuration from most recent backup."""
        try:
            backups = sorted(
                self.backup_dir.glob("config_*.json"),
                key=lambda x: x.stat().st_mtime,
                reverse=True
            )

            if backups:
                self.logger.info(f"Restoring from backup: {backups[0].name}")
                shutil.copy2(backups[0], self.config_path)
            else:
                self.logger.warning("No backups found, creating default config")
                await self._create_default_config()

        except Exception as e:
            self.logger.error(f"Failed to restore from backup: {e}")
            await self._create_default_config()

    async def _start_file_watching(self) -> None:
        """Start watching configuration file for changes."""
        try:
            if self.observer:
                return

            self.file_handler = ConfigFileHandler(self)
            self.observer = Observer()
            self.observer.schedule(
                self.file_handler,
                str(self.config_dir),
                recursive=False
            )
            self.observer.start()

            self.logger.info("Configuration file watching started")

        except Exception as e:
            self.logger.error(f"Failed to start file watching: {e}")

    async def _stop_file_watching(self) -> None:
        """Stop watching configuration file."""
        try:
            if self.observer:
                self.observer.stop()
                self.observer.join(timeout=5)
                self.observer = None
                self.file_handler = None

            self.logger.info("Configuration file watching stopped")

        except Exception as e:
            self.logger.error(f"Failed to stop file watching: {e}")

    async def _handle_file_change(self) -> None:
        """Handle configuration file changes."""
        try:
            # Small delay to ensure file write is complete
            await asyncio.sleep(0.5)

            old_config = self.current_config
            new_config = await self.load_config()

            # Check if configuration actually changed
            if old_config and old_config.dict() == new_config.dict():
                return

            self.logger.info("Configuration file changed, reloading")
            await self._notify_change_callbacks(new_config)

        except Exception as e:
            self.logger.error(f"Failed to handle file change: {e}")

    def add_change_callback(self, callback: Callable) -> None:
        """Add callback for configuration changes."""
        self.change_callbacks.append(callback)

    def remove_change_callback(self, callback: Callable) -> None:
        """Remove configuration change callback."""
        if callback in self.change_callbacks:
            self.change_callbacks.remove(callback)

    async def _notify_change_callbacks(self, new_config: Config) -> None:
        """Notify callbacks of configuration changes."""
        for callback in self.change_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(new_config)
                else:
                    callback(new_config)
            except Exception as e:
                self.logger.error(f"Configuration change callback error: {e}")

    async def validate_config(self, config_data: Dict[str, Any]) -> tuple[bool, List[str]]:
        """Validate configuration data."""
        errors = []
        try:
            Config(**config_data)
            return True, []
        except Exception as e:
            errors.append(str(e))
            return False, errors

    async def export_config(self, export_path: str) -> bool:
        """Export current configuration to file."""
        try:
            config = await self.get_config()
            export_file = Path(export_path)

            with open(export_file, 'w') as f:
                json.dump(config.dict(), f, indent=2, default=str)

            self.logger.info(f"Configuration exported to {export_path}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to export configuration: {e}")
            return False

    async def import_config(self, import_path: str) -> bool:
        """Import configuration from file."""
        try:
            import_file = Path(import_path)
            if not import_file.exists():
                self.logger.error(f"Import file not found: {import_path}")
                return False

            with open(import_file, 'r') as f:
                config_data = json.load(f)

            # Validate imported configuration
            is_valid, errors = await self.validate_config(config_data)
            if not is_valid:
                self.logger.error(f"Invalid configuration: {errors}")
                return False

            # Save imported configuration
            imported_config = Config(**config_data)
            success = await self.save_config(imported_config)

            if success:
                self.logger.info(f"Configuration imported from {import_path}")

            return success

        except Exception as e:
            self.logger.error(f"Failed to import configuration: {e}")
            return False

    async def reset_to_defaults(self) -> bool:
        """Reset configuration to defaults."""
        try:
            self.logger.info("Resetting configuration to defaults")
            await self._create_default_config()
            return True

        except Exception as e:
            self.logger.error(f"Failed to reset configuration: {e}")
            return False

    async def get_config_schema(self) -> Dict[str, Any]:
        """Get configuration schema for validation."""
        try:
            return Config.schema()
        except Exception as e:
            self.logger.error(f"Failed to get config schema: {e}")
            return {}

    async def shutdown(self) -> None:
        """Shutdown configuration manager."""
        try:
            self.logger.info("Shutting down configuration manager")
            await self._stop_file_watching()

        except Exception as e:
            self.logger.error(f"Failed to shutdown config manager: {e}")