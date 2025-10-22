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
if [[ -d "/home/lc/Documents/ossuary-pi" ]]; then
    print_step "Updating all Ossuary files..."

    # Update systemd service files
    if [[ -d "/home/lc/Documents/ossuary-pi/systemd" ]]; then
        cp /home/lc/Documents/ossuary-pi/systemd/*.service /etc/systemd/system/
        systemctl daemon-reload
        print_success "Systemd services updated"
    fi

    # Update source code (this fixes the Pydantic and import issues)
    if [[ -d "/home/lc/Documents/ossuary-pi/src" ]]; then
        cp -r /home/lc/Documents/ossuary-pi/src/* /opt/ossuary/src/
        print_success "Source code updated (fixes Pydantic regex and import issues)"
    fi

    # Update scripts
    if [[ -d "/home/lc/Documents/ossuary-pi/scripts" ]]; then
        if [[ -d "/home/lc/Documents/ossuary-pi/scripts/bin" ]]; then
            cp -r /home/lc/Documents/ossuary-pi/scripts/bin/* /opt/ossuary/bin/
            chmod +x /opt/ossuary/bin/*
        fi
        if [[ -f "/home/lc/Documents/ossuary-pi/scripts/ossuaryctl" ]]; then
            cp /home/lc/Documents/ossuary-pi/scripts/ossuaryctl /usr/local/bin/
            chmod +x /usr/local/bin/ossuaryctl
        fi
        print_success "Scripts updated"
    fi
else
    print_warning "Local ossuary-pi directory not found at /home/lc/Documents/ossuary-pi"
    print_step "You may need to git pull the latest changes first"
fi

# 2. Install missing packages
print_step "Installing missing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xinit xserver-xorg-legacy gir1.2-nm-1.0
print_success "X11 packages installed"

# 3. Set up X11 auto-start
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