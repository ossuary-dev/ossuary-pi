PiFi Portal – Raspberry Pi WiFi Access Point and Kiosk
Overview

PiFi Portal is a project plan for a drop-in solution that turns any Raspberry Pi into a Wi-Fi access point with a captive portal for network configuration. When the Pi is 
not connected to a known WiFi network, it automatically starts an access point (AP) and presents a captive portal. This portal allows users to scan for available WiFi 
networks, select one, enter the password, and save the credentials to the Pi for future use. Once configured, the Pi will remember multiple networks, enabling seamless 
relocation without re-entering credentials. In normal operation (when WiFi is configured), the Pi runs a full-screen Chromium browser (kiosk mode) to display a 
user-specified URL (with WebGL/WebGPU support enabled). The same configuration interface is also accessible via a web browser by navigating to the Pi’s hostname or IP 
address on the network, allowing users to adjust settings (like the target URL) at any time. The entire system is designed to run as proper background services and be 
installable with a single script for ease of setup.

Features and Goals

Auto Hotspot & Captive Portal: If the Pi has no active WiFi connection on boot, it launches a WiFi hotspot (AP mode) with a captive portal. Any phone or laptop that 
connects to this hotspot is automatically redirected to the configuration webpage
github.com
. This captive portal webpage lets the user configure the device’s WiFi.

WiFi Network Scanning & Setup: The portal displays a list of nearby WiFi SSIDs (networks) and allows the user to select one and input the password
github.com
. Upon submission, the Pi will disable the AP and attempt to connect to the chosen WiFi network. If the connection succeeds, the credentials are saved (so the Pi will 
auto-join next time); if it fails, the AP is brought back up for another attempt
github.com
. This ensures an intuitive way to set or change WiFi without needing console access.

Persisting Multiple Networks: The system remembers all configured WiFi networks. This means you can set up WiFi for home, office, or other locations, and PiFi Portal will 
auto-connect if any of them are in range. (NetworkManager on Raspberry Pi OS can store multiple WiFi profiles by default and handle this seamlessly
github.com
.) As a result, moving the Pi to a new place is as easy as plugging it in – no need to reconfigure if that network was set before.

Custom Full-Screen Content (Kiosk Mode): Users can specify a default URL or web application that the Pi should display when it’s online. This URL can be configured through 
the portal. The Pi runs a Chromium browser in kiosk mode on boot, which opens this URL in full-screen without any window chrome. If the Pi is not yet configured (or not 
connected), it will instead open the local configuration page in full-screen – effectively guiding the user to set up the device. Once WiFi is connected, the browser can 
automatically navigate to the user-defined page. This makes PiFi Portal ideal for IoT appliances, digital signage, or kiosk applications that require an initial WiFi setup 
followed by display of web content.

WebGL/WebGPU Enabled: The Chromium browser launched on the Pi will have hardware acceleration enabled for graphics, allowing WebGL and WebGPU content to run. On Raspberry 
Pi, Chromium can support WebGL2 with the proper drivers, and enabling the “ignore GPU blocklist” flag may be needed to ensure WebGL is not disabled
forums.raspberrypi.com
. The install/setup process will configure Chromium with flags (and GPU drivers) so that rich interactive graphics or GPU-accelerated content run smoothly on the kiosk. 
This is especially important if the displayed content is graphically intensive.

