#!/bin/bash
# Ossuary Pi Installation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation configuration
OSSUARY_USER="ossuary"
OSSUARY_HOME="/home/${OSSUARY_USER}"
INSTALL_DIR="/opt/ossuary"
CONFIG_DIR="/etc/ossuary"
DATA_DIR="/var/lib/ossuary"
LOG_DIR="/var/log/ossuary"
BIN_DIR="/usr/local/bin"

# Version and repository
OSSUARY_VERSION="1.0.0"
REPO_URL="https://github.com/ossuary-dev/ossuary-pi.git"

# System requirements
MIN_PYTHON_VERSION="3.9"
REQUIRED_PACKAGES=(
    "python3"
    "python3-pip"
    "python3-venv"
    "git"
    "curl"
    "wget"
    "network-manager"
    "chromium"
    "xserver-xorg"
    "openbox"
    "unclutter"
    "sqlite3"
    "hostapd"
    "dnsmasq"
    "python3-gi"
    "python3-gi-cairo"
    "libcairo2-dev"
    "libgirepository1.0-dev"
    "gir1.2-nm-1.0"
    "xinit"
    "xserver-xorg-legacy"
    "x11-utils"
    "x11-xserver-utils"
)

print_banner() {
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║                   Ossuary Pi Installer                    ║"
    echo "  ║                                                           ║"
    echo "  ║         Robust Kiosk & Captive Portal System             ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}Version: ${OSSUARY_VERSION}${NC}"
    echo ""
}

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

check_os() {
    print_step "Checking operating system compatibility..."

    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine operating system"
        exit 1
    fi

    source /etc/os-release

    # Check for Raspberry Pi OS or Debian-based systems
    if [[ "$ID" != "raspbian" && "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
        print_warning "This installer is designed for Raspberry Pi OS or Debian-based systems"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    print_success "Operating system check passed"
}

detect_pi_model() {
    local model="Unknown"
    if [[ -f /proc/cpuinfo ]]; then
        local cpuinfo=$(cat /proc/cpuinfo)
        if grep -q "BCM2712" <<< "$cpuinfo"; then
            model="Pi5"
        elif grep -q "BCM2711" <<< "$cpuinfo"; then
            model="Pi4"
        elif grep -q "BCM2837" <<< "$cpuinfo"; then
            model="Pi3"
        elif grep -q "BCM2836" <<< "$cpuinfo"; then
            model="Pi2"
        elif grep -q "BCM2835" <<< "$cpuinfo"; then
            model="Pi1"
        fi
    fi
    echo "$model"
}

check_hardware() {
    print_step "Checking hardware compatibility..."

    # Check if running on Raspberry Pi
    if [[ -f /proc/cpuinfo ]] && grep -q "BCM\|Raspberry Pi" /proc/cpuinfo; then
        local pi_model=$(detect_pi_model)
        print_success "Raspberry Pi detected: $pi_model"

        # Special notes for different models
        case "$pi_model" in
            "Pi5")
                print_step "Pi 5 detected - will use optimized Wayland/X11 and Vulkan support"
                ;;
            "Pi4")
                print_step "Pi 4 detected - will use VideoCore VI acceleration"
                ;;
            "Pi3")
                print_step "Pi 3 detected - will use VideoCore IV acceleration"
                ;;
        esac
    else
        print_warning "Not running on Raspberry Pi hardware"
    fi

    # Check architecture (ARM required for Pi)
    local arch=$(uname -m)
    case $arch in
        armv6l|armv7l|aarch64|arm64)
            print_success "ARM architecture detected ($arch)"
            ;;
        x86_64|i386|i686)
            print_warning "x86 architecture detected ($arch) - this installer is designed for ARM"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
        *)
            print_warning "Unknown architecture: $arch"
            ;;
    esac

    # Check memory (minimum 1GB recommended)
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))

    if [[ $mem_mb -lt 1024 ]]; then
        print_warning "System has less than 1GB RAM ($mem_mb MB). Performance may be limited."
        if [[ $mem_mb -lt 512 ]]; then
            print_error "System has less than 512MB RAM. Installation may fail."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        print_success "Memory check passed ($mem_mb MB)"
    fi

    # Check for WiFi interface
    if ip link show | grep -q "wlan"; then
        print_success "WiFi interface detected"
    else
        print_warning "No WiFi interface found. WiFi functionality will be limited."
    fi

    # Check available disk space (require at least 1GB free)
    local available_kb=$(df / | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt 1024 ]]; then
        print_error "Insufficient disk space. Need at least 1GB free, found ${available_mb}MB"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Disk space check passed (${available_mb}MB available)"
    fi
}

