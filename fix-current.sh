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

# 1. Copy updated systemd files if available locally
if [[ -d "/home/lc/Documents/ossuary-pi/systemd" ]]; then
    print_step "Updating systemd service files..."
    cp /home/lc/Documents/ossuary-pi/systemd/*.service /etc/systemd/system/
    systemctl daemon-reload
    print_success "Systemd services updated"
fi

# 2. Install missing X11 packages
print_step "Installing missing X11 packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xinit xserver-xorg-legacy
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