#!/usr/bin/env python3
"""Comprehensive system test suite for Ossuary Pi."""

import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Any, Optional

import aiohttp
import psutil
import pytest


class OssuaryTestSuite:
    """Test suite for Ossuary Pi system validation."""

    def __init__(self):
        """Initialize test suite."""
        self.logger = logging.getLogger(__name__)
        self.config = self._load_test_config()
        self.test_results: List[Dict[str, Any]] = []

    def _load_test_config(self) -> Dict[str, Any]:
        """Load test configuration."""
        config_path = Path(__file__).parent / "test_config.json"

        if config_path.exists():
            with open(config_path) as f:
                return json.load(f)

        # Default test configuration
        return {
            "portal_url": "http://localhost",
            "api_url": "http://localhost:8080",
            "timeout": 30,
            "retry_count": 3,
            "expected_services": [
                "ossuary-config",
                "ossuary-netd",
                "ossuary-api",
                "ossuary-portal",
                "ossuary-kiosk"
            ]
        }

    async def test_service_status(self) -> Dict[str, Any]:
        """Test all system services are running."""
        self.logger.info("Testing service status...")

        results = {
            "test_name": "service_status",
            "passed": True,
            "details": {},
            "errors": []
        }

        for service in self.config["expected_services"]:
            try:
                # Check if service is active
                result = subprocess.run(
                    ["systemctl", "is-active", service],
                    capture_output=True, text=True, timeout=10
                )

                active = result.returncode == 0 and result.stdout.strip() == "active"
                results["details"][service] = {
                    "active": active,
                    "status": result.stdout.strip()
                }

                if not active:
                    results["passed"] = False
                    results["errors"].append(f"Service {service} is not active")

            except Exception as e:
                results["passed"] = False
                results["errors"].append(f"Failed to check {service}: {e}")
                results["details"][service] = {"error": str(e)}

        return results

    async def test_network_connectivity(self) -> Dict[str, Any]:
        """Test network connectivity and interfaces."""
        self.logger.info("Testing network connectivity...")

        results = {
            "test_name": "network_connectivity",
            "passed": True,
            "details": {},
            "errors": []
        }

        try:
            # Check network interfaces
            interfaces = psutil.net_if_addrs()
            results["details"]["interfaces"] = list(interfaces.keys())

            # Check for WiFi interface
            wifi_interfaces = [iface for iface in interfaces.keys() if "wlan" in iface]
            if not wifi_interfaces:
                results["errors"].append("No WiFi interface found")
                results["passed"] = False
            else:
                results["details"]["wifi_interfaces"] = wifi_interfaces

            # Check NetworkManager status
            try:
                nm_result = subprocess.run(
                    ["nmcli", "general", "status"],
                    capture_output=True, text=True, timeout=10
                )
                results["details"]["networkmanager"] = {
                    "available": nm_result.returncode == 0,
                    "output": nm_result.stdout.strip()
                }
            except Exception as e:
                results["errors"].append(f"NetworkManager check failed: {e}")

        except Exception as e:
            results["passed"] = False
            results["errors"].append(f"Network connectivity test failed: {e}")

        return results

    async def test_portal_endpoints(self) -> Dict[str, Any]:
        """Test portal web interface endpoints."""
        self.logger.info("Testing portal endpoints...")

        results = {
            "test_name": "portal_endpoints",
            "passed": True,
            "details": {},
            "errors": []
        }

        endpoints = [
            "/",
            "/health",
            "/assets/style.css",
            "/assets/app.js"
        ]

        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30)) as session:
            for endpoint in endpoints:
                try:
                    url = f"{self.config['portal_url']}{endpoint}"
                    async with session.get(url) as response:
                        results["details"][endpoint] = {
                            "status_code": response.status,
                            "accessible": response.status < 400
                        }

                        if response.status >= 400:
                            results["passed"] = False
                            results["errors"].append(f"Endpoint {endpoint} returned {response.status}")

                except Exception as e:
                    results["passed"] = False
                    results["errors"].append(f"Failed to access {endpoint}: {e}")
                    results["details"][endpoint] = {"error": str(e)}

        return results

    async def test_api_endpoints(self) -> Dict[str, Any]:
        """Test API endpoints functionality."""
        self.logger.info("Testing API endpoints...")

        results = {
            "test_name": "api_endpoints",
            "passed": True,
            "details": {},
            "errors": []
        }

        endpoints = [
            {"path": "/health", "method": "GET"},
            {"path": "/api/v1/system/info", "method": "GET"},
            {"path": "/api/v1/network/status", "method": "GET"},
            {"path": "/api/v1/kiosk/status", "method": "GET"},
            {"path": "/api/v1/config", "method": "GET"}
        ]

        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30)) as session:
            for endpoint in endpoints:
                try:
                    url = f"{self.config['api_url']}{endpoint['path']}"
                    method = getattr(session, endpoint["method"].lower())

                    async with method(url) as response:
                        results["details"][endpoint["path"]] = {
                            "status_code": response.status,
                            "accessible": response.status < 400
                        }

                        if response.status == 200:
                            try:
                                data = await response.json()
                                results["details"][endpoint["path"]]["response_valid"] = True
                                results["details"][endpoint["path"]]["response_size"] = len(str(data))
                            except Exception:
                                results["details"][endpoint["path"]]["response_valid"] = False

                        if response.status >= 400:
                            results["passed"] = False
                            results["errors"].append(
                                f"API endpoint {endpoint['path']} returned {response.status}"
                            )

                except Exception as e:
                    results["passed"] = False
                    results["errors"].append(f"Failed to access API {endpoint['path']}: {e}")
                    results["details"][endpoint["path"]] = {"error": str(e)}

        return results

    async def test_display_system(self) -> Dict[str, Any]:
        """Test display and X11 system."""
        self.logger.info("Testing display system...")

        results = {
            "test_name": "display_system",
            "passed": True,
            "details": {},
            "errors": []
        }

        try:
            # Check if X server is running
            x_result = subprocess.run(
                ["xdpyinfo", "-display", ":0"],
                capture_output=True, text=True, timeout=10
            )

            results["details"]["x_server"] = {
                "running": x_result.returncode == 0,
                "display": ":0"
            }

            if x_result.returncode != 0:
                results["errors"].append("X server is not running on :0")
                results["passed"] = False

            # Check GPU capabilities
            try:
                gpu_result = subprocess.run(
                    ["glxinfo", "-display", ":0"],
                    capture_output=True, text=True, timeout=10
                )

                if gpu_result.returncode == 0:
                    gpu_info = gpu_result.stdout
                    results["details"]["gpu"] = {
                        "available": True,
                        "opengl_vendor": self._extract_gpu_info(gpu_info, "OpenGL vendor string"),
                        "opengl_renderer": self._extract_gpu_info(gpu_info, "OpenGL renderer string"),
                        "webgl_supported": "Mesa" in gpu_info or "VC4" in gpu_info
                    }
                else:
                    results["details"]["gpu"] = {"available": False}

            except FileNotFoundError:
                results["details"]["gpu"] = {"available": False, "glxinfo_missing": True}

            # Check Chromium availability
            try:
                chrome_result = subprocess.run(
                    ["chromium-browser", "--version"],
                    capture_output=True, text=True, timeout=10
                )

                results["details"]["chromium"] = {
                    "available": chrome_result.returncode == 0,
                    "version": chrome_result.stdout.strip() if chrome_result.returncode == 0 else None
                }

                if chrome_result.returncode != 0:
                    results["errors"].append("Chromium browser is not available")
                    results["passed"] = False

            except FileNotFoundError:
                results["passed"] = False
                results["errors"].append("Chromium browser is not installed")
                results["details"]["chromium"] = {"available": False}

        except Exception as e:
            results["passed"] = False
            results["errors"].append(f"Display system test failed: {e}")

        return results

    def _extract_gpu_info(self, gpu_info: str, field: str) -> Optional[str]:
        """Extract GPU information from glxinfo output."""
        for line in gpu_info.split('\n'):
            if field in line:
                return line.split(':', 1)[1].strip()
        return None

    async def test_configuration_system(self) -> Dict[str, Any]:
        """Test configuration management system."""
        self.logger.info("Testing configuration system...")

        results = {
            "test_name": "configuration_system",
            "passed": True,
            "details": {},
            "errors": []
        }

        try:
            # Check configuration files
            config_files = [
                "/etc/ossuary/config.json",
                "/etc/ossuary/default.json"
            ]

            for config_file in config_files:
                if Path(config_file).exists():
                    try:
                        with open(config_file) as f:
                            config_data = json.load(f)
                        results["details"][config_file] = {
                            "exists": True,
                            "valid_json": True,
                            "size": len(str(config_data))
                        }
                    except json.JSONDecodeError:
                        results["passed"] = False
                        results["errors"].append(f"Invalid JSON in {config_file}")
                        results["details"][config_file] = {
                            "exists": True,
                            "valid_json": False
                        }
                else:
                    results["passed"] = False
                    results["errors"].append(f"Configuration file {config_file} does not exist")
                    results["details"][config_file] = {"exists": False}

            # Check data directories
            data_dirs = [
                "/var/lib/ossuary",
                "/var/log/ossuary"
            ]

            for data_dir in data_dirs:
                if Path(data_dir).exists():
                    results["details"][data_dir] = {
                        "exists": True,
                        "writable": os.access(data_dir, os.W_OK)
                    }
                else:
                    results["passed"] = False
                    results["errors"].append(f"Data directory {data_dir} does not exist")
                    results["details"][data_dir] = {"exists": False}

        except Exception as e:
            results["passed"] = False
            results["errors"].append(f"Configuration system test failed: {e}")

        return results

    async def test_system_resources(self) -> Dict[str, Any]:
        """Test system resource availability."""
        self.logger.info("Testing system resources...")

        results = {
            "test_name": "system_resources",
            "passed": True,
            "details": {},
            "errors": []
        }

        try:
            # Memory check
            memory = psutil.virtual_memory()
            results["details"]["memory"] = {
                "total_mb": memory.total // 1024 // 1024,
                "available_mb": memory.available // 1024 // 1024,
                "usage_percent": memory.percent
            }

            if memory.available < 128 * 1024 * 1024:  # Less than 128MB available
                results["errors"].append("Low available memory")
                results["passed"] = False

            # CPU check
            cpu_percent = psutil.cpu_percent(interval=1)
            results["details"]["cpu"] = {
                "count": psutil.cpu_count(),
                "usage_percent": cpu_percent
            }

            # Disk check
            disk = psutil.disk_usage('/')
            results["details"]["disk"] = {
                "total_gb": disk.total // 1024 // 1024 // 1024,
                "free_gb": disk.free // 1024 // 1024 // 1024,
                "usage_percent": (disk.used / disk.total) * 100
            }

            if disk.free < 1024 * 1024 * 1024:  # Less than 1GB free
                results["errors"].append("Low disk space")
                results["passed"] = False

            # Temperature check (Raspberry Pi specific)
            try:
                with open("/sys/class/thermal/thermal_zone0/temp") as f:
                    temp_raw = f.read().strip()
                    temp_celsius = float(temp_raw) / 1000.0
                    results["details"]["temperature"] = {
                        "celsius": temp_celsius,
                        "fahrenheit": (temp_celsius * 9/5) + 32
                    }

                    if temp_celsius > 80:  # High temperature
                        results["errors"].append("High CPU temperature")
                        results["passed"] = False

            except FileNotFoundError:
                results["details"]["temperature"] = {"available": False}

        except Exception as e:
            results["passed"] = False
            results["errors"].append(f"System resources test failed: {e}")

        return results

    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all system tests."""
        self.logger.info("Starting comprehensive system test suite...")

        test_suite_results = {
            "start_time": time.time(),
            "tests": [],
            "summary": {
                "total": 0,
                "passed": 0,
                "failed": 0
            }
        }

        # List of test methods
        test_methods = [
            self.test_service_status,
            self.test_network_connectivity,
            self.test_portal_endpoints,
            self.test_api_endpoints,
            self.test_display_system,
            self.test_configuration_system,
            self.test_system_resources
        ]

        # Run all tests
        for test_method in test_methods:
            try:
                result = await test_method()
                test_suite_results["tests"].append(result)
                test_suite_results["summary"]["total"] += 1

                if result["passed"]:
                    test_suite_results["summary"]["passed"] += 1
                    self.logger.info(f"✓ {result['test_name']} PASSED")
                else:
                    test_suite_results["summary"]["failed"] += 1
                    self.logger.error(f"✗ {result['test_name']} FAILED: {result['errors']}")

            except Exception as e:
                self.logger.error(f"Test {test_method.__name__} crashed: {e}")
                test_suite_results["tests"].append({
                    "test_name": test_method.__name__,
                    "passed": False,
                    "errors": [f"Test crashed: {e}"],
                    "details": {}
                })
                test_suite_results["summary"]["total"] += 1
                test_suite_results["summary"]["failed"] += 1

        test_suite_results["end_time"] = time.time()
        test_suite_results["duration"] = test_suite_results["end_time"] - test_suite_results["start_time"]

        return test_suite_results

    def generate_report(self, results: Dict[str, Any]) -> str:
        """Generate a formatted test report."""
        report = []
        report.append("="*60)
        report.append("OSSUARY PI SYSTEM TEST REPORT")
        report.append("="*60)
        report.append("")

        # Summary
        summary = results["summary"]
        report.append(f"Total Tests: {summary['total']}")
        report.append(f"Passed: {summary['passed']}")
        report.append(f"Failed: {summary['failed']}")
        report.append(f"Success Rate: {(summary['passed']/summary['total']*100):.1f}%")
        report.append(f"Duration: {results['duration']:.2f} seconds")
        report.append("")

        # Individual test results
        for test in results["tests"]:
            status = "PASS" if test["passed"] else "FAIL"
            report.append(f"[{status}] {test['test_name']}")

            if test["errors"]:
                for error in test["errors"]:
                    report.append(f"  ERROR: {error}")

            if test["details"]:
                report.append("  Details:")
                for key, value in test["details"].items():
                    report.append(f"    {key}: {value}")

            report.append("")

        return "\n".join(report)


async def main():
    """Main test runner."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

    test_suite = OssuaryTestSuite()
    results = await test_suite.run_all_tests()

    # Generate report
    report = test_suite.generate_report(results)
    print(report)

    # Save report to file
    timestamp = int(time.time())
    report_file = f"/tmp/ossuary_test_report_{timestamp}.txt"
    with open(report_file, 'w') as f:
        f.write(report)

    print(f"\nTest report saved to: {report_file}")

    # Exit with appropriate code
    if results["summary"]["failed"] > 0:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    asyncio.run(main())