check_python() {
    print_step "Checking Python version..."

    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        return 1
    fi

    local python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
    local required_version=$MIN_PYTHON_VERSION

    if ! python3 -c "import sys; exit(0 if sys.version_info >= tuple(map(int, '${required_version}'.split('.'))) else 1)"; then
        print_error "Python ${required_version} or newer is required (found ${python_version})"
        return 1
    fi

    print_success "Python version check passed (${python_version})"
}

update_system() {
    print_step "Updating system packages..."

    export DEBIAN_FRONTEND=noninteractive

    # Fix any broken packages first
    dpkg --configure -a || true

    # Update with retry logic
    local attempts=0
    local max_attempts=3
    while [[ $attempts -lt $max_attempts ]]; do
        if apt-get update; then
            break
        else
            ((attempts++))
            if [[ $attempts -lt $max_attempts ]]; then
                print_warning "Package update failed, retrying in 5 seconds..."
                sleep 5
            else
                print_error "Failed to update package lists after $max_attempts attempts"
                exit 1
            fi
        fi
    done

    if ! apt-get upgrade -y; then
        print_warning "Failed to upgrade some packages, continuing..."
    fi

    print_success "System updated successfully"
}

detect_chromium_package() {
    # First check what's already installed
    if dpkg -l chromium-browser 2>/dev/null | grep -q "^ii"; then
        echo "chromium-browser"
        return
    elif dpkg -l chromium 2>/dev/null | grep -q "^ii"; then
        echo "chromium"
        return
    elif dpkg -l firefox-esr 2>/dev/null | grep -q "^ii"; then
        echo "firefox-esr"
        return
    fi

    # Check what's available in repositories
    if apt-cache show chromium-browser >/dev/null 2>&1; then
        echo "chromium-browser"
    elif apt-cache show chromium >/dev/null 2>&1; then
        echo "chromium"
    elif apt-cache show firefox-esr >/dev/null 2>&1; then
        echo "firefox-esr"
    else
        echo "skip-browser"
    fi
}

install_packages() {
    print_step "Installing required packages..."

    export DEBIAN_FRONTEND=noninteractive

    # Check available disk space before installation
    local available_kb=$(df /var/cache/apt | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt 500 ]]; then
        print_warning "Low disk space detected (${available_mb}MB available)"
        print_step "Cleaning package cache to free space..."
        apt-get clean || true
        apt-get autoremove -y || true

        # Recheck after cleanup
        available_kb=$(df /var/cache/apt | awk 'NR==2 {print $4}')
        available_mb=$((available_kb / 1024))

        if [[ $available_mb -lt 200 ]]; then
            print_error "Insufficient disk space for package installation (${available_mb}MB)"
            print_error "Please free up disk space and try again"
            exit 1
        fi
    fi

    # Replace "chromium" in REQUIRED_PACKAGES with detected package
    print_step "Detecting correct Chromium package..."
    local chromium_package=$(detect_chromium_package)
    local packages=()
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if [[ "$package" == "chromium" ]]; then
            if [[ "$chromium_package" != "skip-browser" ]]; then
                packages+=("$chromium_package")
                if dpkg -l "$chromium_package" 2>/dev/null | grep -q "^ii"; then
                    print_success "$chromium_package already installed"
                else
                    print_success "Using $chromium_package package"
                fi
            else
                print_warning "No suitable browser package found - install manually later"
            fi
        else
            packages+=("$package")
        fi
    done

    # Install packages with retry logic
    for package in "${packages[@]}"; do
        echo -n "Installing $package... "

        # Check if package is already installed
        if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
            echo -e "${GREEN}ALREADY INSTALLED${NC}"
            continue
        fi

        local attempts=0
        local max_attempts=3
        local success=false

        while [[ $attempts -lt $max_attempts ]]; do
            if apt-get install -y "$package"; then
                echo -e "${GREEN}OK${NC}"
                success=true
                break
            else
                local exit_code=$?
                ((attempts++))
                if [[ $attempts -lt $max_attempts ]]; then
                    echo -n "retry $attempts... "
                    sleep 2
                else
                    echo -e "${RED}FAILED${NC}"
                    print_error "Failed to install $package after $max_attempts attempts (exit code: $exit_code)"
                    print_error "This may be due to:"
                    print_error "  - Package not available in repositories"
                    print_error "  - Network connectivity issues"
                    print_error "  - Dependency conflicts"
                    print_error "  - Insufficient disk space"
                    print_error ""
                    print_error "Try running manually: apt-get install -y $package"
                    exit 1
                fi
            fi
        done
    done

    # Python GI packages are now installed via apt, no additional pip packages needed
    print_success "System Python GI packages installed via apt"

    print_success "All packages installed successfully"
}

