# WiFi Provisioning System - In-Depth Implementation Plan

## Document Overview

This plan describes the step-by-step implementation of a WiFi provisioning system for the ESP32 lighthouse attendance tracker. The system is designed to **build incrementally on existing firmware** without disrupting current RFID functionality. Each component integrates with established code patterns (button debouncing, GPIO state management, task-based architecture).

**Key Principle:** Additions are modular and isolated. Existing code in `my_project.c` and `uart_reader.c` remains untouched; new functionality is added through separate modules that integrate at clean boundaries.

---

## Part 1: Core Architecture & Integration Points

### 1.1 System Overview

```
[ESP32 Boot]
    ↓
[Check settings partition for "configured" flag]
    ├→ NOT configured → Wait for BUTTON2 long-press (5s)
    │                   ↓
    │                   [Setup Mode]
    │                   - Enter AP mode
    │                   - Start HTTP provisioning server
    │                   - LED blinks at 1s interval
    │                   - User configures WiFi
    │                   - Settings encrypted & saved to partition
    │                   - Hard reboot
    │
    └→ Configured → Load & decrypt credentials
                   ↓
                   [Try WiFi connection (STA mode)]
                   ├→ Success → Normal operation (existing code)
                   └→ Failure → Offline mode (existing code)
```

### 1.2 Firmware Integration Points

**Existing code that integrates with WiFi provisioning:**

1. **Button handling in `my_project.c` (lines 147-201)**
   - `process_buttons()` runs in main loop every 10ms
   - Currently handles BUTTON2 short-press for statistics
   - **Integration point:** Extend debounce logic to detect 5-second press
   - No modification to existing short-press behavior

2. **LED status in `my_project.c` (lines 99-133)**
   - LED1_PIN (GPIO5) for WiFi status (already designated)
   - Currently controlled by RFID scanning state
   - **Integration point:** Add LED blinking task for setup mode
   - Setup blinking takes precedence over RFID state during AP mode

3. **Main task in `my_project.c` (lines 239-249)**
   - Runs at 10ms intervals in main loop
   - Processes buttons and PIR
   - **Integration point:** Call WiFi status check function here (minimal overhead)

4. **RFID reader in `uart_reader.c`**
   - Runs independently in background task
   - **Integration point:** No modification needed; can coexist with WiFi provisioning

### 1.3 Module Structure

The WiFi provisioning system consists of 4 new modules:

```
wifi_provisioning/
├── wifi_provisioning.h          (Public API & types)
├── wifi_provisioning.c          (Core state machine & event handling)
├── wifi_settings_storage.h      (Partition I/O & encryption)
├── wifi_settings_storage.c      (Implementation)
├── wifi_http_server.h           (HTTP server interface)
└── wifi_http_server.c           (HTTP handler & HTML serving)
```

Each module is independent and can be tested separately.

---

## Part 2: Detailed Component Specifications

### 2.1 WiFi Settings Storage Module

**File: `wifi_settings_storage.h` & `wifi_settings_storage.c`**

**Purpose:** Manage encrypted storage of WiFi credentials in dedicated NVS partition.

#### Partition Layout (16KB recommended)

```
Offset  Size    Field                   Type
------  ------  --------------------    --------
0       1       configured flag         uint8_t (0=unconfigured, 1=configured)
1       1       [reserved]              
2-33    32      encrypted SSID          uint8_t[32]
34-97   64      encrypted password      uint8_t[64]
98-127  30      reserved for MQTT       (future)
128     16384   [free]                  

Total: 16384 bytes
```

#### Data Structures

```c
// wifi_settings_storage.h

typedef struct {
    char ssid[32];              // Plaintext SSID (RAM only)
    char password[64];          // Plaintext password (RAM only)
    uint8_t configured;         // Flag from partition
} wifi_credentials_t;

typedef enum {
    WIFI_STORAGE_OK = 0,
    WIFI_STORAGE_NOT_FOUND = 1,
    WIFI_STORAGE_CORRUPT = 2,
    WIFI_STORAGE_ENCRYPTION_ERROR = 3,
    WIFI_STORAGE_WRITE_ERROR = 4,
} wifi_storage_error_t;
```