Headless or Display Flexibility: The solution works whether or not you have a screen attached. With a display attached, the Pi will show the captive portal or kiosk content 
full-screen on the Pi’s own monitor. If headless, the captive portal still works for users who connect via WiFi using another device. The configuration page is always 
accessible at a known address (e.g. http://pifi.local or the Pi’s IP) so that once the Pi is on a network, an admin can change settings (like the target URL) from their 
laptop or phone. No login/password is required for this local config page by design (to keep it simple for quick setup, assuming the network access is restricted to trusted 
users).

System Architecture and Components
1. Network Management & Auto AP Mode

At the core, PiFi Portal will manage the Pi’s WiFi interface to switch between Client Mode (connecting to a router) and Access Point Mode (hosting its own network). Modern 
Raspberry Pi OS releases (e.g. Bookworm) include NetworkManager by default, which simplifies toggling between these modes and handling WiFi credentials
github.com
. We will leverage NetworkManager for reliability and simplicity, instead of manually manipulating wpa_supplicant, hostapd, and dnsmasq configurations (though those tools 
underlie NetworkManager’s functionality).

Access Point Setup: When triggered, the Pi’s WLAN interface (wlan0) will be configured as an AP with a preset SSID (e.g. “PiFi-Setup”) and WPA2 password (or open network if 
desired). If using NetworkManager, this can be done via a connection profile for hotspot mode. Alternatively, if using classic tools: hostapd will broadcast the SSID and 
manage WiFi authentication, while dnsmasq (or dhcpd) will assign IPs to clients on the AP network and act as a DNS forwarder. The AP will use a static IP for the Pi 
(commonly something like 192.168.4.1)
github.com
. We will also set up firewall/iptables rules to intercept HTTP traffic for captive portal (see below).

Captive Portal Trigger: To make connecting devices show the captive portal automatically, the system will use a standard trick: any HTTP request by a connected client is 
redirected to the Pi’s local web server. This is achieved by running a DNS service that resolves all queries to the Pi’s IP (for the AP clients) and/or by using iptables to 
DNAT port 80 to the local portal web server. Thus, when a phone connects and tries to check connectivity (e.g. by accessing a known site on http), it will be served our 
portal page. Many OSes will then automatically pop up the “captive portal” login view showing our page. (If not, the user can open a browser and any URL will redirect to 
the portal.) We will configure these details (via dnsmasq or NM’s built-in DNS) so that the captive portal experience is smooth
github.com
github.com
.

Auto-Start and Fallback Logic: A WiFi Manager Service (likely a systemd service or a script launched at boot) will check the connectivity state. Pseudocode for logic: “On 
boot, if the Pi is not connected to any known WiFi, start AP mode and launch captive portal. If it is connected, ensure AP mode is off.” We can detect “not connected” 
either via NetworkManager’s status or by trying to ping a known address. If using NetworkManager, we might write a small script or use balena’s wifi-connect utility which 
already implements this flow. In fact, wifi-connect can be run such that it only starts an AP if no connection is active
planb.nicecupoftea.org
. Using that approach, the Pi boots, the service calls wifi-connect (or similar code): if NM says a connection is active, it exits (meaning normal operation continues); if 
not, it brings up the AP and portal and waits for credentials. This method ensures users aren’t “driven crazy” by an AP popping up when not needed (some solutions 
considered auto-detection vs a physical trigger; we aim for auto-detection but with robust checks to avoid flapping)
forums.raspberrypi.com
forums.raspberrypi.com
.

Dual WiFi Mode Consideration: The Pi only has one WiFi interface, so it cannot maintain an AP and connect to another WiFi simultaneously on different channels. When a user 
is entering credentials, the Pi stays in AP mode; as soon as credentials are submitted, the AP will shut down so the same radio can reconnect as a client. During that 
transition, the user’s phone will briefly lose connection (since the Pi’s hotspot goes away). This is expected behavior – the phone should automatically switch to the newly 
configured WiFi network (if it’s the same one the Pi joins) or back to cellular data. If the target WiFi network is on a different channel than the AP was, the AP drop is 
required anyway (the one-radio limitation)
forums.raspberrypi.com
. We will communicate this on the portal page (a message like “Configuring WiFi... If setup is successful, reconnect to the Pi on the new network”). If connection fails, 
our service will bring the AP back up so the user can try again.

2. Captive Portal Web Interface

The captive portal is essentially a local web application running on the Pi, which serves the configuration UI. This will be implemented as a lightweight web server (for 
example, a Python Flask app or a Node.js/Express server, depending on the development preference). Key aspects of the portal:

Network Scan and Selection UI: Upon loading the portal page, the server will scan for nearby WiFi networks and present a list of SSIDs. If using NetworkManager, we can call 
nmcli device wifi list or use NM’s D-Bus API to get scan results. Alternatively, we could invoke iwlist or iw for scanning if not using NM. The SSIDs will be displayed in a 
simple HTML form (possibly with signal strength info). The user can pick one or enter a hidden SSID manually. This list updates on page load or via a “refresh” button. (We 
might caution that scanning will temporarily disrupt the AP if using the same radio, but wifi-connect and NM handle this by caching scan results before enabling AP).

Credentials Input: The portal form will have fields for WiFi password (if required by the chosen network). We will enforce no password for open networks and show the 
appropriate input otherwise. There may also be an option for advanced config (like static IP or other WiFi settings), but by default we’ll keep it simple (DHCP client on 
the Pi for normal operation).

Target URL Configuration: Crucially, the portal will include a section to set the “Content URL” (the web page that the Pi’s browser should display in kiosk mode). This can 
be a text field where the user inputs a URL (and we might validate it or ensure it’s reachable). The chosen URL will be stored in a config file (for example, in 
/etc/pifi-portal/config.json or a similar location). If the user doesn’t set one, a default (perhaps a local info page or a PiFi Portal logo page) could be used. This 
feature allows the device to know what web content to display once it’s online.

Applying Settings: When the user submits the form (choosing SSID, entering password, and optionally the content URL), the web server backend will:

Save the content URL to the config file (if provided).

Instruct the network service to connect to the WiFi. If using NetworkManager, this could be done by creating a new NM connection profile with the SSID and passphrase (via 
nmcli dev wifi connect "SSID" password "PASS" or using the NM API). NetworkManager will handle storing the credentials securely and auto-connecting in the future
github.com
. If we were using a manual approach, the backend would instead update /etc/wpa_supplicant/wpa_supplicant.conf with a new network block and reload wpa_supplicant.

Shut down the access point services (hostapd & dnsmasq, or if NM hotspot mode was active, simply tell NM to disconnect the hotspot). This will drop the captive portal 
connection as expected.

The portal webpage can show a message like “Connecting... Please join the WiFi network YourSSID to find the device at pifi.local.” Since the AP goes off, the user will 
likely need to reconnect their phone to their normal WiFi (which hopefully is the same network the Pi is joining, for easy access).

Web Server Implementation: The web interface will be simple and mobile-friendly (since users likely connect via phone). We might use plain HTML/JS or a small single-page 
app for a better UX (e.g. using Vue or React for dynamic updates), but this is optional. The server should run as a service (e.g., pifi-portal.service) starting at boot 
listening on a port (port 80 for captive portal simplicity). The portal will only be accessible to those connected to the Pi’s AP, or on the same LAN as the Pi (when in 
client mode), which is fine. We will not require authentication for the portal page as it’s meant to be easily accessible during setup (if additional security is needed, 
one could add a simple PIN in the future).

Captive Portal Compatibility: To ensure captive portal pop-up detection works on various devices, we will host a simple generate_204 endpoint (Android uses 
connectivitycheck) or hotspot-detect.html (Apple), etc., that respond appropriately. However, a simpler method is to just intercept all HTTP and show our page. The 
nodogsplash project is an example of captive portal software; we won’t necessarily use it since we need custom UI, but we borrow the concept that any HTTP access is served 
our content
github.com
. We will likely have the Pi respond to http://connectivity-check.gstatic.com/generate_204 and similar with a 302 redirect to our portal page (or a short HTML that does 
meta refresh), prompting the device’s captive portal helper to display the UI.

