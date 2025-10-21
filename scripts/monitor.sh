#!/bin/bash
"""Service monitoring script for Ossuary Pi."""

# Simple monitoring script that can be run via cron
# to ensure services stay running

SERVICES=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-kiosk")
LOG_FILE="/var/log/ossuary/monitor.log"
ALERT_FILE="/tmp/ossuary_alerts"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_service() {
    local service=$1

    if ! systemctl is-active --quiet "$service"; then
        log_message "WARNING: $service is not running, attempting restart"

        if systemctl restart "$service"; then
            log_message "SUCCESS: $service restarted successfully"
        else
            log_message "ERROR: Failed to restart $service"
            echo "$service failed to restart at $(date)" >> "$ALERT_FILE"
        fi
    fi
}

# Main monitoring loop
for service in "${SERVICES[@]}"; do
    check_service "$service"
done

# Clean up old alerts (older than 1 hour)
if [[ -f "$ALERT_FILE" ]]; then
    find "$ALERT_FILE" -mmin +60 -delete 2>/dev/null || true
fi

# Rotate log file if it gets too large (>10MB)
if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 10485760 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log_message "Log file rotated"
fi