#### Public API

```c
/**
 * Initialize NVS partition for WiFi settings
 * Opens nvs_settings partition, prepares for read/write
 * 
 * @return WIFI_STORAGE_OK on success
 */
wifi_storage_error_t wifi_settings_init(void);

/**
 * Check if device has been configured
 * Reads "configured" flag from partition without decryption
 * 
 * @return true if configuration complete, false otherwise
 */
bool wifi_settings_is_configured(void);

/**
 * Load WiFi credentials from partition
 * Only call if wifi_settings_is_configured() returns true
 * Decrypts credentials using device-specific key
 * Credentials stored in RAM only (not persistent)
 * 
 * @param creds Output: decrypted credentials
 * @return WIFI_STORAGE_OK on success
 */
wifi_storage_error_t wifi_settings_load(wifi_credentials_t* creds);

/**
 * Save WiFi credentials to partition
 * Encrypts credentials before writing
 * Sets "configured" flag to 1
 * 
 * IMPORTANT: Caller must trigger esp_restart() after this
 * Partition is written but not reloaded until reboot
 * 
 * @param ssid WiFi network name (max 31 chars, null-terminated)
 * @param password WiFi password (max 63 chars, null-terminated)
 * @return WIFI_STORAGE_OK on success
 */
wifi_storage_error_t wifi_settings_save(const char* ssid, const char* password);

/**
 * Factory reset - clear configuration
 * Sets "configured" flag to 0, erases credentials
 * Used for testing and device reset scenarios
 * 
 * IMPORTANT: Caller must trigger esp_restart() after this
 * 
 * @return WIFI_STORAGE_OK on success
 */
wifi_storage_error_t wifi_settings_factory_reset(void);

/**
 * Get last error description
 * Useful for debugging storage issues
 * 
 * @return Human-readable error string
 */
const char* wifi_settings_error_to_string(wifi_storage_error_t err);
```

#### Implementation Details

**Encryption approach:**
- Algorithm: AES-128-ECB (simple, hardware-accelerated on ESP32)
- Key: Device-specific 16-byte key (pre-computed, flashed with firmware)
- IV: Not used (ECB mode for simplicity; credentials are 96 bytes, encrypted in blocks)
- Reference: ESP32 TRM Section 14 (AES Accelerator)

**Key storage:**
- Stored as const array in flash
- Part of firmware binary, not exposed at runtime
- Different per device build
- Suggestion: Define in `sdkconfig.defaults` or custom header

**Partition initialization:**
```c
// In partitions.csv (project root):
nvs_settings,  data,  nvs,     0x9000,  0x4000,   encrypted
```

Note: `encrypted` parameter enables ESP32 Flash Encryption if enabled globally.

**Read process:**
1. Open nvs_settings partition with nvs_open
2. Read uint8_t at offset 0 (configured flag)
3. If configured:
   - Read encrypted SSID (bytes 2-33)
   - Read encrypted password (bytes 34-97)
   - Decrypt both using AES-128
   - Return plaintext credentials

**Write process:**
1. Validate inputs (SSID non-empty, password 8-63 chars)
2. Encrypt SSID (pad to 32 bytes)
3. Encrypt password (pad to 64 bytes)
4. Write encrypted data to partition
5. Write configured flag = 1
6. Flush and close partition
7. Return to caller for esp_restart()

**Error handling:**
- Return specific enum values
- Log errors but don't panic
- Allow graceful fallback

#### Encryption/Decryption Helper Functions (Internal)

```c
// Internal only - not exposed in header
static void aes_encrypt_block(const uint8_t* plaintext, uint8_t* ciphertext, size_t len);
static void aes_decrypt_block(const uint8_t* ciphertext, uint8_t* plaintext, size_t len);
```

