// Ossuary Portal JavaScript

class OssuaryPortal {
    constructor() {
        this.api = '/api/v1';
        this.wsUrl = `ws://${window.location.host}/ws`;
        this.ws = null;
        this.networks = [];
        this.selectedNetwork = null;

        this.init();
    }

    async init() {
        await this.loadSystemStatus();
        await this.loadNetworkStatus();
        this.setupWebSocket();
        this.setupEventListeners();
        this.startStatusPolling();
    }

    setupEventListeners() {
        // WiFi form submission
        const wifiForm = document.getElementById('wifi-form');
        wifiForm.addEventListener('submit', (e) => this.handleWifiSubmit(e));

        // Kiosk form submission
        const kioskForm = document.getElementById('kiosk-form');
        kioskForm.addEventListener('submit', (e) => this.handleKioskSubmit(e));

        // Auto-refresh networks every 30 seconds
        setInterval(() => this.scanNetworks(false), 30000);
    }

    setupWebSocket() {
        try {
            this.ws = new WebSocket(this.wsUrl);

            this.ws.onopen = () => {
                console.log('WebSocket connected');
                this.updateStatus('connected', 'Connected');
            };

            this.ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                this.handleWebSocketMessage(data);
            };

            this.ws.onclose = () => {
                console.log('WebSocket disconnected');
                this.updateStatus('disconnected', 'Disconnected');
                // Reconnect after 5 seconds
                setTimeout(() => this.setupWebSocket(), 5000);
            };

            this.ws.onerror = (error) => {
                console.error('WebSocket error:', error);
            };
        } catch (error) {
            console.error('Failed to setup WebSocket:', error);
        }
    }

    handleWebSocketMessage(data) {
        switch (data.type) {
            case 'network_status_changed':
                this.loadNetworkStatus();
                break;
            case 'wifi_scan_complete':
                this.loadWifiNetworks();
                break;
            case 'kiosk_config_changed':
                this.loadKioskConfig();
                break;
            default:
                console.log('Unknown WebSocket message:', data);
        }
    }

    async loadSystemStatus() {
        try {
            const response = await fetch(`${this.api}/system/status`);
            const data = await response.json();
            this.renderSystemInfo(data);
        } catch (error) {
            console.error('Failed to load system status:', error);
        }
    }

    async loadNetworkStatus() {
        try {
            const response = await fetch(`${this.api}/network/status`);
            const data = await response.json();
            this.renderNetworkStatus(data);
        } catch (error) {
            console.error('Failed to load network status:', error);
        }
    }

    async scanNetworks(showLoading = true) {
        if (showLoading) {
            document.getElementById('wifi-networks').innerHTML = '<div class="loading">Scanning networks...</div>';
        }

        try {
            const response = await fetch(`${this.api}/network/scan`, { method: 'POST' });
            const data = await response.json();
            this.networks = data.networks || [];
            this.renderWifiNetworks();
        } catch (error) {
            console.error('Failed to scan networks:', error);
            this.showToast('Failed to scan networks', 'error');
        }
    }

    async loadWifiNetworks() {
        try {
            const response = await fetch(`${this.api}/network/networks`);
            const data = await response.json();
            this.networks = data.networks || [];
            this.renderWifiNetworks();
        } catch (error) {
            console.error('Failed to load networks:', error);
        }
    }

    renderNetworkStatus(status) {
        const container = document.getElementById('network-info');
        const isConnected = status.state === 'connected';

        if (isConnected) {
            this.updateStatus('connected', `Connected to ${status.ssid}`);
            container.innerHTML = `
                <div class="network-info-connected">
                    <div class="system-detail">
                        <span class="detail-label">Network:</span>
                        <span class="detail-value">${status.ssid}</span>
                    </div>
                    <div class="system-detail">
                        <span class="detail-label">IP Address:</span>
                        <span class="detail-value">${status.ip_address}</span>
                    </div>
                    <div class="system-detail">
                        <span class="detail-label">Signal:</span>
                        <span class="detail-value">${status.signal_strength}%</span>
                    </div>
                </div>
            `;
        } else if (status.state === 'connecting') {
            this.updateStatus('connecting', 'Connecting...');
            container.innerHTML = '<div class="loading">Connecting to network...</div>';
        } else {
            this.updateStatus('disconnected', 'Not connected');
            container.innerHTML = `
                <div class="network-info-disconnected">
                    <p>No active network connection. Connect to a WiFi network below.</p>
                </div>
            `;
        }
    }

    renderWifiNetworks() {
        const container = document.getElementById('wifi-networks');

        if (this.networks.length === 0) {
            container.innerHTML = '<div class="loading">No networks found. Click scan to search again.</div>';
            return;
        }

        const networksHtml = this.networks.map(network => {
            const signalIcon = this.getSignalIcon(network.signal_strength);
            const securityText = network.security ? 'Secured' : 'Open';
            const connectedClass = network.connected ? 'connected' : '';

            return `
                <div class="wifi-network ${connectedClass}" onclick="selectNetwork('${network.ssid}', ${network.security})">
                    <div class="wifi-info">
                        <div>
                            <div class="wifi-name">${network.ssid}</div>
                            <div class="wifi-security">${securityText}</div>
                        </div>
                    </div>
                    <div class="wifi-signal">
                        <span class="signal-strength">${network.signal_strength}%</span>
                        ${signalIcon}
                    </div>
                </div>
            `;
        }).join('');

        container.innerHTML = networksHtml;
    }

    renderSystemInfo(info) {
        const container = document.getElementById('system-details');
        container.innerHTML = `
            <div class="system-detail">
                <span class="detail-label">Hostname:</span>
                <span class="detail-value">${info.hostname}</span>
            </div>
            <div class="system-detail">
                <span class="detail-label">Uptime:</span>
                <span class="detail-value">${this.formatUptime(info.uptime)}</span>
            </div>
            <div class="system-detail">
                <span class="detail-label">CPU Usage:</span>
                <span class="detail-value">${info.cpu_percent}%</span>
            </div>
            <div class="system-detail">
                <span class="detail-label">Memory:</span>
                <span class="detail-value">${info.memory_percent}%</span>
            </div>
            <div class="system-detail">
                <span class="detail-label">Temperature:</span>
                <span class="detail-value">${info.temperature}°C</span>
            </div>
            <div class="system-detail">
                <span class="detail-label">Version:</span>
                <span class="detail-value">${info.version}</span>
            </div>
        `;
    }

    selectNetwork(ssid, requiresPassword) {
        this.selectedNetwork = { ssid, requiresPassword };

        document.getElementById('ssid').value = ssid;
        document.getElementById('wifi-form').classList.remove('hidden');

        const passwordGroup = document.getElementById('password-group');
        if (requiresPassword) {
            passwordGroup.style.display = 'block';
            document.getElementById('password').required = true;
        } else {
            passwordGroup.style.display = 'none';
            document.getElementById('password').required = false;
        }
    }

    async handleWifiSubmit(event) {
        event.preventDefault();

        const formData = new FormData(event.target);
        const ssid = formData.get('ssid');
        const password = formData.get('password');

        try {
            this.showToast('Connecting to network...', 'info');

            const response = await fetch(`${this.api}/network/connect`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ssid, password })
            });

            const result = await response.json();

            if (response.ok) {
                this.showToast('Successfully connected to network', 'success');
                this.cancelWifiForm();
                setTimeout(() => this.loadNetworkStatus(), 2000);
            } else {
                this.showToast(result.detail || 'Failed to connect', 'error');
            }
        } catch (error) {
            console.error('Connection error:', error);
            this.showToast('Failed to connect to network', 'error');
        }
    }

    async handleKioskSubmit(event) {
        event.preventDefault();

        const formData = new FormData(event.target);
        const url = formData.get('url');
        const enableWebgl = formData.get('enable-webgl') === 'on';

        try {
            const response = await fetch(`${this.api}/kiosk/config`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ url, enable_webgl: enableWebgl })
            });

            if (response.ok) {
                this.showToast('Kiosk configuration saved', 'success');
            } else {
                this.showToast('Failed to save configuration', 'error');
            }
        } catch (error) {
            console.error('Save error:', error);
            this.showToast('Failed to save configuration', 'error');
        }
    }

    cancelWifiForm() {
        document.getElementById('wifi-form').classList.add('hidden');
        document.getElementById('wifi-form').reset();
        this.selectedNetwork = null;
    }

    togglePassword() {
        const passwordField = document.getElementById('password');
        const type = passwordField.type === 'password' ? 'text' : 'password';
        passwordField.type = type;
    }

    async restartSystem() {
        if (!confirm('Are you sure you want to restart the system?')) {
            return;
        }

        try {
            await fetch(`${this.api}/system/restart`, { method: 'POST' });
            this.showToast('System restart initiated', 'info');
        } catch (error) {
            console.error('Restart error:', error);
            this.showToast('Failed to restart system', 'error');
        }
    }

    updateStatus(state, text) {
        const indicator = document.getElementById('status-indicator');
        const statusText = document.getElementById('status-text');

        indicator.className = `status-indicator ${state}`;
        statusText.textContent = text;
    }

    showToast(message, type = 'info') {
        const container = document.getElementById('toast-container');
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.textContent = message;

        container.appendChild(toast);

        setTimeout(() => {
            toast.remove();
        }, 5000);
    }

    getSignalIcon(strength) {
        if (strength >= 75) return '📶';
        if (strength >= 50) return '📶';
        if (strength >= 25) return '📶';
        return '📶';
    }

    formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (days > 0) return `${days}d ${hours}h ${minutes}m`;
        if (hours > 0) return `${hours}h ${minutes}m`;
        return `${minutes}m`;
    }

    startStatusPolling() {
        // Poll system status every 30 seconds
        setInterval(() => this.loadSystemStatus(), 30000);
        // Poll network status every 10 seconds
        setInterval(() => this.loadNetworkStatus(), 10000);
    }
}

// Global functions for onclick handlers
function selectNetwork(ssid, requiresPassword) {
    window.portal.selectNetwork(ssid, requiresPassword);
}

function scanNetworks() {
    window.portal.scanNetworks();
}

function cancelWifiForm() {
    window.portal.cancelWifiForm();
}

function togglePassword() {
    window.portal.togglePassword();
}

function restartSystem() {
    window.portal.restartSystem();
}

function closeQRModal() {
    document.getElementById('qr-modal').classList.add('hidden');
}

// Initialize portal when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.portal = new OssuaryPortal();
});