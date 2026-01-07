# WiFi Provisioning System - Implementation Addendum

## Overview

The WiFi provisioning system was implemented as described in the sequential steps, but critical integration points were not fully specified. This addendum addresses:

1. Loading saved credentials on boot instead of using hardcoded SDK config values
2. Proper feedback mechanism from HTTP handler to provisioning webpage
3. Seamless transition between AP mode and STA mode with credential persistence

---

## Issue 1: Saved Credentials Not Used on Boot

### Current Problem

The `wifi_settings_load()` function exists and works correctly, but is never called during boot. Instead, the WiFi manager uses hardcoded credentials from `sdkconfig.h`:

```c
// In wifi_manager.c (incorrect approach)
#define WIFI_SSID               CONFIG_WIFI_SSID
#define WIFI_PASSWORD           CONFIG_WIFI_PASSWORD

wifi_config_t wifi_config = {
    .sta = {
        .ssid               = WIFI_SSID,
        .password           = WIFI_PASSWORD,
        .threshold.authmode = WIFI_AUTH_WPA2_PSK,
        .pmf_cfg            = {.capable = true, .required = false},
    },
};

esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
esp_wifi_start();
```

This means:
- User provisions device with new credentials via HTTP form
- Credentials saved to NVS partition
- Device reboots
- But boot sequence still uses hardcoded SDK config credentials
- Provisioned credentials are ignored ❌

### Solution Required

**File: `components/wifi_provisioning/wifi_manager.c` (existing file integrating with provisioning)**

**What needs to change:**

1. **Before WiFi initialization, check for saved credentials:**
   ```
   If credentials exist in NVS partition:
     - Load them using wifi_settings_load()
     - Use loaded SSID and password for WiFi connection
   Else if credentials don't exist:
     - Fall back to hardcoded SDK config values (for first boot)
     - OR log warning that device is unconfigured
   ```

2. **Modify WiFi initialization flow:**
   - Call `wifi_settings_is_configured()` to check if credentials saved
   - If yes: call `wifi_settings_load(&creds)` to get SSID and password
   - Create `wifi_config_t` struct dynamically with loaded values
   - If no: use fallback (hardcoded or skip STA mode)

3. **Handle both boot scenarios:**
   - **First boot (unconfigured):** Use hardcoded values OR skip WiFi entirely and wait for provisioning
   - **After provisioning (configured):** Use values from NVS partition
   - **On every subsequent boot:** Load and use NVS credentials (not hardcoded)

### Implementation Approach

In `wifi_manager.c`, modify the WiFi initialization sequence:

**Pseudocode:**

```c
// Instead of static wifi_config_t, make it dynamic
void wifi_manager_init() {
    // Step 1: Check if credentials exist in storage
    wifi_credentials_t saved_creds = {0};
    wifi_storage_error_t load_err = wifi_settings_load(&saved_creds);
    
    // Step 2: Prepare WiFi configuration
    wifi_config_t wifi_config = {.sta = {0}};
    
    if (load_err == WIFI_STORAGE_OK) {
        // Use saved credentials
        strncpy((char*)wifi_config.sta.ssid, saved_creds.ssid, sizeof(wifi_config.sta.ssid)-1);
        strncpy((char*)wifi_config.sta.password, saved_creds.password, sizeof(wifi_config.sta.password)-1);
        ESP_LOGI(TAG, "Using saved WiFi credentials: %s", saved_creds.ssid);
    } else {
        // Fall back to SDK config (or skip)
        strncpy((char*)wifi_config.sta.ssid, CONFIG_WIFI_SSID, sizeof(wifi_config.sta.ssid)-1);
        strncpy((char*)wifi_config.sta.password, CONFIG_WIFI_PASSWORD, sizeof(wifi_config.sta.password)-1);
        ESP_LOGI(TAG, "Using SDK config credentials");
    }
    
    // Set security
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    wifi_config.sta.pmf_cfg.capable = true;
    wifi_config.sta.pmf_cfg.required = false;
    
    // Step 3: Apply configuration
    esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    esp_wifi_start();
}
```

