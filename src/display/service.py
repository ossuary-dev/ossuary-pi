"""Display service for managing X server and display system."""

import asyncio
import logging
import subprocess
import os
import time
from pathlib import Path
from typing import Optional, Dict, Any, Tuple

from config.manager import ConfigManager


class DisplayService:
    """Service for managing display system and X server."""

    def __init__(self):
        """Initialize display service."""
        self.logger = logging.getLogger(__name__)
        self.config_manager = ConfigManager()

        # Display state
        self.x_server_process: Optional[subprocess.Popen] = None
        self.window_manager_process: Optional[subprocess.Popen] = None
        self.display = ":0"
        self.is_running = False

        # Environment detection
        self.is_desktop_environment = self._detect_desktop_environment()
        self.is_wayland = self._detect_wayland()

        self.logger.info(f"Display system: {'Wayland' if self.is_wayland else 'X11'}")
        self.logger.info(f"Desktop environment: {self.is_desktop_environment}")

    def _detect_desktop_environment(self) -> bool:
        """Detect if we're running on an existing desktop environment."""
        try:
            # Check if graphical.target is active
            result = subprocess.run(
                ["systemctl", "is-active", "--quiet", "graphical.target"],
                capture_output=True, timeout=5
            )
            if result.returncode == 0:
                # Check for common display managers
                display_managers = ["lightdm", "gdm", "sddm", "lxdm", "xdm"]
                for dm in display_managers:
                    result = subprocess.run(
                        ["pgrep", "-f", dm],
                        capture_output=True, timeout=5
                    )
                    if result.returncode == 0:
                        self.logger.info(f"Desktop environment detected: {dm} is running")
                        return True

                # Check for desktop session processes
                desktop_processes = ["lxsession", "gnome-session", "plasma", "xfce4-session", "mate-session"]
                for process in desktop_processes:
                    result = subprocess.run(
                        ["pgrep", "-f", process],
                        capture_output=True, timeout=5
                    )
                    if result.returncode == 0:
                        self.logger.info(f"Desktop environment detected: {process} is running")
                        return True

            return False
        except Exception as e:
            self.logger.debug(f"Failed to detect desktop environment: {e}")
            return False

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

            # Fallback: Check for Wayland compositor processes
            try:
                result = subprocess.run(
                    ["pgrep", "-f", "labwc|wayfire|weston|sway"],
                    capture_output=True, timeout=5
                )
                if result.returncode == 0:
                    return True
            except Exception:
                pass

            return False
        except Exception:
            return False

    async def start(self) -> bool:
        """Start the display service."""
        try:
            self.logger.info("Starting display service")

            if self.is_desktop_environment:
                self.logger.info("Desktop environment detected - using existing display session")
                return await self._setup_desktop_environment()
            else:
                self.logger.info("Headless environment detected - starting our own display system")
                return await self._setup_headless_environment()

        except Exception as e:
            self.logger.error(f"Failed to start display service: {e}")
            return False

    async def _setup_desktop_environment(self) -> bool:
        """Set up display access for existing desktop environment."""
        try:
            self.logger.info("Configuring access to existing desktop session")

            # Grant root access to X session
            if not self.is_wayland:
                await self._setup_x11_access()
            else:
                await self._setup_wayland_access()

            self.is_running = True
            return True

        except Exception as e:
            self.logger.error(f"Failed to setup desktop environment access: {e}")
            return False

    async def _setup_headless_environment(self) -> bool:
        """Set up display system for headless environment."""
        try:
            self.logger.info("Setting up headless display environment")

            if self.is_wayland:
                # For Wayland, we'd need to start a compositor
                # For now, fall back to X11 in headless mode
                self.logger.warning("Wayland not fully supported in headless mode, using X11")

            # Start X server
            if await self._start_x_server():
                await self._start_window_manager()
                await self._configure_display()
                self.is_running = True
                return True
            else:
                return False

        except Exception as e:
            self.logger.error(f"Failed to setup headless environment: {e}")
            return False

    async def _setup_x11_access(self) -> None:
        """Set up X11 access for root user."""
        try:
            # Find the primary user running the desktop session
            desktop_user = await self._find_desktop_user()
            if not desktop_user:
                desktop_user = "pi"  # Default fallback

            self.logger.info(f"Desktop user detected: {desktop_user}")
            desktop_home = f"/home/{desktop_user}"

            # Grant root access to X session
            try:
                subprocess.run(
                    ["sudo", "-u", desktop_user, "xhost", "+SI:localuser:root"],
                    env={"DISPLAY": ":0"}, timeout=10, check=False
                )
                self.logger.info("Added root user to X11 access list")
            except Exception as e:
                self.logger.debug(f"Failed to add root to xhost: {e}")

            # Set up root X authority by copying from desktop user
            xauth_source = f"{desktop_home}/.Xauthority"
            xauth_dest = "/root/.Xauthority"

            if os.path.exists(xauth_source):
                try:
                    subprocess.run(["cp", xauth_source, xauth_dest], check=True, timeout=5)
                    subprocess.run(["chmod", "600", xauth_dest], check=True, timeout=5)
                    self.logger.info("Copied X authority to root")
                except Exception as e:
                    self.logger.warning(f"Failed to copy X authority: {e}")
            else:
                # Create empty X authority for root
                try:
                    Path(xauth_dest).touch()
                    subprocess.run(["chmod", "600", xauth_dest], check=True, timeout=5)
                    self.logger.info("Created empty X authority file for root")
                except Exception as e:
                    self.logger.warning(f"Failed to create X authority: {e}")

        except Exception as e:
            self.logger.error(f"Failed to setup X11 access: {e}")

    async def _setup_wayland_access(self) -> None:
        """Set up Wayland access for root user."""
        try:
            self.logger.info("Configuring Wayland access for root")
            # Wayland access is typically through user groups
            # Root should already have access to all groups

            # Set environment variables for Wayland
            wayland_display = os.environ.get('WAYLAND_DISPLAY', 'wayland-0')
            self.logger.info(f"Wayland display: {wayland_display}")

        except Exception as e:
            self.logger.error(f"Failed to setup Wayland access: {e}")

    async def _find_desktop_user(self) -> Optional[str]:
        """Find the user running the desktop session."""
        try:
            # Check who command for users on display :0
            result = subprocess.run(
                ["who"], capture_output=True, text=True, timeout=5
            )

            for line in result.stdout.splitlines():
                if ':0' in line or 'tty7' in line:
                    parts = line.split()
                    if parts:
                        return parts[0]

            # Fallback: check for X server owner
            result = subprocess.run(
                ["ps", "aux"], capture_output=True, text=True, timeout=5
            )

            for line in result.stdout.splitlines():
                if '/usr/bin/X' in line or 'Xorg' in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        return parts[0]

            return None

        except Exception as e:
            self.logger.debug(f"Failed to find desktop user: {e}")
            return None

    async def _check_x_server_availability(self) -> bool:
        """Check if X server binary is available."""
        try:
            result = subprocess.run(
                ["which", "X"], capture_output=True, timeout=5
            )
            if result.returncode != 0:
                self.logger.error("X server binary not found - display stack not installed")
                self.logger.error("On Pi OS Lite, run: sudo apt install xserver-xorg xinit")
                return False
            return True
        except Exception as e:
            self.logger.error(f"Failed to check X server availability: {e}")
            return False

    async def _start_x_server(self) -> bool:
        """Start X server if not already running."""
        try:
            # Check if X server is already running
            if await self._is_x_server_running():
                self.logger.info("X server already running")
                return True

            # Check if X server is available
            if not await self._check_x_server_availability():
                return False

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

            # Start X server with error capture
            self.x_server_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            # Wait for X server to start
            for attempt in range(20):  # Wait up to 20 seconds
                if await self._is_x_server_running():
                    self.logger.info("X server started successfully")
                    return True

                # Check if process died
                if self.x_server_process.poll() is not None:
                    stdout, stderr = self.x_server_process.communicate()
                    self.logger.error("X server failed to start:")
                    if stderr:
                        self.logger.error(f"STDERR: {stderr.decode('utf-8', errors='ignore')}")
                    if stdout:
                        self.logger.error(f"STDOUT: {stdout.decode('utf-8', errors='ignore')}")
                    return False

                await asyncio.sleep(1)

            self.logger.error("X server failed to start within timeout")
            return False

        except Exception as e:
            self.logger.error(f"Failed to start X server: {e}")
            return False

    async def _is_x_server_running(self) -> bool:
        """Check if X server is running."""
        try:
            # Try xdpyinfo
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

    async def _start_window_manager(self) -> bool:
        """Start a minimal window manager."""
        try:
            self.logger.info("Starting window manager")

            # Create minimal openbox config
            await self._create_openbox_config()

            env = {"DISPLAY": self.display}

            self.window_manager_process = subprocess.Popen(
                ["openbox", "--sm-disable"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            await asyncio.sleep(2)  # Give window manager time to start

            # Configure window manager
            await self._configure_window_manager(env)

            self.logger.info("Window manager started")
            return True

        except Exception as e:
            self.logger.debug(f"Failed to start window manager: {e}")
            return False

    async def _create_openbox_config(self) -> None:
        """Create minimal openbox configuration."""
        try:
            config_dir = Path("/root/.config/openbox")
            config_dir.mkdir(parents=True, exist_ok=True)

            # Minimal rc.xml configuration for kiosk mode
            rc_config = """<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
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
                env=env, timeout=5, check=False
            )

            # Hide cursor
            subprocess.run(
                ["xsetroot", "-cursor_name", "none"],
                env=env, timeout=5, check=False
            )

        except Exception as e:
            self.logger.debug(f"Failed to configure window manager: {e}")

    async def _configure_display(self) -> None:
        """Configure display settings."""
        try:
            env = {"DISPLAY": self.display}

            # Disable screen blanking
            commands = [
                ["xset", "s", "off"],
                ["xset", "s", "noblank"],
                ["xset", "-dpms"],
            ]

            for cmd in commands:
                try:
                    subprocess.run(cmd, env=env, timeout=5, check=False)
                except Exception as e:
                    self.logger.debug(f"Failed to run {cmd}: {e}")

        except Exception as e:
            self.logger.error(f"Failed to configure display: {e}")

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
        return {
            "is_running": self.is_running,
            "display": self.display,
            "is_desktop_environment": self.is_desktop_environment,
            "is_wayland": self.is_wayland,
            "x_server_running": await self._is_x_server_running(),
        }

    async def stop(self) -> None:
        """Stop the display service."""
        try:
            self.logger.info("Stopping display service")

            # If we're using a desktop environment, don't shut anything down
            if self.is_desktop_environment:
                self.logger.info("Desktop environment mode - skipping display shutdown")
                self.is_running = False
                return

            # Stop window manager only if we started it
            if self.window_manager_process:
                try:
                    self.window_manager_process.terminate()
                    await asyncio.sleep(2)
                    if self.window_manager_process.poll() is None:
                        self.window_manager_process.kill()
                    self.logger.info("Stopped window manager")
                except Exception as e:
                    self.logger.debug(f"Failed to stop window manager: {e}")

            # Stop X server only if we started it
            if self.x_server_process:
                try:
                    self.x_server_process.terminate()
                    await asyncio.sleep(2)
                    if self.x_server_process.poll() is None:
                        self.x_server_process.kill()
                    self.logger.info("Stopped X server")
                except Exception as e:
                    self.logger.debug(f"Failed to stop X server: {e}")

            self.is_running = False

        except Exception as e:
            self.logger.error(f"Failed to stop display service: {e}")