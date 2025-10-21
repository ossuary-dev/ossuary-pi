# Ossuary Pi - Multi-stage Docker build for Balena deployment

# Build stage for web assets
FROM node:18-slim as web-builder

WORKDIR /app/web
COPY web/package*.json ./
RUN npm ci --only=production

COPY web/ ./
RUN npm run build 2>/dev/null || echo "No build script found, using files as-is"

# Main application stage
FROM balenalib/raspberrypi4-64-debian:bookworm

# Install runtime dependencies
RUN install_packages \
    python3 \
    python3-pip \
    python3-venv \
    python3-gi \
    python3-gi-cairo \
    gir1.2-nm-1.0 \
    network-manager \
    dbus \
    chromium-browser \
    xserver-xorg \
    xinit \
    openbox \
    unclutter \
    hostapd \
    dnsmasq \
    sqlite3 \
    curl \
    wget \
    psmisc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create ossuary user
RUN useradd -m -s /bin/bash ossuary && \
    usermod -a -G video,audio,input,netdev,gpio ossuary

# Set up application directories
WORKDIR /opt/ossuary

# Copy requirements and install Python dependencies
COPY requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Copy application source
COPY src/ ./src/
COPY config/ ./config/
COPY scripts/ ./scripts/
COPY systemd/ ./systemd/

# Copy web assets from build stage
COPY --from=web-builder /app/web ./web/

# Set up configuration directory
RUN mkdir -p /etc/ossuary /var/lib/ossuary /var/log/ossuary && \
    cp config/default.json /etc/ossuary/config.json && \
    chown -R ossuary:ossuary /var/lib/ossuary /var/log/ossuary && \
    chmod +x scripts/bin/* scripts/*.sh

# Create symlinks for executables
RUN ln -sf /opt/ossuary/scripts/bin/* /usr/local/bin/ && \
    ln -sf /opt/ossuary/scripts/ossuaryctl /usr/local/bin/ossuaryctl

# Set up X11 for ossuary user
RUN mkdir -p /home/ossuary/.config && \
    echo '#!/bin/bash\n\
xset s off\n\
xset -dpms\n\
xset s noblank\n\
unclutter -idle 1 -root &\n\
exec openbox-session' > /home/ossuary/.xinitrc && \
    chown ossuary:ossuary /home/ossuary/.xinitrc && \
    chmod +x /home/ossuary/.xinitrc

# Configure NetworkManager for container
RUN mkdir -p /etc/NetworkManager && \
    echo '[main]\n\
plugins=keyfile\n\
dhcp=internal\n\
\n\
[keyfile]\n\
unmanaged-devices=none\n\
\n\
[device]\n\
wifi.scan-rand-mac-address=no' > /etc/NetworkManager/NetworkManager.conf

# Set up dbus and systemd-style init
RUN mkdir -p /run/dbus && \
    mkdir -p /etc/systemd/system

# Copy startup script
COPY balena/start.sh /opt/ossuary/start.sh
RUN chmod +x /opt/ossuary/start.sh

# Environment variables for Balena
ENV DISPLAY=:0
ENV DBUS_SYSTEM_BUS_ADDRESS=unix:path=/host/run/dbus/system_bus_socket
ENV UDEV=1

# Labels for Balena
LABEL io.balena.features.dbus=1
LABEL io.balena.features.supervisor-api=1
LABEL io.balena.features.balena-api=1

# Expose ports
EXPOSE 80 443 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Start script
CMD ["/opt/ossuary/start.sh"]