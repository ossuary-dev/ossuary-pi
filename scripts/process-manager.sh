#!/bin/bash

# Ossuary Process Manager
# Keeps user's command running continuously with automatic restart

CONFIG_FILE="/etc/ossuary/config.json"
LOG_FILE="/var/log/ossuary-process.log"
PID_FILE="/var/run/ossuary-process.pid"
RESTART_DELAY=5

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get command from config
get_command() {
    if [ -f "$CONFIG_FILE" ]; then
        # Extract startup_command from JSON
        python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
        print(config.get('startup_command', ''))
except:
    pass
"
    fi
}

# Function to detect display server type
detect_display_server() {
    # Check XDG_SESSION_TYPE first (most reliable)
    if [ -n "$XDG_SESSION_TYPE" ]; then
        echo "$XDG_SESSION_TYPE"
        return
    fi

    # Check for Wayland
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
        return
    fi

    # Check for X11
    if [ -n "$DISPLAY" ]; then
        echo "x11"
        return
    fi

    # Try to detect from running processes
    if pgrep -x "Xorg" > /dev/null || pgrep -x "X" > /dev/null; then
        echo "x11"
        return
    fi

    if pgrep -x "sway" > /dev/null || pgrep -x "weston" > /dev/null || pgrep -x "wayfire" > /dev/null; then
        echo "wayland"
        return
    fi

    echo "unknown"
}

# Function to wait for display (for GUI apps)
wait_for_display() {
    local max_wait=60  # Increased wait time for boot scenarios
    local waited=0
    local display_type=$(detect_display_server)

    log "Detected display server: $display_type"

    while [ $waited -lt $max_wait ]; do
        # For Wayland
        if [ "$display_type" = "wayland" ]; then
            if [ -n "$WAYLAND_DISPLAY" ] && [ -e "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
                log "Wayland display is ready"
                return 0
            fi
            # Also check if compositor is running
            if pgrep -x "sway" > /dev/null || pgrep -x "weston" > /dev/null || pgrep -x "wayfire" > /dev/null; then
                log "Wayland compositor is running"
                return 0
            fi
        # For X11
        elif [ "$display_type" = "x11" ] || [ "$display_type" = "unknown" ]; then
            if xset q &>/dev/null 2>&1; then
                log "X11 display is ready"
                return 0
            fi
            # Alternative X11 check
            if [ -n "$DISPLAY" ] && xdpyinfo &>/dev/null 2>&1; then
                log "X11 display verified with xdpyinfo"
                return 0
            fi
        fi

        log "Waiting for display server ($display_type)..."
        sleep 2
        waited=$((waited + 2))

        # Re-detect in case it started late
        if [ $waited -eq 20 ] || [ $waited -eq 40 ]; then
            display_type=$(detect_display_server)
            log "Re-detected display server: $display_type"
        fi
    done

    log "Display not ready after ${max_wait} seconds, continuing anyway"
    return 1
}

# Function to setup environment for GUI apps
setup_gui_environment() {
    local user_home=""
    local display_type=$(detect_display_server)

    # Get the home directory for the user
    if id "pi" &>/dev/null; then
        user_home=$(getent passwd pi | cut -d: -f6)
        local run_user="pi"
    else
        # Find first non-root user
        local default_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -1)
        if [ -n "$default_user" ]; then
            user_home=$(getent passwd "$default_user" | cut -d: -f6)
            local run_user="$default_user"
        else
            user_home="/home/pi"
            local run_user="pi"
        fi
    fi

    # Set common environment
    export HOME="$user_home"

    # Setup display-specific variables
    if [ "$display_type" = "wayland" ]; then
        # Wayland-specific setup
        export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u $run_user)}"
        export XDG_SESSION_TYPE="wayland"

        # Some apps need these even on Wayland
        export DISPLAY="${DISPLAY:-:0}"

        log "Wayland environment set: WAYLAND_DISPLAY=$WAYLAND_DISPLAY, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    else
        # X11-specific setup
        export DISPLAY="${DISPLAY:-:0}"
        export XAUTHORITY="${user_home}/.Xauthority"
        export XDG_SESSION_TYPE="x11"

        log "X11 environment set: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY"
    fi

    log "Common environment set: HOME=$HOME, SESSION_TYPE=$XDG_SESSION_TYPE"
}