3. WiFi Credential Storage and Reconnection

Once credentials are provided, PiFi Portal relies on NetworkManager (or the underlying wpa_supplicant) to handle connecting and reconnecting. NetworkManager will auto-save 
the network profile with the password securely, and by default it will try known networks in the future
github.com
. If multiple networks are saved, NM will choose the one with the strongest signal or last known. We will ensure that the NetworkManager service is enabled and that dhcpcd 
(the old Raspbian network daemon) is disabled to avoid conflicts (the install script will handle this, as Balena’s installer does
github.com
). In the event that no known network is in range (e.g., you take the Pi to a new location), the WiFi Manager Service will time out on connecting and then revert to AP 
mode, bringing up the captive portal again for new input. This makes the solution self-healing – it always provides a way to configure WiFi whenever the Pi finds itself 
disconnected. The user can also manually trigger the AP mode (for instance, by pressing a GPIO button or via a software switch on the config page) if they want to force 
reconfiguration, but auto-fallback should handle most cases.

4. Kiosk Browser Service (Chromium)

A separate component is the kiosk-mode browser that displays content on the Pi’s display. This will be implemented as a systemd service (e.g., pifi-kiosk.service) that 
launches the Chromium browser at startup, under the Pi user account with an X session. Key points:

Launching Chromium on Boot: On a Raspberry Pi OS with Desktop, we can configure an autologin to the desktop and use an autostart script to open Chromium. However, a more 
robust way is to use a minimal X session or openbox that launches Chromium in kiosk. For instance, we can install Chromium and create a systemd service that uses xinit or 
chromium-browser --kiosk. Another option is to use Chromium’s kiosk mode in a full OS environment; since the user might use the Pi for this sole purpose, running it 
standalone is fine. We’ll ensure the service depends on graphical.target or uses After=multi-user.target appropriately.

