#!/bin/bash

# Post-install script for SSH-breaking operations
# This script runs operations that will break SSH connections
# It's designed to continue running even if SSH drops

set -e

LOG_FILE="/var/log/ossuary-post-install.log"

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/ossuary-post-install.log"

log() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

log "=== Starting Ossuary Post-Install Operations ==="
log "PID: $$"
log "These operations may break SSH connections but will continue running"

# Make sure this script continues even if parent process dies
nohup bash -c "

# Source the script functions if available
if [[ -f '/tmp/ossuary_install_functions.sh' ]]; then
    source '/tmp/ossuary_install_functions.sh'
fi

log() {
    echo \"\$(date): \$1\" | tee -a '$LOG_FILE'
}

# Function to configure DNS for captive portal
configure_captive_portal_dns() {
    log \"Configuring DNS for captive portal detection...\"

    # Create NetworkManager dispatcher script for DNS override
    cat > /etc/NetworkManager/dispatcher.d/99-ossuary-dns << 'EOF'
#!/bin/bash
# Ossuary DNS configuration for captive portal detection

if [[ \"\$1\" == \"ossuary-ap\" && \"\$2\" == \"up\" ]]; then
    # Override DNS for captive portal
    echo \"nameserver 192.168.42.1\" > /etc/resolv.conf
    echo \"search ossuary.local\" >> /etc/resolv.conf

    # Ensure dnsmasq is configured for captive portal
    if [[ -f /etc/dnsmasq.d/ossuary-ap.conf ]]; then
        systemctl restart dnsmasq || true
    fi
fi
EOF

    chmod +x /etc/NetworkManager/dispatcher.d/99-ossuary-dns
    log \"DNS dispatcher script created\"

    # Create dnsmasq configuration for AP mode
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/ossuary-ap.conf << 'EOF'
# Ossuary AP mode DNS configuration
interface=wlan0
dhcp-range=192.168.42.10,192.168.42.100,12h
dhcp-option=option:router,192.168.42.1
dhcp-option=option:dns-server,192.168.42.1
address=/ossuary.local/192.168.42.1
address=/connectivitycheck.gstatic.com/192.168.42.1
address=/clients3.google.com/192.168.42.1
address=/captive.apple.com/192.168.42.1
EOF

    log \"dnsmasq configuration created\"

    # This will restart NetworkManager and break SSH
    log \"WARNING: About to restart NetworkManager - SSH will disconnect\"
    sleep 2
    systemctl restart NetworkManager
    log \"NetworkManager restarted\"
}

# Function to perform final system configuration
final_system_setup() {
    log \"Performing final system setup...\"

    # Reload systemd to pick up any new services
    systemctl daemon-reload

    # Enable and start critical services
    for service in ossuary-config ossuary-display ossuary-kiosk ossuary-netd ossuary-portal; do
        if systemctl list-unit-files | grep -q \"\$service.service\"; then
            log \"Enabling \$service service\"
            systemctl enable \"\$service\" || log \"Failed to enable \$service\"
        fi
    done

    # Start essential services that don't depend on network
    for service in ossuary-config ossuary-display; do
        if systemctl list-unit-files | grep -q \"\$service.service\"; then
            log \"Starting \$service service\"
            systemctl start \"\$service\" || log \"Failed to start \$service\"
        fi
    done

    log \"Services configured\"
}

# Function to reboot system
schedule_reboot() {
    log \"Scheduling system reboot in 30 seconds...\"
    log \"Post-install operations completed successfully\"
    log \"System will reboot to apply all changes\"

    # Schedule reboot
    shutdown -r +1 \"Ossuary post-install reboot - system will be ready in 2 minutes\" || reboot
}

# Execute post-install operations
log \"Starting DNS configuration (will break SSH)...\"
configure_captive_portal_dns

log \"DNS configuration completed\"

log \"Performing final system setup...\"
final_system_setup

log \"Scheduling reboot...\"
schedule_reboot

# Clean up post-install service and files
log \"Cleaning up post-install service...\"
systemctl disable ossuary-post-install.service
rm -f /etc/systemd/system/ossuary-post-install.service
rm -f /tmp/ossuary_install_functions.sh
systemctl daemon-reload

log \"=== Post-install operations completed ===\""

" > /dev/null 2>&1 &

log "Post-install script started in background (PID: $!)"
log "Operations will continue even if SSH disconnects"
log "Check $LOG_FILE for progress"

exit 0