### Key Points

1. **Priority order:**
   - First choice: Credentials from NVS (user-provisioned)
   - Second choice: Hardcoded SDK config (factory defaults)
   - This allows factory defaults while respecting user provisioning

2. **Clean credentials after loading:**
   - Don't keep plaintext in RAM longer than necessary
   - Zero out local `wifi_credentials_t` struct after use
   - Only keep in `wifi_config_t` which ESP-IDF manages

3. **Error handling:**
   - If load fails: log reason and fall back to SDK config
   - Don't crash on storage errors
   - Device can still work with fallback

4. **Integration point:**
   - This must happen BEFORE `esp_wifi_start()`
   - Should happen in `wifi_provisioning_init()` or right after
   - After WiFi provisioning system initializes but before starting WiFi

---

## Issue 2: No Feedback from WiFi Test to HTTP Form

### Current Problem

The HTTP form submission flow is broken:

1. User submits form with credentials
2. HTTP handler receives POST /configure
3. Handler invokes callback `wifi_provisioning_callback_t(ssid, password)`
4. Callback stores credentials and triggers WiFi test
5. **HERE: Handler must wait for test result**
6. Test completes (~10 seconds later)
7. Handler should send JSON response with success/failure
8. **BUT:** Handler has no way to know when test completes

Current issue: Handler waits forever or times out without getting real result.

### Root Cause

The provisioning state machine sets result via:
```c
wifi_http_server_set_connection_result(bool success, const char* error_message);
```

But the HTTP handler (running in separate httpd task) doesn't know when to call this or how to wait for it to be set.

**The synchronization is incomplete.**

### Solution Required

**Files to modify:**
- `components/wifi_provisioning/wifi_http_server.h`
- `components/wifi_provisioning/wifi_http_server.c`
- `components/wifi_provisioning/wifi_provisioning.c`

**What needs to happen:**

1. **Add synchronization mechanism:**
   - HTTP handler needs to wait for state machine to complete WiFi test
   - State machine needs to signal handler when test result available
   - Options: semaphore, flag with timeout, queue, event group

2. **HTTP handler flow (corrected):**
   ```
   POST /configure received
     ↓
   Parse and validate SSID/password
     ↓
   Invoke callback (triggers WiFi test in state machine)
     ↓
   Wait for result signal (with timeout)
     ↓
   Get result (success/failure, error message)
     ↓
   Send JSON response to browser
   ```

3. **State machine flow (corrected):**
   ```
   CONNECTING state
     ↓
   Poll WiFi.status() for ~10 seconds
     ↓
   Connection succeeds OR timeout
     ↓
   Call wifi_http_server_set_connection_result()
     ↓
   Signal/notify waiting HTTP handler
   ```

### Implementation Approach

**In `wifi_http_server.h`, add synchronization:**

```c
/**
 * Wait for WiFi connection test result
 * 
 * Called by POST handler after invoking callback.
 * Blocks until result available or timeout.
 * 
 * @param timeout_ms Maximum time to wait (milliseconds)
 * @param out_success Output: true if connection succeeded
 * @param out_error Output: error message (if failed)
 * @return ESP_OK if result ready, ESP_ERR_TIMEOUT if timeout
 */
esp_err_t wifi_http_server_wait_connection_result(
    uint32_t timeout_ms,
    bool* out_success,
    const char** out_error);
```

**In `wifi_http_server.c`, implement waiting mechanism:**