Full Screen & No Distractions: Chromium will be started with flags for kiosk mode (full-screen, no window borders), and likely --no-sandbox (if needed for Pi GPU), 
--disable-infobars, --autoplay-policy=no-user-gesture-required (if the content needs video autoplay), etc. The WebGPU/WebGL support can be ensured by flags like 
--ignore-gpu-blocklist (to force enable GPU accel)
forums.raspberrypi.com
, --enable-features=Vulkan or appropriate flag for WebGPU if available (as of 2025, WebGPU may require --enable-unsafe-webgpu depending on Chrome version). We will test 
that chrome://gpu shows WebGL2 as hardware accelerated on the Pi – on Pi 4 with proper Mesa drivers, WebGL and WebGL2 are typically hardware-accelerated
forums.raspberrypi.com
. Our installation instructions will include enabling the V3D graphics driver (on Pi 4, this is usually enabled by default on 32-bit, and on 64-bit via KMS). By doing so, 
the browser can handle rich 3D content or data visualizations as intended.

Displaying the Right Page: The kiosk service will need to know what URL to open. We will have it read the stored URL from our config (for example, a simple text file 
containing the URL). If none is set or if the device is not yet configured, it should default to the local config portal page. For example, if the portal web server is 
running on the Pi at http://192.168.4.1 (in AP mode) or http://pifi.local (mDNS name in client mode), the browser can open that. Concretely:

If WiFi is unconfigured (first boot, AP mode active), launch Chromium to http://192.168.4.1 (or a custom captive portal hostname if we set one, like http://pifi.portal as 
in some examples
github.com
). This will show the config UI on the Pi’s own screen, which is useful if the Pi has a touchscreen or if a keyboard/mouse is attached. It’s an alternate way to configure, 
besides using a phone.

If WiFi is configured and a content URL is set, launch Chromium to that URL. This could be an internet website (e.g. a dashboard or application) or a local web app. The 
service might wait until network is up before launching, to avoid showing a “cannot load” page. We can achieve that by making the service depend on network-online.target or 
by writing a tiny wrapper script that pings a site a few times before opening the browser.

Refresh/Recovery: We might include a mechanism to periodically verify the page is up (especially if network dropped) and reload or show an error. However, this is an 
advanced consideration. At minimum, if the network drops completely, our other service will kick in and potentially restart in AP mode; in such a case, we’d probably want 
to kill the browser (which was pointing to an internet URL) and reopen it to the local portal. This could be handled by the WiFi manager service (e.g., if it switches to AP 
mode, it can send a signal to restart the kiosk service in config mode). Planning these interactions ensures the user always sees a relevant screen (either their content if 
online, or the setup page if offline).

