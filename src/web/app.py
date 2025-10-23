#!/usr/bin/env python3

from flask import Flask, render_template, request, jsonify, redirect, url_for
import subprocess
import json
import os
import re
import logging
import sys
from pathlib import Path
from werkzeug.serving import run_simple

app = Flask(__name__)
app.config['SECRET_KEY'] = 'ossuary-captive-portal-secret-key'

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONFIG_FILE = '/etc/ossuary/config.json'
WPA_CONF = '/etc/wpa_supplicant/wpa_supplicant.conf'


def load_config():
    """Load configuration"""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
    return {'startup_command': '', 'wifi_networks': []}


def save_config(config):
    """Save configuration"""
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        logger.error(f"Failed to save config: {e}")
        return False


def validate_ssid(ssid):
    """Validate SSID format"""
    if not ssid or len(ssid) > 32:
        return False
    # SSIDs should be printable ASCII
    return all(32 <= ord(c) <= 126 for c in ssid)


def validate_command(command):
    """Basic validation for startup command"""
    if not command:
        return True  # Empty command is valid (disables startup)
    # Basic sanity check - no null bytes
    return '\x00' not in command and len(command) < 4096


def scan_wifi_networks():
    """Scan for available WiFi networks"""
    networks = []
    try:
        # Check if interface exists first
        check_result = subprocess.run(
            ['ip', 'link', 'show', 'wlan0'],
            capture_output=True,
            timeout=5
        )
        if check_result.returncode != 0:
            logger.error("WiFi interface wlan0 not found")
            return []

        result = subprocess.run(
            ['sudo', 'iwlist', 'wlan0', 'scan'],
            capture_output=True,
            text=True,
            timeout=15
        )

        if result.returncode == 0:
            current_network = {}
            for line in result.stdout.split('\n'):
                line = line.strip()

                if 'Cell' in line:
                    if current_network:
                        networks.append(current_network)
                    current_network = {}

                elif 'ESSID:' in line:
                    match = re.search(r'ESSID:"([^"]*)"', line)
                    if match:
                        current_network['ssid'] = match.group(1)

                elif 'Quality=' in line:
                    match = re.search(r'Quality=(\d+)/(\d+)', line)
                    if match:
                        quality = int(match.group(1))
                        max_quality = int(match.group(2))
                        current_network['signal'] = int((quality / max_quality) * 100)

                elif 'Encryption key:' in line:
                    current_network['encrypted'] = 'on' in line.lower()

            if current_network:
                networks.append(current_network)

        # Remove duplicates and empty SSIDs
        seen = set()
        unique_networks = []
        for net in networks:
            if 'ssid' in net and net['ssid'] and net['ssid'] not in seen:
                seen.add(net['ssid'])
                unique_networks.append(net)

        # Sort by signal strength
        unique_networks.sort(key=lambda x: x.get('signal', 0), reverse=True)

    except Exception as e:
        logger.error(f"Error scanning WiFi: {e}")

    return unique_networks


def add_wifi_network(ssid, password):
    """Add WiFi network to wpa_supplicant"""
    try:
        # Create network entry
        network_config = f'''
network={{
    ssid="{ssid}"
    psk="{password}"
    key_mgmt=WPA-PSK
}}
'''

        # Append to wpa_supplicant.conf
        with open(WPA_CONF, 'a') as f:
            f.write(network_config)

        # Reconfigure wpa_supplicant
        subprocess.run(['wpa_cli', 'reconfigure'], check=True, timeout=5)

        # Save to our config as well
        config = load_config()
        if 'wifi_networks' not in config:
            config['wifi_networks'] = []

        # Check if network already exists
        for net in config['wifi_networks']:
            if net['ssid'] == ssid:
                net['password'] = password
                break
        else:
            config['wifi_networks'].append({'ssid': ssid, 'password': password})

        save_config(config)
        return True

    except Exception as e:
        logger.error(f"Error adding WiFi network: {e}")
        return False


def connect_wifi(ssid):
    """Connect to a specific WiFi network"""
    try:
        # Use wpa_cli to connect
        subprocess.run(['wpa_cli', 'select_network', ssid], check=True, timeout=10)
        return True
    except Exception as e:
        logger.error(f"Error connecting to WiFi: {e}")
        return False


@app.route('/')
def index():
    """Main page"""
    config = load_config()
    return render_template('index.html', config=config)


