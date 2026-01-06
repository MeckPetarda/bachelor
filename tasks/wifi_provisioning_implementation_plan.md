# WiFi Provisioning System - Sequential Implementation Steps

## Overview

This document breaks down the WiFi provisioning implementation into discrete, testable steps. Each step is designed to:
- Build on previous steps
- Be independently testable
- Not break existing functionality
- Minimize risk of regression

**Estimated effort per step:** 1-4 hours depending on complexity.

Follow steps in order. Do not skip ahead.

---

## PHASE 1: FOUNDATION - STORAGE LAYER

### Step 1.1: Create NVS Settings Partition Definition

**Objective:** Define and configure the settings partition in ESP32 partitions table.

**Files to Create/Modify:**
- Create: `partitions.csv` (in project root, if not exists)
- Reference: ESP32 TRM Section 3 (System and Memory)

**What to Do:**

Add entry to `partitions.csv` defining the nvs_settings partition:
- Name: `nvs_settings`
- Type: `data`
- SubType: `nvs`
- Offset: Choose offset after existing partitions (typically 0x290000)
- Size: `0x4000` (16KB minimum)
- Optional flags: `encrypted`

Verify offsets don't overlap with app partitions and existing NVS partition.

**Validation:**
- Run `idf.py partition-table` to check syntax
- No address conflicts in output
- Partition size sufficient for future MQTT settings (reserved bytes 98-127)

---

### Step 1.2: Create WiFi Settings Storage Header

**Objective:** Define the interface and data structures for credential storage.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_settings_storage.h`

**What to Define:**

Create header with:

1. **Error codes enum** (wifi_storage_error_t):
   - WIFI_STORAGE_OK
   - WIFI_STORAGE_NOT_FOUND
   - WIFI_STORAGE_CORRUPT
   - WIFI_STORAGE_ENCRYPTION_ERROR
   - WIFI_STORAGE_WRITE_ERROR
   - WIFI_STORAGE_INVALID_PARAM

2. **Data structure** (wifi_credentials_t):
   - char ssid[32]
   - char password[64]
   - uint8_t configured

3. **Public function declarations**:
   - wifi_settings_init()
   - wifi_settings_is_configured()
   - wifi_settings_load(wifi_credentials_t* creds)
   - wifi_settings_save(const char* ssid, const char* password)
   - wifi_settings_factory_reset()
   - wifi_settings_error_to_string(wifi_storage_error_t err)

Each function needs:
- Complete documentation comment
- Parameter descriptions
- Return value description
- Any important notes (e.g., "Never log plaintext credentials")

**Reference:** WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.1

---

### Step 1.3: Create WiFi Settings Storage Implementation

**Objective:** Implement NVS I/O and AES encryption for credential storage.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_settings_storage.c`

**What to Implement:**

The implementation must:

1. **NVS Initialization:**
   - Initialize the "nvs_settings" partition using `nvs_flash_init_partition()`
   - Open namespace "wifi_settings" with `nvs_open_from_partition()`
   - Store handle for later read/write operations
   - Handle initialization errors gracefully (partition not found, etc.)

2. **Configuration Flag Check:**
   - Read uint8_t from NVS key "configured"
   - Return false if key doesn't exist (first boot)
   - Return true if value == 1

3. **Credential Loading (decrypt from NVS):**
   - Verify initialized and configured flag is set
   - Read encrypted SSID (32 bytes) from key "ssid_enc"
   - Read encrypted password (64 bytes) from key "pass_enc"
   - Decrypt both using AES-128-ECB with device-specific key
   - Copy decrypted data as null-terminated C strings to output structure
   - Handle decryption/corruption errors

4. **Credential Saving (encrypt and write to NVS):**
   - Validate inputs: SSID (1-31 chars), password (8-63 chars per WPA2)
   - Pad SSID to 32 bytes with zeros
   - Pad password to 64 bytes with zeros
   - Encrypt both using AES-128-ECB
   - Write encrypted blobs to NVS keys "ssid_enc" and "pass_enc"
   - Set uint8_t "configured" = 1
   - Commit NVS changes with `nvs_commit()`
   - Log success but never log plaintext credentials

5. **Factory Reset:**
   - Erase all keys in NVS namespace using `nvs_erase_all()`
   - Commit changes
   - Returns device to unconfigured state

6. **Error Messages:**
   - Implement error_to_string() to return human-readable descriptions
   - Each error enum value should have a string representation

**AES Encryption Details:**

- Use mbedTLS library (included in ESP-IDF)
- Algorithm: AES-128 in ECB mode
- Key: Device-specific 16-byte constant (defined as static const array)
- Plaintext and ciphertext must be multiples of 16 bytes (pad with zeros)
- Reference: ESP32 TRM Section 14 (AES Accelerator) and ESP-IDF mbedTLS documentation

**Key Implementation Challenges:**

1. **Padding:** SSID is 32 bytes (already aligned); password must pad from variable length to 64 bytes
2. **Null termination:** After decryption, ensure decrypted strings are null-terminated as C strings
3. **Error propagation:** Return appropriate error codes from aes_encrypt/aes_decrypt to caller
4. **Partition keys:** Use "ssid_enc" and "pass_enc" as NVS keys to store encrypted data

**Testing Strategy:**

Create a temporary test program (Step 1.5) to validate:
- Initialization succeeds
- Save/load round-trip preserves credentials
- Invalid inputs are rejected (empty SSID, password too short/long)
- Encryption actually changes data (verify encrypted != plaintext)
- Factory reset clears configuration
- Decryption fails gracefully if data corrupted
- Error codes and messages work correctly