5. Configuration Page Access & Management

After initial setup, users may want to change the content URL or add another WiFi network. Rather than requiring a reset of everything, PiFi Portal keeps the configuration 
page available. When the Pi is connected to a network, a user can find it by hostname (e.g. pifi.local via mDNS, or by checking the router for its IP). Navigating to that 
address in a browser will load the same captive portal web interface (though it won’t literally be a “captive” portal since now the Pi has internet; it will just be a 
normal website in that case). From there, the user can modify settings: for example, update the default display URL, or initiate a new WiFi scan to connect to a different 
network. We will provide a section on the page for these configurations. The changes will be applied similarly (writing new values to config, updating NM profiles). If a 
user chooses to connect to a new WiFi while already on one, we might warn that the device will switch networks (and the session might cut off). But since multiple networks 
can be saved, the Pi can remember both the old and new.

No login is required to access the config page on purpose – this device is meant to be easily set up by anyone with local network access. For security, one could add an 
optional admin password in the future, but initially ease-of-use is the priority. In typical use (like setting up a digital sign or IoT gadget), the user will configure it 
and then there’s little risk of others meddling, or the device might be on an isolated network.

6. Services and Daemon Processes

All functionality will run automatically via background services:

Installer Script: We will provide a one-step installer (e.g., curl ... | bash style or a packaged script) that sets up everything. This script will install required 
packages (NetworkManager if not present, hostapd/dnsmasq if we use them, chromium, lighttpd or needed web server libs, etc.). It will also deploy our web portal files and 
set up systemd units. The user just needs to run this on a fresh Pi OS install, and after a reboot, PiFi Portal should be active. (We will caution users running it via SSH 
over WiFi, to use ethernet or console, since the WiFi will drop during AP setup
github.com
.)

pifi-manager.service: Handles WiFi status monitoring and mode switching. It could be a small Python script or even utilize balena’s wifi-connect binary. This service starts 
at boot, checks connectivity. If none, it starts AP (could call nmcli to bring up hotspot or start hostapd/dnsmasq via their own services). It might then launch or enable 
the portal webserver. If using wifi-connect, this service might simply be running that binary which encapsulates the loop of “advertise AP -> wait for credentials -> 
connect”
github.com
github.com
. After a successful connect, wifi-connect exits, and our service could then trigger the kiosk to show the content page.

pifi-portal.service: The captive portal web server (e.g. an Express or Flask app) listening on port 80 (or port 80 redirected to its port). It starts on boot as well, but 
it’s mostly idle unless the user accesses it. It should be lightweight (serving a static page and handling a couple of API calls for scan/connect). We will ensure it has 
minimal overhead.

pifi-kiosk.service: The Chromium autostart service. This might be tied to graphical target. If using a full Raspberry Pi OS Desktop, we might instead use the autostart file 
in /etc/xdg/lxsession to launch a kiosk script. But a systemd service could use xinit to start an X session with chromium if we want to also support Lite (headless) 
installations + manual X. In any case, it should launch Chromium pointing to the right URL as discussed. We also mark this service to restart on failure (so if Chromium 
crashes, it restarts).

Dependency Coordination: The manager service should probably run before the kiosk starts, to decide which page the kiosk should load. One approach: The kiosk service could 
always load a local HTML that contains logic to redirect to either config or content URL based on a small script (for instance, the local page could check an API on the Pi 
to see if WiFi is configured). However, for simplicity, we might restart or reconfigure the kiosk after WiFi config. For example, initially (no config) it opens local page; 
after user sets WiFi and URL, we can programmatically close Chromium and reopen it to the new URL (or simpler: reboot the Pi automatically after successful config, which 
then starts Chromium to the correct page with network up). A reboot after initial setup might be acceptable for user experience and ensures all services come back cleanly 
on the new network. This can be communicated (“The device will reboot to finalize configuration”). If we don’t reboot, we’d have to handle switching the Chromium page at 
runtime, which is possible via remote control (sending a command to an open Chrome instance) but not as straightforward. A reboot is cleaner given this is usually a 
one-time setup step.