create_user() {
    print_step "Checking user configuration..."

    # Services now run as root, but we still create the ossuary user for reference
    if id "$OSSUARY_USER" &>/dev/null; then
        print_step "User $OSSUARY_USER already exists"
    else
        # Create user with home directory for compatibility
        if useradd -m -s /bin/bash "$OSSUARY_USER"; then
            print_success "Created user $OSSUARY_USER (for reference)"
        else
            print_warning "Failed to create user $OSSUARY_USER (continuing anyway)"
        fi
    fi

    # Add user to required groups (only if they exist)
    if id "$OSSUARY_USER" &>/dev/null; then
        local groups_to_add=()
        for group in video audio input netdev gpio; do
            if getent group "$group" &>/dev/null; then
                groups_to_add+=("$group")
            fi
        done

        if [[ ${#groups_to_add[@]} -gt 0 ]]; then
            local group_list=$(IFS=,; echo "${groups_to_add[*]}")
            usermod -a -G "$group_list" "$OSSUARY_USER" 2>/dev/null || true
        fi
    fi

    print_success "User configuration completed (services run as root)"
}

create_directories() {
    print_step "Creating directory structure..."

    # Create directories
    local dirs=(
        "$INSTALL_DIR"
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$LOG_DIR"
        "$INSTALL_DIR/bin"
        "$INSTALL_DIR/src"
        "$INSTALL_DIR/web"
        "$INSTALL_DIR/plugins"
        "$DATA_DIR/chromium"
        "$CONFIG_DIR/ssl"
        "$CONFIG_DIR/backups"
    )

    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir"; then
            echo "Created directory: $dir"
        else
            print_error "Failed to create directory: $dir"
            exit 1
        fi
    done

    # Set proper ownership and permissions (services now run as root)
    chown -R root:root "$INSTALL_DIR" || print_warning "Failed to set ownership for $INSTALL_DIR"
    chown -R root:root "$CONFIG_DIR" || print_warning "Failed to set ownership for $CONFIG_DIR"
    chown -R root:root "$DATA_DIR" || print_warning "Failed to set ownership for $DATA_DIR"
    chown -R root:root "$LOG_DIR" || print_warning "Failed to set ownership for $LOG_DIR"

    # Ensure browser data directory has proper permissions
    if [[ -d "$DATA_DIR/chromium" ]]; then
        chmod -R 755 "$DATA_DIR/chromium" || print_warning "Failed to set permissions for chromium data dir"
    fi

    chmod 755 "$INSTALL_DIR" || print_warning "Failed to set permissions for $INSTALL_DIR"
    chmod 755 "$CONFIG_DIR" || print_warning "Failed to set permissions for $CONFIG_DIR"
    chmod 755 "$DATA_DIR" || print_warning "Failed to set permissions for $DATA_DIR"
    chmod 755 "$LOG_DIR" || print_warning "Failed to set permissions for $LOG_DIR"

    print_success "Directory structure created"
}

install_ossuary() {
    print_step "Installing Ossuary Pi files..."

    # Determine source directory (current directory if running from git repo)
    local source_dir
    if [[ -f "$(dirname "$0")/src/config/__init__.py" ]]; then
        source_dir="$(cd "$(dirname "$0")" && pwd)"
        print_step "Installing from local source: $source_dir"

        # Validate required directories exist in local source
        local required_dirs=("src" "systemd")
        local missing_dirs=()
        for dir in "${required_dirs[@]}"; do
            if [[ ! -d "$source_dir/$dir" ]]; then
                missing_dirs+=("$dir")
            fi
        done

        if [[ ${#missing_dirs[@]} -gt 0 ]]; then
            print_error "Missing required directories in source: ${missing_dirs[*]}"
            print_error "Please ensure you're running from the correct ossuary-pi directory"
            exit 1
        fi
    else
        print_step "Cloning from repository..."
        cd /tmp

        # Clean up any existing clone
        if [[ -d "/tmp/ossuary-pi-install" ]]; then
            rm -rf "/tmp/ossuary-pi-install"
        fi

        # Clone with retry logic
        local attempts=0
        local max_attempts=3
        while [[ $attempts -lt $max_attempts ]]; do
            if git clone "$REPO_URL" ossuary-pi-install; then
                source_dir="/tmp/ossuary-pi-install"
                break
            else
                ((attempts++))
                if [[ $attempts -lt $max_attempts ]]; then
                    print_warning "Git clone failed, retrying in 5 seconds..."
                    sleep 5
                    rm -rf "/tmp/ossuary-pi-install" 2>/dev/null || true
                else
                    print_error "Failed to clone repository after $max_attempts attempts"
                    exit 1
                fi
            fi
        done
    fi

    # Copy source files with error checking
    print_step "Copying source files..."

    if [[ -d "$source_dir/src" ]] && [[ -n "$(ls -A "$source_dir/src" 2>/dev/null)" ]]; then
        cp -r "$source_dir/src/"* "$INSTALL_DIR/src/" || { print_error "Failed to copy src files"; exit 1; }
    elif [[ -d "$source_dir/src" ]]; then
        print_warning "Source src directory is empty, skipping"
    else
        print_error "Source src directory not found: $source_dir/src"
        exit 1
    fi

    if [[ -d "$source_dir/web" ]] && [[ -n "$(ls -A "$source_dir/web" 2>/dev/null)" ]]; then
        cp -r "$source_dir/web/"* "$INSTALL_DIR/web/" || { print_error "Failed to copy web files"; exit 1; }
    elif [[ -d "$source_dir/web" ]]; then
        print_warning "Source web directory is empty, skipping"
    else
        print_error "Source web directory not found: $source_dir/web"
        exit 1
    fi

    if [[ -d "$source_dir/config" ]] && [[ -n "$(ls -A "$source_dir/config" 2>/dev/null)" ]]; then
        cp -r "$source_dir/config/"* "$CONFIG_DIR/" || { print_error "Failed to copy config files"; exit 1; }
    elif [[ -d "$source_dir/config" ]]; then
        print_warning "Source config directory is empty, skipping"
    else
        print_warning "Source config directory not found: $source_dir/config"
    fi

    if [[ -d "$source_dir/systemd" ]] && [[ -n "$(ls -A "$source_dir/systemd" 2>/dev/null)" ]]; then
        cp -r "$source_dir/systemd/"* "/etc/systemd/system/" || { print_error "Failed to copy systemd files"; exit 1; }
    elif [[ -d "$source_dir/systemd" ]]; then
        print_warning "Source systemd directory is empty, skipping"
    else
        print_error "Source systemd directory not found: $source_dir/systemd"
        exit 1
    fi

    if [[ -d "$source_dir/scripts/bin" ]] && [[ -n "$(ls -A "$source_dir/scripts/bin" 2>/dev/null)" ]]; then
        cp -r "$source_dir/scripts/bin/"* "$INSTALL_DIR/bin/" || { print_error "Failed to copy bin files"; exit 1; }
    elif [[ -d "$source_dir/scripts/bin" ]]; then
        print_warning "Source scripts/bin directory is empty, skipping"
    else
        print_warning "Source scripts/bin directory not found: $source_dir/scripts/bin"
    fi

    if [[ -f "$source_dir/scripts/ossuaryctl" ]]; then
        mkdir -p "$BIN_DIR"
        cp "$source_dir/scripts/ossuaryctl" "$BIN_DIR/" || { print_error "Failed to copy ossuaryctl"; exit 1; }
    fi

    if [[ -f "$source_dir/scripts/monitor.sh" ]]; then
        cp "$source_dir/scripts/monitor.sh" "$INSTALL_DIR/" || { print_error "Failed to copy monitor.sh"; exit 1; }
    fi

    if [[ -f "$source_dir/requirements.txt" ]]; then
        cp "$source_dir/requirements.txt" "$INSTALL_DIR/" || { print_error "Failed to copy requirements.txt"; exit 1; }
    fi

    # Set proper permissions
    chmod +x "$INSTALL_DIR/bin/"*
    chmod +x "$BIN_DIR/ossuaryctl"
    chmod +x "$INSTALL_DIR/monitor.sh"

    # Install Python dependencies
    print_step "Installing Python dependencies..."
    cd "$INSTALL_DIR"

    # Use virtual environment for safe Python package management
    print_step "Creating Python virtual environment for safe package isolation..."

    local venv_path="/opt/ossuary/venv"
    if [[ ! -d "$venv_path" ]]; then
        if ! python3 -m venv --system-site-packages "$venv_path"; then
            print_error "Failed to create virtual environment"
            exit 1
        fi
    fi

    # Install packages in virtual environment
    print_step "Installing Python dependencies in virtual environment..."
    if ! "$venv_path/bin/pip" install -r requirements.txt; then
        print_error "Failed to install Python dependencies in virtual environment"
        exit 1
    fi

    # Update service scripts to use virtual environment
    for script in "$INSTALL_DIR/bin/"*; do
        if [[ -f "$script" ]] && head -1 "$script" | grep -q "python3"; then
            sed -i "1s|.*|#!$venv_path/bin/python|" "$script"
        fi
    done

    print_success "Python dependencies installed safely in virtual environment"

    print_success "Ossuary Pi files installed"
}

configure_network_manager() {
    print_step "Configuring NetworkManager..."

    # Check if we're on a desktop environment - skip NetworkManager config if so
    if systemctl is-active --quiet graphical.target && pgrep -f "lightdm|gdm|sddm|lxdm" > /dev/null; then
        print_warning "Desktop environment detected - skipping NetworkManager reconfiguration"
        print_step "Using existing NetworkManager configuration"
        return 0
    fi

    # Enable NetworkManager and disable conflicting services
    systemctl enable NetworkManager

    # Disable dhcpcd only if it exists
    if systemctl is-enabled dhcpcd &>/dev/null; then
        systemctl disable dhcpcd
        print_step "Disabled dhcpcd service"
    else
        print_step "dhcpcd service not present (normal on current Pi OS)"
    fi

    # Stop wpa_supplicant only if it's running
    if systemctl is-active wpa_supplicant &>/dev/null; then
        systemctl stop wpa_supplicant
        print_step "Stopped wpa_supplicant service"
    else
        print_step "wpa_supplicant not running"
    fi

    # Configure NetworkManager
    mkdir -p "/etc/NetworkManager"
    cat > "/etc/NetworkManager/NetworkManager.conf" << 'EOF'
[main]
plugins=ifupdown,keyfile
dhcp=internal

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=no
EOF

    # Allow ossuary user to manage network connections
    mkdir -p "/etc/polkit-1/localauthority/50-local.d"
    cat > "/etc/polkit-1/localauthority/50-local.d/ossuary-networkmanager.pkla" << 'EOF'
[Allow ossuary user to control NetworkManager]
Identity=unix-user:ossuary
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

    print_success "NetworkManager configured"
}

configure_display() {
    print_step "Configuring display system..."

    # Check if we're on a desktop environment
    if systemctl is-active --quiet graphical.target && pgrep -f "lightdm|gdm|sddm|lxdm" > /dev/null; then
        print_warning "Desktop environment detected - skipping autologin configuration"
        print_step "Ossuary will work with existing desktop session"
    else
        print_step "Configuring headless kiosk autologin"
        # Configure autologin for ossuary user
        mkdir -p "/etc/systemd/system/getty@tty1.service.d"

        if [[ -f "/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]]; then
            print_warning "Autologin configuration already exists, backing up"
            cp "/etc/systemd/system/getty@tty1.service.d/autologin.conf" "/etc/systemd/system/getty@tty1.service.d/autologin.conf.backup"
        fi

        cat > "/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $OSSUARY_USER --noclear %I \$TERM
EOF
    fi

    # Configure X11 for ossuary user (only for headless setups)
    if ! systemctl is-active --quiet graphical.target || ! pgrep -f "lightdm|gdm|sddm|lxdm" > /dev/null; then
        if [[ -d "$OSSUARY_HOME" ]] && [[ ! -f "$OSSUARY_HOME/.xinitrc" ]]; then
            print_step "Setting up X11 configuration for headless mode"
            cat > "$OSSUARY_HOME/.xinitrc" << 'EOF'
#!/bin/bash
# Disable screensaver and power management
xset s off
xset -dpms
xset s noblank

# Hide cursor
unclutter -idle 1 -root &

# Start window manager
exec openbox-session
EOF
            chown "$OSSUARY_USER:$OSSUARY_USER" "$OSSUARY_HOME/.xinitrc"
            chmod +x "$OSSUARY_HOME/.xinitrc"

            # Set up automatic X11 startup in .bashrc
            if [[ ! -f "$OSSUARY_HOME/.bashrc" ]] || ! grep -q "startx" "$OSSUARY_HOME/.bashrc"; then
                cat >> "$OSSUARY_HOME/.bashrc" << 'EOF'

# Auto-start X11 on login to tty1
if [[ -z $DISPLAY && $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
                chown "$OSSUARY_USER:$OSSUARY_USER" "$OSSUARY_HOME/.bashrc"
            fi
        fi
    else
        print_step "Desktop environment detected - skipping X11 auto-start configuration"
    fi

    # Set up X authority permissions
    if [[ -d "$OSSUARY_HOME" ]]; then
        if [[ ! -f "$OSSUARY_HOME/.Xauthority" ]]; then
            touch "$OSSUARY_HOME/.Xauthority"
            chown "$OSSUARY_USER:$OSSUARY_USER" "$OSSUARY_HOME/.Xauthority"
            chmod 600 "$OSSUARY_HOME/.Xauthority"
        fi

        # Handle X11 authorization for desktop environments
        if systemctl is-active --quiet graphical.target && pgrep -f "lightdm|gdm|sddm|lxdm" > /dev/null; then
            print_step "Configuring X11 authorization for desktop environment"

            # Find the primary user running the desktop session
            local desktop_user=$(who | grep -E '(:0|tty7)' | head -1 | awk '{print $1}')
            if [[ -z "$desktop_user" ]]; then
                desktop_user="pi"  # Default to pi user
            fi

            print_step "Desktop user detected: $desktop_user"

            # Grant ossuary user access to X session
            if command -v xhost >/dev/null 2>&1; then
                sudo -u "$desktop_user" DISPLAY=:0 xhost +SI:localuser:$OSSUARY_USER 2>/dev/null || true
                print_step "Added ossuary user to X11 access list"
            fi

            # Handle X11 vs Wayland authorization
            local desktop_home="/home/$desktop_user"
            local is_wayland=false

            # Detect if running Wayland
            if [[ -n "$WAYLAND_DISPLAY" ]] || pgrep -f "labwc|wayfire|weston|sway" > /dev/null; then
                is_wayland=true
                print_step "Wayland session detected"
            else
                print_step "X11 session detected"
            fi

            if [[ "$is_wayland" == "true" ]]; then
                # Wayland authorization setup
                print_step "Configuring Wayland authorization"

                # Add ossuary user to video and input groups for Wayland access
                usermod -a -G video,input "$OSSUARY_USER" 2>/dev/null || true

                # Set up Wayland environment variables for ossuary user
                local wayland_display=""
                if [[ -n "$WAYLAND_DISPLAY" ]]; then
                    wayland_display="$WAYLAND_DISPLAY"
                else
                    wayland_display="wayland-0"  # Default
                fi

                # Create Wayland runtime directory for ossuary user
                local ossuary_runtime="/run/user/$(id -u $OSSUARY_USER)"
                if [[ ! -d "$ossuary_runtime" ]]; then
                    mkdir -p "$ossuary_runtime"
                    chown "$OSSUARY_USER:$OSSUARY_USER" "$ossuary_runtime"
                    chmod 700 "$ossuary_runtime"
                fi

                # Copy Wayland socket permissions (if accessible)
                local wayland_socket="/run/user/$(id -u $desktop_user)/$wayland_display"
                if [[ -S "$wayland_socket" ]]; then
                    # Grant access to Wayland socket via group permissions
                    local wayland_group=$(stat -c '%G' "$wayland_socket" 2>/dev/null || echo "")
                    if [[ -n "$wayland_group" ]]; then
                        usermod -a -G "$wayland_group" "$OSSUARY_USER" 2>/dev/null || true
                        print_step "Added ossuary user to Wayland group: $wayland_group"
                    fi
                fi

                print_step "Wayland authorization configured"
            else
                # X11 authorization setup
                if [[ -f "$desktop_home/.Xauthority" ]]; then
                    sudo -u "$desktop_user" xauth extract - :0 2>/dev/null | sudo -u "$OSSUARY_USER" xauth merge - 2>/dev/null || true
                    print_step "Copied X11 authority from $desktop_user to ossuary user"
                fi
            fi

            # Update systemd services to use desktop user's display
            print_step "Updating systemd services for desktop environment"

            if [[ "$is_wayland" == "true" ]]; then
                # Update services for Wayland
                local wayland_display=""
                if [[ -n "$WAYLAND_DISPLAY" ]]; then
                    wayland_display="$WAYLAND_DISPLAY"
                else
                    wayland_display="wayland-0"
                fi

                # Update kiosk service for Wayland
                if [[ -f "/etc/systemd/system/ossuary-kiosk.service" ]]; then
                    cp "/etc/systemd/system/ossuary-kiosk.service" "/etc/systemd/system/ossuary-kiosk.service.backup"

                    # Add Wayland environment variables
                    if ! grep -q "WAYLAND_DISPLAY" "/etc/systemd/system/ossuary-kiosk.service"; then
                        sed -i "/Environment=DISPLAY=:0/a Environment=WAYLAND_DISPLAY=$wayland_display" "/etc/systemd/system/ossuary-kiosk.service"
                        sed -i "/Environment=WAYLAND_DISPLAY/a Environment=XDG_SESSION_TYPE=wayland" "/etc/systemd/system/ossuary-kiosk.service"
                        sed -i "/Environment=XDG_SESSION_TYPE/a Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $OSSUARY_USER)" "/etc/systemd/system/ossuary-kiosk.service"
                    fi
                    print_step "Updated kiosk service for Wayland"
                fi

                # Update API service for Wayland
                if [[ -f "/etc/systemd/system/ossuary-api.service" ]]; then
                    cp "/etc/systemd/system/ossuary-api.service" "/etc/systemd/system/ossuary-api.service.backup"

                    # Add Wayland environment variables
                    if ! grep -q "WAYLAND_DISPLAY" "/etc/systemd/system/ossuary-api.service"; then
                        sed -i "/Environment=DISPLAY=:0/a Environment=WAYLAND_DISPLAY=$wayland_display" "/etc/systemd/system/ossuary-api.service"
                        sed -i "/Environment=WAYLAND_DISPLAY/a Environment=XDG_SESSION_TYPE=wayland" "/etc/systemd/system/ossuary-api.service"
                        sed -i "/Environment=XDG_SESSION_TYPE/a Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $OSSUARY_USER)" "/etc/systemd/system/ossuary-api.service"
                    fi
                    print_step "Updated API service for Wayland"
                fi
            else
                # Update services for X11
                # Update kiosk service for desktop environment
                if [[ -f "/etc/systemd/system/ossuary-kiosk.service" ]]; then
                    # Backup original
                    cp "/etc/systemd/system/ossuary-kiosk.service" "/etc/systemd/system/ossuary-kiosk.service.backup"

                    # Update environment variables
                    sed -i "s|Environment=XAUTHORITY=/home/ossuary/.Xauthority|Environment=XAUTHORITY=$desktop_home/.Xauthority|g" "/etc/systemd/system/ossuary-kiosk.service"
                    print_step "Updated kiosk service X authority path"
                fi

                # Update API service for desktop environment
                if [[ -f "/etc/systemd/system/ossuary-api.service" ]]; then
                    # Backup original
                    cp "/etc/systemd/system/ossuary-api.service" "/etc/systemd/system/ossuary-api.service.backup"

                    # Update environment variables
                    sed -i "s|Environment=XAUTHORITY=/home/ossuary/.Xauthority|Environment=XAUTHORITY=$desktop_home/.Xauthority|g" "/etc/systemd/system/ossuary-api.service"
                    print_step "Updated API service X authority path"
                fi
            fi
        fi
    else
        print_warning "User home directory $OSSUARY_HOME does not exist"
    fi

    # Enable GPU memory split for Pi
    if [[ -f /boot/firmware/config.txt ]] || [[ -f /boot/config.txt ]]; then
        local config_file
        if [[ -f /boot/firmware/config.txt ]]; then
            config_file="/boot/firmware/config.txt"
        else
            config_file="/boot/config.txt"
        fi

        # Enable GPU memory split and V3D driver
        if ! grep -q "gpu_mem=" "$config_file"; then
            echo "gpu_mem=128" >> "$config_file"
        fi
        if ! grep -q "dtoverlay=vc4-kms-v3d" "$config_file"; then
            echo "dtoverlay=vc4-kms-v3d" >> "$config_file"
        fi
    fi

    print_success "Display system configured"
}

configure_services() {
    print_step "Configuring systemd services..."

    # Reload systemd to pick up new service files
    systemctl daemon-reload

    # Enable Ossuary services
    local services=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-kiosk")
    local failed_services=()

    for service in "${services[@]}"; do
        if [[ -f "/etc/systemd/system/${service}.service" ]]; then
            if systemctl enable "$service"; then
                echo "Enabled $service"
                # Start the service immediately (except kiosk which needs X11)
                if [[ "$service" != "ossuary-kiosk" ]]; then
                    if systemctl start "$service"; then
                        echo "Started $service"
                    else
                        print_warning "Failed to start $service (will start on reboot)"
                    fi
                fi
            else
                print_warning "Failed to enable $service"
                failed_services+=("$service")
            fi
        else
            print_warning "Service file for $service not found"
            failed_services+=("$service")
        fi
    done

    if [[ ${#failed_services[@]} -gt 0 ]]; then
        print_warning "Some services failed to enable: ${failed_services[*]}"
    fi

    # Set up monitoring cron job
    print_step "Setting up monitoring cron job..."
    if crontab -l 2>/dev/null | grep -q "monitor.sh"; then
        print_warning "Monitor cron job already exists"
    else
        (crontab -l 2>/dev/null || true; echo "*/5 * * * * $INSTALL_DIR/monitor.sh") | crontab - || print_warning "Failed to set up cron job"
    fi

    print_success "Services configured"
}

configure_firewall() {
    print_step "Configuring firewall rules..."

    # Install and configure ufw if not present
    if ! command -v ufw &> /dev/null; then
        if ! apt-get install -y ufw; then
            print_warning "Failed to install ufw, skipping firewall configuration"
            return 0
        fi
    fi

    # Check if ufw is already active
    if ufw status | grep -q "Status: active"; then
        print_warning "UFW is already active, backing up current rules"
        ufw status numbered > "/tmp/ufw-backup-$(date +%Y%m%d-%H%M%S).txt" || true
    fi

    # Basic firewall rules
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (be careful not to lock ourselves out)
    ufw allow ssh

    # Allow HTTP and HTTPS for captive portal
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Allow API access on local network
    ufw allow from 192.168.0.0/16 to any port 8080
    ufw allow from 10.0.0.0/8 to any port 8080
    ufw allow from 172.16.0.0/12 to any port 8080

    # Enable firewall with error handling
    if ! ufw --force enable; then
        print_warning "Failed to enable UFW firewall"
        return 0
    fi

    print_success "Firewall configured"
}

create_default_config() {
    print_step "Creating default configuration..."

    # Copy default configuration if it doesn't exist
    if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
        if [[ -f "$CONFIG_DIR/default.json" ]]; then
            cp "$CONFIG_DIR/default.json" "$CONFIG_DIR/config.json" || print_warning "Failed to copy default config"
        else
            print_warning "Default config file not found at $CONFIG_DIR/default.json"
        fi
    fi

    # Set proper ownership
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
        chown root:root "$CONFIG_DIR/config.json" || print_warning "Failed to set config ownership"
        chmod 644 "$CONFIG_DIR/config.json" || print_warning "Failed to set config permissions"
    fi

    print_success "Default configuration created"
}

cleanup_previous_install() {
    print_step "Checking for previous installation remnants..."

    # Stop any running services quietly
    local services=("ossuary-kiosk" "ossuary-portal" "ossuary-api" "ossuary-netd" "ossuary-config")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            print_step "Stopping existing $service service..."
            systemctl stop "$service" || true
        fi
    done

    # Fix any broken package installations
    print_step "Fixing any broken package installations..."
    dpkg --configure -a || true
    apt-get install -f || true

    # Clear package cache to avoid conflicts
    apt-get clean || true

    print_success "Previous installation cleanup completed"
}

cleanup() {
    print_step "Cleaning up..."

    # Clean up temporary files
    if [[ -d "/tmp/ossuary-pi-install" ]]; then
        rm -rf "/tmp/ossuary-pi-install"
    fi

    # Clean package cache
    apt-get autoremove -y
    apt-get autoclean

    print_success "Cleanup completed"
}

print_completion() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║             Ossuary Pi Installation Complete!            ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "  • Services installed, configured, and started"
    echo "  • User '$OSSUARY_USER' created with proper permissions"
    echo "  • NetworkManager configured for WiFi management"
    echo "  • Display system configured for kiosk mode"
    echo "  • Firewall rules applied"
    echo ""
    echo -e "${CYAN}Service Status:${NC}"
    for service in ossuary-config ossuary-netd ossuary-api ossuary-portal; do
        if systemctl is-active "$service" &>/dev/null; then
            echo "  • $service: ${GREEN}running${NC}"
        else
            echo "  • $service: ${YELLOW}stopped (will start on reboot)${NC}"
        fi
    done
    echo "  • ossuary-kiosk: ${YELLOW}will start after reboot with X11${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Reboot the system: ${BLUE}sudo reboot${NC}"
    echo "  2. After reboot, connect to the 'ossuary-setup' WiFi network"
    echo "  3. Configure your WiFi and display URL via the captive portal"
    echo ""
    echo -e "${CYAN}Management Commands:${NC}"
    echo "  • Control services: ${BLUE}sudo ossuaryctl {start|stop|restart|status}${NC}"
    echo "  • View logs: ${BLUE}sudo ossuaryctl logs${NC}"
    echo "  • Monitor services: ${BLUE}sudo ossuaryctl status${NC}"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  • Config file: ${BLUE}$CONFIG_DIR/config.json${NC}"
    echo "  • Logs: ${BLUE}$LOG_DIR/${NC}"
    echo "  • Web interface: ${BLUE}http://ossuary.local${NC} (after setup)"
    echo ""
    echo -e "${GREEN}A reboot is required to complete the installation.${NC}"
    echo ""
}

ask_reboot() {
    echo -e "${YELLOW}Reboot now to complete installation? (recommended)${NC}"
    read -p "Reboot now? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Please reboot manually when convenient: sudo reboot${NC}"
    else
        echo "Rebooting in 5 seconds..."
        sleep 5
        reboot
    fi
}

# Main installation function
main() {
    print_banner

    echo -e "${CYAN}This installer will:${NC}"
    echo "  • Install all required packages and dependencies"
    echo "  • Create the ossuary user and configure permissions"
    echo "  • Set up NetworkManager for WiFi management"
    echo "  • Configure the display system for kiosk mode"
    echo "  • Install and enable all Ossuary Pi services"
    echo "  • Configure basic security settings"
    echo ""

    read -p "Continue with installation? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    echo ""
    print_step "Starting Ossuary Pi installation..."

    # Pre-installation checks
    check_root
    check_os
    check_hardware

    # Check internet connectivity
    print_step "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &>/dev/null && ! ping -c 1 github.com &>/dev/null; then
        print_error "No internet connection detected. Installation requires internet access."
        exit 1
    fi
    print_success "Internet connectivity confirmed"

    # Clean up any previous installation remnants
    cleanup_previous_install

    # System preparation
    update_system
    check_python
    install_packages

    # User and directory setup
    create_user
    create_directories

    # Install Ossuary Pi
    install_ossuary

    # System configuration
    configure_network_manager
    configure_display
    configure_services
    configure_firewall
    create_default_config

    # Cleanup and completion
    cleanup
    print_completion
    ask_reboot
}

# Cleanup function for failed installations
cleanup_on_error() {
    print_error "Installation failed at line $LINENO"
    print_step "Cleaning up partial installation..."

    # Stop any services that might have been started
    for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-kiosk; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
    done

    # Remove temporary files
    rm -rf "/tmp/ossuary-pi-install" 2>/dev/null || true

    print_warning "Partial installation cleaned up. You can retry the installation."
    exit 1
}

# Error handling
trap cleanup_on_error ERR

# Run main installation
main "$@"
