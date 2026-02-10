# Task: ESP32 SoftAP Bridge Firmware

## Objective

Create a minimal standalone ESP-IDF application that runs an ESP32 as a WiFi access point, allowing connected clients to communicate with each other. This is needed because the mobile hotspot being used for development has client isolation enabled, preventing the lighthouse ESP32 from reaching the MQTT broker running on the development laptop.

## Context

- The lighthouse project already has a working WiFi provisioning component located at `components/wifi_provisioning/`
- That component includes SoftAP functionality, DNS server, and HTTP server for captive portal
- This task requires extracting and simplifying only the SoftAP portion into a standalone project
- The second ESP32 will act purely as a network bridge—no HTTP server, no captive portal, no configuration interface

## Requirements

**Functional:**
- ESP32 starts in AP mode immediately on boot
- SSID: `lighthouse-bridge` (hardcoded)
- Password: open network (no password) or simple WPA2 key like `devbridge`
- Connected clients must be able to communicate with each other (no AP isolation)
- DHCP server assigns IPs in `192.168.4.x` range (ESP-IDF default behavior)

**Non-functional:**
- Absolute minimum code—no features beyond basic AP functionality
- No HTTP server
- No DNS server
- No captive portal
- No NVS storage
- No configuration interface
- Single source file if possible

## Reference Implementation

The existing lighthouse project's WiFi provisioning component contains relevant code:

| File | Relevant Section |
|------|------------------|
| `components/wifi_provisioning/wifi_http_server.c` | AP startup sequence using `esp_wifi_set_mode(WIFI_MODE_AP)` and `esp_wifi_set_config()` |
| `components/wifi_provisioning/wifi_provisioning.c` | WiFi event handling and initialization |

**Key ESP-IDF APIs to use:**
- `esp_netif_create_default_wifi_ap()` — creates network interface for AP
- `esp_wifi_set_mode(WIFI_MODE_AP)` — sets WiFi to access point mode
- `esp_wifi_set_config(WIFI_IF_AP, &wifi_config)` — configures AP parameters
- `esp_wifi_start()` — starts the WiFi driver

**Reference documentation:**
- ESP-IDF Programming Guide: Wi-Fi Driver → AP Mode: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/wifi.html#esp32-wi-fi-ap-mode
- ESP-IDF example: `examples/wifi/getting_started/softAP`

## Project Structure

```
softap_bridge/
├── CMakeLists.txt
├── main/
│   ├── CMakeLists.txt
│   └── main.c
└── sdkconfig.defaults (optional)
```

## Implementation Notes

1. **Do not copy the entire wifi_provisioning component** — extract only what's needed for AP mode
2. **DHCP server is automatic** — ESP-IDF enables it by default when AP mode starts
3. **No need for event handling beyond basic startup** — the AP just needs to run; no connection callbacks required
4. **Client-to-client communication works by default** — ESP32 SoftAP does not isolate clients unless explicitly configured to do so

## Configuration Constants

```c
#define AP_SSID         "lighthouse-bridge"
#define AP_PASS         ""                    // Open network, or use "devbridge" for WPA2
#define AP_CHANNEL      1
#define AP_MAX_CONN     4
```

## Expected Behavior

1. Flash firmware to second ESP32
2. Power on
3. Serial log shows: `AP started. SSID: lighthouse-bridge`
4. Development laptop connects to `lighthouse-bridge`, receives IP `192.168.4.2`
5. Lighthouse ESP32 connects to `lighthouse-bridge`, receives IP `192.168.4.3`
6. Laptop runs MQTT broker on `192.168.4.2:1883`
7. Lighthouse successfully connects to broker

## Verification

```bash
# From laptop connected to the bridge AP:
ping 192.168.4.1    # Should reach the bridge ESP32
ping 192.168.4.3    # Should reach the lighthouse ESP32 (once connected)
```

## Out of Scope

- Internet connectivity / NAT
- Persistent configuration
- Web interface
- OTA updates
- Any lighthouse-specific functionality