Storage of Config: WiFi creds go to NetworkManager (which stores them in /etc/NetworkManager/system-connections/). The content URL and perhaps a flag for “configured” can 
be stored in a small config file (e.g., /etc/pifi-portal/config.json). The installer will create this file with defaults (maybe empty URL or a default page). The portal web 
UI edits this file. The various services will read it: the kiosk launcher reads the URL from there; the manager service might check a flag from there if needed. Keeping it 
in one place makes it easy to backup or edit manually if needed.

Installation and Setup Process

Ease of installation is a major goal, so we plan to distribute PiFi Portal as a script or package that sets up everything with minimal user effort. The steps likely 
include:

Prerequisites: A Raspberry Pi with WiFi (built-in or a supported USB dongle) running Raspberry Pi OS (ideally Bullseye/Bookworm or later). It can have a screen (if kiosk is 
desired) or can be headless for pure network config purposes. We assume the OS is relatively up-to-date (the script will run apt update && apt upgrade to ensure latest 
packages, including possibly installing NetworkManager if not already present on older OS).

Single-Line Install Script: We will provide a one-liner command in the README, for example:

curl -L https://raw.githubusercontent.com/YourUsername/PiFi-Portal/master/install.sh | sudo bash


This script will perform all necessary installation steps. These include installing required packages via apt (e.g. network-manager if needed, hostapd, dnsmasq, 
chromium-browser, lighttpd or Python3 if using Flask, etc.). It will then download or git clone the PiFi Portal repository into a directory (say /opt/pifi-portal). Config 
files (like a default hostapd.conf, dnsmasq.conf, and our own config.json) will be placed in proper locations or linked. The script will also set up systemd services by 
copying unit files from the repo into /etc/systemd/system/ and enabling them. Finally, it may reboot the system (or prompt the user to reboot) to start using the new setup.

NetworkManager configuration: If the OS uses dhcpcd by default (older releases), the script will disable dhcpcd and enable NetworkManager
github.com
. It will also ensure NetworkManager is set to manage the WiFi interface (unblocking rfkill, etc.). On Raspberry Pi OS Bookworm or newer, NM is already the default, so this 
step might be skipped or just verified.

Hostapd/Dnsmasq config (if not using NM hotspot): We will include template config files:

/etc/hostapd/hostapd.conf with SSID “PiFi-Portal” (or customizable) and a WPA2 passphrase (which could be generated or fixed). We’ll set country code, channel (default 6 or 
11, can be changed), and driver settings suitable for Pi’s WiFi.

/etc/dnsmasq.conf snippet to serve DHCP in, say, 192.168.4.0/24 range and set DNS to Pi’s IP. Possibly we’ll use address=/#/192.168.4.1 in dnsmasq to resolve all domains to 
itself for captive portal.

We’ll configure a systemd service hostapd and dnsmasq to be controlled by our manager (or only started when needed). If using NM’s built-in, we may skip these and let NM 
handle AP mode (but many find hostapd reliable for custom scenarios, so we might stick with it but still use NM for station mode connectivity).

Web UI files: The installer will put the web portal files (HTML/JS and server script) perhaps in /opt/pifi-portal/web/ for the static files, and install the server app (if 
Python, maybe as a systemd service running a gunicorn or just Flask with waitress; if Node, as a small Node service). It will open the necessary port (80) by adjusting UFW 
or iptables if a firewall is enabled.

