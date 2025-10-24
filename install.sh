#!/bin/bash

# Ossuary Pi - Installation, Update, and Repair Script
# Handles fresh installs, updates existing installations, and repairs broken components

set -e

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
CUSTOM_UI_DIR="$INSTALL_DIR/custom-ui"
LOG_FILE="/tmp/ossuary-install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Show spinner for long operations
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if already installed
check_existing_installation() {
    local is_installed=false
    local needs_repair=false

    if [ -d "$INSTALL_DIR" ]; then
        is_installed=true
        log "Existing installation detected at $INSTALL_DIR"
    fi

    if systemctl list-units --full -all | grep -q "wifi-connect.service"; then
        is_installed=true
        log "WiFi Connect service detected"

        # Check if service is broken
        if ! systemctl is-active --quiet wifi-connect 2>/dev/null; then
            if journalctl -u wifi-connect -n 1 | grep -q "No such file or directory"; then
                needs_repair=true
                warning "WiFi Connect binary is missing - will reinstall"
            fi
        fi
    fi

    if [ "$is_installed" = true ]; then
        if [ "$needs_repair" = true ]; then
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}       REPAIR MODE - FIXING BROKEN COMPONENTS     ${NC}"
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            return 2  # Repair mode
        else
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}        UPDATE MODE - REFRESHING INSTALLATION     ${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            return 1  # Update mode
        fi
    fi

    return 0  # Fresh install
}

# Backup configuration
backup_config() {
    if [ -f "$CONFIG_DIR/config.json" ]; then
        local backup_file="/tmp/ossuary-config-backup-$(date +%Y%m%d-%H%M%S).json"
        cp "$CONFIG_DIR/config.json" "$backup_file"
        log "Configuration backed up to $backup_file"
        echo "$backup_file"  # Return backup path
    fi
}