Use mbedTLS for AES operations. Include:
```c
#include "mbedtls/aes.h"
```

---

### 2.2 WiFi Provisioning Core Module

**File: `wifi_provisioning.h` & `wifi_provisioning.c`**

**Purpose:** State machine managing setup mode, WiFi connection attempts, and mode transitions.

#### State Machine Definition

```c
// wifi_provisioning.h

typedef enum {
    WIFI_STATE_UNCONFIGURED = 0,      // No config; waiting for user action
    WIFI_STATE_SETUP_REQUESTED = 1,   // User pressed BUTTON2 for 5s
    WIFI_STATE_AP_ACTIVE = 2,         // Broadcasting AP, serving provisioning page
    WIFI_STATE_CONNECTING = 3,        // Attempting STA connection with new creds
    WIFI_STATE_CONNECTED = 4,         // Successfully connected to network
    WIFI_STATE_OFFLINE = 5,           // Connection failed, running offline
} wifi_state_t;

typedef enum {
    WIFI_EVENT_NONE = 0,
    WIFI_EVENT_CONFIG_LOADED = 1,      // Credentials loaded from partition
    WIFI_EVENT_SETUP_BUTTON_PRESSED = 2, // User triggered setup mode
    WIFI_EVENT_CREDS_SUBMITTED = 3,    // Provisioning form submitted
    WIFI_EVENT_CONNECTION_SUCCESS = 4, // STA connected
    WIFI_EVENT_CONNECTION_FAILED = 5,  // STA connection timeout
    WIFI_EVENT_REBOOT_REQUESTED = 6,   // User clicked restart button
} wifi_event_t;
```

#### Data Structures

```c
typedef struct {
    wifi_state_t current_state;
    wifi_event_t pending_event;
    uint32_t state_enter_time_ms;
    uint32_t connection_timeout_ms;    // Configurable, default 10000
    
    // Provisional credentials during setup
    char pending_ssid[32];
    char pending_password[64];
    
    // LED control
    uint32_t led_blink_interval_ms;
    uint32_t last_led_toggle_ms;
    uint8_t led_state;                 // 0 or 1
} wifi_provisioning_state_t;
```

#### Public API

```c
/**
 * Initialize WiFi provisioning system
 * Call this early in app_main(), before RFID initialization
 * Checks partition, determines initial state
 * 
 * @param led_pin GPIO pin for WiFi status LED (LED1_PIN)
 * @param connection_timeout_ms How long to wait for WiFi connection (default 10000)
 * @return ESP_OK on success
 */
esp_err_t wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms);

/**
 * Report that BUTTON2 was held for 5 seconds
 * Called from process_buttons() in main_task
 * Initiates setup mode
 * 
 * NOTE: This function triggers esp_restart() internally
 * Code after calling this will not execute
 */
void wifi_provisioning_setup_button_pressed(void);

/**
 * Process WiFi provisioning state machine
 * Call from main loop (main_task) every ~10ms
 * Handles LED blinking, connection attempts, state transitions
 * 
 * Low CPU cost: mostly checks flags, minimal WiFi operations
 */
void wifi_provisioning_process(void);

/**
 * Check current WiFi state
 * Useful for main application to decide behavior
 * 
 * @return Current state
 */
wifi_state_t wifi_provisioning_get_state(void);

/**
 * Check if device is ready for normal operation
 * True when either:
 *   - WiFi is connected (WIFI_STATE_CONNECTED)
 *   - Running offline (WIFI_STATE_OFFLINE)
 * 
 * @return true if RFID system should start
 */
bool wifi_provisioning_is_ready(void);

/**
 * Get description of current state
 * For logging/debugging
 * 
 * @return String like "CONNECTED", "OFFLINE", "AP_ACTIVE", etc.
 */
const char* wifi_provisioning_state_to_string(wifi_state_t state);
```

