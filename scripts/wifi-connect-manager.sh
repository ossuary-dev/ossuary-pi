#!/bin/bash

# WiFi Connect Manager
# Intelligently manages when to run WiFi Connect captive portal
# Only starts AP mode when no WiFi connection is available

CONFIG_FILE="/etc/ossuary/config.json"
LOG_FILE="/var/log/wifi-connect-manager.log"
CHECK_INTERVAL=30  # Check every 30 seconds
MAX_WAIT_FOR_NETWORK=120  # Wait up to 2 minutes for network on boot

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if we have a working internet connection
has_internet() {
    # Try multiple methods to detect internet connectivity

    # Method 1: Check if we can reach a reliable DNS server
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi

    # Method 2: Check if we can reach Cloudflare DNS
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi

    # Method 3: Try HTTP connectivity test
    if curl -s --max-time 5 http://detectportal.firefox.com/canonical.html >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Check if we have WiFi connection (not necessarily internet)
has_wifi_connection() {
    # Check if any WiFi interface is connected
    if iwgetid -r >/dev/null 2>&1; then
        local ssid=$(iwgetid -r)
        if [ -n "$ssid" ]; then
            log "Connected to WiFi: $ssid"
            return 0
        fi
    fi

    # Alternative check using NetworkManager
    if command -v nmcli >/dev/null; then
        if nmcli -t -f WIFI g status 2>/dev/null | grep -q "enabled"; then
            if nmcli -t -f STATE,CONNECTION device status 2>/dev/null | grep "wifi" | grep -q "connected"; then
                return 0
            fi
        fi
    fi

    return 1
}

# Check if WiFi Connect is running
wifi_connect_running() {
    systemctl is-active --quiet wifi-connect
}

# Start WiFi Connect (captive portal)
start_wifi_connect() {
    log "No WiFi connection detected, starting captive portal..."
    systemctl start wifi-connect

    if systemctl is-active --quiet wifi-connect; then
        log "WiFi Connect captive portal started successfully on port 80"
        log "Connect to 'Ossuary-Setup' network to configure WiFi"
    else
        log "ERROR: Failed to start WiFi Connect"
    fi
}

# Stop WiFi Connect
stop_wifi_connect() {
    if wifi_connect_running; then
        log "WiFi connection restored, stopping captive portal..."
        systemctl stop wifi-connect
        log "Captive portal stopped"
    fi
}

# Wait for network on boot
wait_for_network_on_boot() {
    local waited=0
    log "Waiting for network connection on boot..."

    while [ $waited -lt $MAX_WAIT_FOR_NETWORK ]; do
        if has_wifi_connection; then
            log "WiFi connection found after ${waited}s"
            return 0
        fi

        sleep 5
        waited=$((waited + 5))

        if [ $((waited % 30)) -eq 0 ]; then
            log "Still waiting for network... (${waited}s/${MAX_WAIT_FOR_NETWORK}s)"
        fi
    done

    log "No network connection after ${MAX_WAIT_FOR_NETWORK}s"
    return 1
}

# Main monitoring loop
monitor_network() {
    log "Starting WiFi connection monitoring..."

    while true; do
        if has_wifi_connection; then
            # We have WiFi, make sure captive portal is off
            stop_wifi_connect

            # Also check if we have internet
            if has_internet; then
                # All good, check again later
                sleep $CHECK_INTERVAL
            else
                log "WiFi connected but no internet, waiting..."
                sleep $((CHECK_INTERVAL / 2))  # Check more frequently
            fi
        else
            # No WiFi, start captive portal if not already running
            if ! wifi_connect_running; then
                start_wifi_connect
            fi

            # Check more frequently when in AP mode
            sleep $((CHECK_INTERVAL / 3))
        fi
    done
}

# Signal handlers
handle_term() {
    log "Received TERM signal, shutting down..."
    stop_wifi_connect
    exit 0
}

handle_hup() {
    log "Received HUP signal, reloading..."
    # Could reload config here if needed
}

trap handle_term TERM INT
trap handle_hup HUP

# Main execution
main() {
    log "===== WiFi Connect Manager Starting ====="
    log "PID: $$"

    # On boot, wait a bit for the network to come up
    wait_for_network_on_boot

    # Start the monitoring loop
    monitor_network
}

# Run main function
main "$@"