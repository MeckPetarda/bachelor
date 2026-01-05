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

## PHASE 3: HTTP SERVER & WEB PROVISIONING

[This phase will be covered in subsequent steps - starting with Step 3.1: Create WiFi HTTP Server Header]

---

## Summary of Phase 1 & 2 Completion

At the end of Phase 2, you will have:
- ✅ NVS settings partition configured
- ✅ Credential storage implemented (encrypted)
- ✅ State machine framework operational
- ✅ Button integration complete (5s press detected)
- ✅ LED blinking in AP mode
- ✅ Device boots to "waiting for config" state if unconfigured
- ✅ Setup mode triggerable and state transitions working

**NOT YET IMPLEMENTED:**
- HTTP server
- WiFi connection testing
- Credential provisioning form
- Actual WiFi STA mode connection

These will be completed in Phase 3.

---

## How to Use This Document

1. **Follow steps in order** - each builds on previous ones
2. **Verify each step** before moving to next
3. **Commit after each step** - easier to track progress and debug issues
4. **Reference the implementation plan** - each step links to relevant sections
5. **Test incrementally** - don't wait until all phases complete to test

**Estimated time investment:**
- Phase 1 (5 steps): 4-6 hours
- Phase 2 (7 steps): 2-3 hours
- Phase 3 (not yet written): 4-6 hours

**Total estimated: 10-15 hours for complete implementation**

Each step is designed to be completable in 1-4 hours of focused work.