**Dependencies:**
- `nvs_flash.h` (ESP-IDF)
- `mbedtls/aes.h` (ESP-IDF)
- `wifi_settings_storage.h` (header from Step 1.2)
- Standard C: `<string.h>`, `<stdint.h>`, `<stdbool.h>`

---

### Step 1.4: Create CMakeLists.txt for Component

**Objective:** Set up build configuration for new WiFi provisioning component.

**Files to Create:**
- Create: `components/wifi_provisioning/CMakeLists.txt`

**What to Define:**

Create CMake configuration that:

1. **Registers the component** with idf_component_register()
2. **Lists source files:**
   - wifi_settings_storage.c (only this module in this step)
3. **Sets include directory** to current directory (".")
4. **Declares requirements:**
   - nvs_flash (for NVS operations)
   - mbedtls (for AES encryption)
   - esp_common (for error codes)
   - freertos (for vTaskDelay if needed)

Use standard ESP-IDF CMake conventions.

**Validation:**
- Run `idf.py build` - should compile with no errors
- Check no missing dependencies

---

### Step 1.5: Create Test Harness for Storage Module

**Objective:** Verify storage module works correctly with real NVS partition.

**Files to Create:**
- Create: `test_wifi_storage.c` (in project root, temporary test file)

**What to Implement:**

Create a test program that:

1. **Initialize NVS:** Call `nvs_flash_init()` with erase-if-needed handling
2. **Test initialization:** Call wifi_settings_init(), verify WIFI_STORAGE_OK
3. **Test unconfigured state:** Call is_configured(), should return false on first run
4. **Test credential save:** Call wifi_settings_save() with valid SSID and password
5. **Test configured state:** Call is_configured(), should now return true
6. **Test credential load:** Call wifi_settings_load(), verify SSID and password match what was saved
7. **Test invalid inputs:** Try saving empty SSID, password too short, password too long - all should fail
8. **Test factory reset:** Call wifi_settings_factory_reset(), verify is_configured() returns false
9. **Test error strings:** Call error_to_string() for each error code, verify non-NULL and reasonable

Each test should:
- Print pass/fail result
- Log inputs and outputs for debugging
- Report errors with context
- Continue to next test even if one fails

**Compilation:**
- Main program (app_main) initializes NVS then calls test_storage_module()
- Print summary at end showing number passed/failed