Option A: Use semaphore (simplest)
```c
static SemaphoreHandle_t result_semaphore = NULL;

void wifi_http_server_set_connection_result(bool success, const char* error_message) {
    // Store result
    last_result.success = success;
    strncpy(last_result.error, error_message ? error_message : "", sizeof(last_result.error)-1);
    
    // Signal waiting handler
    if (result_semaphore) {
        xSemaphoreGive(result_semaphore);
    }
}

esp_err_t wifi_http_server_wait_connection_result(uint32_t timeout_ms, bool* success, const char** error) {
    // Create semaphore on first use
    if (result_semaphore == NULL) {
        result_semaphore = xSemaphoreCreateBinary();
    }
    
    // Wait for signal (with timeout)
    BaseType_t ret = xSemaphoreTake(result_semaphore, pdMS_TO_TICKS(timeout_ms));
    
    if (ret == pdTRUE) {
        // Result ready
        *success = last_result.success;
        *error = last_result.error;
        return ESP_OK;
    } else {
        // Timeout
        return ESP_ERR_TIMEOUT;
    }
}
```

**In POST handler, use wait:**

```c
// POST /configure handler
static esp_err_t post_configure_handler(httpd_req_t *req) {
    // ... parse form data ...
    
    // Invoke callback (triggers WiFi test)
    credentials_callback(ssid, password);
    
    // Wait for result (up to 15 seconds)
    bool success = false;
    const char* error = NULL;
    esp_err_t wait_ret = wifi_http_server_wait_connection_result(15000, &success, &error);
    
    // Send response based on result
    cJSON *response = cJSON_CreateObject();
    if (wait_ret == ESP_OK && success) {
        cJSON_AddStringToObject(response, "status", "success");
        cJSON_AddStringToObject(response, "message", "Connected successfully. Click button to restart.");
    } else if (wait_ret == ESP_OK) {
        cJSON_AddStringToObject(response, "status", "failed");
        cJSON_AddStringToObject(response, "message", error ? error : "Connection failed");
    } else {
        cJSON_AddStringToObject(response, "status", "failed");
        cJSON_AddStringToObject(response, "message", "Connection timeout");
    }
    
    // Send JSON to browser
    char *json_str = cJSON_Print(response);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_send(req, json_str, strlen(json_str));
    
    // Cleanup
    free(json_str);
    cJSON_Delete(response);
    
    return ESP_OK;
}
```

### Key Points

1. **Semaphore approach is simple:**
   - FreeRTOS primitive, already available
   - No custom state tracking needed
   - Works well for one-off signals

2. **Timeout protection:**
   - Handler waits max 15 seconds
   - If timeout, return error to user
   - User can retry

3. **Result storage:**
   - Store success flag and error message in module-level structure
   - Clear after handler reads (or on next request)
   - Thread-safe with semaphore

4. **AP shutdown timing:**
   - AP should NOT shut down immediately after successful connection
   - Wait for handler to send response to browser
   - Only shut down after restart button clicked (or timeout)
   - Otherwise browser never gets response

---

## Issue 3: AP Shuts Down Before Response Sent

### Current Problem

After WiFi connection succeeds:

1. State machine transitions from CONNECTING → CONNECTED
2. Credentials saved to NVS
3. **AP is turned off immediately** ❌
4. Browser gets disconnected
5. Browser never receives success message
6. User sees blank page or connection error

### Why This Happens

In state machine, likely something like:

```c
case WIFI_STATE_CONNECTING:
    // ... poll WiFi.status() ...
    if (status == WL_CONNECTED) {
        // Save credentials
        wifi_settings_save(ssid, password);
        
        // WRONG: Turn off AP here
        WiFi.mode(WIFI_STA);  // ❌ Drops user's browser connection!
        
        // Transition state
        transition_to(WIFI_STATE_CONNECTED);
    }
```

### Solution Required

**Files to modify:**
- `components/wifi_provisioning/wifi_provisioning.c`
- `components/wifi_provisioning/wifi_http_server.c`

**What needs to happen:**

1. **Keep AP alive until user restarts:**
   - When WiFi test succeeds, stay in CONNECTING or go to CONNECTED
   - Do NOT turn off AP immediately
   - Let HTTP handler finish responding to browser
   - Wait for /restart endpoint to be called

