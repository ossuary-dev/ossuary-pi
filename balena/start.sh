#!/bin/bash
"""Balena startup script for Ossuary Pi."""

set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to check if a process is running
is_running() {
    local pid_file=$1
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    return 1
}

# Function to start a service
start_service() {
    local service_name=$1
    local service_cmd=$2
    local pid_file="/var/run/ossuary-${service_name}.pid"
    local log_file="/var/log/ossuary/${service_name}.log"

    if is_running "$pid_file"; then
        log_warning "$service_name is already running"
        return 0
    fi

    log "Starting $service_name..."

    # Create log directory
    mkdir -p /var/log/ossuary

    # Start service in background
    nohup $service_cmd > "$log_file" 2>&1 &
    local pid=$!

    # Save PID
    echo "$pid" > "$pid_file"

    # Wait a moment and check if it's still running
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        log_success "$service_name started (PID: $pid)"
        return 0
    else
        log_error "$service_name failed to start"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to stop a service
stop_service() {
    local service_name=$1
    local pid_file="/var/run/ossuary-${service_name}.pid"

    if is_running "$pid_file"; then
        local pid=$(cat "$pid_file")
        log "Stopping $service_name (PID: $pid)..."

        kill "$pid"

        # Wait for graceful shutdown
        for i in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Force killing $service_name"
            kill -9 "$pid" 2>/dev/null || true
        fi

        rm -f "$pid_file"
        log_success "$service_name stopped"
    else
        log_warning "$service_name is not running"
    fi
}

# Signal handlers
cleanup() {
    log "Received shutdown signal, stopping services..."

    stop_service "kiosk"
    stop_service "portal"
    stop_service "api"
    stop_service "netd"
    stop_service "config"

    # Stop X server
    if [[ -n "$XORG_PID" ]] && kill -0 "$XORG_PID" 2>/dev/null; then
        log "Stopping X server..."
        kill "$XORG_PID" 2>/dev/null || true
    fi

    # Stop dbus
    if [[ -n "$DBUS_PID" ]] && kill -0 "$DBUS_PID" 2>/dev/null; then
        log "Stopping D-Bus..."
        kill "$DBUS_PID" 2>/dev/null || true
    fi

    # Stop NetworkManager
    if [[ -n "$NM_PID" ]] && kill -0 "$NM_PID" 2>/dev/null; then
        log "Stopping NetworkManager..."
        kill "$NM_PID" 2>/dev/null || true
    fi

    log "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Banner
echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║           Ossuary Pi                  ║"
echo "  ║         Balena Container              ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"

log "Starting Ossuary Pi in Balena container..."

# Set up environment
export PYTHONPATH="/opt/ossuary/src:$PYTHONPATH"
export DISPLAY=:0

# Create runtime directories
mkdir -p /var/run/ossuary /var/log/ossuary /tmp/ossuary

# Set permissions
chown -R ossuary:ossuary /var/lib/ossuary /var/log/ossuary /tmp/ossuary

# Start D-Bus (required for NetworkManager)
log "Starting D-Bus..."
if [[ ! -S /var/run/dbus/system_bus_socket ]]; then
    dbus-daemon --system --fork
    DBUS_PID=$(pgrep -f "dbus-daemon --system")
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket
fi

# Wait for D-Bus to be ready
for i in {1..10}; do
    if [[ -S /var/run/dbus/system_bus_socket ]]; then
        break
    fi
    log "Waiting for D-Bus to be ready..."
    sleep 1
done

# Start NetworkManager
log "Starting NetworkManager..."
NetworkManager --no-daemon &
NM_PID=$!

# Wait for NetworkManager to be ready
for i in {1..15}; do
    if nmcli general status &>/dev/null; then
        log_success "NetworkManager is ready"
        break
    fi
    log "Waiting for NetworkManager to be ready..."
    sleep 2
done

# Start X server for kiosk mode
log "Starting X server..."
export DISPLAY=:0
Xorg :0 -ac -nolisten tcp vt1 &
XORG_PID=$!

# Wait for X server to be ready
for i in {1..10}; do
    if xdpyinfo -display :0 &>/dev/null; then
        log_success "X server is ready"
        break
    fi
    log "Waiting for X server to be ready..."
    sleep 2
done

# Set up X11 permissions for ossuary user
if command -v xhost &>/dev/null; then
    xhost +local:ossuary 2>/dev/null || true
fi

# Configure display
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Start ossuary services in dependency order
log "Starting Ossuary services..."

# 1. Configuration service
start_service "config" "python3 /opt/ossuary/src/config/manager.py"

# 2. Network management service
start_service "netd" "python3 /opt/ossuary/src/netd/service.py"

# 3. API service
start_service "api" "python3 /opt/ossuary/src/api/service.py"

# 4. Portal service
start_service "portal" "python3 /opt/ossuary/src/portal/server.py"

# 5. Kiosk service (as ossuary user)
start_service "kiosk" "su -c 'DISPLAY=:0 python3 /opt/ossuary/src/kiosk/service.py' ossuary"

# Health check function
health_check() {
    local failed_services=()

    # Check each service
    for service in config netd api portal kiosk; do
        if ! is_running "/var/run/ossuary-${service}.pid"; then
            failed_services+=("$service")
        fi
    done

    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_error "Failed services: ${failed_services[*]}"
        return 1
    fi

    # Check if portal is responding
    if ! curl -f http://localhost/health &>/dev/null; then
        log_error "Portal health check failed"
        return 1
    fi

    return 0
}

# Wait for services to start
log "Waiting for services to initialize..."
sleep 10

# Perform initial health check
if health_check; then
    log_success "All services started successfully"
else
    log_error "Some services failed to start"
fi

# Service monitoring loop
log "Starting service monitoring..."

while true; do
    # Check service health every 30 seconds
    sleep 30

    # Restart failed services
    for service in config netd api portal kiosk; do
        if ! is_running "/var/run/ossuary-${service}.pid"; then
            log_warning "$service has stopped, restarting..."

            case $service in
                "config")
                    start_service "config" "python3 /opt/ossuary/src/config/manager.py"
                    ;;
                "netd")
                    start_service "netd" "python3 /opt/ossuary/src/netd/service.py"
                    ;;
                "api")
                    start_service "api" "python3 /opt/ossuary/src/api/service.py"
                    ;;
                "portal")
                    start_service "portal" "python3 /opt/ossuary/src/portal/server.py"
                    ;;
                "kiosk")
                    start_service "kiosk" "su -c 'DISPLAY=:0 python3 /opt/ossuary/src/kiosk/service.py' ossuary"
                    ;;
            esac
        fi
    done

    # Log service status periodically (every 5 minutes)
    if (( $(date +%s) % 300 == 0 )); then
        log "Service status check - all services running"
    fi
done