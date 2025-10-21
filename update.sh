#!/bin/bash
# Ossuary Pi Update Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
REPO_URL="https://github.com/ossuary-dev/ossuary-pi.git"
BACKUP_DIR="/var/backups/ossuary"

print_step() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

backup_config() {
    print_step "Backing up current configuration..."

    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/config-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    if [[ -d "$CONFIG_DIR" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")"
        print_success "Configuration backed up to $backup_file"
    fi
}

stop_services() {
    print_step "Stopping Ossuary services..."

    local services=("ossuary-kiosk" "ossuary-portal" "ossuary-api" "ossuary-netd" "ossuary-config")

    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            systemctl stop "$service"
            echo "Stopped $service"
        fi
    done
}

start_services() {
    print_step "Starting Ossuary services..."

    local services=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-kiosk")

    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            systemctl start "$service"
            echo "Started $service"
        fi
    done
}

update_code() {
    print_step "Updating Ossuary Pi code..."

    # Create temporary directory
    local temp_dir="/tmp/ossuary-pi-update"
    rm -rf "$temp_dir"

    # Clone latest version
    if git clone "$REPO_URL" "$temp_dir"; then
        print_success "Downloaded latest version"
    else
        print_error "Failed to download updates"
        exit 1
    fi

    # Update source files
    if [[ -d "$temp_dir/src" ]]; then
        cp -r "$temp_dir/src/"* "$INSTALL_DIR/src/"
        print_success "Updated source files"
    fi

    # Update web files
    if [[ -d "$temp_dir/web" ]]; then
        cp -r "$temp_dir/web/"* "$INSTALL_DIR/web/"
        print_success "Updated web files"
    fi

    # Update systemd files
    if [[ -d "$temp_dir/systemd" ]]; then
        cp -r "$temp_dir/systemd/"* "/etc/systemd/system/"
        systemctl daemon-reload
        print_success "Updated systemd services"
    fi

    # Update scripts
    if [[ -d "$temp_dir/scripts/bin" ]]; then
        cp -r "$temp_dir/scripts/bin/"* "$INSTALL_DIR/bin/"
        chmod +x "$INSTALL_DIR/bin/"*
    fi

    if [[ -f "$temp_dir/scripts/ossuaryctl" ]]; then
        cp "$temp_dir/scripts/ossuaryctl" "/usr/local/bin/"
        chmod +x "/usr/local/bin/ossuaryctl"
    fi

    if [[ -f "$temp_dir/scripts/monitor.sh" ]]; then
        cp "$temp_dir/scripts/monitor.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/monitor.sh"
    fi

    # Update Python dependencies
    print_step "Updating Python dependencies..."
    if [[ -f "$temp_dir/requirements.txt" ]]; then
        cp "$temp_dir/requirements.txt" "$INSTALL_DIR/"
        "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" --upgrade
        print_success "Updated Python dependencies"
    fi

    # Cleanup
    rm -rf "$temp_dir"
}

main() {
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║         Ossuary Pi Updater            ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    backup_config
    stop_services
    update_code
    start_services

    print_success "Update completed successfully!"
    echo ""
    echo "Check service status with: sudo ossuaryctl status"
}

main "$@"