2. **Proper shutdown sequence:**
   ```
   WiFi test succeeds
     ↓
   Save credentials
     ↓
   Signal HTTP handler (set_connection_result)
     ↓
   HTTP handler sends JSON success to browser
   Browser shows restart button
     ↓
   User clicks restart button → GET /restart
     ↓
   /restart handler calls esp_restart()
     ↓
   Device reboots (AP automatically shuts down during reboot)
   ```

3. **Don't turn off AP in state machine:**
   - Keep both AP and STA modes active (WIFI_AP_STA)
   - OR keep AP active until restart requested
   - Browser stays connected until user clicks restart

### Implementation Approach

**In state machine, after successful connection:**

```c
case WIFI_STATE_CONNECTING:
    // Poll WiFi status...
    
    if (WiFi.status() == WL_CONNECTED) {
        // Test succeeded
        
        // Get IP
        IPAddress ip = WiFi.localIP();
        ESP_LOGI(TAG, "WiFi connected! IP: %s", ip.toString().c_str());
        
        // Save credentials
        wifi_settings_save(pending_ssid, pending_password);
        
        // Notify HTTP handler of success
        wifi_http_server_set_connection_result(true, NULL);
        
        // Transition to CONNECTED state
        transition_to(WIFI_STATE_CONNECTED);
        
        // DO NOT turn off AP here
        // Wait for user to click restart button
        // /restart handler will call esp_restart()
    }
    break;

case WIFI_STATE_CONNECTED:
    // Connected, AP still running
    // HTTP handler will send success response to browser
    // Browser shows restart button
    // User clicks → /restart called → device restarts
    
    // Monitor connection (optional - could disconnect and retry)
    if (WiFi.status() != WL_CONNECTED) {
        ESP_LOGW(TAG, "WiFi disconnected after successful test");
        // Could transition to OFFLINE or back to AP for retry
    }
    break;
```

**In /restart handler:**

```c
static esp_err_t get_restart_handler(httpd_req_t *req) {
    // Send response
    const char response[] = "Device restarting...";
    httpd_resp_send(req, response, strlen(response));
    
    // Brief delay to ensure response sent
    vTaskDelay(pdMS_TO_TICKS(500));
    
    // Now restart (AP will shut down during reboot)
    esp_restart();
    
    // Never reaches here
    return ESP_OK;
}
```

### Key Points

1. **Keep AP active longer:**
   - Avoids disconnecting browser mid-response
   - User sees success message
   - User can click restart button

2. **Device restart handles AP shutdown:**
   - esp_restart() reboots entire device
   - WiFi module stops automatically
   - No need to manually disable AP

3. **Sequential flow:**
   - Success → save credentials
   - Signal handler
   - Handler sends response
   - User clicks restart
   - Device reboots
   - Next boot: load credentials and connect STA

---

## Issue 4: State Machine Should Load Credentials on Boot

### Current Problem

On boot, the state machine checks `wifi_settings_is_configured()` but doesn't immediately load credentials. When transitioning to CONNECTING state, credentials aren't available in state machine's memory.

### Solution Required

**File: `components/wifi_provisioning/wifi_provisioning.c`**

**What needs to happen:**

1. **On init, if configured, load credentials immediately:**
   ```c
   esp_err_t wifi_provisioning_init(...) {
       // ... existing code ...
       
       if (wifi_settings_is_configured()) {
           // Load credentials into state machine's pending fields
           wifi_credentials_t creds = {0};
           wifi_storage_error_t err = wifi_settings_load(&creds);
           
           if (err == WIFI_STORAGE_OK) {
               strcpy(prov_state.pending_ssid, creds.ssid);
               strcpy(prov_state.pending_password, creds.password);
               
               // Transition to CONNECTING to attempt connection
               transition_to(WIFI_STATE_CONNECTING);
           } else {
               // Load failed, fall back to unconfigured
               transition_to(WIFI_STATE_UNCONFIGURED);
           }
       } else {
           transition_to(WIFI_STATE_UNCONFIGURED);
       }
   }
   ```

