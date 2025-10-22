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
    "sqlite3"
    "hostapd"
    "dnsmasq"
    "python3-gi"
    "python3-gi-cairo"
    "libcairo2-dev"
    "libgirepository1.0-dev"
    "gir1.2-nm-1.0"
)

# Display stack packages (added separately based on OS detection)
DISPLAY_PACKAGES_X11=(
    "xserver-xorg"
    "xserver-xorg-core"
    "xserver-common"
    "xinit"
    "x11-utils"
    "x11-xserver-utils"
    "xserver-xorg-legacy"
    "xserver-xorg-video-fbdev"
    "openbox"
    "unclutter"
)

# Meta-packages for Pi OS Trixie (Debian 13) - official way to add display stack
DISPLAY_PACKAGES_PI_TRIXIE=(
    "rpd-x-core"
    "gldriver-test"
    "xcompmgr"
)

# Fallback meta-package for Pi OS Bookworm (Debian 12)
DISPLAY_PACKAGES_PI_BOOKWORM=(
    "rpd-x-core"
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
    # On Debian Trixie (13), use 'chromium' regardless of Pi model
    local debian_version=""
    if [[ -f /etc/os-release ]]; then
        debian_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    fi

    if [[ "$debian_version" == "13" ]]; then
        # Trixie uses 'chromium' package
        if apt-cache show chromium >/dev/null 2>&1; then
            echo "chromium"
            return
        fi
    fi

    # For other versions, check 64-bit Pi 5 first
    local pi_model=$(detect_pi_model)
    local arch=$(uname -m)

    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && [[ "$pi_model" == "Pi5" ]]; then
        # Pi 5 with 64-bit OS should use chromium
        if apt-cache show chromium >/dev/null 2>&1; then
            echo "chromium"
            return
        fi
    fi

    # Standard detection for other systems
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

detect_pi_os_variant() {
    print_step "Detecting Raspberry Pi OS variant and version..."

    # Detect Debian version
    local debian_version=""
    if [[ -f /etc/os-release ]]; then
        debian_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
        print_step "Detected Debian version: $debian_version"
    fi

    # Check if this is Pi OS Lite (no desktop packages)
    if ! dpkg -l | grep -q "raspberrypi-ui-mods"; then
        if [[ "$debian_version" == "13" ]]; then
            print_step "Pi OS Trixie Lite detected - will install Trixie display stack"
            export PI_OS_VARIANT="trixie_lite"
        else
            print_step "Pi OS Lite detected - will install standard display stack"
            export PI_OS_VARIANT="bookworm_lite"
        fi
        return 0  # Is Lite
    else
        print_step "Pi OS with desktop detected - using existing display stack"
        export PI_OS_VARIANT="desktop"
        return 1  # Has desktop
    fi
}

install_display_packages() {
    print_step "Installing display stack packages for $PI_OS_VARIANT..."

    # Choose package list based on OS variant
    local packages_to_install=()
    local use_meta_package=false

    case "$PI_OS_VARIANT" in
        "trixie_lite")
            print_step "Using Trixie meta-packages (Debian 13)"
            packages_to_install=("${DISPLAY_PACKAGES_PI_TRIXIE[@]}")
            use_meta_package=true
            ;;
        "bookworm_lite")
            print_step "Using Bookworm meta-packages (Debian 12)"
            packages_to_install=("${DISPLAY_PACKAGES_PI_BOOKWORM[@]}")
            use_meta_package=true
            ;;
        *)
            print_step "Using individual packages (fallback)"
            packages_to_install=("${DISPLAY_PACKAGES_X11[@]}")
            use_meta_package=false
            ;;
    esac

    if [ "$use_meta_package" = true ]; then
        # Install Pi-specific display packages
        print_step "Installing Pi OS meta-packages..."
        for package in "${packages_to_install[@]}"; do
            if apt-cache show "$package" >/dev/null 2>&1; then
                echo -n "Installing $package... "
                if apt-get install -y "$package"; then
                    echo -e "${GREEN}OK${NC}"
                else
                    echo -e "${YELLOW}FAILED - will try individual packages${NC}"
                    use_meta_package=false
                    break
                fi
            else
                echo -e "${YELLOW}$package not available - will try individual packages${NC}"
                use_meta_package=false
                break
            fi
        done
    fi

    # If meta-package failed or not available, install individual packages
    if [ "$use_meta_package" = false ]; then
        print_step "Installing individual display packages..."
        for package in "${DISPLAY_PACKAGES_X11[@]}"; do
            echo -n "Installing $package... "

            # Check if package is already installed
            if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                echo -e "${GREEN}ALREADY INSTALLED${NC}"
                continue
            fi

            # Check if package exists
            if ! apt-cache show "$package" >/dev/null 2>&1; then
                echo -e "${YELLOW}NOT AVAILABLE${NC}"
                continue
            fi

            local attempts=0
            local max_attempts=3
            local success=false

            while [[ $attempts -lt $max_attempts ]]; do
                if apt-get install -y --no-install-recommends "$package"; then
                    echo -e "${GREEN}OK${NC}"
                    success=true
                    break
                else
                    ((attempts++))
                    if [[ $attempts -lt $max_attempts ]]; then
                        echo -n "retry $attempts... "
                        sleep 2
                    else
                        echo -e "${RED}FAILED${NC}"
                        print_warning "Failed to install $package - continuing anyway"
                    fi
                fi
            done
        done
    fi

    print_success "Display stack installation completed"
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

    # Install display stack if needed (Pi OS Lite)
    if detect_pi_os_variant; then
        install_display_packages
    fi

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
        "/var/log/ossuary"
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

    # Force overwrite existing files to ensure updates are applied
    print_step "Copying source files (will overwrite existing)..."

    if [[ -d "$source_dir/src" ]] && [[ -n "$(ls -A "$source_dir/src" 2>/dev/null)" ]]; then
        cp -rf "$source_dir/src/"* "$INSTALL_DIR/src/" || { print_error "Failed to copy src files"; exit 1; }
        print_step "Updated source files"
    elif [[ -d "$source_dir/src" ]]; then
        print_warning "Source src directory is empty, skipping"
    else
        print_error "Source src directory not found: $source_dir/src"
        exit 1
    fi

    if [[ -d "$source_dir/web" ]] && [[ -n "$(ls -A "$source_dir/web" 2>/dev/null)" ]]; then
        cp -rf "$source_dir/web/"* "$INSTALL_DIR/web/" || { print_error "Failed to copy web files"; exit 1; }
        print_step "Updated web files"
    elif [[ -d "$source_dir/web" ]]; then
        print_warning "Source web directory is empty, skipping"
    else
        print_error "Source web directory not found: $source_dir/web"
        exit 1
    fi

    if [[ -d "$source_dir/config" ]] && [[ -n "$(ls -A "$source_dir/config" 2>/dev/null)" ]]; then
        # Only overwrite default config, preserve user config
        if [[ -f "$source_dir/config/default.json" ]]; then
            cp -f "$source_dir/config/default.json" "$CONFIG_DIR/" || { print_error "Failed to copy default config"; exit 1; }
            print_step "Updated default configuration"
        fi
        # Copy other config files
        for file in "$source_dir/config/"*; do
            filename=$(basename "$file")
            if [[ "$filename" != "default.json" && "$filename" != "config.json" ]]; then
                cp -f "$file" "$CONFIG_DIR/" 2>/dev/null || true
            fi
        done
    elif [[ -d "$source_dir/config" ]]; then
        print_warning "Source config directory is empty, skipping"
    else
        print_warning "Source config directory not found: $source_dir/config"
    fi

    if [[ -d "$source_dir/systemd" ]] && [[ -n "$(ls -A "$source_dir/systemd" 2>/dev/null)" ]]; then
        cp -rf "$source_dir/systemd/"* "/etc/systemd/system/" || { print_error "Failed to copy systemd files"; exit 1; }
        print_step "Updated systemd service files"
        # Reload systemd after updating service files
        systemctl daemon-reload
    elif [[ -d "$source_dir/systemd" ]]; then
        print_warning "Source systemd directory is empty, skipping"
    else
        print_error "Source systemd directory not found: $source_dir/systemd"
        exit 1
    fi

    if [[ -d "$source_dir/scripts/bin" ]] && [[ -n "$(ls -A "$source_dir/scripts/bin" 2>/dev/null)" ]]; then
        cp -rf "$source_dir/scripts/bin/"* "$INSTALL_DIR/bin/" || { print_error "Failed to copy bin files"; exit 1; }
        print_step "Updated binary files"
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
        print_warning "Desktop environment detected - skipping all autologin configuration"
        print_step "Ossuary services will run as root and integrate with existing desktop session"
        return 0
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

    # Set up X authority permissions for headless mode only
    if ! systemctl is-active --quiet graphical.target || ! pgrep -f "lightdm|gdm|sddm|lxdm" > /dev/null; then
        if [[ -d "$OSSUARY_HOME" ]]; then
            if [[ ! -f "$OSSUARY_HOME/.Xauthority" ]]; then
                touch "$OSSUARY_HOME/.Xauthority"
                chown "$OSSUARY_USER:$OSSUARY_USER" "$OSSUARY_HOME/.Xauthority"
                chmod 600 "$OSSUARY_HOME/.Xauthority"
            fi
        fi
    else
        # Desktop environment detected - configure root access to existing X session
        print_step "Configuring root access to desktop X session"

        # Find the primary user running the desktop session
        local desktop_user=$(who | grep -E '(:0|tty7)' | head -1 | awk '{print $1}')
        if [[ -z "$desktop_user" ]]; then
            desktop_user="pi"  # Default to pi user
        fi

        print_step "Desktop user detected: $desktop_user"
        local desktop_home="/home/$desktop_user"

        # Grant root access to X session (since services run as root)
        if command -v xhost >/dev/null 2>&1; then
            sudo -u "$desktop_user" DISPLAY=:0 xhost +SI:localuser:root 2>/dev/null || true
            print_step "Added root user to X11 access list"
        fi

        # Set up root X authority by copying from desktop user
        if [[ -f "$desktop_home/.Xauthority" ]]; then
            cp "$desktop_home/.Xauthority" "/root/.Xauthority" 2>/dev/null || true
            chmod 600 "/root/.Xauthority" 2>/dev/null || true
            print_step "Copied X authority to root"
        else
            # Create empty X authority for root
            touch "/root/.Xauthority"
            chmod 600 "/root/.Xauthority"
            print_step "Created X authority file for root"
        fi

        # Detect display system
        local is_wayland=false
        if [[ -n "$WAYLAND_DISPLAY" ]] || pgrep -f "labwc|wayfire|weston|sway" > /dev/null; then
            is_wayland=true
            print_step "Wayland session detected"
        else
            print_step "X11 session detected"
        fi

        if [[ "$is_wayland" == "true" ]]; then
            # Wayland authorization setup for root
            print_step "Configuring Wayland authorization for root"

            # Root should have access to all groups, but ensure video and input
            # groups are available for hardware access
            if getent group video >/dev/null 2>&1; then
                print_step "Video group available for hardware access"
            fi
            if getent group input >/dev/null 2>&1; then
                print_step "Input group available for hardware access"
            fi

            # Set up Wayland environment variables for root services
            local wayland_display=""
            if [[ -n "$WAYLAND_DISPLAY" ]]; then
                wayland_display="$WAYLAND_DISPLAY"
            else
                wayland_display="wayland-0"  # Default
            fi

            print_step "Wayland display: $wayland_display"
        else
            # X11 authorization setup for root (already handled above)
            print_step "X11 authorization for root configured"
        fi
    fi

    # Configure boot settings for display and kiosk mode
    if [[ -f /boot/firmware/config.txt ]] || [[ -f /boot/config.txt ]]; then
        local config_file
        if [[ -f /boot/firmware/config.txt ]]; then
            config_file="/boot/firmware/config.txt"
        else
            config_file="/boot/config.txt"
        fi

        print_step "Configuring $config_file for kiosk mode..."

        # Backup config file
        cp "$config_file" "$config_file.backup" 2>/dev/null || true

        # Pi model detection for specific settings
        local pi_model=$(detect_pi_model)
        local debian_version=$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "12")

        # Common settings for all Pi models
        local settings_to_add=()

        # HDMI settings for headless operation
        if ! grep -q "hdmi_force_hotplug=1" "$config_file"; then
            settings_to_add+=("hdmi_force_hotplug=1")
        fi
        if ! grep -q "hdmi_ignore_edid=0xa5000080" "$config_file"; then
            settings_to_add+=("hdmi_ignore_edid=0xa5000080")
        fi

        # Display driver settings based on Pi model and OS version
        if [[ "$pi_model" == "Pi5" ]]; then
            # Pi 5 specific settings for optimal hardware acceleration
            print_step "Applying Pi 5 hardware acceleration settings..."

            # Pi 5 uses different overlays for proper acceleration
            if ! grep -q "dtoverlay=vc4-kms-v3d-pi5" "$config_file"; then
                settings_to_add+=("dtoverlay=vc4-kms-v3d-pi5")
            fi

            # Video decode acceleration (H.264/HEVC support)
            if ! grep -q "dtoverlay=rpivid-v4l2" "$config_file"; then
                settings_to_add+=("dtoverlay=rpivid-v4l2")
            fi

            # Pi 5 framebuffer settings
            if ! grep -q "max_framebuffers=" "$config_file"; then
                settings_to_add+=("max_framebuffers=2")
            fi

            # Note: gpu_mem has no effect on Pi 5, but CMA is managed automatically
            # Pi 5 does not allocate GPU memory on behalf of the OS

            # Headless resolution for Pi 5 (via config.txt method)
            if ! grep -q "hdmi_group=" "$config_file"; then
                settings_to_add+=("hdmi_group=2")
                settings_to_add+=("hdmi_mode=82")  # 1920x1080 @ 60Hz
            fi

            # Alternative headless resolution method
            if ! grep -q "framebuffer_width=" "$config_file"; then
                settings_to_add+=("framebuffer_width=1920")
                settings_to_add+=("framebuffer_height=1080")
            fi

        elif [[ "$pi_model" == "Pi4" ]]; then
            # Pi 4 hardware acceleration settings
            print_step "Applying Pi 4 hardware acceleration settings..."

            # Pi 4 uses standard KMS overlay
            if ! grep -q "dtoverlay=vc4-kms-v3d" "$config_file"; then
                settings_to_add+=("dtoverlay=vc4-kms-v3d")
            fi

            # Pi 4 optimal GPU memory allocation
            # 128MB for 4GB+ models, 76MB for 1-2GB models
            if ! grep -q "gpu_mem=" "$config_file"; then
                # Check total memory to set appropriate gpu_mem
                local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                local total_mem_mb=$((total_mem_kb / 1024))

                if [[ $total_mem_mb -ge 4096 ]]; then
                    settings_to_add+=("gpu_mem=128")  # 4GB+ models
                elif [[ $total_mem_mb -ge 1024 ]]; then
                    settings_to_add+=("gpu_mem=76")   # 1-2GB models
                else
                    settings_to_add+=("gpu_mem=64")   # <1GB models
                fi
            fi

            # Pi 4 framebuffer optimization
            if ! grep -q "max_framebuffers=" "$config_file"; then
                settings_to_add+=("max_framebuffers=2")
            fi

        else
            # Pi 3 and older - conservative settings
            print_step "Applying Pi 3/older display settings..."

            if ! grep -q "dtoverlay=vc4-kms-v3d" "$config_file"; then
                settings_to_add+=("dtoverlay=vc4-kms-v3d")
            fi
            if ! grep -q "gpu_mem=" "$config_file"; then
                settings_to_add+=("gpu_mem=64")  # Conservative for older models
            fi
        fi

        # Common performance optimizations for all models
        if ! grep -q "arm_64bit=1" "$config_file" && [[ $(uname -m) == "aarch64" ]]; then
            settings_to_add+=("arm_64bit=1")
        fi

        # Disable rainbow splash
        if ! grep -q "disable_splash=1" "$config_file"; then
            settings_to_add+=("disable_splash=1")
        fi

        # Disable overscan (important for kiosk displays)
        if ! grep -q "disable_overscan=1" "$config_file"; then
            settings_to_add+=("disable_overscan=1")
        fi

        # Add all settings
        if [[ ${#settings_to_add[@]} -gt 0 ]]; then
            echo "" >> "$config_file"
            echo "# Ossuary Pi kiosk mode settings" >> "$config_file"
            for setting in "${settings_to_add[@]}"; do
                echo "$setting" >> "$config_file"
                print_step "Added: $setting"
            done
        fi

        # Configure cmdline.txt for headless resolution (Pi 5 with Trixie)
        if [[ "$pi_model" == "Pi5" && "$debian_version" == "13" ]]; then
            local cmdline_file
            if [[ -f /boot/firmware/cmdline.txt ]]; then
                cmdline_file="/boot/firmware/cmdline.txt"
            elif [[ -f /boot/cmdline.txt ]]; then
                cmdline_file="/boot/cmdline.txt"
            fi

            if [[ -n "$cmdline_file" && -f "$cmdline_file" ]]; then
                print_step "Configuring $cmdline_file for headless resolution..."

                # Backup cmdline file
                cp "$cmdline_file" "$cmdline_file.backup" 2>/dev/null || true

                # Add video resolution if not present
                if ! grep -q "video=HDMI-A-1:" "$cmdline_file"; then
                    # Add to beginning of line
                    sed -i '1s/^/video=HDMI-A-1:1920x1080@60D /' "$cmdline_file"
                    print_step "Added headless resolution to cmdline.txt"
                fi
            fi
        fi
    fi

    print_success "Display system configured"
}

configure_services() {
    print_step "Configuring systemd services..."

    # Reload systemd to pick up new service files
    systemctl daemon-reload

    # Verify critical display service setup
    if ! check_display_service_setup; then
        print_error "Display service setup failed - this will cause kiosk service to fail"
        exit 1
    fi

    # Enable Ossuary services
    local services=("ossuary-config" "ossuary-netd" "ossuary-api" "ossuary-portal" "ossuary-display" "ossuary-kiosk")
    local failed_services=()

    for service in "${services[@]}"; do
        if [[ -f "/etc/systemd/system/${service}.service" ]]; then
            print_step "Configuring $service..."

            if systemctl enable "$service"; then
                echo "✓ Enabled $service"

                # Start the service immediately (except kiosk which needs display service first)
                if [[ "$service" != "ossuary-kiosk" ]]; then
                    if systemctl start "$service"; then
                        echo "✓ Started $service"

                        # Special handling for display service
                        if [[ "$service" == "ossuary-display" ]]; then
                            sleep 3  # Give display service time to start X server
                            if systemctl is-active "$service" &>/dev/null; then
                                echo "✓ Display service is running"
                            else
                                print_error "Display service failed to start!"
                                journalctl -u ossuary-display -n 10 --no-pager
                                failed_services+=("$service")
                            fi
                        fi
                    else
                        print_warning "Failed to start $service"
                        if [[ "$service" == "ossuary-display" ]]; then
                            print_error "CRITICAL: Display service failed to start - kiosk will not work!"
                            print_step "Display service logs:"
                            journalctl -u ossuary-display -n 10 --no-pager || echo "No logs available"
                        fi
                        failed_services+=("$service")
                    fi
                fi
            else
                print_error "Failed to enable $service"
                failed_services+=("$service")
            fi
        else
            print_error "Service file for $service not found at /etc/systemd/system/${service}.service"
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

    # DNS configuration will be handled in post-install phase
    print_step "DNS configuration scheduled for post-install phase..."

    # Final verification of critical services
    print_step "Final service verification..."

    # Check that display service is enabled and can be started
    if systemctl is-enabled ossuary-display &>/dev/null; then
        echo "✓ Display service is enabled"
    else
        print_error "Display service is not enabled!"
        systemctl enable ossuary-display
        echo "✓ Enabled display service"
    fi

    # Check that kiosk service dependencies are correct
    if systemctl is-enabled ossuary-kiosk &>/dev/null; then
        echo "✓ Kiosk service is enabled"
        # Verify kiosk service can see its dependencies
        if systemctl list-dependencies ossuary-kiosk | grep -q ossuary-display; then
            echo "✓ Kiosk service has display service dependency"
        else
            print_warning "Kiosk service dependency chain may be incomplete"
        fi
    else
        print_error "Kiosk service is not enabled!"
        systemctl enable ossuary-kiosk
        echo "✓ Enabled kiosk service"
    fi

    print_success "Services configured and verified"
}

should_configure_dns_now() {
    # Check if user is connected via SSH over WiFi
    # If so, skip DNS config to prevent disconnection

    if [[ -z "$SSH_CLIENT" && -z "$SSH_TTY" ]]; then
        # Not an SSH session, safe to configure DNS
        return 0
    fi

    # Check if SSH connection is over WiFi
    local ssh_ip=$(echo $SSH_CLIENT | awk '{print $1}' 2>/dev/null || echo "")

    # Check for active WiFi connections
    if nmcli connection show --active 2>/dev/null | grep -q wifi; then
        # There's an active WiFi connection and this is SSH - risky
        return 1
    fi

    # Seems safe (ethernet or no active WiFi detected)
    return 0
}

configure_captive_portal_dns() {
    print_step "Setting up DNS for captive portal functionality..."

    # Create NetworkManager configuration directory if it doesn't exist
    mkdir -p /etc/NetworkManager/conf.d

    # Configure NetworkManager to use dnsmasq for better captive portal support
    cat > /etc/NetworkManager/conf.d/99-ossuary-dns.conf << 'EOF'
[main]
dns=dnsmasq

[logging]
level=INFO
domains=CORE,DHCP,WIFI,IP4,IP6,AUTOIP4,DHCP6,PPP,WIFI_SCAN,RFC3484,AUDIT,VPN_PLUGIN,DBUS_PROPS,TEAM,CONCHECK,DCB,DISPATCH,AGENT_MANAGER,SETTINGS_PLUGIN,SUSPEND_RESUME,CORE,DEVICE,OLPC,INFINIBAND,FIREWALL,ADSL,BOND,VLAN,BRIDGE,DBUS_PROPS,WIFI_SCAN,SIM,CONCHECK,DISPATCHER,AUDIT,VPN_PLUGIN,OTHER

EOF

    # Create dnsmasq configuration for NetworkManager
    mkdir -p /etc/NetworkManager/dnsmasq-shared.d

    cat > /etc/NetworkManager/dnsmasq-shared.d/99-ossuary-captive.conf << 'EOF'
# DNS configuration for captive portal
# Redirect all DNS queries to the captive portal when in AP mode

# Enable logging for debugging
log-queries
log-dhcp

# Set cache size
cache-size=1000

# Faster DNS responses
min-cache-ttl=60

# Domain handling for captive portal
# These domains are commonly used by devices to detect captive portals
address=/connectivitycheck.gstatic.com/192.168.42.1
address=/www.gstatic.com/192.168.42.1
address=/clients3.google.com/192.168.42.1
address=/captive.apple.com/192.168.42.1
address=/www.apple.com/192.168.42.1
address=/www.appleiphonecell.com/192.168.42.1
address=/msftconnecttest.com/192.168.42.1
address=/www.msftconnecttest.com/192.168.42.1

EOF

    # Disable the system dnsmasq service if it's running
    # NetworkManager will manage its own dnsmasq instance
    if systemctl is-active dnsmasq &>/dev/null; then
        print_step "Disabling system dnsmasq (NetworkManager will manage its own)"
        systemctl stop dnsmasq
        systemctl disable dnsmasq
    fi

    print_success "DNS configured for captive portal"
}

check_display_service_setup() {
    print_step "Verifying display service setup..."

    # Check if ossuary-display binary exists and is executable
    if [[ -f "/opt/ossuary/bin/ossuary-display" ]]; then
        if [[ -x "/opt/ossuary/bin/ossuary-display" ]]; then
            echo "✓ Display service binary exists and is executable"
        else
            print_error "Display service binary is not executable!"
            chmod +x "/opt/ossuary/bin/ossuary-display"
            echo "✓ Fixed display service binary permissions"
        fi
    else
        print_error "Display service binary missing at /opt/ossuary/bin/ossuary-display"
        print_error "This is a critical issue - kiosk will not work!"
        return 1
    fi

    # Check if display service file exists
    if [[ -f "/etc/systemd/system/ossuary-display.service" ]]; then
        echo "✓ Display service file exists"
    else
        print_error "Display service file missing at /etc/systemd/system/ossuary-display.service"
        return 1
    fi

    # Check if display service source exists
    if [[ -f "/opt/ossuary/src/display/service.py" ]]; then
        echo "✓ Display service source exists"
    else
        print_error "Display service source missing at /opt/ossuary/src/display/service.py"
        return 1
    fi

    # Check Python virtual environment
    if [[ -f "/opt/ossuary/venv/bin/python" ]]; then
        echo "✓ Python virtual environment exists"
    else
        print_error "Python virtual environment missing at /opt/ossuary/venv"
        return 1
    fi

    # Try to validate the service file
    if systemctl cat ossuary-display >/dev/null 2>&1; then
        echo "✓ Display service file is valid"
    else
        print_error "Display service file is invalid or not loaded"
        systemctl daemon-reload
        echo "✓ Reloaded systemd daemon"
    fi

    print_success "Display service setup verified"
    return 0
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
    local services=("ossuary-kiosk" "ossuary-display" "ossuary-portal" "ossuary-api" "ossuary-netd" "ossuary-config")
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
    for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-display; do
        if systemctl is-active "$service" &>/dev/null; then
            echo "  • $service: ${GREEN}running${NC}"
        else
            echo "  • $service: ${YELLOW}stopped (will start on reboot)${NC}"
        fi
    done
    echo "  • ossuary-kiosk: ${YELLOW}will start after reboot with display service${NC}"
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

    echo -e "${YELLOW}Phase 2 Operations (Automatic on Next Boot):${NC}"
    echo "  • DNS configuration for captive portal"
    echo "  • NetworkManager optimization"
    echo "  • Final service startup"
    echo "  • Second reboot"
    echo ""

    echo -e "${GREEN}Installation Phase 1 complete. Phase 2 will run automatically.${NC}"
    echo ""
}

create_post_install_helpers() {
    print_step "Creating post-install helper functions..."

    # Copy current install functions to temp file for post-install use
    cat > /tmp/ossuary_install_functions.sh << 'EOF'
# Helper functions for post-install operations

log() {
    echo "$(date): $1" | tee -a /var/log/ossuary-post-install.log
}

print_step() {
    log "[INFO] $1"
}

print_success() {
    log "[SUCCESS] $1"
}

print_warning() {
    log "[WARNING] $1"
}

print_error() {
    log "[ERROR] $1"
}

EOF

    print_success "Post-install helpers created"
}

schedule_post_install_operations() {
    print_step "Scheduling SSH-breaking operations for post-install..."

    echo ""
    echo -e "${YELLOW}===============================================${NC}"
    echo -e "${YELLOW}          IMPORTANT NOTICE${NC}"
    echo -e "${YELLOW}===============================================${NC}"
    echo ""
    echo -e "${RED}The following operations will break SSH connections:${NC}"
    echo "  • DNS configuration for captive portal"
    echo "  • NetworkManager restart"
    echo "  • Final system reboot"
    echo ""
    echo -e "${CYAN}These operations will be performed automatically after reboot${NC}"
    echo -e "${CYAN}and will continue even if SSH disconnects.${NC}"
    echo ""
    echo -e "${GREEN}The system will be fully configured after the second reboot.${NC}"
    echo ""

    # Create systemd service to run post-install operations on next boot
    cat > /etc/systemd/system/ossuary-post-install.service << 'EOF'
[Unit]
Description=Ossuary Post-Install Operations
After=multi-user.target network.target
Before=ossuary-netd.service ossuary-portal.service

[Service]
Type=oneshot
ExecStart=/opt/ossuary/post-install.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Copy post-install script to installation directory
    cp "$(dirname "$0")/post-install.sh" /opt/ossuary/post-install.sh || {
        print_error "Failed to copy post-install script"
        return 1
    }
    chmod +x /opt/ossuary/post-install.sh

    # Enable the post-install service
    systemctl enable ossuary-post-install.service

    print_success "Post-install operations scheduled"
}

ask_post_install_reboot() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}         INSTALLATION PHASE 1 COMPLETE${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "${CYAN}Phase 1 completed successfully! SSH-safe operations done.${NC}"
    echo ""
    echo -e "${YELLOW}Phase 2 (SSH-breaking operations) will run after reboot:${NC}"
    echo "  • DNS configuration for captive portal"
    echo "  • NetworkManager optimization"
    echo "  • Final service enablement"
    echo "  • Automatic second reboot"
    echo ""
    echo -e "${CYAN}After the second reboot, your system will be ready.${NC}"
    echo -e "${CYAN}You can then connect to the 'ossuary-setup' WiFi network.${NC}"
    echo ""

    read -p "Reboot now to complete installation? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Please reboot manually when convenient: sudo reboot${NC}"
        echo -e "${YELLOW}Post-install operations will run automatically on next boot.${NC}"
        exit 0
    fi

    print_step "Rebooting to complete installation..."
    reboot
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

    # System configuration (SSH-safe operations only)
    configure_network_manager
    configure_display
    configure_services
    configure_firewall
    create_default_config

    # Create SSH-safe helper functions for post-install
    create_post_install_helpers

    # Schedule SSH-breaking operations for post-install
    schedule_post_install_operations

    # Cleanup and completion
    cleanup
    print_completion
    ask_post_install_reboot
}

# Cleanup function for failed installations
cleanup_on_error() {
    print_error "Installation failed at line $LINENO"
    print_step "Cleaning up partial installation..."

    # Stop any services that might have been started
    for service in ossuary-config ossuary-netd ossuary-api ossuary-portal ossuary-display ossuary-kiosk; do
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