#### State Transition Logic

**Transition table:**

```
Current State       | Event                    | Next State           | Action
-----------------  | ----------------------   | -------------------- | -------
UNCONFIGURED        | boot (configured=false)  | UNCONFIGURED         | Wait
UNCONFIGURED        | SETUP_BUTTON_PRESSED     | SETUP_REQUESTED      | Reboot
SETUP_REQUESTED     | (post-reboot)            | AP_ACTIVE            | Start AP
AP_ACTIVE           | CREDS_SUBMITTED          | CONNECTING           | Test WiFi
CONNECTING          | CONNECTION_SUCCESS       | CONNECTED            | Done
CONNECTING          | CONNECTION_FAILED        | AP_ACTIVE            | Retry form
CONNECTED           | (normal)                 | CONNECTED            | Operate
AP_ACTIVE           | (normal, no action)      | AP_ACTIVE            | Serve AP
UNCONFIGURED        | boot (configured=true)   | CONNECTING           | Load creds
CONNECTING          | (post-boot)              | CONNECTED/OFFLINE    | Save state
```

#### Implementation Notes

**Setup mode flow (high-level):**

1. **Boot detection:** `app_main()` calls `wifi_provisioning_init()`
2. **State check:** Reads partition for configured flag
3. **Wait state:** If unconfigured, stays in UNCONFIGURED
4. **Button press:** `process_buttons()` detects 5s press, calls `wifi_provisioning_setup_button_pressed()`
5. **Reboot:** Function triggers `esp_restart()`
6. **Next boot:** Post-reboot, firmware sets internal flag to "setup requested"
7. **AP start:** HTTP server module starts AP with compile-time SSID/password
8. **Provisioning:** HTTP server handles credential submission
9. **Connection test:** State machine attempts WiFi connection
10. **Save & reboot:** On success, settings saved to partition, `esp_restart()` called

**Why reboot to enter setup?**
- Clean state, no interference from existing tasks
- Allows state machine to detect setup mode reliably
- Prevents accidental entry into setup during normal operation

**LED control during setup:**
- State machine toggles LED every 1 second (1000ms)
- `wifi_provisioning_process()` handles toggling in main loop
- No separate LED task needed

---

### 2.3 WiFi HTTP Server Module

**File: `wifi_http_server.h` & `wifi_http_server.c`**

**Purpose:** Minimal HTTP server providing provisioning webpage and API.

#### Public API

```c
/**
 * Start HTTP server in AP mode
 * Call only when in AP_ACTIVE state
 * Serves provisioning page and handles credential submission
 * 
 * @param ap_ssid SSID of access point (compile-time constant)
 * @param ap_password Password of access point (compile-time constant)
 * @return ESP_OK on success
 */
esp_err_t wifi_http_server_start(const char* ap_ssid, const char* ap_password);

/**
 * Stop HTTP server
 * Called when exiting AP mode
 * 
 * @return ESP_OK on success
 */
esp_err_t wifi_http_server_stop(void);

/**
 * Callback: Called when user submits provisioning form
 * Signature: void callback(const char* ssid, const char* password)
 * 
 * Implementation should:
 *   - Store credentials in wifi_provisioning module
 *   - Trigger WiFi connection attempt
 */
typedef void (*wifi_credentials_callback_t)(const char* ssid, const char* password);

/**
 * Register callback for credential submission
 * Must be called before wifi_http_server_start()
 * 
 * @param callback Function to call when credentials submitted
 */
void wifi_http_server_set_credentials_callback(wifi_credentials_callback_t callback);

/**
 * Report connection test result back to webpage
 * Server sends response to browser showing success/failure
 * User can then click restart button or retry
 * 
 * @param success true if WiFi connection succeeded
 * @param error_message Human-readable error if success=false
 */
void wifi_http_server_set_connection_result(bool success, const char* error_message);

/**
 * Get current HTTP server status
 * 
 * @return true if server is running
 */
bool wifi_http_server_is_running(void);
```