Chromium autostart: The script will create the kiosk service unit. For example, a unit file that might execute: xinit /usr/bin/chromium-browser --no-sandbox --kiosk 
"http://localhost:8000" --user-data-dir=/home/pi/.config/chromium (assuming our portal runs on 8000 and we forward 80). We’ll ensure this runs as the pi user with display 
environment set (like DISPLAY=:0). If the Raspberry Pi OS desktop is installed, we might integrate with its autostart instead for simplicity. Otherwise, we’ll install a 
minimal X if needed.

Enable Services: The installer enables pifi-manager.service, pifi-portal.service, and pifi-kiosk.service to start on boot (and possibly disables conflicting services like 
wpa_supplicant if NM handles it, or disables any existing autologin if we do our own, etc).

Completion: Once installation is done and the Pi reboots, it should either come up in AP mode (if no WiFi configured yet) or connect to a remembered network if this is not 
the first run. The user can then follow the standard usage: connect to “PiFi-Portal” WiFi on their phone to configure, or if already configured, visit the Pi’s interface.

We will provide documentation in the repo for troubleshooting (for example, if the AP doesn’t show up, instruct to check hostapd status
github.com
, etc., and also note that some wireless dongles don’t support AP mode if using external adapters
github.com
).

Usage Workflow (Example Scenario)

Initial Power-Up (No WiFi Known): You power on the Raspberry Pi with PiFi Portal installed. The device finds no known WiFi connection, so within a minute it launches its 
own hotspot. You see an SSID like “PiFi-Portal Setup” on your phone’s WiFi list. You connect to it (password might be displayed on the device or in documentation, e.g. 
“pifipassword”). Your phone indicates “Sign into network” and automatically shows the captive portal page. There, you find a list of WiFi networks. You tap your home WiFi 
“MyHomeNetwork” and enter the password. You also see a field for “Content URL” – you enter https://weather-dashboard.example.com (for instance, if you want the Pi to 
display a weather dashboard). You submit the form.

Switching to Client Mode: The Pi shuts down the AP as it transitions to connect to “MyHomeNetwork” with the provided credentials. Your phone momentarily loses connection to 
PiFi’s network. After a short wait, the Pi connects to your home WiFi. The credentials are saved in its system. The captive portal on your phone disappears since that 
network is gone. Now your phone might reconnect to your normal WiFi (which is the same “MyHomeNetwork”). You can now reach the Pi on the home network. For example, you can 
ping or visit http://pifi.local and you will see the PiFi Portal config page (this time served over your LAN). The Pi might also automatically reboot after setup (as a 
design choice) – once it comes back, it’s on your WiFi.

Kiosk Mode in Action: Meanwhile, if the Pi has an HDMI display attached, after the reboot (or immediately if we didn’t reboot), it launches Chromium and because WiFi is now 
connected, it loads the weather-dashboard.example.com page in full-screen. You now see the live weather dashboard on the Pi’s screen. WebGL content on that site (say, a 3D 
globe or animated graph) runs smoothly because we enabled the GPU support in Chromium. The Pi is now functioning as a kiosk device.

Reconfiguration Later: A week later, you take the Pi to your friend’s house. Your home network is no longer in range. The Pi boots up and after failing to find 
“MyHomeNetwork”, it automatically falls back to AP mode again. Your friend connects to the “PiFi-Portal” SSID, goes through the captive portal, and adds their WiFi 
“FriendWifi” and password. The Pi switches to that and now joins their network. It still remembers your home network too. The content URL remains set to the weather 
dashboard (unless changed), so once online at your friend’s house, it continues to load that same URL on its display. If you wanted to change the URL or any setting, you or 
your friend can open a browser to pifi.local (resolves to the Pi’s new IP via mDNS) and adjust the configuration without needing to reconnect to the AP.

Manual Access to Config: If the Pi is online and you want to tweak settings (say change the kiosk URL), just visit the Pi’s IP or hostname from any device on the same WiFi. 
You’ll see the PiFi Portal page again (it might not pop up automatically since there’s internet, but you navigate there directly). You edit the URL field and hit save. The 
backend updates the config and signals the kiosk browser to load the new URL (perhaps by restarting the browser or via a websocket message to refresh – an enhancement we 
can add). Within seconds, the Pi’s screen now shows the new content.