2. **On every boot:**
   - If credentials configured: load them and auto-connect (no AP needed)
   - If not configured: wait for user to press setup button
   - This eliminates the manual provisioning step on every boot

---

## Summary of Missing Features

| Feature | Issue | Location | Fix |
|---------|-------|----------|-----|
| Load saved credentials on boot | Never called `wifi_settings_load()` | `wifi_manager.c` | Call load function, use returned values instead of hardcoded SDK config |
| HTTP handler waits for result | Handler doesn't block for test result | `wifi_http_server.c` + state machine | Add semaphore-based wait, signal from state machine |
| AP shuts down too early | Disabled before browser gets response | State machine | Keep AP active until /restart called |
| Auto-connect on boot | State machine doesn't load credentials early | State machine init | Load credentials in init if configured, transition to CONNECTING |

---

## Implementation Order

1. **First: Add credentials loading to boot (Issue 4)**
   - Modify `wifi_provisioning_init()`
   - Load credentials if configured
   - Auto-transition to CONNECTING state

2. **Second: Add synchronization (Issue 2)**
   - Add semaphore wait to `wifi_http_server.h`
   - Implement in `wifi_http_server.c`
   - Use in POST handler

3. **Third: Keep AP alive longer (Issue 3)**
   - Don't disable AP after successful connection
   - Let /restart handler do the shutdown

4. **Fourth: Use loaded credentials for WiFi (Issue 1)**
   - Modify `wifi_manager.c` initialization
   - Call `wifi_settings_load()` to get SSID/password
   - Use returned values instead of hardcoded config

---

## Testing the Fixes

**Test scenario: Complete provisioning workflow**

1. Device boots unconfigured
   - Serial: "Device not configured; waiting for user"
   - RFID doesn't start

2. Press BUTTON2 5 seconds
   - Device enters AP mode
   - LED blinking

3. Submit valid WiFi credentials via form
   - Form shows "Testing..."
   - Serial: "Attempting WiFi connection"
   - After ~5 seconds: form shows "Connected successfully"
   - **IMPORTANT:** Browser stays connected (doesn't disconnect)
   - Restart button appears

4. Click restart button
   - Device reboots
   - LED stops blinking
   - RFID starts

5. Power off and back on
   - Device boots
   - **SHOULD:** Automatically connect to provisioned WiFi
   - **BEFORE:** Would wait for setup button
   - Serial: "Attempting WiFi connection to [saved SSID]"
   - RFID starts automatically

6. Unplug from that WiFi, provision different network
   - BUTTON2 5 seconds → AP mode
   - Submit different credentials
   - Device connects to new network
   - Restart
   - Next boot: connects to new network (old credentials replaced)

---

## Integration with Existing `wifi_manager.c`

The current `wifi_manager.c` likely handles all WiFi initialization. It needs to:

1. Call `wifi_provisioning_init()` early (or ensure called from somewhere)
2. Check `wifi_provisioning_is_ready()` before starting WiFi
3. Load credentials via `wifi_settings_load()` instead of using hardcoded config
4. Handle both configured and unconfigured states

**Rough integration flow:**

```c
// In app_main or early init
void app_init(void) {
    // ... other init ...
    
    // Initialize provisioning (handles NVS, checks configured state)
    wifi_provisioning_init(LED_PIN, 10000);
    
    // Initialize WiFi hardware
    wifi_manager_init();
    
    // Loop until ready (blocks if unconfigured, waiting for setup)
    while (!wifi_provisioning_is_ready()) {
        wifi_provisioning_process();
        vTaskDelay(50);
    }
    
    // Now can start RFID system
    rfid_reader_init();
}

// In wifi_manager.c
void wifi_manager_init(void) {
    // Load credentials (if configured) or use fallback
    wifi_credentials_t creds = {0};
    if (wifi_settings_load(&creds) == WIFI_STORAGE_OK) {
        // Use provisioned credentials
        // ...
    } else {
        // Use SDK config defaults
        // ...
    }
}
```