#### HTTP Endpoints

**GET `/`**
- Returns provisioning webpage (HTML form)
- Form fields:
  - `ssid` (text input, max 32 chars)
  - `password` (password input, 8-63 chars)
  - Submit button

**POST `/configure`**
- Receives: form data with `ssid` and `password`
- Returns: JSON response with status

Response format:
```json
{
  "status": "testing",
  "message": "Attempting connection..."
}
```

After connection test completes:
```json
{
  "status": "success",
  "message": "Connected successfully. Click button to restart."
}
```

Or on failure:
```json
{
  "status": "failed",
  "message": "Connection timeout"
}
```

**GET `/restart`**
- Triggers device restart
- Causes esp_restart()

#### HTML Webpage

Simple, minimal HTML (~1.5KB):

```html
<!DOCTYPE html>
<html>
<head>
  <title>Lighthouse WiFi Setup</title>
  <style>
    body { font-family: sans-serif; margin: 20px; }
    .form { max-width: 400px; }
    input { width: 100%; padding: 8px; margin: 5px 0; }
    button { padding: 10px; margin-top: 10px; }
    .status { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
  </style>
</head>
<body>
  <h1>Lighthouse WiFi Configuration</h1>
  <div class="form">
    <form id="setupForm">
      <label>WiFi Network (SSID):</label>
      <input type="text" name="ssid" required>
      
      <label>Password:</label>
      <input type="password" name="password" required minlength="8" maxlength="63">
      
      <button type="submit">Test Connection</button>
    </form>
    <div class="status" id="status"></div>
  </div>
  
  <script>
    document.getElementById('setupForm').onsubmit = async (e) => {
      e.preventDefault();
      const fd = new FormData(e.target);
      const res = await fetch('/configure', { method: 'POST', body: fd });
      const json = await res.json();
      const st = document.getElementById('status');
      st.innerText = json.message;
      if (json.status === 'success') {
        st.innerHTML += '<br><button onclick="location.href=\"/restart\"">Restart Device</button>';
      }
    };
  </script>
</body>
</html>
```

#### Implementation Notes

**Server framework:**
- Use esp_http_server (built into ESP-IDF)
- Single-threaded, minimal memory footprint
- Reference: ESP-IDF HTTP Server documentation

**Credential validation:**
- SSID: non-empty, max 32 chars
- Password: 8-63 chars (WPA2 requirement)
- Return form with errors if validation fails

**Connection testing:**
- WiFi.mode(WIFI_STA)
- WiFi.begin(ssid, password)
- Wait up to configured timeout (default 10 seconds)
- Return success/failure to webpage

**Concurrent requests:**
- Server handles multiple clients
- Only one provisioning form submission at a time
- Queue additional requests or return "busy" error

---

## Part 3: Integration with Existing Code

### 3.1 Modifications to `my_project.c`

**Location: `process_buttons()` function (lines 147-201)**

**Change: Extend BUTTON2 press detection to recognize 5-second hold**

Current code (simplified):
```c
// BUTTON2: Show statistics
{
    uint32_t level = gpio_get_level(BUTTON2_PIN);
    button_state_t* state = &button_states[1];
    
    if (level == 0 && state->last_stable_state == 1) {
        if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS) {
            state->press_count++;
            state->last_press_time = current_time;
            // Handle short press → show statistics
        }
    }
    state->last_stable_state = level;
}
```

