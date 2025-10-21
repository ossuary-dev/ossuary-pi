"""Browser controller for Chromium kiosk mode."""

import asyncio
import logging
import subprocess
import signal
import os
import psutil
import time
from pathlib import Path
from typing import Optional, List, Dict, Any
from datetime import datetime


class BrowserController:
    """Controls Chromium browser in kiosk mode."""

    def __init__(self, config: Dict[str, Any]):
        """Initialize browser controller."""
        self.config = config
        self.logger = logging.getLogger(__name__)

        # Browser process
        self.process: Optional[subprocess.Popen] = None
        self.pid: Optional[int] = None

        # Configuration
        self.current_url = config.get("url", "")
        self.default_url = config.get("default_url", "http://ossuary.local")
        self.enable_webgl = config.get("enable_webgl", True)
        self.enable_webgpu = config.get("enable_webgpu", False)
        self.disable_screensaver = config.get("disable_screensaver", True)
        self.hide_cursor = config.get("hide_cursor", True)
        self.refresh_interval = config.get("refresh_interval", 0)

        # User data directory
        self.user_data_dir = Path("/var/lib/ossuary/chromium")
        self.user_data_dir.mkdir(parents=True, exist_ok=True)

        # State
        self.is_running = False
        self.last_refresh = None
        self.restart_count = 0
        self.max_restarts = 5

    def _get_chromium_command(self, url: str) -> List[str]:
        """Build Chromium command with appropriate flags."""
        cmd = [
            "chromium-browser",
            "--kiosk",
            "--noerrdialogs",
            "--disable-infobars",
            "--disable-session-crashed-bubble",
            "--disable-first-run-ui",
            "--disable-component-update",
            "--disable-background-timer-throttling",
            "--disable-backgrounding-occluded-windows",
            "--disable-renderer-backgrounding",
            "--disable-features=TranslateUI",
            "--disable-ipc-flooding-protection",
            "--no-first-run",
            "--check-for-update-interval=31536000",  # Never check for updates
            f"--user-data-dir={self.user_data_dir}",
            "--autoplay-policy=no-user-gesture-required",
        ]

        # Detect GPU driver for compatibility (2025 fix)
        gpu_driver = self._detect_gpu_driver()
        self.logger.info(f"Detected GPU driver: {gpu_driver}")

        # GPU and hardware acceleration flags
        if self.enable_webgl or self.enable_webgpu:
            if gpu_driver == 'vc4_v3d':
                # VC4 V3D driver - known issues with EGL
                cmd.extend([
                    "--enable-gpu",
                    "--use-gl=desktop",  # Don't use EGL with VC4
                    "--enable-gpu-rasterization",
                    "--ignore-gpu-blocklist",
                    "--ignore-gpu-blacklist",
                    "--enable-features=VaapiVideoDecoder",  # Hardware video decode
                ])
            elif gpu_driver == 'vc4_fkms':
                # Fake KMS driver - more stable WebGL
                cmd.extend([
                    "--enable-gpu",
                    "--use-gl=egl",
                    "--enable-gpu-rasterization",
                    "--ignore-gpu-blocklist",
                ])
            elif gpu_driver == 'software':
                # Software rendering fallback
                cmd.extend([
                    "--disable-gpu",
                    "--disable-gpu-rasterization",
                ])
            else:
                # Default hardware acceleration
                cmd.extend([
                    "--enable-gpu",
                    "--use-gl=egl",
                    "--enable-gpu-rasterization",
                    "--enable-native-gpu-memory-buffers",
                    "--ignore-gpu-blocklist",
                    "--ignore-gpu-blacklist",
                    "--enable-gpu-memory-buffer-compositor-resources",
                    "--enable-zero-copy",
                ])

            # WebGL specific flags
            if self.enable_webgl:
                cmd.extend([
                    "--enable-webgl",
                    "--enable-webgl2-compute-context",
                ])

            # WebGPU specific flags (experimental)
            if self.enable_webgpu:
                cmd.extend([
                    "--enable-unsafe-webgpu",
                    "--enable-features=WebGPU",
                ])
        else:
            cmd.extend([
                "--disable-gpu",
                "--disable-webgl",
            ])

        # Security flags - conditional based on environment (2025 security fix)
        cmd.extend(self._get_security_flags())

        # Disable various Chrome features that aren't needed
        cmd.extend([
            "--disable-background-networking",
            "--disable-background-timer-throttling",
            "--disable-backgrounding-occluded-windows",
            "--disable-breakpad",
            "--disable-client-side-phishing-detection",
            "--disable-default-apps",
            "--disable-dev-shm-usage",
            "--disable-extensions",
            "--disable-features=VizDisplayCompositor",
            "--disable-hang-monitor",
            "--disable-ipc-flooding-protection",
            "--disable-popup-blocking",
            "--disable-prompt-on-repost",
            "--disable-renderer-backgrounding",
            "--disable-sync",
            "--disable-translate",
            "--disable-windows10-custom-titlebar",
            "--metrics-recording-only",
            "--no-default-browser-check",
            "--no-pings",
            "--password-store=basic",
            "--use-mock-keychain",
        ])

        # Memory optimization for Pi
        cmd.extend([
            "--memory-pressure-off",
            "--max_old_space_size=512",
            "--js-flags=--max-old-space-size=512",
        ])

        # Add URL
        cmd.append(url)

        return cmd

    async def start(self, url: Optional[str] = None) -> bool:
        """Start the browser."""
        if self.is_running:
            self.logger.warning("Browser is already running")
            return True

        # Use provided URL or default
        target_url = url or self.current_url or self.default_url

        try:
            self.logger.info(f"Starting Chromium browser with URL: {target_url}")

            # Prepare environment
            env = os.environ.copy()
            env.update({
                "DISPLAY": ":0",
                "XAUTHORITY": "/home/pi/.Xauthority",
            })

            # Disable screensaver if configured
            if self.disable_screensaver:
                await self._disable_screensaver()

            # Hide cursor if configured
            if self.hide_cursor:
                await self._hide_cursor()

            # Build command
            cmd = self._get_chromium_command(target_url)

            # Start process
            self.process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                preexec_fn=os.setsid  # Create new process group
            )

            self.pid = self.process.pid
            self.is_running = True
            self.current_url = target_url
            self.last_refresh = datetime.now()
            self.restart_count = 0

            self.logger.info(f"Browser started with PID: {self.pid}")

            # Start monitoring
            asyncio.create_task(self._monitor_process())

            return True

        except Exception as e:
            self.logger.error(f"Failed to start browser: {e}")
            self.is_running = False
            return False

    async def stop(self) -> bool:
        """Stop the browser."""
        if not self.is_running or not self.process:
            return True

        try:
            self.logger.info("Stopping browser")

            # Send SIGTERM to process group
            if self.pid:
                try:
                    os.killpg(os.getpgid(self.pid), signal.SIGTERM)
                except ProcessLookupError:
                    pass

            # Wait for graceful shutdown
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                # Force kill if needed
                self.logger.warning("Browser didn't stop gracefully, force killing")
                try:
                    os.killpg(os.getpgid(self.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass

            self.process = None
            self.pid = None
            self.is_running = False

            self.logger.info("Browser stopped")
            return True

        except Exception as e:
            self.logger.error(f"Failed to stop browser: {e}")
            return False

    async def restart(self, url: Optional[str] = None) -> bool:
        """Restart the browser."""
        self.logger.info("Restarting browser")

        # Increment restart count
        self.restart_count += 1
        if self.restart_count > self.max_restarts:
            self.logger.error(f"Too many restarts ({self.restart_count}), giving up")
            return False

        await self.stop()
        await asyncio.sleep(2)  # Give it time to fully stop
        return await self.start(url)

    async def refresh(self) -> bool:
        """Refresh the current page."""
        if not self.is_running or not self.pid:
            self.logger.warning("Cannot refresh: browser not running")
            return False

        try:
            # Send USR1 signal to browser for refresh
            os.kill(self.pid, signal.SIGUSR1)
            self.last_refresh = datetime.now()
            self.logger.info("Browser refresh signal sent")
            return True

        except ProcessLookupError:
            self.logger.warning("Browser process not found for refresh")
            return False
        except Exception as e:
            self.logger.error(f"Failed to refresh browser: {e}")
            return False

    async def navigate_to(self, url: str) -> bool:
        """Navigate to a new URL."""
        if url == self.current_url:
            return True

        self.logger.info(f"Navigating to: {url}")
        self.current_url = url

        # Restart browser with new URL
        return await self.restart(url)

    async def _monitor_process(self) -> None:
        """Monitor browser process and restart if needed."""
        while self.is_running and self.process:
            try:
                # Check if process is still running
                if self.process.poll() is not None:
                    self.logger.warning("Browser process died, restarting")
                    self.is_running = False
                    asyncio.create_task(self.restart())
                    break

                # Check periodic refresh
                if (self.refresh_interval > 0 and
                    self.last_refresh and
                    (datetime.now() - self.last_refresh).seconds >= self.refresh_interval):
                    await self.refresh()

                await asyncio.sleep(5)  # Check every 5 seconds

            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Monitor error: {e}")
                await asyncio.sleep(10)

    async def _disable_screensaver(self) -> None:
        """Disable screensaver and screen blanking."""
        try:
            # Disable screen blanking
            commands = [
                ["xset", "s", "off"],
                ["xset", "s", "noblank"],
                ["xset", "-dpms"],
            ]

            for cmd in commands:
                try:
                    subprocess.run(cmd, check=True, timeout=5)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    self.logger.debug(f"Failed to run {cmd}: {e}")

        except Exception as e:
            self.logger.debug(f"Failed to disable screensaver: {e}")

    async def _hide_cursor(self) -> None:
        """Hide mouse cursor."""
        try:
            # Use unclutter to hide cursor
            subprocess.Popen(
                ["unclutter", "-idle", "1", "-root"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception as e:
            self.logger.debug(f"Failed to hide cursor: {e}")

    def get_status(self) -> Dict[str, Any]:
        """Get browser status."""
        return {
            "running": self.is_running,
            "pid": self.pid,
            "url": self.current_url,
            "restart_count": self.restart_count,
            "last_refresh": self.last_refresh.isoformat() if self.last_refresh else None,
        }

    async def check_gpu_support(self) -> Dict[str, Any]:
        """Check GPU support and acceleration status."""
        try:
            # Try to get GPU info from chrome://gpu equivalent
            cmd = [
                "chromium-browser",
                "--headless",
                "--disable-gpu-sandbox",
                "--no-sandbox",
                "--dump-dom",
                "chrome://gpu"
            ]

            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=30
            )

            gpu_info = {
                "webgl_supported": False,
                "webgl2_supported": False,
                "webgpu_supported": False,
                "hardware_accelerated": False,
                "gpu_vendor": "unknown",
                "gpu_renderer": "unknown"
            }

            if result.returncode == 0:
                output = result.stdout.lower()

                # Check for WebGL support
                if "webgl: hardware accelerated" in output:
                    gpu_info["webgl_supported"] = True
                    gpu_info["hardware_accelerated"] = True

                if "webgl2: hardware accelerated" in output:
                    gpu_info["webgl2_supported"] = True

                # Check for WebGPU (experimental)
                if "webgpu" in output and "enabled" in output:
                    gpu_info["webgpu_supported"] = True

            return gpu_info

        except Exception as e:
            self.logger.error(f"Failed to check GPU support: {e}")
            return {
                "webgl_supported": False,
                "webgl2_supported": False,
                "webgpu_supported": False,
                "hardware_accelerated": False,
                "gpu_vendor": "unknown",
                "gpu_renderer": "unknown",
                "error": str(e)
            }

    async def cleanup(self) -> None:
        """Cleanup browser resources."""
        await self.stop()

        # Clean up user data directory if needed
        try:
            import shutil
            if self.user_data_dir.exists():
                # Only clean specific cache directories, keep profiles
                cache_dirs = [
                    self.user_data_dir / "Default" / "Cache",
                    self.user_data_dir / "Default" / "Code Cache",
                    self.user_data_dir / "ShaderCache",
                ]

                for cache_dir in cache_dirs:
                    if cache_dir.exists():
                        shutil.rmtree(cache_dir, ignore_errors=True)

        except Exception as e:
            self.logger.debug(f"Failed to cleanup cache: {e}")

    def _detect_gpu_driver(self) -> str:
        """Detect GPU driver type for Chromium compatibility (2025 fix)."""
        try:
            # Check boot config for GPU driver
            config_files = ["/boot/config.txt", "/boot/firmware/config.txt"]

            for config_file in config_files:
                if os.path.exists(config_file):
                    with open(config_file, 'r') as f:
                        content = f.read()

                    if 'dtoverlay=vc4-kms-v3d' in content:
                        # Check if V3D is actually working
                        if self._check_v3d_status():
                            return 'vc4_v3d'
                        else:
                            return 'vc4_fkms'  # Fallback
                    elif 'dtoverlay=vc4-fkms-v3d' in content:
                        return 'vc4_fkms'

            # Try to detect via glxinfo
            try:
                result = subprocess.run(['glxinfo'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    output = result.stdout.lower()
                    if 'vc4 v3d' in output:
                        return 'vc4_v3d'
                    elif 'mesa' in output:
                        return 'vc4_fkms'
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

            # Default to software rendering
            self.logger.warning("Could not detect GPU driver, using software rendering")
            return 'software'

        except Exception as e:
            self.logger.error(f"GPU detection failed: {e}")
            return 'software'

    def _check_v3d_status(self) -> bool:
        """Check if VC4 V3D driver is properly initialized."""
        try:
            # Check device tree status
            status_files = [
                "/proc/device-tree/soc/firmwarekms@7e600000/status",
                "/proc/device-tree/v3dbus/v3d@7ec04000/status"
            ]

            for status_file in status_files:
                if os.path.exists(status_file):
                    with open(status_file, 'r') as f:
                        status = f.read().strip().rstrip('\x00')
                        if status != "okay":
                            return False
                else:
                    return False

            return True

        except Exception:
            return False

    def _get_security_flags(self) -> List[str]:
        """Get security flags based on environment (2025 security fix)."""
        flags = []

        # Check if running in container
        if self._is_container():
            self.logger.warning("Container detected - disabling sandbox for compatibility")
            flags.extend([
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-dev-shm-usage",
            ])
        else:
            # Host system - try to use sandbox
            self.logger.info("Host system detected - enabling sandbox")
            flags.extend([
                "--enable-sandbox",
                # Still need dev-shm-usage fix on Pi
                "--disable-dev-shm-usage",
            ])

        return flags

    def _is_container(self) -> bool:
        """Detect if running in container."""
        try:
            # Check for container indicators
            if os.path.exists('/.dockerenv'):
                return True
            if 'container' in os.environ or 'BALENA' in os.environ:
                return True
            if os.path.exists('/proc/1/cgroup'):
                with open('/proc/1/cgroup', 'r') as f:
                    if 'docker' in f.read():
                        return True
            return False
        except Exception:
            return False