#!/bin/bash
"""Ossuary Pi Uninstaller Script."""

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Installation paths
OSSUARY_USER="ossuary"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
DATA_DIR="/var/lib/ossuary"
LOG_DIR="/var/log/ossuary"
BIN_DIR="/usr/local/bin"

# Services to remove
SERVICES=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-kiosk")

print_banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║           Ossuary Pi                  ║"
    echo "  ║          Uninstaller                  ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

confirm_removal() {
    echo -e "${YELLOW}WARNING: This will completely remove Ossuary Pi from your system.${NC}"
    echo ""
    echo "The following will be removed:"
    echo "  • All Ossuary Pi services and files"
    echo "  • User account: $OSSUARY_USER"
    echo "  • Configuration files in $CONFIG_DIR"
    echo "  • Data files in $DATA_DIR"
    echo "  • Log files in $LOG_DIR"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""

    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ $REPLY != "yes" ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
}

stop_services() {
    echo -e "${BLUE}[INFO]${NC} Stopping Ossuary services..."

    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "Stopping $service..."
            systemctl stop "$service" || true
        fi
    done

    echo -e "${GREEN}[SUCCESS]${NC} Services stopped"
}

disable_services() {
    echo -e "${BLUE}[INFO]${NC} Disabling and removing services..."

    for service in "${SERVICES[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo "Disabling $service..."
            systemctl disable "$service" || true
        fi

        # Remove service file
        if [[ -f "/etc/systemd/system/${service}.service" ]]; then
            rm -f "/etc/systemd/system/${service}.service"
            echo "Removed ${service}.service"
        fi
    done

    # Reload systemd
    systemctl daemon-reload

    echo -e "${GREEN}[SUCCESS]${NC} Services removed"
}

remove_user() {
    echo -e "${BLUE}[INFO]${NC} Removing user account..."

    if id "$OSSUARY_USER" &>/dev/null; then
        # Kill any running processes
        pkill -u "$OSSUARY_USER" || true
        sleep 2

        # Remove user and home directory
        userdel -r "$OSSUARY_USER" 2>/dev/null || true

        # Remove sudo configuration
        rm -f "/etc/sudoers.d/ossuary"

        # Remove polkit configuration
        rm -f "/etc/polkit-1/localauthority/50-local.d/ossuary-networkmanager.pkla"

        echo -e "${GREEN}[SUCCESS]${NC} User $OSSUARY_USER removed"
    else
        echo -e "${YELLOW}[WARNING]${NC} User $OSSUARY_USER not found"
    fi
}

remove_files() {
    echo -e "${BLUE}[INFO]${NC} Removing installation files..."

    # Remove directories
    local dirs=("$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            echo "Removed directory: $dir"
        fi
    done

    # Remove binaries
    if [[ -f "$BIN_DIR/ossuaryctl" ]]; then
        rm -f "$BIN_DIR/ossuaryctl"
        echo "Removed: $BIN_DIR/ossuaryctl"
    fi

    echo -e "${GREEN}[SUCCESS]${NC} Installation files removed"
}

remove_cron_jobs() {
    echo -e "${BLUE}[INFO]${NC} Removing cron jobs..."

    # Remove monitoring cron job
    crontab -l 2>/dev/null | grep -v "ossuary" | crontab - || true

    echo -e "${GREEN}[SUCCESS]${NC} Cron jobs removed"
}

revert_system_changes() {
    echo -e "${BLUE}[INFO]${NC} Reverting system configuration changes..."

    # Revert autologin
    if [[ -d "/etc/systemd/system/getty@tty1.service.d" ]]; then
        rm -rf "/etc/systemd/system/getty@tty1.service.d"
        echo "Removed autologin configuration"
    fi

    # Note: We don't revert NetworkManager changes as they might be needed
    # for the system to continue functioning properly

    echo -e "${GREEN}[SUCCESS]${NC} System configuration reverted"
}

cleanup_packages() {
    echo -e "${BLUE}[INFO]${NC} Cleaning up packages..."

    # Note: We don't remove packages that might be used by other software
    # Users can manually remove packages if needed

    # Clean package cache
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true

    echo -e "${GREEN}[SUCCESS]${NC} Package cleanup completed"
}

print_completion() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║             Ossuary Pi Uninstallation Complete           ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Uninstallation Summary:${NC}"
    echo "  • All Ossuary Pi services removed"
    echo "  • User account '$OSSUARY_USER' deleted"
    echo "  • Configuration and data files removed"
    echo "  • System configuration reverted"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "  • Some system packages were left installed (they may be used by other software)"
    echo "  • NetworkManager configuration was left intact to maintain network connectivity"
    echo "  • You may want to reboot the system to complete the cleanup"
    echo ""
    echo -e "${GREEN}Ossuary Pi has been successfully removed from your system.${NC}"
    echo ""
}

main() {
    print_banner
    check_root
    confirm_removal

    echo ""
    echo -e "${BLUE}[INFO]${NC} Starting Ossuary Pi uninstallation..."

    stop_services
    disable_services
    remove_user
    remove_files
    remove_cron_jobs
    revert_system_changes
    cleanup_packages

    print_completion
}

# Error handling
trap 'echo -e "\n${RED}[ERROR]${NC} Uninstallation failed at line $LINENO"; exit 1' ERR

# Run main uninstallation
main "$@"