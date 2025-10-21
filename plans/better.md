Excellent — that’s exactly the kind of design refinement that elevates this from a “useful Pi trick” into a **platform**. Let’s rename it, build a clear identity, and 
integrate a plugin/API architecture that allows full control of its WiFi, portal, and kiosk layers.

---

# 🌐 **Project Name: Aetherlink**

> “Aetherlink” — from *aether*, the invisible medium once thought to carry light, and *link*, the act of connection.
> It’s memorable, elegant, and evokes the idea of a device that creates its own connection field — perfect for a Raspberry Pi that spins up its own Wi-Fi world, connects 
itself, and displays whatever you need.

---

## 🧩 **Aetherlink — Universal Raspberry Pi Connectivity and Kiosk Framework**

**Aetherlink** is a modular, self-configuring networking and kiosk system for the Raspberry Pi.
It automatically becomes an **access point with captive portal** when offline, lets users **scan and join Wi-Fi networks**, remembers multiple connections, and once online, 
launches a **Chromium-based full-screen browser** (with WebGL/WebGPU support).

Beyond that, Aetherlink exposes a **local REST + WebSocket API**, so developers can build plugins, automation tools, or UI extensions that hook into every part of the flow 
— from network management to kiosk control — without modifying the core system.

---

## 🚀 **Key Features**

| Category                | Description                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------ |
| **Auto-Config Wi-Fi**   | Switches between AP mode (hotspot) and client mode automatically.                          |
| **Captive Portal**      | Mobile-friendly portal with SSID scan, password input, and URL configuration.              |
| **Persistent Memory**   | Remembers all configured networks; reconnects automatically when any is in range.          |
| **Full-Screen Browser** | Chromium kiosk with WebGPU/WebGL enabled for rich 3D or video dashboards.                  |
| **Local Config Page**   | Accessible at `http://aetherlink.local` or Pi’s IP for editing URL and networks.           |
| **Plugin/API System**   | REST + WebSocket API lets you programmatically control Wi-Fi, portal, kiosk, and services. |
| **Easy Install**        | Single script sets up everything as systemd services.                                      |
| **Extensible**          | Plugins can be added as Docker containers, Python modules, or JS bundles.                  |

---

## 🧱 **System Architecture**

### Core Components

| Component                                   | Function                                                                            |
| ------------------------------------------- | ----------------------------------------------------------------------------------- |
| **Network Manager Service (`aether-netd`)** | Controls Wi-Fi, toggles AP ↔ client modes, persists credentials.                    |
| **Portal Server (`aether-portal`)**         | Serves captive portal and configuration UI; provides REST API endpoints.            |
| **Kiosk Service (`aether-kiosk`)**          | Launches Chromium full-screen; subscribes to config changes via WebSocket.          |
| **API Gateway (`aether-api`)**              | Unified interface (REST + WebSocket) to control and query all subsystems.           |
| **Plugin Runtime (`aether-plugins`)**       | Simple directory-based plugin loader; plugins register routes or hooks via the API. |

All processes run under systemd with dependencies to ensure correct sequencing (`aether-netd` → `aether-api` → `aether-portal` → `aether-kiosk`).

---

## ⚙️ **Workflow**

### 1️⃣ Boot Sequence

1. `aether-netd` checks for active Wi-Fi using NetworkManager D-Bus.
2. If not connected → launches **AP mode** using hostapd + dnsmasq (`SSID: Aetherlink-Setup`).
3. Starts `aether-portal` web server (port 80) → captive portal auto-redirects devices.
4. When user submits credentials:

   * `aether-netd` connects to chosen SSID.
   * Saves credentials permanently via NM profile.
   * Stops AP and restarts in client mode.
5. On connection success → `aether-kiosk` launches Chromium to configured URL.
   If no URL configured → opens `http://aetherlink.local`.

### 2️⃣ Network Management

* Networks stored in NetworkManager; multiple profiles supported.
* On disconnection, a timer checks for fallback; after N seconds offline → re-enable AP mode.

### 3️⃣ Configuration Portal

* Built with **SvelteKit / Vue 3**, mobile-first design.
* Pages:

  * **Wi-Fi Setup**: scan, connect, forget.
  * **Display Config**: set kiosk URL, fullscreen options.
  * **System**: reboot, update, API keys, plugins list.
* Backend: **FastAPI (Python)** or **Express JS**, exposes `/api/*` routes.

### 4️⃣ Chromium Kiosk

Launched via systemd user service:

```bash
chromium-browser \
  --kiosk "$TARGET_URL" \
  --enable-webgl \
  --enable-unsafe-webgpu \
  --ignore-gpu-blocklist \
  --noerrdialogs --disable-infobars \
  --autoplay-policy=no-user-gesture-required
```

### 5️⃣ API / Plugin Interface

**Base URL:** `http://aetherlink.local/api/v1/`