# Function to run and monitor the command
run_command() {
    local command="$1"
    local restart_count=0
    local is_gui_app=false

    log "Starting process manager for: $command"

    # Detect if this is a GUI application
    if echo "$command" | grep -qE "chromium|firefox|chrome|midori|DISPLAY="; then
        is_gui_app=true
        log "Detected GUI application"
    fi

    while true; do
        # Check if we should still be running
        if [ ! -f "$PID_FILE" ]; then
            log "PID file removed, stopping process manager"
            break
        fi

        # Get latest command from config (allows hot reload)
        local current_command=$(get_command)
        if [ "$current_command" != "$command" ]; then
            log "Command changed in config, restarting with new command"
            command="$current_command"
            restart_count=0

            # Re-detect GUI app
            if echo "$command" | grep -qE "chromium|firefox|chrome|midori|DISPLAY="; then
                is_gui_app=true
            else
                is_gui_app=false
            fi
        fi

        if [ -z "$command" ]; then
            log "No command configured, waiting..."
            sleep 10
            continue
        fi

        # Setup GUI environment if needed
        if [ "$is_gui_app" = true ]; then
            setup_gui_environment
            wait_for_display

            # Kill existing Chrome/Chromium instances if starting Chrome
            if echo "$command" | grep -qE "chrom(e|ium)"; then
                log "Killing existing Chrome/Chromium instances..."
                pkill -f "chrom(e|ium)" 2>/dev/null || true
                sleep 2
            fi
        fi

        # Run the command
        log "Starting process (attempt #$((restart_count + 1))): $command"

        # Create a subshell to run the command and capture its PID
        (
            # Setup environment and run command
            if id "pi" &>/dev/null; then
                if [ "$is_gui_app" = true ]; then
                    # For GUI apps, preserve all display environment variables
                    exec su pi -c "export DISPLAY='${DISPLAY:-:0}'; \
                        export XAUTHORITY='${XAUTHORITY}'; \
                        export HOME='${HOME}'; \
                        export WAYLAND_DISPLAY='${WAYLAND_DISPLAY}'; \
                        export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR}'; \
                        export XDG_SESSION_TYPE='${XDG_SESSION_TYPE}'; \
                        $command"
                else
                    exec su pi -c "$command"
                fi
            else
                # Find first non-root user
                local default_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -1)
                if [ -n "$default_user" ]; then
                    if [ "$is_gui_app" = true ]; then
                        exec su "$default_user" -c "export DISPLAY='${DISPLAY:-:0}'; \
                            export XAUTHORITY='${XAUTHORITY}'; \
                            export HOME='${HOME}'; \
                            export WAYLAND_DISPLAY='${WAYLAND_DISPLAY}'; \
                            export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR}'; \
                            export XDG_SESSION_TYPE='${XDG_SESSION_TYPE}'; \
                            $command"
                    else
                        exec su "$default_user" -c "$command"
                    fi
                else
                    # Fallback to running as current user
                    if [ "$is_gui_app" = true ]; then
                        exec bash -c "export DISPLAY='${DISPLAY:-:0}'; \
                            export XAUTHORITY='${XAUTHORITY}'; \
                            export HOME='${HOME}'; \
                            export WAYLAND_DISPLAY='${WAYLAND_DISPLAY}'; \
                            export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR}'; \
                            export XDG_SESSION_TYPE='${XDG_SESSION_TYPE}'; \
                            $command"
                    else
                        exec bash -c "$command"
                    fi
                fi
            fi
        ) 2>&1 | while IFS= read -r line; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] OUTPUT: $line" >> "$LOG_FILE"
        done &

        CHILD_PID=$!
        echo $CHILD_PID > "${PID_FILE}.child"

        # Wait for the process to finish
        wait $CHILD_PID
        EXIT_CODE=$?

        rm -f "${PID_FILE}.child"

        # Log the exit
        if [ $EXIT_CODE -eq 0 ]; then
            log "Process exited normally (code 0)"
        else
            log "Process crashed with exit code $EXIT_CODE"
        fi

        restart_count=$((restart_count + 1))

        # If it crashed too many times too quickly, slow down
        if [ $restart_count -gt 10 ]; then
            log "Too many restarts, waiting 30 seconds before retry..."
            sleep 30
            restart_count=0
        else
            log "Restarting in $RESTART_DELAY seconds..."
            sleep $RESTART_DELAY
        fi
    done
}

# Function to stop the managed process
stop_process() {
    if [ -f "${PID_FILE}.child" ]; then
        local child_pid=$(cat "${PID_FILE}.child")
        log "Stopping managed process (PID $child_pid)"
        kill -TERM $child_pid 2>/dev/null
        sleep 2
        kill -KILL $child_pid 2>/dev/null
        rm -f "${PID_FILE}.child"
    fi
}

# Signal handlers
handle_term() {
    log "Received TERM signal, shutting down..."
    stop_process
    rm -f "$PID_FILE"
    exit 0
}

handle_hup() {
    log "Received HUP signal, reloading configuration..."
    stop_process
    # Will restart with new config in main loop
}

# Trap signals
trap handle_term TERM INT
trap handle_hup HUP

# Main execution
main() {
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 $OLD_PID 2>/dev/null; then
            log "Process manager already running (PID $OLD_PID)"
            exit 1
        fi
        rm -f "$PID_FILE"
    fi

    # Save our PID
    echo $$ > "$PID_FILE"

    log "==================================="
    log "Ossuary Process Manager started"
    log "PID: $$"
    log "==================================="

    # Wait for network if needed
    log "Waiting for network connectivity..."
    for i in {1..30}; do
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            log "Network is up"
            break
        fi
        sleep 2
    done

    # Add startup delay for system stabilization (important for GUI apps)
    log "Waiting 10 seconds for system to stabilize..."
    sleep 10

    # Get and run the command
    COMMAND=$(get_command)

    if [ -n "$COMMAND" ]; then
        run_command "$COMMAND"
    else
        log "No startup command configured"
        # Still run the loop in case command is added later
        run_command ""
    fi

    # Cleanup
    rm -f "$PID_FILE"
    log "Process manager stopped"
}

# Run main function
main