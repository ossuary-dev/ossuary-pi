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
        self.default_url = config.get("default_url", "http://localhost")
        self.enable_webgl = config.get("enable_webgl", True)
        self.enable_webgpu = config.get("enable_webgpu", False)
        self.disable_screensaver = config.get("disable_screensaver", True)
        self.hide_cursor = config.get("hide_cursor", True)
        self.refresh_interval = config.get("refresh_interval", 0)

        # Detect Pi model and display system
        self.pi_model = self._detect_pi_model()
        self.is_wayland = self._detect_display_system()
        self.chromium_binary = self._get_chromium_binary()

        self.logger.info(f"Pi model: {self.pi_model}, Display: {'Wayland' if self.is_wayland else 'X11'}, Binary: {self.chromium_binary}")

        # User data directory
        self.user_data_dir = Path("/var/lib/ossuary/chromium")
        self.user_data_dir.mkdir(parents=True, exist_ok=True)

        # State
        self.is_running = False
        self.last_refresh = None
        self.restart_count = 0
        self.max_restarts = 5

    def _detect_pi_model(self) -> str:
        """Detect Raspberry Pi model."""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                content = f.read()
                if 'BCM2711' in content:
                    return 'Pi4'
                elif 'BCM2712' in content:
                    return 'Pi5'
                elif 'BCM2837' in content:
                    return 'Pi3'
                else:
                    return 'Unknown'
        except:
            return 'Unknown'

    def _detect_display_system(self) -> bool:
        """Detect display system based on config and environment."""
        display_pref = self.config.get("display_preference", "auto")

        if display_pref == "wayland":
            return True
        elif display_pref == "x11":
            return False
        else:  # auto
            # Auto-detect from environment
            session_type = os.environ.get('XDG_SESSION_TYPE', '').lower()
            return session_type == 'wayland' or bool(os.environ.get('WAYLAND_DISPLAY'))

    def _get_chromium_binary(self) -> str:
        """Get correct Chromium binary for the system."""
        # Check if user specified a binary
        browser_pref = self.config.get("browser_binary", "auto")
        if browser_pref != "auto":
            # User specified a specific binary
            try:
                subprocess.run([browser_pref, '--version'], capture_output=True, timeout=5)
                self.logger.info(f"Using user-specified browser: {browser_pref}")
                return browser_pref
            except Exception as e:
                self.logger.warning(f"User-specified binary {browser_pref} not working: {e}")

        # Auto-detect what's available (intelligent detection)
        # Priority order based on Pi model and OS version
        candidates = []

        # Detect OS version
        try:
            with open('/etc/os-release', 'r') as f:
                os_content = f.read()
                if 'VERSION_ID="13"' in os_content:  # Trixie
                    # Trixie prefers chromium package
                    candidates = ['chromium', 'chromium-browser']
                else:  # Bookworm and older
                    candidates = ['chromium-browser', 'chromium']
        except:
            # Fallback order
            candidates = ['chromium-browser', 'chromium']

        for binary in candidates:
            try:
                result = subprocess.run(
                    ['which', binary],
                    capture_output=True,
                    timeout=5
                )
                if result.returncode == 0:
                    # Verify it actually works
                    version_check = subprocess.run(
                        [binary, '--version'],
                        capture_output=True,
                        timeout=5
                    )
                    if version_check.returncode == 0:
                        self.logger.info(f"Found working browser: {binary}")
                        return binary
            except Exception as e:
                self.logger.debug(f"Binary {binary} not available: {e}")
                continue

        # Fallback based on Pi model if nothing found
        if self.pi_model == 'Pi5':
            return 'chromium'  # Pi 5 with Trixie typically uses chromium
        else:
            return 'chromium-browser'  # Older Pi models often use chromium-browser

    def _get_chromium_command(self, url: str) -> List[str]:
        """Build Chromium command with appropriate flags."""
        cmd = [
            self.chromium_binary,
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
            "--password-store=basic",  # Use basic password store to avoid keyring issues
        ]

        # Hardware acceleration flags based on Pi model and display system
        if self.enable_webgl or self.enable_webgpu:
            if self.pi_model == 'Pi5':
                # Pi 5: Based on proven working command for Pi OS 64-bit desktop
                # DISPLAY=:0 chromium --kiosk --noerrdialogs --disable-infobars
                # --enable-features=Vulkan --enable-unsafe-webgpu --ignore-gpu-blocklist
                # --enable-features=VaapiVideoDecoder,CanvasOopRasterization --password-store=basic

                # Build features list exactly as in working command
                # Combine all features into single --enable-features flag for best practice
                features = ["VaapiVideoDecoder", "CanvasOopRasterization"]

                if self.enable_webgpu:
                    features.append("Vulkan")
                    cmd.append("--enable-unsafe-webgpu")

                # Core acceleration flags that worked
                cmd.extend([
                    "--ignore-gpu-blocklist",
                    f"--enable-features={','.join(features)}",
                ])

                # Note: Intentionally NOT adding --use-gl=egl or --ozone-platform flags
                # Pi 5 with proper dtoverlay config handles display system detection automatically

            elif self.pi_model == 'Pi4':
                # Pi 4: VideoCore VI with V3D driver - optimized settings
                features = [
                    "VaapiVideoDecoder",        # H.264 hardware decode
                    "CanvasOopRasterization",   # GPU canvas rendering
                ]

                cmd.extend([
                    "--enable-gpu",
                    "--enable-gpu-rasterization",
                    "--ignore-gpu-blocklist",
                    "--ignore-gpu-blacklist",
                    "--enable-zero-copy",
                    f"--enable-features={','.join(features)}",
                ])

                if self.is_wayland:
                    cmd.extend(["--ozone-platform=wayland"])
                else:
                    cmd.extend(["--use-gl=egl"])

            elif self.pi_model == 'Pi3':
                # Pi 3: VideoCore IV - limited but functional acceleration
                cmd.extend([
                    "--enable-gpu",
                    "--ignore-gpu-blocklist",
                    "--use-gl=egl",
                    "--enable-features=VaapiVideoDecoder",
                ])
            else:
                # Unknown Pi or fallback - conservative acceleration
                cmd.extend([
                    "--enable-gpu",
                    "--ignore-gpu-blocklist",
                    "--use-gl=egl",
                ])
        else:
            # WebGL/WebGPU disabled - use software rendering
            cmd.extend([
                "--disable-gpu",
                "--disable-gpu-rasterization",
            ])

        # WebGL specific flags (separate from GPU acceleration)
        if self.enable_webgl:
            cmd.extend([
                "--enable-webgl",
                "--enable-webgl2-compute-context",
            ])
        else:
            cmd.extend([
                "--disable-webgl",
            ])

        # WebGPU specific flags (experimental)
        if self.enable_webgpu:
            if "--enable-unsafe-webgpu" not in cmd:  # Avoid duplicate if already added for Pi5
                cmd.append("--enable-unsafe-webgpu")
            if not any("WebGPU" in flag for flag in cmd):
                cmd.append("--enable-features=WebGPU")
        else:
            cmd.append("--disable-webgpu")

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

            # Detect X11 session and set appropriate environment
            display = self._detect_display()
            xauthority = self._detect_xauthority()

            env.update({
                "DISPLAY": display,
            })

            if xauthority:
                env["XAUTHORITY"] = xauthority

            # Ensure we have the right permissions
            env["HOME"] = os.path.expanduser("~")

            # Ensure the chromium data directory exists and is writable
            try:
                self.user_data_dir.mkdir(parents=True, exist_ok=True)
                # Test write permissions
                test_file = self.user_data_dir / "test_write"
                test_file.touch()
                test_file.unlink()
            except Exception as e:
                self.logger.warning(f"Cannot write to user data dir {self.user_data_dir}: {e}")
                # Use a temporary directory instead
                import tempfile
                self.user_data_dir = Path(tempfile.mkdtemp(prefix="ossuary_chromium_"))
                self.logger.info(f"Using temporary user data dir: {self.user_data_dir}")

            # Disable screensaver if configured
            if self.disable_screensaver:
                await self._disable_screensaver()

            # Hide cursor if configured
            if self.hide_cursor:
                await self._hide_cursor()

            # Build command
            cmd = self._get_chromium_command(target_url)

            # Log the complete command for debugging
            self.logger.info("=" * 80)
            self.logger.info("BROWSER STARTUP COMMAND:")
            self.logger.info("=" * 80)
            self.logger.info(f"Binary: {cmd[0]}")
            self.logger.info("Flags:")
            for i, flag in enumerate(cmd[1:], 1):
                if flag.startswith('--'):
                    self.logger.info(f"  [{i:2d}] {flag}")
                else:
                    self.logger.info(f"  [{i:2d}] {flag} (URL/value)")

            # Log environment variables
            self.logger.info("Environment:")
            display_env = {k: v for k, v in env.items() if k in ['DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'XDG_SESSION_TYPE', 'XDG_RUNTIME_DIR']}
            for key, value in display_env.items():
                self.logger.info(f"  {key}={value}")

            # Log the full command as a single line for easy copy/paste
            cmd_str = ' '.join(f'"{arg}"' if ' ' in arg else arg for arg in cmd)
            self.logger.info("Full command (copy/paste ready):")
            self.logger.info(f"  {cmd_str}")
            self.logger.info("=" * 80)

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

            # Wait a moment and check if process started successfully
            await asyncio.sleep(2)  # Give browser more time to start
            if self.process.poll() is not None:
                # Process already exited
                try:
                    stdout, stderr = self.process.communicate(timeout=1)
                    self.logger.error("Browser process exited immediately!")
                    self.logger.error(f"Exit code: {self.process.returncode}")
                    if stdout:
                        self.logger.error(f"STDOUT: {stdout.decode('utf-8', errors='ignore')}")
                    if stderr:
                        stderr_text = stderr.decode('utf-8', errors='ignore')
                        self.logger.error(f"STDERR: {stderr_text}")

                        # Check for common errors and provide solutions
                        if "cannot open display" in stderr_text.lower():
                            self.logger.error("SOLUTION: X11 display not accessible. Check DISPLAY env var and X permissions.")
                        elif "gpu process" in stderr_text.lower():
                            self.logger.error("SOLUTION: GPU process failed. Try disabling WebGL/WebGPU in config.")
                        elif "permission denied" in stderr_text.lower():
                            self.logger.error("SOLUTION: Permission issue. Check user permissions and file ownership.")
                except Exception as comm_e:
                    self.logger.error(f"Could not read process output: {comm_e}")
                self.is_running = False
                return False

            # Start monitoring
            asyncio.create_task(self._monitor_process())

            return True

        except Exception as e:
            self.logger.error(f"Failed to start browser: {e}")
            self.logger.error("=" * 80)
            self.logger.error("BROWSER STARTUP FAILED")
            self.logger.error("=" * 80)
            import traceback
            self.logger.error(f"Exception details: {traceback.format_exc()}")
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

        # Check if running as root (takes precedence)
        if os.getuid() == 0:
            self.logger.info("Running as root - using no-sandbox mode")
            flags.extend([
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-dev-shm-usage",
            ])
        # Check if running in container
        elif self._is_container():
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

    def _detect_display(self) -> str:
        """Detect the correct DISPLAY value."""
        # Check environment first
        if 'DISPLAY' in os.environ:
            return os.environ['DISPLAY']

        # Common defaults
        return ":0"

    def _detect_xauthority(self) -> Optional[str]:
        """Detect the correct XAUTHORITY file."""
        # Check environment first
        if 'XAUTHORITY' in os.environ:
            xauth_path = os.environ['XAUTHORITY']
            if os.path.exists(xauth_path):
                return xauth_path

        # Try to find X session owner
        try:
            # Find who owns the X server process
            result = subprocess.run(
                ["ps", "aux"],
                capture_output=True,
                text=True,
                timeout=5
            )

            for line in result.stdout.splitlines():
                if '/usr/bin/X' in line or 'Xorg' in line:
                    # Extract username (second column in ps aux)
                    parts = line.split()
                    if len(parts) >= 2:
                        x_user = parts[0]
                        self.logger.info(f"Found X server running as user: {x_user}")

                        # Try common Xauthority locations for this user
                        possible_paths = [
                            f"/home/{x_user}/.Xauthority",
                            f"/home/{x_user}/.Xauth",
                            f"/tmp/.X11-unix/X{x_user}",
                        ]

                        # Special case for root
                        if x_user == 'root':
                            possible_paths.insert(0, "/root/.Xauthority")

                        for path in possible_paths:
                            if os.path.exists(path):
                                self.logger.info(f"Using XAUTHORITY: {path}")
                                return path

                        break

            # Fallback: try to detect from running X processes
            result = subprocess.run(
                ["who", "-u"],
                capture_output=True,
                text=True,
                timeout=5
            )

            for line in result.stdout.splitlines():
                if ':0' in line or 'tty7' in line:  # Common X session indicators
                    parts = line.split()
                    if parts:
                        x_user = parts[0]
                        xauth_path = f"/home/{x_user}/.Xauthority"
                        if os.path.exists(xauth_path):
                            self.logger.info(f"Using XAUTHORITY from 'who': {xauth_path}")
                            return xauth_path

        except Exception as e:
            self.logger.debug(f"Failed to detect X session user: {e}")

        # Last resort: try common locations
        fallback_paths = [
            "/home/pi/.Xauthority",  # Common Pi default
            "/home/user/.Xauthority",  # Common generic user
            "/root/.Xauthority",  # Root fallback
        ]

        for path in fallback_paths:
            if os.path.exists(path):
                self.logger.warning(f"Using fallback XAUTHORITY: {path}")
                return path

        self.logger.warning("Could not find XAUTHORITY file")
        return None