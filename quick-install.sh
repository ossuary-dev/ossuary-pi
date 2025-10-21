#!/bin/bash
"""Quick installer for Ossuary Pi - downloads and runs full installer."""

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/yourusername/ossuary-pi"
INSTALLER_URL="https://raw.githubusercontent.com/yourusername/ossuary-pi/main/install.sh"
TEMP_DIR="/tmp/ossuary-pi-installer"

print_banner() {
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║           Ossuary Pi                  ║"
    echo "  ║         Quick Installer               ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root"
        echo "Please run: curl -sSL https://get.ossuary-pi.dev | sudo bash"
        exit 1
    fi
}

check_internet() {
    echo -e "${BLUE}[INFO]${NC} Checking internet connectivity..."

    if ! ping -c 1 github.com &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} No internet connection available"
        echo "Please check your network connection and try again."
        exit 1
    fi

    echo -e "${GREEN}[SUCCESS]${NC} Internet connectivity confirmed"
}

download_installer() {
    echo -e "${BLUE}[INFO]${NC} Downloading Ossuary Pi installer..."

    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Try to download installer
    if command -v curl &> /dev/null; then
        if curl -sSL "$INSTALLER_URL" -o install.sh; then
            echo -e "${GREEN}[SUCCESS]${NC} Installer downloaded successfully"
        else
            echo -e "${RED}[ERROR]${NC} Failed to download installer with curl"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if wget -q "$INSTALLER_URL" -O install.sh; then
            echo -e "${GREEN}[SUCCESS]${NC} Installer downloaded successfully"
        else
            echo -e "${RED}[ERROR]${NC} Failed to download installer with wget"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} Neither curl nor wget is available"
        echo "Please install curl or wget and try again."
        exit 1
    fi

    # Make installer executable
    chmod +x install.sh
}

run_installer() {
    echo -e "${BLUE}[INFO]${NC} Running Ossuary Pi installer..."
    echo ""

    # Run the full installer
    if ./install.sh "$@"; then
        echo ""
        echo -e "${GREEN}[SUCCESS]${NC} Ossuary Pi installation completed successfully!"
    else
        echo ""
        echo -e "${RED}[ERROR]${NC} Installation failed"
        exit 1
    fi
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

main() {
    print_banner

    echo -e "${YELLOW}This will download and install Ossuary Pi on your system.${NC}"
    echo ""

    check_root
    check_internet
    download_installer
    run_installer "$@"
}

# Run main function
main "$@"