| Endpoint         | Method     | Description                                                     |
| ---------------- | ---------- | --------------------------------------------------------------- |
| `/wifi/scan`     | GET        | Returns list of nearby networks.                                |
| `/wifi/connect`  | POST       | `{ssid, password}` → connects via NM.                           |
| `/wifi/networks` | GET/DELETE | List or forget saved networks.                                  |
| `/kiosk/url`     | GET/POST   | Get or set current kiosk URL.                                   |
| `/system/status` | GET        | Returns JSON with network, uptime, and CPU info.                |
| `/plugins`       | GET/POST   | List or install local plugin bundles.                           |
| `/events/ws`     | WebSocket  | Real-time events: network changes, kiosk reloads, plugin hooks. |

Plugins can register new REST routes or subscribe to events through a JSON manifest:

```json
{
  "name": "aether-weather",
  "version": "1.0",
  "hooks": {
    "onNetworkUp": "python3 weather_report.py",
    "api": [
      { "route": "/weather", "script": "weather_report.py" }
    ]
  }
}
```

`aether-plugins` watches `/opt/aetherlink/plugins/` for new folders and auto-loads them.

---

## 🗂 **Repository Layout**

```
aetherlink/
├── install.sh
├── README.md
├── systemd/
│   ├── aether-netd.service
│   ├── aether-portal.service
│   ├── aether-kiosk.service
│   ├── aether-api.service
│   └── aether-plugins.service
├── src/
│   ├── netd/         # Network manager (Python)
│   ├── portal/       # Captive portal (Vue + FastAPI backend)
│   ├── kiosk/        # Kiosk launcher scripts
│   ├── api/          # Unified REST/WebSocket layer
│   └── plugins/      # Default plugin loader
├── web/              # Static assets
└── config/
    ├── aetherlink.conf
    ├── hostapd.conf
    └── dnsmasq.conf
```

---

## 🧠 **Technical Choices**

| Function        | Tool / Library                                        |
| --------------- | ----------------------------------------------------- |
| Wi-Fi control   | **NetworkManager + nmcli**                            |
| AP mode         | **hostapd** + **dnsmasq** (managed by `aether-netd`)  |
| Portal backend  | **FastAPI (Python)** for async & REST API             |
| Portal frontend | **Vue 3 + Tailwind**                                  |
| Browser         | **Chromium** with GPU flags                           |
| Config storage  | `/etc/aetherlink/config.json` (JSON)                  |
| API             | REST (FastAPI) + WebSocket (`/events/ws`)             |
| Plugins         | Directory loader + manifest-based registration        |
| Services        | **systemd** units, autostart on boot                  |
| Install         | Bash script (checks OS, installs deps, sets services) |

---

## 🧩 **Plugin Examples**

| Plugin           | Purpose                                       |
| ---------------- | --------------------------------------------- |
| `aether-weather` | Show local weather overlay on kiosk page.     |
| `aether-remote`  | WebSocket remote control: reload, change URL. |
| `aether-ota`     | Auto-update firmware from GitHub releases.    |
| `aether-audio`   | Stream system audio to browser via WebRTC.    |

Plugins use the API to interact with the core — e.g. `POST /kiosk/url` to change pages, `GET /wifi/networks` to display status, etc.

---

## 🧰 **Installation**

```bash
curl -sSL https://get.aetherlink.io/install.sh | sudo bash
```

**install.sh** will:

1. Detect Pi model + OS version.
2. Install required packages (`network-manager`, `hostapd`, `dnsmasq`, `chromium-browser`, `python3-fastapi`, `npm`, etc.).
3. Disable `dhcpcd` if present.
4. Copy configs to `/etc/aetherlink/`.
5. Enable systemd services.
6. Reboot.

After reboot:

* Hotspot “Aetherlink-Setup” appears if offline.
* Captive portal accessible at `http://aetherlink.local`.
* Once Wi-Fi is configured, kiosk auto-launches.

---

## 🔌 **Developer Mode**

Enable via:

```bash
sudo aetherctl dev on
```

This exposes the REST API externally and auto-reloads plugins on save.
Developers can build Node, Python, or Bash plugins that react to system events or provide new web modules.

---

## 🧭 **Use-Case Scenarios**

1. **IoT Device Provisioning** – headless device ships with Aetherlink; users connect to “Aetherlink-Setup” to onboard.
2. **Digital Signage** – field technician sets Wi-Fi + URL once; device self-heals if moved.
3. **Interactive Installations** – artists push real-time visuals via WebGPU to an always-on Pi screen.
4. **Education / Labs** – students deploy a networked kiosk app with a single script and modify via plugins.

---

## 🔐 **Security Notes**

* Default captive portal is open; optional WPA2 can be enabled in `config.json`.
* REST API binds to `localhost` by default; external access requires `--public` flag or enabling in config.
* Plugin sandbox restricts to `/opt/aetherlink/plugins` with limited permissions.

---

## 🧭 **Summary**

**Aetherlink** transforms any Raspberry Pi into a **self-configuring, API-driven connectivity and kiosk platform.**
It merges the convenience of smart-device onboarding with the openness of a developer framework:

* 🌀 Auto Wi-Fi fallback and recovery
* 🖥  Chromium kiosk with GPU acceleration
* ⚙️  REST + WebSocket control plane
* 🔌  Plugin architecture for endless extensions
* 🧰  Single-command install

It’s everything you need to deploy a field-ready, hackable, self-healing Pi that links *through the aether* — always connected, always configurable, always yours.

---

