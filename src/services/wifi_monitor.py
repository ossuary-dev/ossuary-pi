#!/usr/bin/env python3

import subprocess
import time
import logging
import json
import os
import sys
import signal
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('wifi_monitor')

CONFIG_FILE = '/etc/ossuary/config.json'
CAPTIVE_PORTAL_SERVICE = 'ossuary-captive-portal'
CHECK_INTERVAL = 30  # seconds
CONNECTION_TIMEOUT = 10  # seconds


def load_config():
    """Load configuration file"""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
    return {}


def check_internet_connection():
    """Check if we have internet connectivity"""
    try:
        result = subprocess.run(
            ['ping', '-c', '1', '-W', '2', '8.8.8.8'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception as e:
        logger.error(f"Error checking internet connection: {e}")
        return False


def check_wifi_connected():
    """Check if WiFi is connected"""
    try:
        # First check if interface is up
        link_check = subprocess.run(
            ['ip', 'link', 'show', 'wlan0'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if 'state DOWN' in link_check.stdout:
            return False, None

        # Check for connected SSID
        result = subprocess.run(
            ['iwgetid', '-r'],
            capture_output=True,
            text=True,
            timeout=5
        )
        ssid = result.stdout.strip()
        return bool(ssid), ssid
    except Exception as e:
        logger.error(f"Error checking WiFi status: {e}")
        return False, None


def get_known_networks():
    """Get list of known networks from wpa_supplicant"""
    networks = []
    wpa_conf = '/etc/wpa_supplicant/wpa_supplicant.conf'

    if os.path.exists(wpa_conf):
        try:
            with open(wpa_conf, 'r') as f:
                content = f.read()
                import re
                pattern = r'network=\{[^}]*ssid="([^"]+)"[^}]*\}'
                networks = re.findall(pattern, content)
        except Exception as e:
            logger.error(f"Error reading wpa_supplicant.conf: {e}")

    return networks


def try_connect_known_networks():
    """Try to connect to known networks"""
    networks = get_known_networks()

    if not networks:
        logger.info("No known networks found")
        return False

    logger.info(f"Found {len(networks)} known networks")

    for network in networks:
        logger.info(f"Trying to connect to {network}")
        try:
            subprocess.run(
                ['wpa_cli', 'reconfigure'],
                capture_output=True,
                timeout=10
            )
            time.sleep(5)

            connected, ssid = check_wifi_connected()
            if connected and ssid == network:
                logger.info(f"Successfully connected to {network}")
                return True

        except Exception as e:
            logger.error(f"Error connecting to {network}: {e}")

    return False


def start_captive_portal():
    """Start the captive portal service"""
    try:
        logger.info("Starting captive portal...")
        subprocess.run(
            ['systemctl', 'start', CAPTIVE_PORTAL_SERVICE],
            check=True,
            timeout=10
        )
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to start captive portal: {e}")
        return False
    except Exception as e:
        logger.error(f"Error starting captive portal: {e}")
        return False


def stop_captive_portal():
    """Stop the captive portal service"""
    try:
        logger.info("Stopping captive portal...")
        subprocess.run(
            ['systemctl', 'stop', CAPTIVE_PORTAL_SERVICE],
            check=True,
            timeout=10
        )
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to stop captive portal: {e}")
        return False
    except Exception as e:
        logger.error(f"Error stopping captive portal: {e}")
        return False


def is_captive_portal_running():
    """Check if captive portal is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', CAPTIVE_PORTAL_SERVICE],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout.strip() == 'active'
    except Exception as e:
        logger.error(f"Error checking captive portal status: {e}")
        return False


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    logger.info("Received shutdown signal, cleaning up...")
    stop_captive_portal()
    sys.exit(0)


def main():
    """Main monitoring loop"""
    logger.info("WiFi Monitor Service started")

    # Set up signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    captive_portal_active = False
    connection_lost_time = None

    while True:
        try:
            connected, ssid = check_wifi_connected()
            has_internet = check_internet_connection() if connected else False

            if connected and has_internet:
                logger.debug(f"Connected to {ssid} with internet access")
                connection_lost_time = None

                if captive_portal_active:
                    logger.info("WiFi restored, stopping captive portal")
                    stop_captive_portal()
                    captive_portal_active = False

            else:
                if connection_lost_time is None:
                    connection_lost_time = time.time()
                    logger.warning("WiFi connection or internet access lost")

                time_disconnected = time.time() - connection_lost_time

                if time_disconnected > CONNECTION_TIMEOUT:
                    if not captive_portal_active:
                        logger.info(f"No connection for {CONNECTION_TIMEOUT}s, trying known networks...")

                        if not try_connect_known_networks():
                            logger.info("Failed to connect to known networks, starting captive portal")
                            if start_captive_portal():
                                captive_portal_active = True
                            else:
                                logger.error("Failed to start captive portal")
                        else:
                            connection_lost_time = None

        except Exception as e:
            logger.error(f"Error in main loop: {e}")

        time.sleep(CHECK_INTERVAL)


if __name__ == '__main__':
    main()