#!/bin/bash
# Quick fix for current installation issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

print_step "Applying critical fixes to current installation..."

# 1. Copy ALL updated files if available locally
# Try common locations for the ossuary-pi source
local_dirs=(
    "$(pwd)"
    "/home/$(logname)/Documents/ossuary-pi"
    "/home/$(logname)/ossuary-pi"
    "$(dirname "$0")"
)

updated=false
for local_dir in "${local_dirs[@]}"; do
    if [[ -d "$local_dir/src" && -f "$local_dir/install.sh" ]]; then
        print_step "Updating all Ossuary files from $local_dir..."

        # Update systemd service files
        if [[ -d "$local_dir/systemd" ]]; then
            cp "$local_dir/systemd"/*.service /etc/systemd/system/
            systemctl daemon-reload
            print_success "Systemd services updated"
        fi

        # Update source code (this fixes the Pydantic and import issues)
        if [[ -d "$local_dir/src" ]]; then
            cp -r "$local_dir/src"/* /opt/ossuary/src/
            print_success "Source code updated (fixes Pydantic regex and import issues)"
        fi

        # Update scripts (this fixes the async call issues)
        if [[ -d "$local_dir/scripts" ]]; then
            if [[ -d "$local_dir/scripts/bin" ]]; then
                cp -r "$local_dir/scripts/bin"/* /opt/ossuary/bin/
                chmod +x /opt/ossuary/bin/*
                print_success "Service scripts updated (fixes async coroutine issues)"
            fi
            if [[ -f "$local_dir/scripts/ossuaryctl" ]]; then
                cp "$local_dir/scripts/ossuaryctl" /usr/local/bin/
                chmod +x /usr/local/bin/ossuaryctl
            fi
            print_success "Scripts updated"
        fi
        updated=true
        break
    fi
done

if [[ $updated == false ]]; then
    print_warning "Local ossuary-pi directory not found"
    print_step "You may need to cd to the ossuary-pi directory and run this script from there"
fi

# 2. Install missing packages
print_step "Installing missing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xinit xserver-xorg-legacy gir1.2-nm-1.0
print_success "X11 packages installed"

# 3. Set up X11 auto-start and permissions
print_step "Configuring automatic X11 startup..."
if [[ -d "/home/ossuary" ]]; then
    if [[ ! -f "/home/ossuary/.bashrc" ]] || ! grep -q "startx" "/home/ossuary/.bashrc"; then
        cat >> "/home/ossuary/.bashrc" << 'EOF'

# Auto-start X11 on login to tty1
if [[ -z $DISPLAY && $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
        chown ossuary:ossuary "/home/ossuary/.bashrc"
        print_success "X11 auto-start configured"
    else
        print_success "X11 auto-start already configured"
    fi
fi

# Set up X11 access for ossuary user
print_step "Configuring X11 access for kiosk service..."
current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$(whoami)}")
if [[ -f "/home/$current_user/.Xauthority" ]]; then
    # Allow ossuary user to access X session
    usermod -a -G "$current_user" ossuary 2>/dev/null || true
    # Make Xauthority readable by user group
    chmod 640 "/home/$current_user/.Xauthority" 2>/dev/null || true
    chgrp "$current_user" "/home/$current_user/.Xauthority" 2>/dev/null || true
    print_success "X11 access configured for kiosk"
else
    print_warning "No X session found (/home/$current_user/.Xauthority missing)"
fi

# 4. Restart all services
print_step "Restarting Ossuary services..."
systemctl restart ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-kiosk

print_success "Critical fixes applied!"
echo ""
echo "Services should now start properly. Check with:"
echo "  sudo ossuaryctl status"
echo ""
echo "For future updates, use:"
echo "  sudo /opt/ossuary/update.sh"