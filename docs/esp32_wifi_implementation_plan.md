# ESP32 WiFi Station Mode Setup - Research Document

## Overview
To connect your ESP32 to a local network via WiFi, you need to configure it in **Station (STA) mode**. This document covers the hardware requirements, software initialization sequence, and critical setup steps.

---

## Hardware Requirements

### Your Current Setup
- **ESP32 SoC**: Dual-core Xtensa LX6 @ 160-240 MHz (from datasheet v5.2)
- **WiFi Capability**: 802.11 b/g/n @ 2.4 GHz, up to 150 Mbps (datasheet section on Wi-Fi features)
- **Development Board**: Hornaxys devboard (with integrated antenna)
- **sdkconfig Status**: WiFi is already enabled in your project:
  - `CONFIG_ESP_WIFI_ENABLED=y` ✓
  - `CONFIG_ESP32_WIFI_NVS_ENABLED=y` ✓ (Non-Volatile Storage for WiFi config)
  - `CONFIG_TCPIP_TASK_STACK_SIZE=3072` ✓ (adequate for WiFi stack)

**Note**: Your sdkconfig shows WiFi is properly configured. The datasheet (Section 3.2.1 on Wi-Fi) confirms the ESP32 has dual-core architecture supporting simultaneous WiFi operations, which is crucial for your RFID + WiFi task management.

---

## ESP-IDF WiFi Architecture

### Key Components

#### 1. **lwIP & ESP-NETIF** (TCP/IP Stack)
- lwIP is the underlying TCP/IP stack
- ESP-NETIF provides abstraction layer between WiFi driver and lwIP
- Managed automatically when you initialize the event loop
- **Reference**: ESP-IDF v5.5.1 documentation on Wi-Fi Driver

#### 2. **Event Loop System** (FreeRTOS Event Groups)
The WiFi driver is event-driven. Key events you'll handle:
- `WIFI_EVENT_STA_START` - WiFi driver initialized
- `WIFI_EVENT_STA_CONNECTED` - Connected to AP
- `WIFI_EVENT_STA_DISCONNECTED` - Lost connection
- `IP_EVENT_STA_GOT_IP` - DHCP assigned IP address

#### 3. **NVS (Non-Volatile Storage)**
WiFi configuration is stored in flash so it persists across power cycles. Your sdkconfig already enables this with `CONFIG_ESP32_WIFI_NVS_ENABLED=y`.

---

## Initialization Sequence

### Step 1: Initialize NVS Flash
```
nvs_flash_init()
```
Must be called before any WiFi operations. Stores WiFi credentials and configuration persistently.

### Step 2: Initialize Network Interface & Event Loop
```
esp_netif_init()                          // Initialize TCP/IP stack
esp_event_loop_create_default()           // Create event task (from ESP-IDF Event Library)
esp_netif_create_default_wifi_sta()       // Create default WiFi STA interface
```

### Step 3: Initialize WiFi Driver
```
wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();  // Use macro for default values
esp_wifi_init(&cfg)
```

The `WIFI_INIT_CONFIG_DEFAULT()` macro sets safe defaults. Critical note from ESP-IDF documentation: always initialize all struct fields to zero/default values to ensure forward compatibility when ESP-IDF is updated.

### Step 4: Set WiFi Mode
```
esp_wifi_set_mode(WIFI_MODE_STA)          // Station mode (connect to AP)
```

Other modes available (from ESP-IDF):
- `WIFI_MODE_AP` - Access Point (ESP32 acts as router)
- `WIFI_MODE_APSTA` - Both simultaneously
- `WIFI_MODE_NAN` - WiFi Aware Networking

### Step 5: Register Event Handlers
```
esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler, NULL)
esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler, NULL)
```

These register callbacks for WiFi and IP events. Your callbacks handle the "rainy day scenarios" mentioned in ESP-IDF documentation (connection failures, timeouts, disconnects).

### Step 6: Configure Station Settings
```
wifi_config_t wifi_config = {
    .sta = {
        .ssid = "YOUR_SSID",
        .password = "YOUR_PASSWORD",
        .bssid_set = 0,              // Auto-select AP (not critical)
        .channel = 0,                 // Auto-scan (0 = no preference)
    }
};
esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
```

### Step 7: Start WiFi & Connect
```
esp_wifi_start()                          // Activates WiFi driver
esp_wifi_connect()                        // Initiates connection to AP
```

---

## Event Handler Implementation

Your event handler will receive WiFi and IP events. The handler must:
1. Check event type and source
2. Update state (using EventGroups or similar)
3. **Avoid blocking operations** - Event task handles WiFi performance

### Critical "Rainy Day" Scenarios (per ESP-IDF docs)

#### Disconnection Handling
Event: `WIFI_EVENT_STA_DISCONNECTED`
- Contains disconnect reason code
- Must implement retry logic with maximum attempt limits
- Don't scan and connect simultaneously (ESP-IDF will abort the scan)