This workflow demonstrates the full lifecycle: initial setup, using remembered networks, and updating configuration, all without needing keyboard/monitor attached for 
networking setup and without complex commands. It’s meant to be as friendly as configuring a smart home device.

Technical Considerations and Alternatives

Use of Existing Solutions: Our plan is inspired by existing projects like balena’s WiFi Connect and RaspAP. WiFi Connect already provides the core captive portal WiFi setup 
functionality via NetworkManager
github.com
github.com
. In fact, one implementation approach is to incorporate WiFi Connect’s binary or library directly, which would save development time on the network handling. RaspAP, on 
the other hand, is a full-featured router/web-gui for Pi AP mode
forums.raspberrypi.com
, but it might be overkill for our needs and is not focused on captive portal for client WiFi selection (it’s more for turning Pi into a permanent hotspot). Nonetheless, we 
will ensure our design is compatible with the Raspberry Pi networking tools and consider leveraging proven components (for example, using hostapd + dnsmasq config similar 
to RaspAP’s defaults). The PiFi Portal project will differentiate itself by seamlessly integrating the captive portal WiFi onboarding with a kiosk launcher, in a very 
automated fashion.

Captive Portal without Internet: One thing to note: captive portals typically don’t have upstream internet while in setup mode (in our case, the Pi’s AP has no internet 
until the Pi connects as a client). This can cause some devices to drop the connection after setup due to “No internet”. We mitigate this by instructing users to “Use this 
network anyway” if needed
github.com
. Usually, iOS and Android allow staying on the network if the user chooses. Once the Pi connects to the real WiFi, the device will switch over to that internet-bearing 
network, so it’s fine.

WebGPU support: As WebGPU is cutting-edge, we will test if Chromium on Pi (especially with newer Mesa drivers) can enable it. If not fully supported, we will document how 
to use the --enable-unsafe-webgpu flag, noting that it might be experimental. Since the question specifically asks for WebGPU, we assume by 2025 the support is available in 
Chromium for Linux/ARM. Our project will aim to have the latest Chromium installed (perhaps using the Raspberry Pi OS repository or a flatpak if needed for newer version).

Name and Repository: The project will be named PiFi Portal (a blend of Pi and WiFi Portal). This name is concise and reflects the function: turning the Pi into a WiFi 
portal. We will create a repository (e.g., username/pifi-portal) containing the install script, source code for the web interface (HTML/JS and server code), service unit 
files, and any documentation. The README will clearly explain usage and have diagrams of the architecture.

License and Contributions: We plan to make it open-source (perhaps MIT or Apache licensed), so the community can adapt it. Users can easily install it, and advanced users 
can tweak settings (like customizing the captive portal page or adjusting the list of known networks).

In summary, PiFi Portal provides a comprehensive, easy-to-use system to manage WiFi on a Raspberry Pi via a captive portal and to run a full-screen kiosk once connected. 
With an emphasis on one-step installation and robust services, it turns a Raspberry Pi into a portable, network-flexible device — perfect for applications where 
non-technical end-users need to get the device online and view content without hassle. By combining existing reliable solutions (hostapd/dnsmasq or NetworkManager, and 
Chromium’s kiosk capabilities) with a user-friendly web interface, PiFi Portal fulfills the goal of “any Pi, anywhere, easily configurable.” The result will be a polished 
tool that greatly simplifies WiFi setup for Pi-based gadgets while giving the user control over the device’s displayed content.

Sources:

Raspberry Pi captive portal for WiFi configuration concept (forum discussion)
forums.raspberrypi.com

Balena WiFi Connect documentation – explaining captive portal network selection and connection flow
github.com
github.com

Raspberry Pi AP/captive portal setup notes – hostapd, dnsmasq, and NetworkManager on recent OS
github.com
github.com

Enabling WebGL on Raspberry Pi’s Chromium (hardware acceleration flags)
forums.raspberrypi.com