# Restore configuration
restore_config() {
    local backup_file="$1"
    if [ -f "$backup_file" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$backup_file" "$CONFIG_DIR/config.json"
        log "Configuration restored from $backup_file"
    fi
}

# Install or update WiFi Connect
install_wifi_connect() {
    local force_reinstall="${1:-false}"

    # Check if WiFi Connect exists and works
    if [ "$force_reinstall" != true ] && command -v wifi-connect &> /dev/null; then
        if wifi-connect --version &> /dev/null; then
            success "WiFi Connect binary is working"
            return 0
        fi
    fi

    log "Installing/updating WiFi Connect binary..."

    # Detect architecture - Pi 4/5 run 64-bit, older run 32-bit
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        WIFI_CONNECT_ARCH="aarch64"
        log "Detected 64-bit ARM (Pi 4/5 with 64-bit OS)"
    elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armhf" ]; then
        WIFI_CONNECT_ARCH="armv7hf"
        log "Detected 32-bit ARM (Pi 3/Zero 2 W or 32-bit OS)"
    else
        error "Unsupported architecture: $ARCH"
    fi

    # Download directly from GitHub releases
    log "Downloading WiFi Connect from GitHub releases..."
    WIFI_CONNECT_VERSION="v4.14.4"  # Latest stable version compatible with Trixie
    DOWNLOAD_URL="https://github.com/balena-os/wifi-connect/releases/download/${WIFI_CONNECT_VERSION}/wifi-connect-linux-${WIFI_CONNECT_ARCH}.tar.gz"

    # Show which Pi model we're installing for
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' < /proc/device-tree/model)
        log "Installing for: $MODEL"
    fi

    cd /tmp
    rm -f wifi-connect.tar.gz wifi-connect  # Clean up any old files

    wget -q --show-progress "$DOWNLOAD_URL" -O wifi-connect.tar.gz >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error "Failed to download WiFi Connect"
    fi

    log "Extracting WiFi Connect..."
    tar -xzf wifi-connect.tar.gz >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error "Failed to extract WiFi Connect"
    fi

    # Stop service if running
    if systemctl is-active --quiet wifi-connect; then
        systemctl stop wifi-connect
    fi

    mv wifi-connect /usr/local/bin/ >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/bin/wifi-connect
    rm -f wifi-connect.tar.gz

    # Verify installation
    if ! command -v wifi-connect &> /dev/null; then
        error "WiFi Connect installation failed"
    fi

    if wifi-connect --version &> /dev/null; then
        success "WiFi Connect binary installed and verified"
    else
        warning "WiFi Connect installed but may have issues"
    fi
}

# Update custom UI and scripts
update_components() {
    log "Updating Ossuary components..."

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CUSTOM_UI_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$INSTALL_DIR/scripts"

    # Copy custom UI
    if [ -d "$REPO_DIR/custom-ui" ]; then
        cp -r "$REPO_DIR/custom-ui"/* "$CUSTOM_UI_DIR/"
        success "Custom UI updated"
    fi

    # Copy scripts
    if [ -f "$REPO_DIR/scripts/startup-manager.sh" ]; then
        cp "$REPO_DIR/scripts/startup-manager.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/startup-manager.sh"
    fi

    if [ -f "$REPO_DIR/scripts/config-handler.py" ]; then
        cp "$REPO_DIR/scripts/config-handler.py" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/config-handler.py"
    fi

    if [ -f "$REPO_DIR/scripts/config-server.py" ]; then
        cp "$REPO_DIR/scripts/config-server.py" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/config-server.py"
    fi

    success "Scripts updated"
}

# Update systemd services
update_services() {
    log "Updating systemd services..."

    # WiFi Connect service
    cat > /etc/systemd/system/wifi-connect.service << EOF
[Unit]
Description=Balena WiFi Connect
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wifi-connect \\
    --portal-ssid "Ossuary-Setup" \\
    --ui-directory $CUSTOM_UI_DIR \\
    --activity-timeout 600 \\
    --portal-listening-port 80
Restart=on-failure
RestartSec=10
Environment="DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket"

[Install]
WantedBy=multi-user.target
EOF

    # Startup service
    cat > /etc/systemd/system/ossuary-startup.service << EOF
[Unit]
Description=Ossuary Startup Command Manager
After=network-online.target wifi-connect.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/python3 $INSTALL_DIR/config-handler.py
ExecStart=$INSTALL_DIR/startup-manager.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Web configuration service
    cat > /etc/systemd/system/ossuary-web.service << EOF
[Unit]
Description=Ossuary Web Configuration Interface
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $INSTALL_DIR/scripts/config-server.py
Restart=always
RestartSec=10
User=root
WorkingDirectory=$INSTALL_DIR

# Allow binding to port 80
AmbientCapabilities=CAP_NET_BIND_SERVICE

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    success "Services updated"
}

# Main installation function
perform_installation() {
    local mode="$1"  # 0=fresh, 1=update, 2=repair
    local backup_file=""

    # Backup existing config if updating/repairing
    if [ "$mode" -gt 0 ]; then
        backup_file=$(backup_config)
    fi

    # Step 1: Install dependencies (only for fresh install)
    if [ "$mode" -eq 0 ]; then
        log "Installing dependencies..."
        echo "  Updating package lists..."
        apt-get update >> "$LOG_FILE" 2>&1
        echo "  Installing required packages..."
        # Note: network-manager is pre-installed in Pi OS Bookworm/Trixie
        # But we include it to be safe for older versions
        apt-get install -y curl wget jq network-manager python3 python3-pip >> "$LOG_FILE" 2>&1

        # Install Python packages if needed (for config server)
        if ! python3 -c "import json" 2>/dev/null; then
            apt-get install -y python3-json >> "$LOG_FILE" 2>&1
        fi

        # NetworkManager is default in Pi OS Bookworm (2023) and Trixie (2025)
        # But we'll ensure it's enabled
        if ! systemctl is-active --quiet NetworkManager; then
            log "Enabling NetworkManager..."
            systemctl enable NetworkManager >> "$LOG_FILE" 2>&1
            systemctl start NetworkManager >> "$LOG_FILE" 2>&1

            # Wait for NetworkManager to fully start
            sleep 2
        else
            success "NetworkManager is already running (default in Pi OS 2025)"
        fi

        # dhcpcd is deprecated in Bookworm/Trixie but may still be present
        if systemctl list-units --all | grep -q "dhcpcd.service"; then
            if systemctl is-active --quiet dhcpcd; then
                log "Disabling legacy dhcpcd service..."
                systemctl stop dhcpcd >> "$LOG_FILE" 2>&1
                systemctl disable dhcpcd >> "$LOG_FILE" 2>&1
            fi
        fi
    fi

    # Step 2: Install/repair WiFi Connect
    if [ "$mode" -eq 2 ]; then
        # Force reinstall in repair mode
        install_wifi_connect true
    else
        install_wifi_connect false
    fi

    # Step 3: Update components
    update_components

    # Step 4: Update services
    update_services

    # Step 5: Create default config or restore backup
    if [ -n "$backup_file" ]; then
        restore_config "$backup_file"
    elif [ ! -f "$CONFIG_DIR/config.json" ]; then
        log "Creating default configuration..."
        cat > "$CONFIG_DIR/config.json" << EOF
{
  "startup_command": "",
  "wifi_networks": []
}
EOF
    fi

    # Step 6: Enable and restart services
    log "Enabling and restarting services..."
    systemctl enable wifi-connect.service >> "$LOG_FILE" 2>&1
    systemctl enable ossuary-startup.service >> "$LOG_FILE" 2>&1
    systemctl enable ossuary-web.service >> "$LOG_FILE" 2>&1

    # Restart services
    systemctl restart wifi-connect || warning "WiFi Connect service failed to start"
    systemctl restart ossuary-web || warning "Web service failed to start"

    # Step 7: Copy uninstall and fix scripts
    cp "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/uninstall.sh" 2>/dev/null || true

    if [ -f "$REPO_DIR/fix-wifi-connect.sh" ]; then
        cp "$REPO_DIR/fix-wifi-connect.sh" "$INSTALL_DIR/" 2>/dev/null || true
        chmod +x "$INSTALL_DIR/fix-wifi-connect.sh" 2>/dev/null || true
    fi

    # Step 8: Verify installation
    log "Verifying installation..."
    local issues=0

    if ! command -v wifi-connect &> /dev/null; then
        warning "WiFi Connect binary not found"
        issues=$((issues + 1))
    fi

    if ! systemctl is-active --quiet wifi-connect; then
        warning "WiFi Connect service is not running"
        issues=$((issues + 1))
    fi

    if ! systemctl is-active --quiet ossuary-web; then
        warning "Web configuration service is not running"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        success "All components verified successfully!"
    else
        warning "$issues component(s) may need attention"
    fi

    return $issues
}

# SSH safety wrapper (simplified for updates)
run_ssh_safe() {
    echo ""
    echo -e "${YELLOW}Installation will continue in background.${NC}"
    echo "You can monitor progress with: tail -f $LOG_FILE"
    echo ""

    nohup bash -c "
        $(declare -f log error warning success backup_config restore_config install_wifi_connect update_components update_services perform_installation)
        REPO_DIR='$REPO_DIR'
        INSTALL_DIR='$INSTALL_DIR'
        CONFIG_DIR='$CONFIG_DIR'
        CUSTOM_UI_DIR='$CUSTOM_UI_DIR'
        LOG_FILE='$LOG_FILE'
        perform_installation $1
        echo 'Installation complete. System will reboot in 10 seconds...'
        sleep 10
        reboot
    " > /tmp/ossuary-install-output.log 2>&1 &

    local pid=$!
    echo "Installation running in background (PID: $pid)"

    # Monitor for a bit
    local count=0
    while [ $count -lt 10 ] && kill -0 $pid 2>/dev/null; do
        echo -n "."
        sleep 1
        count=$((count + 1))
    done

    echo ""

    if kill -0 $pid 2>/dev/null; then
        echo "Installation is running..."
        echo "Your system will reboot automatically when complete."
    else
        echo "Installation may have completed quickly. Check logs for details."
    fi
}

# Main execution
main() {
    clear
    echo "==========================================="
    echo "    ___                                  "
    echo "   / _ \\__ ____ ___ _____ _____ _____  "
    echo "  | | | / _/ __|| | | / _  |  __| | | | "
    echo "  | |_| \\__ \\__ \\ |_| | (_| | |  | |_| |"
    echo "   \\___/__/____/\\__,_|\\__,_|_|   \\__, |"
    echo "                                    __/ |"
    echo "       Raspberry Pi Edition        |___/ "
    echo "==========================================="
    echo "    WiFi Failover & Configuration System"
    echo "==========================================="
    echo ""

    # Initialize log
    echo "Installation/Update started at $(date)" > "$LOG_FILE"

    # Check root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi

    # Check Pi OS version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Detected OS: $PRETTY_NAME"

        # Check if it's Raspberry Pi OS
        if [[ "$ID" == "raspbian" ]] || [[ "$ID" == "debian" ]]; then
            # Check Debian version
            if [[ "$VERSION_ID" -ge "12" ]]; then
                success "Running on Debian $VERSION_ID (Bookworm or newer) - fully compatible"
            elif [[ "$VERSION_ID" == "11" ]]; then
                warning "Debian 11 (Bullseye) detected - should work but consider upgrading"
            else
                warning "Older Debian version detected - may have compatibility issues"
            fi
        fi
    fi

    # Check WiFi interface (non-fatal for updates)
    WIFI_INTERFACE=$(ip link | grep -E '^[0-9]+: wl' | cut -d: -f2 | tr -d ' ' | head -n1)
    if [ -z "$WIFI_INTERFACE" ]; then
        # Try alternative detection method
        WIFI_INTERFACE=$(iw dev | awk '/Interface/ {print $2}' | head -n1)
    fi

    if [ -z "$WIFI_INTERFACE" ]; then
        # Try one more method
        WIFI_INTERFACE=$(ls /sys/class/net | grep -E '^wl' | head -n1)
    fi

    if [ -n "$WIFI_INTERFACE" ]; then
        log "WiFi interface detected: $WIFI_INTERFACE"
    else
        warning "Could not detect WiFi interface name"
        # Don't exit - WiFi Connect will find it
    fi

    # Check existing installation
    check_existing_installation
    local mode=$?

    # Handle based on mode
    case $mode in
        0)  # Fresh install
            echo "No existing installation found."
            echo "This will install Ossuary Pi with WiFi failover."
            ;;
        1)  # Update
            echo ""
            echo "This will update your existing installation:"
            echo "  • Update WiFi Connect binary"
            echo "  • Refresh custom UI"
            echo "  • Update all scripts"
            echo "  • Preserve your configuration"
            ;;
        2)  # Repair
            echo ""
            echo "Detected broken components. This will:"
            echo "  • Reinstall WiFi Connect binary"
            echo "  • Fix broken services"
            echo "  • Preserve your configuration"
            ;;
    esac

    # Check for SSH session
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        if [ $mode -eq 0 ]; then
            # Fresh install - full SSH warning
            echo ""
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}         SSH SESSION DETECTED - IMPORTANT        ${NC}"
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "This installation will:"
            echo "  1. Disable dhcpcd and enable NetworkManager"
            echo "  2. Install WiFi Connect and dependencies"
            echo "  3. Configure services"
            echo -e "  4. ${YELLOW}REBOOT YOUR SYSTEM AUTOMATICALLY${NC}"
            echo ""
            echo -e "${YELLOW}Your SSH connection WILL be disconnected.${NC}"
            echo ""
            echo "The installation will continue even if SSH disconnects."
            echo "The system will automatically reboot when complete."
            echo ""
            echo -e "${BLUE}After reboot:${NC}"
            echo "  • Look for 'Ossuary-Setup' WiFi network if no WiFi found"
            echo "  • Or SSH back in using the same IP address"
            echo "  • Access config at http://$(hostname)"
        else
            # Update/repair - lighter warning
            echo ""
            echo -e "${YELLOW}SSH session detected!${NC}"
            echo "Update/repair can be done without losing connection."
            echo "No reboot required unless you choose to."
        fi
    else
        # Local installation - show what will happen
        if [ $mode -eq 0 ]; then
            echo ""
            echo "This will:"
            echo "  • Install required packages"
            echo "  • Configure NetworkManager"
            echo "  • Install WiFi Connect"
            echo "  • Set up web configuration interface"
            echo "  • Create systemd services"
            echo ""
            echo "You'll need to reboot after installation."
        fi
    fi

    echo ""
    echo -n "Do you want to continue? (yes/no): "
    read -r response

    if [ "$response" != "yes" ]; then
        echo "Installation cancelled."
        exit 0
    fi

    echo ""

    # Run installation based on context
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        if [ $mode -eq 0 ]; then
            # Fresh install over SSH - use background wrapper
            run_ssh_safe $mode
        else
            # Update/repair over SSH - run directly (no reboot)
            perform_installation $mode
            if [ $? -eq 0 ]; then
                echo ""
                echo "==========================================="
                echo -e "${GREEN}    Installation Complete!${NC}"
                echo "==========================================="
                echo ""
                if [ $mode -eq 1 ]; then
                    echo "Your installation has been updated successfully."
                else
                    echo "Repair completed successfully."
                fi
                echo ""
                echo "Services are running. No reboot required."
                echo "Access configuration at: http://$(hostname)"
            fi
        fi
    else
        # Local installation - run directly
        perform_installation $mode
        if [ $? -eq 0 ]; then
            echo ""
            echo "==========================================="
            echo -e "${GREEN}    Installation Complete!${NC}"
            echo "==========================================="
            echo ""

            if [ $mode -eq 0 ]; then
                echo "Please reboot your system to complete setup:"
                echo "  sudo reboot"
            else
                echo "Update/repair complete. Services have been restarted."
            fi

            echo ""
            echo "After reboot:"
            echo "  • If no WiFi: Look for 'Ossuary-Setup' network"
            echo "  • If connected: Access config at http://$(hostname)"
            echo ""
            echo -e "${BLUE}Thank you for using Ossuary Pi!${NC}"
        fi
    fi
}

# Run main function
main "$@"