@app.route('/wifi')
def wifi_page():
    """WiFi configuration page"""
    networks = scan_wifi_networks()
    config = load_config()
    return render_template('wifi.html', networks=networks, saved_networks=config.get('wifi_networks', []))


@app.route('/scan_wifi', methods=['GET'])
def scan_wifi():
    """API endpoint to scan WiFi networks"""
    networks = scan_wifi_networks()
    return jsonify(networks)


@app.route('/connect_wifi', methods=['POST'])
def connect_wifi_endpoint():
    """Connect to WiFi network"""
    try:
        data = request.json
        ssid = data.get('ssid')
        password = data.get('password')

        if not ssid:
            return jsonify({'success': False, 'error': 'SSID required'}), 400

        if not validate_ssid(ssid):
            return jsonify({'success': False, 'error': 'Invalid SSID format'}), 400

        if password:
            # Add network with password
            if not add_wifi_network(ssid, password):
                return jsonify({'success': False, 'error': 'Failed to add network'}), 500

        # Try to connect
        if connect_wifi(ssid):
            return jsonify({'success': True, 'message': f'Connecting to {ssid}'})
        else:
            return jsonify({'success': False, 'error': 'Failed to connect'}), 500
    except Exception as e:
        logger.error(f"Error in connect_wifi endpoint: {e}")
        return jsonify({'success': False, 'error': 'Internal error'}), 500


@app.route('/startup')
def startup_page():
    """Startup command configuration page"""
    config = load_config()
    return render_template('startup.html', command=config.get('startup_command', ''))


@app.route('/set_startup', methods=['POST'])
def set_startup_command():
    """Set the startup command"""
    try:
        data = request.json
        command = data.get('command', '').strip()

        if not validate_command(command):
            return jsonify({'success': False, 'error': 'Invalid command format'}), 400

        config = load_config()
        config['startup_command'] = command

        if save_config(config):
            # Update the systemd service with new command
            update_startup_service(command)
            return jsonify({'success': True, 'message': 'Startup command updated'})
        else:
            return jsonify({'success': False, 'error': 'Failed to save configuration'}), 500
    except Exception as e:
        logger.error(f"Error setting startup command: {e}")
        return jsonify({'success': False, 'error': 'Internal error'}), 500


def update_startup_service(command):
    """Update the startup service with new command"""
    service_file = '/etc/systemd/system/ossuary-startup.service'

    if command:
        service_content = f'''[Unit]
Description=Ossuary User Startup Command
After=multi-user.target graphical.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Environment="DISPLAY=:0"
Environment="HOME=/home/pi"
ExecStart=/bin/bash -c '{command}'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
'''

        try:
            with open(service_file, 'w') as f:
                f.write(service_content)

            # Reload systemd and enable service
            subprocess.run(['systemctl', 'daemon-reload'], check=True)
            subprocess.run(['systemctl', 'enable', 'ossuary-startup.service'], check=True)
            subprocess.run(['systemctl', 'restart', 'ossuary-startup.service'], check=True)

        except Exception as e:
            logger.error(f"Failed to update startup service: {e}")

    else:
        # Disable service if no command
        try:
            subprocess.run(['systemctl', 'stop', 'ossuary-startup.service'])
            subprocess.run(['systemctl', 'disable', 'ossuary-startup.service'])
        except:
            pass


@app.route('/status')
def status():
    """Get system status"""
    status_info = {}

    # Check WiFi status
    try:
        result = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True)
        status_info['wifi_connected'] = bool(result.stdout.strip())
        status_info['wifi_ssid'] = result.stdout.strip() if result.stdout.strip() else None
    except:
        status_info['wifi_connected'] = False
        status_info['wifi_ssid'] = None

    # Check internet connectivity
    try:
        result = subprocess.run(['ping', '-c', '1', '-W', '2', '8.8.8.8'], capture_output=True, timeout=3)
        status_info['internet'] = result.returncode == 0
    except:
        status_info['internet'] = False

    # Check startup service status
    try:
        result = subprocess.run(['systemctl', 'is-active', 'ossuary-startup.service'], capture_output=True, text=True)
        status_info['startup_service'] = result.stdout.strip() == 'active'
    except:
        status_info['startup_service'] = False

    config = load_config()
    status_info['startup_command'] = config.get('startup_command', '')

    return jsonify(status_info)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)