**Modified code:**
```c
// BUTTON2: Show statistics or enter setup mode (5s hold)
{
    uint32_t level = gpio_get_level(BUTTON2_PIN);
    button_state_t* state = &button_states[1];
    
    // Track press duration while button held
    if (level == 0 && state->last_stable_state == 0) {
        // Button continuously pressed
        uint32_t press_duration = current_time - state->last_press_time;
        
        // Check for 5-second hold
        if (press_duration >= 5000 && !(state->press_count & 0x80)) {
            // 5s threshold crossed - enter setup mode
            ESP_LOGI(TAG, "BUTTON2 held for 5s - entering WiFi setup mode");
            state->press_count |= 0x80;  // Mark that we've triggered setup
            wifi_provisioning_setup_button_pressed();  // Triggers reboot
        }
    }
    
    // Handle button release
    if (level == 1 && state->last_stable_state == 0) {
        if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS) {
            uint32_t press_duration = current_time - state->last_press_time;
            
            // Only handle short press if we didn't trigger setup
            if (press_duration < 5000 && !(state->press_count & 0x80)) {
                state->press_count++;
                // Handle short press → show statistics (existing code)
                rfid_stats_t stats;
                if (rfid_reader_get_stats(&stats) == ESP_OK) {
                    // ... existing statistics display code ...
                }
            }
            
            // Reset press count for next press
            state->press_count = 0;
        }
    }
    
    state->last_stable_state = level;
}
```

**Key points:**
- Detects 5-second continuous press
- Short presses still show statistics (backward compatible)
- Uses high bit of press_count to avoid double-triggering
- Calls `wifi_provisioning_setup_button_pressed()` which handles reboot

**Integration:** Add `#include "wifi_provisioning.h"` at top of file.

### 3.2 Modifications to `app_main()` in `my_project.c`

**Location: Lines 255-294**

**Add WiFi provisioning initialization BEFORE RFID initialization:**

```c
void app_main(void)
{
    ESP_LOGI(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
    ESP_LOGI(TAG, "  ESP32 Attendance System");
    ESP_LOGI(TAG, "  with UHF RFID Reader");
    ESP_LOGI(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n");
    
    // Initialize GPIO
    gpio_init();
    
    // ========== NEW: WiFi Provisioning System ==========
    ESP_LOGI(TAG, "Initializing WiFi provisioning system...");
    esp_err_t wifi_ret = wifi_provisioning_init(LED1_PIN, 10000);  // 10s timeout
    if (wifi_ret != ESP_OK) {
        ESP_LOGW(TAG, "WiFi provisioning initialization failed: %s", 
                 esp_err_to_name(wifi_ret));
        // Continue anyway - device can still work offline
    }
    
    // Wait for WiFi to be ready before starting RFID
    // If not configured, user must press BUTTON2 for 5s
    if (!wifi_provisioning_is_ready()) {
        ESP_LOGI(TAG, "Waiting for WiFi configuration...");
        ESP_LOGI(TAG, "  Press BUTTON2 for 5 seconds to enter setup mode");
        
        // Block here until configured (could add timeout)
        while (!wifi_provisioning_is_ready()) {
            wifi_provisioning_process();
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
    // ====================================================
    
    // Initialize RFID reader
    esp_err_t ret = rfid_reader_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize RFID reader: %s", 
                 esp_err_to_name(ret));
        return;
    }
    
    // ... rest of existing code ...
}
```

**Key points:**
- Initialization happens before RFID setup
- Checks partition for configured status
- If not configured, blocks on LED blink loop (showing setup mode waiting)
- Once configured (or timeout), proceeds to RFID initialization
- No modification to RFID code needed

### 3.3 Modifications to Main Task in `my_project.c`

**Location: `main_task()` function (lines 239-249)**

**Add WiFi provisioning processing:**

```c
static void main_task(void* arg)
{
    ESP_LOGI(TAG, "Main task started");
    
    while (1) {
        // Process WiFi provisioning state machine
        wifi_provisioning_process();
        
        // Existing button and sensor processing
        process_buttons();
        process_pir();
        
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

**Key points:**
- Calls `wifi_provisioning_process()` every 10ms
- Handles LED blinking, state transitions
- Low CPU overhead (mostly flag checks)
- Integrates seamlessly with existing 10ms loop

### 3.4 New Files to Create

Create in project directory:

```
components/
├── wifi_provisioning/
│   ├── CMakeLists.txt
│   ├── wifi_provisioning.h
│   ├── wifi_provisioning.c
│   ├── wifi_settings_storage.h
│   ├── wifi_settings_storage.c
│   ├── wifi_http_server.h
│   └── wifi_http_server.c
└── [existing components]

