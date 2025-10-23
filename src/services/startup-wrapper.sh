#!/bin/bash

# Ossuary Startup Command Wrapper
# Ensures proper process management and cleanup

# Trap signals to ensure child processes are killed
cleanup() {
    echo "Cleaning up child processes..."
    # Kill all child processes of this script
    pkill -P $$
    # Also kill any processes matching the command pattern
    if [ -n "$1" ]; then
        pkill -f "$1" 2>/dev/null || true
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT SIGKILL

# Wait for network connectivity (max 60 seconds)
echo "Checking network connectivity..."
COUNTER=0
while ! ping -c1 8.8.8.8 &>/dev/null; do
    echo "Waiting for network... ($COUNTER/60)"
    sleep 1
    COUNTER=$((COUNTER + 1))
    if [ $COUNTER -ge 60 ]; then
        echo "Warning: Network not available after 60 seconds, starting anyway..."
        break
    fi
done

if ping -c1 8.8.8.8 &>/dev/null; then
    echo "Network is available"
fi

# For GUI applications, wait for display
if echo "$@" | grep -E "chromium|firefox|midori" &>/dev/null; then
    echo "Waiting for display..."
    while ! xset q &>/dev/null; do
        echo "Waiting for X11 display..."
        sleep 2
    done
    echo "Display is ready"
fi

# For Chromium kiosk mode, kill any existing instances first
if echo "$@" | grep -q "chromium"; then
    echo "Killing existing Chromium instances..."
    pkill -f chromium 2>/dev/null || true
    sleep 1
fi

# Execute the command
echo "Starting: $@"
exec "$@"