**Expected behavior:**
- All tests pass
- No segfaults or assertions
- Encryption changes credentials (can't read plaintext from NVS)

**Cleanup:**
- This is a temporary test file
- Can be deleted after verification succeeds
- Or moved to test directory for future regression testing

---

## PHASE 2: STATE MACHINE & BUTTON INTEGRATION

### Step 2.1: Create WiFi Provisioning Header

**Objective:** Define state machine interface and public API for provisioning system.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_provisioning.h`

**What to Define:**

Create header with:

1. **State enum** (wifi_state_t):
   - WIFI_STATE_UNCONFIGURED (no config saved; waiting for user)
   - WIFI_STATE_SETUP_REQUESTED (user triggered setup; reboot flag set)
   - WIFI_STATE_AP_ACTIVE (AP broadcasting, serving provisioning page)
   - WIFI_STATE_CONNECTING (attempting STA connection with test credentials)
   - WIFI_STATE_CONNECTED (successfully connected to WiFi)
   - WIFI_STATE_OFFLINE (connection failed or unavailable)

2. **Event enum** (wifi_event_t):
   - WIFI_EVENT_NONE
   - WIFI_EVENT_CONFIG_LOADED
   - WIFI_EVENT_SETUP_BUTTON_PRESSED
   - WIFI_EVENT_CREDS_SUBMITTED
   - WIFI_EVENT_CONNECTION_SUCCESS
   - WIFI_EVENT_CONNECTION_FAILED
   - WIFI_EVENT_REBOOT_REQUESTED

3. **Public function declarations**:
   - wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms)
   - wifi_provisioning_setup_button_pressed()
   - wifi_provisioning_process()
   - wifi_provisioning_get_state()
   - wifi_provisioning_is_ready()
   - wifi_provisioning_state_to_string(wifi_state_t state)
   - wifi_provisioning_set_connection_result(bool success, const char* error_message)
   - wifi_provisioning_restart_device()

Each function needs:
- Complete documentation
- Parameter descriptions
- Important notes (e.g., "This function does NOT return")
- Context on when to call and from where

**Reference:** WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2

---

### Step 2.2: Create WiFi Provisioning Implementation (Core State Machine)

**Objective:** Implement state machine initialization and basic state transitions.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_provisioning.c`

**What to Implement:**

The implementation must:

1. **State machine data structure:**
   - Current state
   - State entry timestamp
   - LED pin and configuration
   - LED blinking control (interval, last toggle time, current state)
   - Pending credentials during setup
   - Connection result tracking
   - Reboot flag

2. **Initialization (wifi_provisioning_init):**
   - Store LED pin and timeout configuration
   - Configure LED pin as output using `gpio_config()`
   - Call wifi_settings_init() for storage initialization
   - Check if device is configured using is_configured()
   - Transition to appropriate initial state:
     - If configured: WIFI_STATE_CONNECTING (will attempt connection)
     - If not configured: WIFI_STATE_UNCONFIGURED (wait for user)
   - Log initialization status
   - Set initialized flag

3. **Button press handler (wifi_provisioning_setup_button_pressed):**
   - Log that setup mode is being entered
   - Set reboot flag
   - Brief delay (100ms) to ensure logging
   - Call esp_restart() to reboot device
   - Never returns

4. **LED control:**
   - Implement helper to toggle LED at specified interval
   - Only blink when in AP_ACTIVE state
   - 1 second interval (1000ms): off for 500ms, on for 500ms
   - Or off for 1s, on for 0ms - depends on design choice
   - Use get_time_ms() (from esp_timer) to track timing

5. **State machine processing (wifi_provisioning_process):**
   - Called every 10ms from main task
   - Process LED blinking for current state
   - Handle state-specific logic:
     - UNCONFIGURED: Do nothing, wait for button press
     - SETUP_REQUESTED: (handled by reboot, not here)
     - AP_ACTIVE: HTTP server is running (will be added in Phase 3)
     - CONNECTING: (will be implemented with WiFi in Phase 3)
     - CONNECTED: Monitor connection
     - OFFLINE: Running offline
   - Low CPU cost: mostly flag checks

6. **State transitions:**
   - Implement transition_to() helper function
   - Log state changes with from→to notation
   - Update state_enter_time when transitioning

7. **Query functions:**
   - is_ready(): Return true if CONNECTED or OFFLINE
   - get_state(): Return current state
   - state_to_string(): Return human-readable state name

**Key Design Points:**

1. **Why reboot to enter setup?**
   - Clean state, no interference from other tasks
   - Reliable detection on next boot
   - Simple state machine (no complex task coordination)

2. **LED blinking timing:**
   - Use millisecond timer, not vTaskDelay (blocking)
   - Check elapsed time each call to process()
   - Toggle LED when elapsed >= interval

3. **Initialization order:**
   - Storage init must succeed (or log warning but continue)
   - LED must be configured before use
   - State determined from storage, not assumed

**Dependencies:**
- `wifi_settings_storage.h` (from Step 1.2)
- `esp_timer.h` (for timing)
- `driver/gpio.h` (for LED control)
- `esp_log.h` (for logging)
- FreeRTOS headers

**Testing Strategy:**

Manual testing:
1. Flash firmware on unconfigured device
2. Verify boot reaches "waiting for config" state
3. Press BUTTON2 for 5 seconds (not implemented yet, but infrastructure ready)
4. Verify device logs setup mode request
5. Verify device reboots
6. On reboot, verify LED blinking begins

Check serial output for state transition logs.

---

### Step 2.3: Extend Button Detection for 5-Second Press

**Objective:** Modify existing button handling to detect 5-second BUTTON2 hold for setup mode entry.

**Files to Modify:**
- Modify: `my_project.c` (process_buttons function, lines 147-201)

**What to Change:**

In the BUTTON2 handling section:

1. **Track press duration:**
   - While BUTTON2 is held (level == 0 and last_stable_state == 0)
   - Calculate hold_duration = current_time - last_press_time
   - When hold_duration >= 5000ms, trigger setup

2. **Setup trigger:**
   - Use high bit of press_count counter to mark "setup triggered"
   - Prevents multiple triggers from one long press
   - Call wifi_provisioning_setup_button_pressed()
   - This function reboots, so code after it doesn't execute

3. **Short press handling (unchanged):**
   - Only trigger short-press action if hold_duration < 5000ms
   - Short press still shows RFID statistics
   - Requires press_count high bit NOT set

4. **Button release handling:**
   - Reset counters for next press
   - Clear high bit for next button cycle

**Key Points:**
- Backward compatible: short presses unchanged
- Use high bit to prevent double-trigger
- Debounce time (DEBOUNCE_TIME_MS) still applies
- Keeps button state machine unchanged

**Integration:**
- Add `#include "wifi_provisioning.h"` at top of file

---

### Step 2.4: Integrate WiFi Provisioning into app_main()

**Objective:** Add WiFi provisioning initialization to main application startup.

**Files to Modify:**
- Modify: `my_project.c` (app_main function)

**What to Change:**

After gpio_init() and before RFID initialization:

1. **Initialize WiFi provisioning:**
   - Call wifi_provisioning_init(LED1_PIN, 10000)
   - Check return code, log warnings if needed
   - Device can continue offline if init fails

2. **Wait for ready state:**
   - If not ready, enter blocking loop
   - Call wifi_provisioning_process() every 50ms in loop
   - Check is_ready() to exit loop
   - Log status message: "Waiting for WiFi configuration"
   - Log instructions: "Press BUTTON2 for 5 seconds to enter setup mode"

3. **Proceed with RFID:**
   - After ready, continue with existing RFID initialization
   - No RFID code changes needed

**Key Points:**
- Initialization happens before RFID setup
- Blocking on is_ready() acceptable during boot
- LED will blink if entering setup mode (user visible feedback)
- No modification to RFID code

---

### Step 2.5: Integrate WiFi Provisioning into Main Task Loop

**Objective:** Add state machine processing to existing main task.

**Files to Modify:**
- Modify: `my_project.c` (main_task function, lines 239-249)

**What to Change:**

Add call to wifi_provisioning_process() at start of main loop:

1. **First action in main_task loop:**
   - Call wifi_provisioning_process()
   - This runs before button/PIR processing
   - Takes <10ms (mostly flag checks)

2. **Existing processing continues unchanged:**
   - process_buttons() (now with 5s detection)
   - process_pir()
   - vTaskDelay(10ms)

**Effect:**
- LED blinking works during setup mode
- State transitions happen in timely manner
- No blocking, no task delays

---

### Step 2.6: Update CMakeLists.txt to Include Provisioning

**Objective:** Add WiFi provisioning module to component build.

**Files to Modify:**
- Modify: `components/wifi_provisioning/CMakeLists.txt`

**What to Change:**

Add to SRCS list:
- wifi_provisioning.c (in addition to wifi_settings_storage.c)

Add to REQUIRES list:
- esp_timer (for timing)
- driver (for GPIO)

Verify no missing dependencies.

---

### Step 2.7: Test Phase 2 - Button and State Machine

**Objective:** Verify button detection and state machine work together.

**Test Procedure:**

1. **Unconfigured device startup:**
   - Flash firmware
   - Device should reach "Waiting for WiFi configuration" message
   - LED should be off
   - Serial log should show state: UNCONFIGURED

2. **Setup button press (5 seconds):**
   - Press BUTTON2 continuously for 5+ seconds
   - Watch serial log for "entering setup mode" message
   - Device reboots
   - On reboot, LED begins blinking at 1 second interval
   - Serial log should show state: AP_ACTIVE

3. **Short button press (< 1 second):**
   - While in normal operation, quick press BUTTON2
   - Should show RFID statistics (existing functionality)
   - Should NOT trigger setup mode
   - LED should not blink

4. **State transitions logging:**
   - Monitor serial output for state change messages
   - Expected sequence: UNCONFIGURED → SETUP_REQUESTED (after reboot) → AP_ACTIVE

**Expected Serial Output (unconfigured boot):**
```
WIFI_PROV: Initializing WiFi provisioning
WIFI_STORAGE: Initializing NVS flash
WIFI_STORAGE: NVS initialization successful
WIFI_PROV: Device not configured; waiting for user
WIFI_PROV: WiFi provisioning initialized
MAIN: Waiting for WiFi configuration...
MAIN: Press BUTTON2 for 5 seconds to enter setup mode
```

**Expected Serial Output (5s button press):**
```
MAIN: BUTTON2 held for 5+ seconds - entering WiFi setup mode
WIFI_PROV: Setup button pressed - entering setup mode
WIFI_PROV: Restarting...
```

**Expected Serial Output (reboot in setup mode):**
```
WIFI_PROV: State transition: UNCONFIGURED → AP_ACTIVE
(LED begins blinking)
MAIN: System ready!
```

**Notes:**
- No WiFi connectivity test yet
- HTTP server not implemented
- This validates button and state machine only
- Next phase adds HTTP server and WiFi testing

---
# WiFi Provisioning System - Phase 3: HTTP Server & Web Provisioning

This document continues from Phase 2 (end of Step 2.7). At this point:
- ✅ Storage layer complete
- ✅ State machine operational
- ✅ Button integration working
- ✅ LED blinking in AP mode
- ✅ Device enters AP mode on demand

Phase 3 adds the HTTP server and web-based credential submission.

---

## PHASE 3: HTTP SERVER & WEB PROVISIONING

### Step 3.1: Create WiFi HTTP Server Header & Core Implementation

**Objective:** Implement HTTP server for provisioning webpage and credential handling.

**Files to Create:**

#### `components/wifi_provisioning/wifi_http_server.h`

```c
/**
 * wifi_http_server.h - WiFi Provisioning HTTP Server
 * 
 * Provides:
 * - HTTP server on port 80
 * - GET "/" - provisioning webpage
 * - POST "/configure" - credential submission
 * - GET "/restart" - device restart
 * 
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.3
 */

#ifndef WIFI_HTTP_SERVER_H
#define WIFI_HTTP_SERVER_H

#include <stdbool.h>
#include "esp_err.h"

// ============================================================================
// CALLBACK TYPE
// ============================================================================

/**
 * Callback when user submits provisioning form
 * 
 * Called from HTTP handler when POST /configure received with valid data.
 * Receives SSID and password to test/save.
 * 
 * Implementation should:
 * - Store credentials in provisioning state
 * - Trigger WiFi connection attempt
 * - Call wifi_http_server_set_connection_result() after test completes
 */
typedef void (*wifi_credentials_callback_t)(const char* ssid, const char* password);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Start HTTP server in AP mode
 * 
 * Call only when in AP_ACTIVE state (after WiFi AP is broadcasting).
 * 
 * Registers URI handlers for:
 * - GET "/" → Returns provisioning webpage HTML
 * - POST "/configure" → Handles form submission
 * - GET "/restart" → Restarts device
 * 
 * @param ap_ssid Access point SSID (from compile-time constant)
 * @param ap_password Access point password (from compile-time constant)
 * @return ESP_OK on success
 */
esp_err_t wifi_http_server_start(const char* ap_ssid, const char* ap_password);

/**
 * Stop HTTP server
 * 
 * Safe to call even if not running.
 * 
 * @return ESP_OK on success
 */
esp_err_t wifi_http_server_stop(void);

/**
 * Register callback for credential submission
 * 
 * MUST be called BEFORE wifi_http_server_start().
 * 
 * When user submits form with SSID/password, this callback is invoked.
 * Callback should test WiFi connection and call wifi_http_server_set_connection_result()
 * to notify webpage of success/failure.
 * 
 * @param callback Function to invoke on form submission
 */
void wifi_http_server_set_credentials_callback(wifi_credentials_callback_t callback);

/**
 * Report WiFi connection test result to webpage
 * 
 * Called after credentials callback tests WiFi connection.
 * Updates webpage to show success or error message.
 * 
 * @param success true if connection succeeded
 * @param error_message Error description if success=false (can be NULL for success)
 */
void wifi_http_server_set_connection_result(bool success, const char* error_message);

/**
 * Check if HTTP server is running
 * 
 * @return true if server is active
 */
bool wifi_http_server_is_running(void);

#endif // WIFI_HTTP_SERVER_H
```

**What to Implement in `wifi_http_server.c`:**

1. **Global state:**
   - httpd_handle_t server (NULL if not running)
   - Callback function pointer
   - Connection result flags (success, error message)
   - Running flag

2. **wifi_http_server_start():**
   - Configure HTTP server settings (port 80, max handlers)
   - Start server with httpd_start()
   - Register three URI handlers:
     - GET "/" → get_provisioning_page_handler()
     - POST "/configure" → post_configure_handler()
     - GET "/restart" → get_restart_handler()
   - Log server startup and IP address
   - Set running flag = true

3. **wifi_http_server_stop():**
   - Stop server with httpd_stop()
   - Clear callbacks
   - Set running flag = false

4. **Callback registration:**
   - Store callback pointer in module variable
   - Called before start

5. **Connection result storage:**
   - Store success flag
   - Store error message (max 64 chars)
   - Used by handlers to generate response

6. **URI Handlers (GET "/")**
   - Generate simple HTML form in response
   - Include SSID and password inputs
   - Include Submit button and status area
   - Include embedded CSS and JavaScript
   - Send with Content-Type: text/html

7. **URI Handler (POST "/configure")**
   - Parse form data from request body
   - Extract SSID and password (URL-decode)
   - Validate: SSID non-empty, password 8-63 chars
   - Return error JSON if invalid
   - Invoke callback with credentials
   - Wait for connection result (up to 15 seconds)
   - Return result JSON to browser

8. **URI Handler (GET "/restart")**
   - Send simple response
   - Call esp_restart() after brief delay
   - Never returns

**HTML/CSS/JavaScript (embedded in handler):**

```html
<!DOCTYPE html>
<html>
<head>
  <title>Lighthouse WiFi Setup</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .container { max-width: 400px; margin: 0 auto; }
    h1 { font-size: 24px; }
    form { margin: 20px 0; }
    label { display: block; margin-top: 10px; font-weight: bold; }
    input { width: 100%; padding: 8px; margin: 5px 0 15px 0; box-sizing: border-box; }
    button { padding: 10px 20px; background: #007bff; color: white; border: none; 
             cursor: pointer; font-size: 16px; width: 100%; }
    button:disabled { background: #ccc; cursor: not-allowed; }
    .status { margin-top: 20px; padding: 10px; border: 1px solid #ddd; display: none; }
    .status.show { display: block; }
    .success { color: green; border-color: green; }
    .error { color: red; border-color: red; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Lighthouse WiFi Setup</h1>
    <form id="setupForm">
      <label for="ssid">WiFi Network (SSID):</label>
      <input type="text" id="ssid" name="ssid" required maxlength="31">
      
      <label for="password">Password:</label>
      <input type="password" id="password" name="password" required minlength="8" maxlength="63">
      
      <button type="submit" id="submitBtn">Test Connection</button>
    </form>
    <div class="status" id="status"></div>
  </div>
  
  <script>
    const form = document.getElementById('setupForm');
    const status = document.getElementById('status');
    const submitBtn = document.getElementById('submitBtn');
    
    form.onsubmit = async (e) => {
      e.preventDefault();
      const fd = new FormData(form);
      submitBtn.disabled = true;
      submitBtn.textContent = 'Testing...';
      status.textContent = 'Testing WiFi connection...';
      status.className = 'status show';
      
      try {
        const res = await fetch('/configure', { method: 'POST', body: fd });
        const json = await res.json();
        
        if (json.status === 'success') {
          status.className = 'status show success';
          status.innerHTML = json.message + 
            '<br><br><button onclick="location.href=\'/restart\'">Restart Device</button>';
        } else {
          status.className = 'status show error';
          status.textContent = json.message;
          submitBtn.disabled = false;
          submitBtn.textContent = 'Test Connection';
        }
      } catch (err) {
        status.className = 'status show error';
        status.textContent = 'Connection error: ' + err.message;
        submitBtn.disabled = false;
        submitBtn.textContent = 'Test Connection';
      }
    };
  </script>
</body>
</html>
```

**Key Implementation Details:**

1. **Form parsing:**
   - Request body contains: `ssid=VALUE&password=VALUE`
   - URL-decode special characters
   - Trim whitespace

2. **Asynchronous testing:**
   - Handler calls callback with credentials
   - Callback tests WiFi in state machine
   - Handler waits for connection result (with timeout)
   - Then sends response JSON

3. **LED during setup:**
   - Continue blinking while in AP mode
   - State machine handles this independently

**Dependencies:**
- `esp_http_server.h` (ESP-IDF)
- `esp_wifi.h` (WiFi API)
- `esp_log.h` (logging)
- `wifi_settings_storage.h` (from Phase 1)
- Standard C headers

**Testing after this step:**
1. Device boots in AP mode
2. Connect to AP from phone
3. Open http://192.168.4.1
4. Form loads and displays
5. Submit valid credentials
6. See "Testing..." message
7. After ~10 seconds: success or error
8. If success: restart button appears
9. Click restart → device reboots

---

### Step 3.2: Integrate HTTP Server with State Machine & WiFi Testing

**Objective:** Connect HTTP server to provisioning state machine and implement WiFi connection testing.

**Files to Modify:**

- `components/wifi_provisioning/wifi_provisioning.c`
- `components/wifi_provisioning/wifi_provisioning.h` (add one function)

**Additions to `wifi_provisioning.h`:**

Add this function declaration:

```c
/**
 * Request device restart
 * 
 * Called by HTTP /restart handler.
 * Saves credentials and initiates device reboot.
 * 
 * Must have successfully connected to WiFi before calling.
 */
void wifi_provisioning_request_restart(void);
```

**What to Implement in `wifi_provisioning.c`:**

1. **State machine expansion:**
   - Track pending SSID and password during setup
   - Store connection test result (success/failure, error message)

2. **Callback from HTTP handler:**
   - Register function that receives SSID/password from form
   - Stores in state, transitions to CONNECTING state
   - HTTP handler waits for result via wifi_http_server_set_connection_result()

3. **AP_ACTIVE state entry:**
   - Start HTTP server: `wifi_http_server_start(WIFI_SETUP_AP_SSID, WIFI_SETUP_AP_PASSWORD)`
   - Register callback: `wifi_http_server_set_credentials_callback(on_credentials_received)`
   - Log "AP active, HTTP server running"

4. **CONNECTING state:**
   - Switch WiFi to STA mode: `WiFi.mode(WIFI_STA)`
   - Disconnect from AP: `WiFi.disconnect()`
   - Attempt connection: `WiFi.begin(pending_ssid, pending_password)`
   - Poll WiFi.status() every 200ms:
     - WL_CONNECTED → success, transition to CONNECTED
     - Timeout (10 seconds) → failure, back to AP_ACTIVE
     - Other states → keep waiting
   - Call `wifi_http_server_set_connection_result(success, error_msg)`

5. **CONNECTED state entry:**
   - Save credentials to storage: `wifi_settings_save(pending_ssid, pending_password)`
   - Log success with IP address
   - Wait for restart request via HTTP handler

6. **Back to AP_ACTIVE on failure:**
   - Re-enable AP: `WiFi.mode(WIFI_AP)`
   - Restart HTTP server
   - User can retry form

7. **Restart handler:**
   - Called by HTTP GET /restart
   - Verify in CONNECTED state
   - Call `esp_restart()`

**Flow diagram:**

```
AP_ACTIVE (HTTP server running)
  ↓
User submits form
  ↓
HTTP handler calls callback → CONNECTING
  ↓
Poll WiFi.status() for ~10 seconds
  ├→ Connected → save credentials → CONNECTED
  │   HTTP handler shows "Restart available"
  │   User clicks restart button
  │   Device reboots → loads credentials on next boot
  │
  └→ Timeout → back to AP_ACTIVE
      HTTP handler shows error
      User can retry form
```

**LED behavior:**
- Continue 1-second blinking through all states (AP_ACTIVE, CONNECTING, etc.)
- Stop blinking when CONNECTED or OFFLINE

**Testing after this step:**
1. Device in AP mode
2. Form submission triggers CONNECTING state
3. Watch LED continue blinking
4. Serial log shows state transition and WiFi connection attempt
5. After ~5 seconds (if network available): successful connection
6. HTTP handler shows success message
7. Click restart → device reboots and loads credentials
8. On next boot: device connects automatically

---

### Step 3.3: Add Compile-Time Configuration and Build Integration

**Objective:** Define device-specific settings and complete build configuration.

**Files to Create:**

#### `components/wifi_provisioning/wifi_provisioning_config.h`

```c
/**
 * wifi_provisioning_config.h - Configuration Constants
 * 
 * Device-specific settings for WiFi provisioning.
 * Customize these values for each device build.
 */

#ifndef WIFI_PROVISIONING_CONFIG_H
#define WIFI_PROVISIONING_CONFIG_H

// ============================================================================
// PROVISIONING AP CREDENTIALS (compile-time, device-specific)
// ============================================================================

/**
 * SSID for setup mode access point
 * Should be unique per device to avoid confusion when setting up multiple units
 * Max 31 characters
 * Example: "LIGHTHOUSE_SETUP_001"
 */
#define WIFI_SETUP_AP_SSID       "LIGHTHOUSE_SETUP"

/**
 * Password for setup mode access point
 * Min 8 characters, max 63 characters (WPA2 requirement)
 * Should be unique per device (print on device or manual)
 * Example: "setup_key_001"
 */
#define WIFI_SETUP_AP_PASSWORD   "setup_password"

// ============================================================================
// ENCRYPTION KEY (device-specific)
// ============================================================================

/**
 * AES-128 encryption key for credential storage
 * 16 bytes (128 bits)
 * Each device should have a unique key
 * 
 * Current value is placeholder - replace with actual key during device provisioning
 * Future: Generate per device during firmware build process
 */
#define WIFI_ENCRYPTION_KEY      {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, \
                                  0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F}

// ============================================================================
// OPERATIONAL PARAMETERS
// ============================================================================

/**
 * WiFi connection timeout during provisioning (milliseconds)
 * How long to wait for device to connect to test network
 * Default: 10000 (10 seconds)
 * Reasonable range: 5000-15000
 */
#define WIFI_CONNECT_TIMEOUT_MS  10000

/**
 * LED blink interval during setup mode (milliseconds)
 * Period for LED on/off cycle
 * Default: 1000 (1 second total: 500ms on, 500ms off)
 */
#define WIFI_LED_SETUP_BLINK_MS  1000

#endif // WIFI_PROVISIONING_CONFIG_H
```

**Files to Modify:**

#### Update `components/wifi_provisioning/CMakeLists.txt`

```cmake
idf_component_register(
    SRCS
        "wifi_provisioning.c"
        "wifi_settings_storage.c"
        "wifi_http_server.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        "nvs_flash"
        "mbedtls"
        "esp_common"
        "freertos"
        "esp_timer"
        "esp_wifi"
        "esp_http_server"
        "driver"
)
```

**What to Update in Implementation Files:**

1. **In `wifi_settings_storage.c`:**
   - Include `wifi_provisioning_config.h`
   - Use `WIFI_ENCRYPTION_KEY` instead of hardcoded key
   - Reference this header for key definition

2. **In `wifi_provisioning.c`:**
   - Include `wifi_provisioning_config.h`
   - Use `WIFI_SETUP_AP_SSID` and `WIFI_SETUP_AP_PASSWORD` when starting AP
   - Pass timeout from `WIFI_CONNECT_TIMEOUT_MS` to init function
   - Use `WIFI_LED_SETUP_BLINK_MS` for LED timing

3. **In `wifi_http_server.c`:**
   - Include `wifi_provisioning_config.h`
   - Use AP credentials when calling `WiFi.softAP()`

**Documentation in config header:**

- Clear comments explaining each setting
- Notes on valid ranges
- Examples of values
- Instructions for customization per device

**Build validation:**
- `idf.py build` succeeds
- All three modules compile
- No missing dependencies
- All includes resolve correctly

**Multi-device management (for future):**

Current process:
1. Edit `wifi_provisioning_config.h` SSID, password, and key
2. Build firmware for device
3. Flash to device
4. Repeat for next device

Recommended future improvement:
- Script to generate unique values per device
- Build system integration (CMake custom commands)
- Environment variable substitution
- Barcode/QR code generation for device labeling

---

### Step 3.4: Complete End-to-End Testing

**Objective:** Verify full provisioning workflow works correctly.

**Pre-test checklist:**
- ✅ All Phase 1 & 2 components complete
- ✅ HTTP server module implemented
- ✅ WiFi integration in state machine working
- ✅ Config header created
- ✅ Build succeeds: `idf.py build`
- ✅ Test WiFi network available with known credentials
- ✅ Mobile device or laptop for AP connection

**Test scenario 1: First boot (unconfigured device)**

Actions:
1. Flash firmware to unconfigured ESP32
2. Open serial monitor
3. Power on device

Expected observations:
- Device boots normally
- Serial log shows: `"Waiting for WiFi configuration"`
- LED off (no WiFi status yet)
- RFID system does NOT start (blocked on wifi_provisioning_is_ready())
- Serial shows: `"Press BUTTON2 for 5 seconds to enter setup mode"`

✅ Pass/❌ Fail: __________

**Test scenario 2: Enter setup mode**

Actions:
1. Press BUTTON2 for exactly 5+ seconds
2. Watch serial log
3. Observe LED behavior

Expected observations:
- Device logs: `"BUTTON2 held for 5+ seconds - entering setup mode"`
- Device logs: `"Restarting..."`
- Device reboots
- On reboot, LED begins blinking (1 second interval)
- Serial log shows: `"State transition: ... → AP_ACTIVE"`
- Serial log shows: `"HTTP server started"`
- Serial shows: `"System ready!"` (RFID still waiting for WiFi)

✅ Pass/❌ Fail: __________

**Test scenario 3: Access provisioning webpage**

Actions:
1. On mobile/laptop, open WiFi settings
2. Scan for networks
3. Find network named `WIFI_SETUP_AP_SSID` (check config header value)
4. Connect using `WIFI_SETUP_AP_PASSWORD`
5. Open browser
6. Navigate to `http://192.168.4.1`

Expected observations:
- Network appears in WiFi scanner
- Connection succeeds with correct password
- Page loads within 2-3 seconds
- Title shows "Lighthouse WiFi Setup"
- Form displays with two input fields: SSID and password
- Submit button labeled "Test Connection"
- Status area visible but empty

✅ Pass/❌ Fail: __________

**Test scenario 4: Submit valid credentials**

Actions:
1. In form, enter real WiFi network SSID (where device will ultimately connect)
2. Enter correct password for that network
3. Click "Test Connection" button
4. Watch serial log
5. Wait up to 10 seconds

Expected observations:
- Button changes to "Testing..." and disables
- Status area shows: "Testing WiFi connection..."
- Serial log shows: `"State transition: ... → CONNECTING"`
- Serial log shows: `"Attempting WiFi connection to [SSID]"`
- LED continues blinking
- After ~3-5 seconds (if network available):
  - Serial log: `"WiFi connected! IP: 192.168.X.X"`
  - Webpage shows: `"Connected successfully"`
  - New button appears: `"Restart Device"`

✅ Pass/❌ Fail: __________

**Test scenario 5: Device restart after successful connection**

Actions:
1. Click "Restart Device" button on webpage
2. Watch device
3. Monitor serial log

Expected observations:
- Webpage briefly shows: "Restarting..."
- Device reboots
- LED stops blinking (no longer in setup mode)
- Serial log shows: `"State transition: ... → CONNECTED"`
- Serial log shows: `"Credentials saved successfully"`
- Device logs RFID initialization starting
- After ~5 seconds: RFID system fully initialized
- Serial shows: `"System ready!"` with RFID status

✅ Pass/❌ Fail: __________

**Test scenario 6: Configuration persists across reboot**

Actions:
1. Disconnect power from device
2. Wait 5 seconds
3. Power on again
4. Monitor serial log
5. Watch LED behavior

Expected observations:
- Device boots normally
- Serial log shows: `"Device configured; attempting to connect"`
- Serial log shows: `"State transition: ... → CONNECTING"`
- Within ~5 seconds: `"WiFi connected!"`
- LED off (connected state)
- Serial shows RFID initialization
- System ready without any user interaction
- Device automatically joined WiFi network

✅ Pass/❌ Fail: __________

**Test scenario 7: Failed connection attempt**

Actions:
1. Start setup mode again (BUTTON2 5s)
2. Access provisioning page
3. Enter non-existent network SSID (fake name)
4. Click "Test Connection"
5. Wait 10+ seconds

Expected observations:
- Button shows "Testing..."
- Serial log: `"State transition: ... → CONNECTING"`
- Serial log: `"Attempting WiFi connection to [fake]"`
- After ~10 seconds timeout:
  - Serial log: `"Connection timeout"`
  - Serial log: `"State transition: ... → AP_ACTIVE"`
  - Webpage shows error message
  - Form remains available
  - Button re-enables
  - User can modify SSID and retry

✅ Pass/❌ Fail: __________

**Test scenario 8: Multiple retry attempts**

Actions:
1. Try invalid network
2. Get error message
3. Clear SSID field
4. Enter different (but still invalid) network
5. Try again
6. Continue until entering valid network

Expected observations:
- Each attempt goes through same cycle
- Error messages clear on new attempt
- Form accepts multiple retries
- Eventually succeeds with valid credentials
- No crashes or hangs

✅ Pass/❌ Fail: __________

**Test scenario 9: Short button press still works**

Actions:
1. Device in normal operation (connected to WiFi)
2. Quick press BUTTON2 (< 1 second)
3. Watch serial log and RFID system

Expected observations:
- RFID statistics display in serial log
- System continues running
- No entry into setup mode
- LED status unchanged (still off for connected state)

✅ Pass/❌ Fail: __________

**Test scenario 10: LED indicators**

Actions:
Monitor LED throughout all test scenarios

Expected observations:
- Off during normal operation (STA mode, connected)
- Off during unconfigured wait state
- Blinking (1s interval) during AP_ACTIVE state
- Blinking during CONNECTING state
- Off immediately after connection successful
- Off during offline mode

✅ Pass/❌ Fail: __________

**Validation Checklist**

Complete all 10 test scenarios. Mark pass/fail for each:

```
Phase 3 Complete End-to-End Testing Checklist
=============================================

□ Test 1: First boot (unconfigured)
□ Test 2: Enter setup mode via button
□ Test 3: Access provisioning webpage
□ Test 4: Submit and test valid credentials
□ Test 5: Restart device after success
□ Test 6: Configuration persists across reboot
□ Test 7: Failed connection handling
□ Test 8: Multiple retry attempts
□ Test 9: Short button press still works
□ Test 10: LED indicators working correctly

Result: ____ of 10 tests passed
```

**If any test fails:**

1. Note which test failed
2. Check serial log for error messages
3. Verify configuration (config header values correct)
4. Check network connectivity (is WiFi network available?)
5. Review state machine logs for unexpected transitions
6. Isolate issue to specific module (storage, HTTP, WiFi, etc.)
7. Run relevant Phase 1 or Phase 2 test harnesses to validate foundation

**Expected Serial Output Summary**

Unconfigured boot:
```
I (XXX) WIFI_PROV: Device not configured; waiting for user
I (XXX) MAIN: Waiting for WiFi configuration...
```

Setup mode entry:
```
I (XXX) MAIN: BUTTON2 held for 5+ seconds
I (XXX) WIFI_PROV: Setup button pressed - entering setup mode
(device reboots)
```

Setup mode active:
```
I (XXX) WIFI_PROV: State transition: UNCONFIGURED → AP_ACTIVE
I (XXX) WIFI_HTTP: Starting HTTP server
I (XXX) WIFI_HTTP: AP IP: 192.168.4.1
```

WiFi connection test:
```
I (XXX) WIFI_PROV: State transition: AP_ACTIVE → CONNECTING
I (XXX) WIFI_PROV: Attempting WiFi connection to [SSID]
I (XXX) WIFI_PROV: WiFi connected! IP: 192.168.X.X
I (XXX) WIFI_PROV: State transition: CONNECTING → CONNECTED
I (XXX) WIFI_STORAGE: Credentials saved successfully
```

Device restart and boot with saved credentials:
```
I (XXX) WIFI_PROV: Device configured; attempting to connect
I (XXX) WIFI_PROV: State transition: UNCONFIGURED → CONNECTING
I (XXX) WIFI_PROV: Attempting WiFi connection...
I (XXX) WIFI_PROV: WiFi connected! IP: 192.168.X.X
I (XXX) WIFI_PROV: State transition: CONNECTING → CONNECTED
I (XXX) UART_READER: Initializing RFID reader
I (XXX) MAIN: System ready!
```

---

## Phase 3 Summary

**Completion criteria:**
- ✅ HTTP server header created
- ✅ HTTP server implementation complete
- ✅ WiFi integration with state machine working
- ✅ Configuration header created
- ✅ Build system updated
- ✅ All 10 end-to-end tests pass

**Files created in Phase 3:**
- `wifi_http_server.h` (header)
- `wifi_http_server.c` (implementation)
- `wifi_provisioning_config.h` (configuration)

**Files modified in Phase 3:**
- `wifi_provisioning.c` (state machine integration)
- `wifi_provisioning.h` (add restart function)
- `CMakeLists.txt` (build configuration)

**Total implementation complete:**

Phase 1: Storage layer ✅
Phase 2: State machine & button integration ✅
Phase 3: HTTP server & provisioning ✅

**Next steps after this document:**
- User deploys to real devices
- Customizes config header per device (SSID, password, encryption key)
- Generates labels/documentation for setup process
- Optional: Integrate with CI/CD for automated per-device builds