sdkconfig.defaults
  (add partition definitions)
```

### 3.5 CMakeLists.txt for New Component

```cmake
idf_component_register(
    SRCS 
        "wifi_provisioning.c"
        "wifi_settings_storage.c"
        "wifi_http_server.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        "esp_wifi"
        "nvs_flash"
        "mbedtls"
        "esp_http_server"
        "freertos"
)
```

### 3.6 Compile-Time Configuration

**Create `wifi_provisioning_config.h`:**

```c
#ifndef WIFI_PROVISIONING_CONFIG_H
#define WIFI_PROVISIONING_CONFIG_H

// Provisioning AP credentials (compile-time, device-specific)
#define WIFI_SETUP_AP_SSID       "LIGHTHOUSE_SETUP"      // Unique per device
#define WIFI_SETUP_AP_PASSWORD   "setup_password_unique" // Min 8 chars, unique per device

// AES encryption key (device-specific, 16 bytes)
// Generated differently for each device during build
#define WIFI_ENCRYPTION_KEY      {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, \
                                  0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F}

// Connection timeout during provisioning test (milliseconds)
#define WIFI_CONNECT_TIMEOUT_MS  10000

// LED control
#define WIFI_LED_SETUP_BLINK_MS  1000  // 1 second blink interval in setup mode