#### Handshake Timeout
Event: `WIFI_EVENT_STA_DISCONNECTED` with reason `WIFI_REASON_HANDSHAKE_TIMEOUT`
- Indicates 3/4 EAPOL not received within timeout
- Typically means authentication failure (wrong password or AP doesn't support your auth mode)

#### IP Assignment Failure
Event: `IP_EVENT_STA_GOT_IP` never arrives
- DHCP failed
- Check AP is running DHCP server
- Alternatively, set static IP with `esp_netif_set_ip_info()`

---

## Datasheet References

**ESP32 Series Datasheet v5.2** (from your project files):

1. **Wi-Fi Features** (Section on Wi-Fi):
   - 802.11b/g/n support
   - Up to 150 Mbps throughput
   - Supports WPA, WPA2, WPA3 security
   - Automatic Beacon Monitoring (hardware TSF)
   - Multi-interface support (4 virtual Wi-Fi interfaces)

2. **CPU & Memory** (Section 2.2):
   - Dual-core Xtensa 32-bit LX6 @ 240 MHz max
   - 160 MHz default (your config: `CONFIG_ESP32_DEFAULT_CPU_FREQ_160=y`)
   - 520 KB SRAM internal memory
   - **Note**: WiFi task runs on Core 0 (per your sdkconfig: `CONFIG_ESP32_WIFI_TASK_PINNED_TO_CORE_0=y`)

3. **Power Consumption**:
   - WiFi RX: ~80 mA
   - WiFi TX (802.11b, 20dBm): ~140 mA
   - Important for PoE planning in final deployment

---

## Your sdkconfig Status Check

✓ `CONFIG_ESP_WIFI_ENABLED=y`
✓ `CONFIG_ESP32_WIFI_NVS_ENABLED=y` - Persists WiFi config
✓ `CONFIG_TCPIP_TASK_STACK_SIZE=3072` - Sufficient for TCP/IP
✓ `CONFIG_ESP32_WIFI_TASK_PINNED_TO_CORE_0=y` - WiFi on core 0 (good for separating RFID on core 1)
✓ `CONFIG_TCP_SND_BUF_DEFAULT=5760` - Adequate TX buffer for MQTT
✓ `CONFIG_TCP_RECVMBOX_SIZE=6` - RX buffer size

**No additional sdkconfig changes needed** for basic WiFi functionality.

---

## Headers & Dependencies

Required ESP-IDF headers:
```c
#include "nvs_flash.h"           // NVS initialization
#include "esp_netif.h"           // Network interface
#include "esp_event.h"           // Event loop library
#include "esp_wifi.h"            // WiFi driver API
#include "esp_log.h"             // Logging (already in your code)
```

Project CMakeLists.txt requires:
```cmake
idf_component_require(esp_wifi)  # Built-in component
```

---

## Testing Requirements

Before proceeding to MQTT integration:

1. **Verify SSID/Password**: Ensure they're correctly entered
2. **AP Accessibility**: ESP32 should be within range and same band (2.4 GHz)
3. **Event Loop**: All events must be properly handled
4. **IP Assignment**: Confirm `IP_EVENT_STA_GOT_IP` is received
5. **Connection Stability**: WiFi should maintain connection for 60+ seconds
6. **Logs**: Enable WiFi logging with `esp_log_level_set("wifi", ESP_LOG_DEBUG)` for troubleshooting

---

## Known Pitfalls

1. **NVS Not Initialized**: Will cause `ESP_ERR_NVS_NOT_INITIALIZED` - must call `nvs_flash_init()` first
2. **Blocking Operations in Event Handler**: Will degrade WiFi performance - use queues instead
3. **WEP/WPA Security**: Deprecated per IEEE 802.11-2016, use WPA2/WPA3 only
4. **Concurrent Scanning + Connecting**: ESP-IDF will abort the scan - sequence them
5. **Missing Max Retry Logic**: Without it, infinite reconnection attempts will drain power
6. **Event Loop Not Created**: All event handlers will silently fail

---

## Task Separation Strategy for Your Project

Your dual-core architecture allows:
- **Core 0**: WiFi driver task (locked per `CONFIG_ESP32_WIFI_TASK_PINNED_TO_CORE_0=y`)
- **Core 1**: Your RFID reader task + MQTT publishing task

This separation prevents WiFi operations from blocking RFID detection. Set your UART reader task priority lower than WiFi to avoid starvation.

---

## References

1. **Espressif ESP32 Datasheet v5.2**: Wi-Fi features, CPU architecture, power consumption specs
2. **ESP-IDF v5.5.1 Wi-Fi Driver Guide**: https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/wifi.html
3. **ESP-IDF Event Loop Documentation**: Event handler patterns and best practices
4. **Official Example**: `esp-idf/examples/wifi/getting_started/station/` in your ESP-IDF installation
5. **IEEE 802.11-2016**: WiFi protocol specifications (deprecated auth modes)

---

## Next Steps

1. Create `wifi_manager.h` and `wifi_manager.c` with initialization functions
2. Implement event handler with proper error recovery
3. Add SSID/password configuration (hardcoded for testing, move to menuconfig later)
4. Test basic connection and IP assignment
5. Add logging to verify event sequence
6. Once stable, integrate with your UART reader in separate FreeRTOS task
