"""Display management for kiosk mode."""

import asyncio
import logging
import subprocess
import os
import time
from pathlib import Path
from typing import Optional, Dict, Any, Tuple


class DisplayManager:
    """Manages display for kiosk mode (X11 and Wayland)."""

    def __init__(self, config: Dict[str, Any]):
        """Initialize display manager."""
        self.config = config
        self.logger = logging.getLogger(__name__)

        # Display configuration
        self.display = ":0"
        self.x_server_process: Optional[subprocess.Popen] = None
        self.window_manager_process: Optional[subprocess.Popen] = None

        # Detect display system
        self.is_wayland = self._detect_wayland()
        self.logger.info(f"Display system: {'Wayland' if self.is_wayland else 'X11'}")

        # Display settings
        self.rotation = config.get("rotation", 0)
        self.resolution = config.get("resolution", "auto")
        self.brightness = config.get("brightness", 100)

    def _detect_wayland(self) -> bool:
        """Detect if we're running on Wayland."""
        try:
            # Primary detection: XDG_SESSION_TYPE
            session_type = os.environ.get('XDG_SESSION_TYPE', '').lower()
            if session_type == 'wayland':
                return True
            elif session_type == 'x11':
                return False

            # Fallback: Check WAYLAND_DISPLAY
            if os.environ.get('WAYLAND_DISPLAY'):
                return True

            # Fallback: Check for labwc process (Pi 5 Wayland compositor)
            try:
                result = subprocess.run(
                    ["pgrep", "-f", "labwc"],
                    capture_output=True, timeout=5
                )
                if result.returncode == 0:
                    return True
            except Exception:
                pass

            return False
        except Exception:
            return False

    async def initialize(self) -> bool:
        """Initialize display system."""
        try:
            self.logger.info("Initializing display system")

            if self.is_wayland:
                return await self._initialize_wayland()
            else:
                return await self._initialize_x11()

        except Exception as e:
            self.logger.error(f"Failed to initialize display: {e}")
            return False

    async def _initialize_wayland(self) -> bool:
        """Initialize Wayland display."""
        try:
            self.logger.info("Initializing Wayland display")

            # For Wayland, we just need to verify the compositor is running
            if await self._is_wayland_running():
                self.logger.info("Wayland compositor is running")
                await self._configure_display()
                return True
            else:
                self.logger.error("Wayland compositor not running")
                return False

        except Exception as e:
            self.logger.error(f"Failed to initialize Wayland: {e}")
            return False

    async def _initialize_x11(self) -> bool:
        """Initialize X11 display."""
        try:
            self.logger.info("Initializing X11 display")

            # Check if X server is already running
            if await self._is_x_server_running():
                self.logger.info("X server already running")
                await self._configure_display()
                return True

            # Start X server if not running
            if await self._start_x_server():
                await self._configure_display()
                await self._start_window_manager()
                return True

            return False

        except Exception as e:
            self.logger.error(f"Failed to initialize X11: {e}")
            return False

    async def _is_x_server_running(self) -> bool:
        """Check if X server is running."""
        try:
            # First try xdpyinfo
            result = subprocess.run(
                ["xdpyinfo", "-display", self.display],
                capture_output=True, timeout=5
            )
            if result.returncode == 0:
                return True

            # Fallback: check if X process is running
            result = subprocess.run(
                ["pgrep", "-f", f"X.*{self.display}"],
                capture_output=True, timeout=5
            )
            return result.returncode == 0

        except Exception as e:
            self.logger.debug(f"Failed to check X server: {e}")
            return False

    async def _is_wayland_running(self) -> bool:
        """Check if Wayland compositor is running."""
        try:
            # Check for WAYLAND_DISPLAY environment variable
            if os.environ.get('WAYLAND_DISPLAY'):
                return True

            # Check for labwc process (Pi 5 default compositor)
            result = subprocess.run(
                ["pgrep", "-f", "labwc"],
                capture_output=True, timeout=5
            )
            if result.returncode == 0:
                return True

            # Check for other common Wayland compositors
            for compositor in ["wayfire", "weston", "sway"]:
                result = subprocess.run(
                    ["pgrep", "-f", compositor],
                    capture_output=True, timeout=5
                )
                if result.returncode == 0:
                    return True

            return False

        except Exception as e:
            self.logger.debug(f"Failed to check Wayland: {e}")
            return False

    async def _start_x_server(self) -> bool:
        """Start X server."""
        try:
            self.logger.info("Starting X server")

            # Create X server command
            cmd = [
                "X",
                self.display,
                "-nolisten", "tcp",
                "-quiet",
                "-background", "none",
                "-nocursor",
            ]

            # Add platform-specific options for Raspberry Pi
            if self._is_raspberry_pi():
                cmd.extend([
                    "-screen", "0", "1920x1080x24",  # Default resolution
                ])

            # Start X server
            self.x_server_process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            # Wait for X server to start
            for _ in range(10):
                if await self._is_x_server_running():
                    self.logger.info("X server started successfully")
                    return True
                await asyncio.sleep(1)

            self.logger.error("X server failed to start")
            return False

        except Exception as e:
            self.logger.error(f"Failed to start X server: {e}")
            return False

    async def _configure_display(self) -> None:
        """Configure display settings."""
        try:
            env = {"DISPLAY": self.display}

            # Set resolution if specified
            if self.resolution != "auto":
                await self._set_resolution(self.resolution, env)

            # Set rotation if specified
            if self.rotation != 0:
                await self._set_rotation(self.rotation, env)

            # Set brightness
            if self.brightness != 100:
                await self._set_brightness(self.brightness)

            # Disable screen blanking
            await self._disable_screen_blanking(env)

        except Exception as e:
            self.logger.error(f"Failed to configure display: {e}")

    async def _set_resolution(self, resolution: str, env: Dict[str, str]) -> None:
        """Set display resolution."""
        try:
            if "x" in resolution:
                width, height = resolution.split("x")
                cmd = ["xrandr", "--output", "HDMI-1", "--mode", f"{width}x{height}"]
                subprocess.run(cmd, env=env, timeout=10)
                self.logger.info(f"Set resolution to {resolution}")
        except Exception as e:
            self.logger.debug(f"Failed to set resolution: {e}")

    async def _set_rotation(self, rotation: int, env: Dict[str, str]) -> None:
        """Set display rotation."""
        try:
            rotation_map = {0: "normal", 90: "left", 180: "inverted", 270: "right"}
            rotation_name = rotation_map.get(rotation, "normal")

            cmd = ["xrandr", "--output", "HDMI-1", "--rotate", rotation_name]
            subprocess.run(cmd, env=env, timeout=10)
            self.logger.info(f"Set rotation to {rotation} degrees")
        except Exception as e:
            self.logger.debug(f"Failed to set rotation: {e}")

    async def _set_brightness(self, brightness: int) -> None:
        """Set display brightness."""
        try:
            # For Raspberry Pi, try different brightness control methods
            brightness_value = max(0, min(100, brightness))

            # Try backlight control
            backlight_path = Path("/sys/class/backlight")
            if backlight_path.exists():
                for backlight in backlight_path.iterdir():
                    try:
                        max_brightness_file = backlight / "max_brightness"
                        brightness_file = backlight / "brightness"

                        if max_brightness_file.exists() and brightness_file.exists():
                            max_brightness = int(max_brightness_file.read_text().strip())
                            target_brightness = int((brightness_value / 100) * max_brightness)

                            brightness_file.write_text(str(target_brightness))
                            self.logger.info(f"Set brightness to {brightness_value}%")
                            return
                    except Exception:
                        continue

            # Fallback to xrandr brightness (software-based)
            brightness_factor = brightness_value / 100
            cmd = ["xrandr", "--output", "HDMI-1", "--brightness", str(brightness_factor)]
            subprocess.run(cmd, env={"DISPLAY": self.display}, timeout=10)

        except Exception as e:
            self.logger.debug(f"Failed to set brightness: {e}")

    async def _disable_screen_blanking(self, env: Dict[str, str]) -> None:
        """Disable screen blanking and screensaver."""
        try:
            commands = [
                ["xset", "s", "off"],
                ["xset", "s", "noblank"],
                ["xset", "-dpms"],
            ]

            for cmd in commands:
                subprocess.run(cmd, env=env, timeout=5)

        except Exception as e:
            self.logger.debug(f"Failed to disable screen blanking: {e}")

    async def _start_window_manager(self) -> bool:
        """Start a minimal window manager."""
        try:
            self.logger.info("Starting window manager")

            # Try to start openbox (lightweight window manager)
            env = {"DISPLAY": self.display}

            # Create minimal openbox config
            await self._create_openbox_config()

            self.window_manager_process = subprocess.Popen(
                ["openbox", "--sm-disable"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            await asyncio.sleep(2)  # Give window manager time to start

            # Set window manager properties
            await self._configure_window_manager(env)

            self.logger.info("Window manager started")
            return True

        except Exception as e:
            self.logger.debug(f"Failed to start window manager: {e}")
            return False

    async def _create_openbox_config(self) -> None:
        """Create minimal openbox configuration."""
        try:
            config_dir = Path.home() / ".config" / "openbox"
            config_dir.mkdir(parents=True, exist_ok=True)

            # Minimal rc.xml configuration
            rc_config = """<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Desktop</name>
    </names>
    <popupTime>875</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
    <popupFixedPosition>
      <x>10</x>
      <y>10</y>
    </popupFixedPosition>
  </resize>
  <dock>
    <position>TopLeft</position>
    <floatingX>0</floatingX>
    <floatingY>0</floatingY>
    <noStrut>no</noStrut>
    <stacking>Above</stacking>
    <direction>Vertical</direction>
    <autoHide>no</autoHide>
    <hideDelay>300</hideDelay>
    <showDelay>300</showDelay>
    <moveButton>Middle</moveButton>
  </dock>
  <keyboard/>
  <mouse/>
  <menu/>
  <applications>
    <application class="*">
      <decor>no</decor>
      <fullscreen>yes</fullscreen>
    </application>
  </applications>
</openbox_config>"""

            rc_file = config_dir / "rc.xml"
            rc_file.write_text(rc_config)

        except Exception as e:
            self.logger.debug(f"Failed to create openbox config: {e}")

    async def _configure_window_manager(self, env: Dict[str, str]) -> None:
        """Configure window manager settings."""
        try:
            # Set desktop background to black
            subprocess.run(
                ["xsetroot", "-solid", "black"],
                env=env, timeout=5
            )

            # Hide cursor
            subprocess.run(
                ["xsetroot", "-cursor_name", "none"],
                env=env, timeout=5
            )

        except Exception as e:
            self.logger.debug(f"Failed to configure window manager: {e}")

    def _is_raspberry_pi(self) -> bool:
        """Check if running on Raspberry Pi."""
        try:
            with open("/proc/cpuinfo", "r") as f:
                content = f.read()
                return "BCM" in content or "Raspberry Pi" in content
        except Exception:
            return False

    async def get_display_info(self) -> Dict[str, Any]:
        """Get display information."""
        try:
            env = {"DISPLAY": self.display}

            # Get display resolution
            result = subprocess.run(
                ["xdpyinfo"], env=env, capture_output=True, text=True, timeout=10
            )

            info = {
                "display": self.display,
                "x_server_running": await self._is_x_server_running(),
                "resolution": "unknown",
                "depth": "unknown",
                "rotation": self.rotation,
                "brightness": self.brightness
            }

            if result.returncode == 0:
                lines = result.stdout.split("\n")
                for line in lines:
                    if "dimensions:" in line:
                        parts = line.split()
                        if len(parts) >= 2:
                            info["resolution"] = parts[1]
                    elif "depth:" in line:
                        parts = line.split()
                        if len(parts) >= 2:
                            info["depth"] = parts[1]

            return info

        except Exception as e:
            self.logger.error(f"Failed to get display info: {e}")
            return {
                "display": self.display,
                "x_server_running": False,
                "error": str(e)
            }

    async def shutdown(self) -> None:
        """Shutdown display system."""
        try:
            self.logger.info("Shutting down display system")

            # Stop window manager
            if self.window_manager_process:
                try:
                    self.window_manager_process.terminate()
                    await asyncio.sleep(2)
                    if self.window_manager_process.poll() is None:
                        self.window_manager_process.kill()
                except Exception as e:
                    self.logger.debug(f"Failed to stop window manager: {e}")

            # Stop X server if we started it
            if self.x_server_process:
                try:
                    self.x_server_process.terminate()
                    await asyncio.sleep(2)
                    if self.x_server_process.poll() is None:
                        self.x_server_process.kill()
                except Exception as e:
                    self.logger.debug(f"Failed to stop X server: {e}")

        except Exception as e:
            self.logger.error(f"Failed to shutdown display: {e}")

    async def restart_x_server(self) -> bool:
        """Restart X server."""
        await self.shutdown()
        await asyncio.sleep(3)
        return await self.initialize()