#endif
```

Future improvement: Read these from environment variables or build script to avoid manual edits per device.

---

## Part 4: Testing & Validation Strategy

### 4.1 Unit Testing (Per Module)

**Test `wifi_settings_storage`:**
1. Initialize partition (first boot)
2. Check `is_configured()` returns false
3. Save credentials
4. Load credentials, verify match
5. Factory reset, verify cleared

**Test `wifi_provisioning`:**
1. Boot with unconfigured flag
2. Simulate button press
3. Verify state transitions (UNCONFIGURED → SETUP_REQUESTED → AP_ACTIVE)
4. Simulate HTTP submission
5. Verify connection attempt
6. Verify LED blinking at 1s interval

**Test `wifi_http_server`:**
1. Start server in AP mode
2. Connect client to AP
3. Request GET `/` → verify HTML received
4. POST to `/configure` with valid credentials
5. Verify JSON response
6. Verify callback triggered

### 4.2 Integration Testing

1. **Full setup flow:**
   - Device powers on (unconfigured)
   - Shows "waiting for setup" pattern on LED
   - Press BUTTON2 for 5 seconds
   - Device reboots into AP mode
   - Connect phone to AP
   - Load provisioning page in browser
   - Submit WiFi credentials
   - Page shows connection result
   - Device restarts in STA mode
   - RFID system starts normally

2. **Configuration persistence:**
   - Reboot device
   - Verify WiFi connects automatically
   - Verify RFID operates normally

3. **Failure scenarios:**
   - Wrong password submitted
   - Network unreachable
   - Timeout during connection test
   - Verify form re-appears with error
   - Verify device doesn't brick

### 4.3 Regression Testing

Ensure existing functionality unaffected:
- BUTTON1 still starts/stops RFID
- Short press BUTTON2 still shows statistics
- RFID scanning operates normally
- PIR sensor auto-start still works
- Offline mode still caches events

---

## Part 5: Implementation Sequence

### Phase 1: Foundation (Storage & State Machine)

1. **Create `wifi_settings_storage.c/h`**
   - Implement NVS partition I/O
   - Implement AES encryption/decryption
   - Test read/write of credentials

2. **Create `wifi_provisioning.c/h`**
   - Implement state machine
   - Test state transitions
   - Implement LED blinking logic
   - Test button integration

3. **Modify `my_project.c`**
   - Update button detection for 5s press
   - Call initialization in app_main
   - Call processing in main_task

### Phase 2: HTTP Server & Web UI

1. **Create `wifi_http_server.c/h`**
   - Implement HTTP server startup
   - Serve HTML form
   - Handle POST requests
   - Return JSON responses

2. **Test web interface**
   - Browser access to provisioning page
   - Form submission
   - Error display

### Phase 3: Integration Testing

1. **End-to-end workflow**
   - Full provisioning flow
   - Persistence across reboot
   - Fallback to offline mode on failure

2. **Regression testing**
   - Existing RFID functionality
   - Button handling
   - LED status

---

## Part 6: Key Design Decisions & Rationale

### Decision 1: Separate Partition for Settings

**Why:** Keeps event data and configuration separate, reduces corruption risk, easier backup/restore.

**Alternative considered:** Store in main NVS → harder to manage, mixed data types.

### Decision 2: Encryption at Rest

**Why:** Device will be deployed in enterprise; credentials should not be readable from flash dump.

**Alternative considered:** Plaintext → security risk for enterprise deployment.

### Decision 3: Reboot to Enter Setup

**Why:** Clean state, no interference from running tasks, reliable detection, simple implementation.

**Alternative considered:** AP mode while running RFID → complex, potential conflicts.

### Decision 4: 5-Second Button Hold

**Why:** Prevents accidental entry into setup, allows short-press statistics to coexist.

**Alternative considered:** Double-click → harder to detect reliably.

### Decision 5: Minimal HTML Form

**Why:** Reduces firmware size, fast loading on slow connection, no dependencies.

**Alternative considered:** Framework (Bootstrap, etc.) → too much overhead.

### Decision 6: No Bridging Between AP & STA

**Why:** Simplifies implementation, Enterprise WiFi typically requires explicit approval.

**Alternative considered:** NAT/bridge → adds complexity, potential security issues.

---

## Part 7: Hardware & Documentation References

### ESP32 Technical Reference Manual
- Section 6: IO MUX and GPIO Matrix (button GPIO configuration)
- Section 14: AES Accelerator (encryption)
- Section 3: System and Memory (partition layout)

### ESP-IDF Documentation
- NVS (Non-Volatile Storage) API
- WiFi API (Station and AP modes)
- HTTP Server
- Partition Tables

### Arduino-ESP32 WiFi API
- WiFi.mode(WIFI_AP)
- WiFi.softAP()
- WiFi.begin() for STA mode
- Reference: https://docs.espressif.com/projects/arduino-esp32/en/latest/api/wifi.html

---

## Part 8: Future Enhancements

1. **MQTT Broker Configuration**
   - Add fields to provisioning form
   - Store encrypted in settings partition (reserved bytes 98-127)
   - Load during boot, pass to MQTT client

2. **Device Reset Button**
   - 10-second button hold → factory reset
   - Clear WiFi config, revert to unconfigured state

3. **Captive Portal**
   - Redirect HTTP requests to provisioning page (auto-login)
   - Better UX on mobile devices

4. **OTA Firmware Updates**
   - Serve firmware update endpoint during setup mode
   - Allow device to be updated without disassembly

5. **Multi-Device Management**
   - Build system integration for unique SSID/password per device
   - Barcode or QR code on device
   - Documentation with device-specific setup instructions

---

## Summary

This plan provides a **complete, incremental implementation** of WiFi provisioning that:

- ✅ Integrates cleanly with existing firmware
- ✅ Uses established code patterns (GPIO, buttons, main loop)
- ✅ Requires no modification to RFID code
- ✅ Provides secure credential storage (encrypted)
- ✅ Offers simple provisioning UX (web form)
- ✅ Follows ESP32 best practices and datasheets
- ✅ Testable at each phase
- ✅ Extensible for future features

Worker should proceed with Phase 1 (storage & state machine) before moving to HTTP server implementation.
