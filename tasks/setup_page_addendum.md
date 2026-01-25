# WiFi Provisioning System - HTML File Management & Reliable Message Delivery Addendum

## Overview

This addendum addresses two key improvements to the HTTP server:

1. **External HTML File Storage** - Move embedded HTML/CSS/JS from C source code to separate files
2. **Acknowledgment-Based Message Delivery** - Implement reliable two-way communication between browser and ESP32

These improvements enhance maintainability, allow for better frontend development, and ensure critical messages (success/failure) are reliably delivered and acknowledged.

---

## Part 1: External HTML File Management

### Current Problem

The setup webpage is currently embedded as a large string literal in `wifi_http_server.c`. This causes:
- Difficult to edit HTML (must escape quotes, handle long strings)
- Hard to maintain CSS and JavaScript
- Impossible to preview HTML in browser during development
- Large C source files mixing firmware and web UI code
- Any HTML change requires recompiling C code

### Solution Overview

Store HTML, CSS, and JavaScript in separate files that are:
1. Included in the firmware binary at build time
2. Served directly from SPIFFS filesystem (preferred) or embedded as binary blobs
3. Loaded dynamically when HTTP handler is called
4. Compiled into firmware but editable independently

### Approach: SPIFFS Filesystem with build-time file inclusion

**Why SPIFFS?**
- Lightweight filesystem built into ESP-IDF
- Files compiled into firmware image at build time
- No flash wear concerns (read-only after build)
- Minimal RAM overhead
- Industry standard on ESP32

---

## Implementation Task 1: Create External HTML File

### Task: Create provisioning webpage as separate HTML file

**File to create:**
- `components/wifi_provisioning/spiffs_image/setup.html`

**Directory structure:**
```
components/wifi_provisioning/
├── spiffs_image/
│   └── setup.html          (NEW - standalone HTML file)
├── CMakeLists.txt          (modify)
├── wifi_provisioning.h
├── wifi_provisioning.c
├── wifi_settings_storage.h
├── wifi_settings_storage.c
├── wifi_http_server.h
├── wifi_http_server.c      (modify)
└── dns_server.h/c
```

**What to create in `setup.html`:**

A complete, standalone HTML file with:

1. **Doctype and meta tags:**
   - HTML5 doctype
   - UTF-8 charset
   - Viewport for responsive design
   - Title: "Lighthouse WiFi Setup"

2. **Embedded CSS (in `<style>` tag):**
   - Full styling for form, inputs, status messages
   - Responsive design (works on mobile/tablet/desktop)
   - Support for success/error/info status states
   - Professional appearance matching current inline CSS

3. **HTML structure:**
   - Container div
   - Form with id="setupForm"
   - Two inputs: ssid (text), password (password type)
   - Submit button with id="submitBtn"
   - Status div for displaying results

4. **Embedded JavaScript (in `<script>` tag):**
   - Form submission handler
   - POST to /configure with FormData
   - Parse JSON response
   - Display result (success/error)
   - Handle acknowledgment (see Part 2)
   - Restart button functionality

**HTML file should NOT contain:**
- External stylesheet links (no `<link rel="stylesheet">`)
- External script imports (no `<script src=...>`)
- External image references
- Any external dependencies

**Result:**
- Single, self-contained HTML file
- ~4-5KB total size (HTML + CSS + JS)
- Can be edited in any text editor
- Can be previewed in browser before embedding
- All logic stays in the file

---

## Implementation Task 2: Build Integration - SPIFFS Configuration

### Task: Configure build system to include HTML file in firmware

**Files to create:**

1. **`components/wifi_provisioning/partitions_spiffs.csv`**

Defines SPIFFS partition in partition table:

```csv
# Name,     Type, SubType, Offset,  Size
nvs,        data, nvs,     0x9000,  0x5000,
nvs_settings, data, nvs,   0xe000,  0x2000,
otadata,    data, ota,     0x10000, 0x2000,
app0,       app,  ota_0,   0x12000, 0x140000,
app1,       app,  ota_1,   0x152000, 0x140000,
spiffs,     data, spiffs,  0x292000, 0x6e000,
```

**Or modify existing `partitions.csv` to add:**
```
spiffs,     data, spiffs,  [offset], 0x6e000,
```

Where:
- Offset: Must not overlap with other partitions
- Size: 0x6e000 (448KB) - sufficient for HTML + future files
- Type: data, SubType: spiffs

**2. `components/wifi_provisioning/CMakeLists.txt`**

Modify to include SPIFFS build:

```cmake
idf_component_register(
    SRCS
        "wifi_provisioning.c"
        "wifi_settings_storage.c"
        "wifi_http_server.c"
        "dns_server.c"
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
        "lwip"
        "spiffs"                    # NEW
)

# NEW: Build SPIFFS image from spiffs_image directory
set(SPIFFS_IMAGE_FLASHING_MODE raw)
spiffs_create_partition_image(spiffs ../spiffs_image FLASH_IN_BINARY)
```

**What this does:**
- Tells ESP-IDF build system to look in `spiffs_image/` directory
- Converts HTML file to SPIFFS filesystem image
- Includes it in the firmware binary
- On first boot, SPIFFS partition is populated with files

---

## Implementation Task 3: Initialize SPIFFS in Firmware

### Task: Add SPIFFS initialization code

**Modify: `components/wifi_provisioning/wifi_http_server.c`**

Add at start of module:

```c
// Include SPIFFS
#include "esp_spiffs.h"

// SPIFFS mount configuration
static bool spiffs_initialized = false;

/**
 * Initialize SPIFFS filesystem
 * Must be called once before serving files
 */
static esp_err_t init_spiffs(void) {
    if (spiffs_initialized) {
        return ESP_OK;
    }
    
    ESP_LOGI(TAG, "Initializing SPIFFS");
    
    esp_vfs_spiffs_conf_t conf = {
        .base_path = "/spiffs",           // Mount point
        .partition_label = "spiffs",      // Partition name from partitions.csv
        .max_files = 5,                   // Max open files
        .format_if_mount_failed = false,  // Don't auto-format
    };
    
    esp_err_t ret = esp_vfs_spiffs_register(&conf);
    
    if (ret != ESP_OK) {
        if (ret == ESP_ERR_ESP_SPIFFS_NOT_FOUND) {
            ESP_LOGE(TAG, "SPIFFS partition not found. Check partitions.csv");
        } else if (ret == ESP_ERR_ESP_SPIFFS_INVALID_SIZE) {
            ESP_LOGE(TAG, "SPIFFS size invalid. Check partition size in partitions.csv");
        } else {
            ESP_LOGE(TAG, "SPIFFS init failed: %s", esp_err_to_name(ret));
        }
        return ret;
    }
    
    // Verify files exist
    FILE *f = fopen("/spiffs/setup.html", "r");
    if (f == NULL) {
        ESP_LOGE(TAG, "setup.html not found in SPIFFS");
        return ESP_ERR_NOT_FOUND;
    }
    fclose(f);
    
    spiffs_initialized = true;
    ESP_LOGI(TAG, "SPIFFS initialized successfully");
    
    return ESP_OK;
}
```

**Call during HTTP server startup:**

```c
esp_err_t wifi_http_server_start(const char* ap_ssid, const char* ap_password) {
    // Initialize SPIFFS (load HTML file)
    esp_err_t spiffs_ret = init_spiffs();
    if (spiffs_ret != ESP_OK) {
        ESP_LOGE(TAG, "SPIFFS init failed, cannot serve setup page");
        return spiffs_ret;
    }
    
    // ... rest of HTTP server startup ...
}
```

---

## Implementation Task 4: Serve HTML File from SPIFFS

### Task: Modify GET "/" handler to serve HTML from file

**Modify: `components/wifi_provisioning/wifi_http_server.c`**

Replace inline HTML string with file serving:

```c
/**
 * GET / handler - Serve setup.html from SPIFFS
 */
static esp_err_t get_provisioning_page_handler(httpd_req_t *req) {
    ESP_LOGI(TAG, "GET / - Serving setup page");
    
    // Open setup.html from SPIFFS
    FILE *f = fopen("/spiffs/setup.html", "r");
    if (f == NULL) {
        ESP_LOGE(TAG, "Failed to open setup.html");
        httpd_resp_send_404(req);
        return ESP_OK;  // 404 sent, no error from handler
    }
    
    // Determine file size
    fseek(f, 0, SEEK_END);
    size_t file_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    // Set HTTP headers
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    httpd_resp_set_hdr(req, "Content-Length", itoa(file_size, NULL, 10));
    
    // Send file in chunks (avoid large buffer)
    char buffer[512];
    size_t read_bytes;
    while ((read_bytes = fread(buffer, 1, sizeof(buffer), f)) > 0) {
        if (httpd_resp_send_chunk(req, buffer, read_bytes) != ESP_OK) {
            ESP_LOGE(TAG, "Error sending setup page chunk");
            fclose(f);
            return ESP_FAIL;
        }
    }
    
    // End response
    httpd_resp_send_chunk(req, NULL, 0);
    fclose(f);
    
    return ESP_OK;
}
```

**Key points:**
- Opens file from `/spiffs/setup.html`
- Reads in chunks (doesn't load entire file into RAM)
- Sets proper Content-Type header
- Handles errors gracefully
- Returns 404 if file not found

---

## Part 2: Acknowledgment-Based Message Delivery

### Current Problem

Currently, HTTP handler sends result to browser, but:
- No guarantee browser receives it
- No confirmation browser displays message
- ESP immediately reboots on success
- If browser doesn't get response (network hiccup, etc.), user sees blank page

### Solution Overview

Implement request-response-acknowledgment pattern:

```
ESP sends result (JSON)
  ↓
Browser receives and displays
  ↓
Browser sends acknowledgment (POST /ack)
  ↓
ESP receives ack, then safe to restart
```

---

## Implementation Task 5: Add Result Storage & Acknowledgment Endpoint

### Task: Implement reliable message delivery with acknowledgment

**Modify: `components/wifi_provisioning/wifi_http_server.h`**

Add new function:

```c
/**
 * Wait for browser acknowledgment
 * 
 * Called by /configure handler after sending result.
 * Blocks until browser sends acknowledgment or timeout.
 * 
 * Browser sends acknowledgment to /ack endpoint after displaying result.
 * This ensures result was received and displayed before proceeding.
 * 
 * @param timeout_ms Maximum time to wait for acknowledgment (e.g., 10000 for 10s)
 * @return ESP_OK if acknowledgment received, ESP_ERR_TIMEOUT if timeout
 */
esp_err_t wifi_http_server_wait_for_ack(uint32_t timeout_ms);
```

**Modify: `components/wifi_provisioning/wifi_http_server.c`**

Add acknowledgment system:

```c
// Module-level state
typedef struct {
    bool ack_received;
    SemaphoreHandle_t ack_semaphore;
} ack_state_t;

static ack_state_t ack_state = {
    .ack_received = false,
    .ack_semaphore = NULL
};

/**
 * POST /ack handler - Browser acknowledgment
 * 
 * Called by browser after displaying result
 * Signals that user has seen the message
 */
static esp_err_t post_ack_handler(httpd_req_t *req) {
    ESP_LOGI(TAG, "Browser acknowledged result");
    
    // Mark acknowledgment received
    ack_state.ack_received = true;
    
    // Signal waiting handler
    if (ack_state.ack_semaphore) {
        xSemaphoreGive(ack_state.ack_semaphore);
    }
    
    // Return simple response
    httpd_resp_set_type(req, "application/json");
    const char *response = "{\"status\":\"ack_received\"}";
    httpd_resp_send(req, response, strlen(response));
    
    return ESP_OK;
}

/**
 * Wait for browser acknowledgment
 */
esp_err_t wifi_http_server_wait_for_ack(uint32_t timeout_ms) {
    // Create semaphore on first use
    if (ack_state.ack_semaphore == NULL) {
        ack_state.ack_semaphore = xSemaphoreCreateBinary();
    }
    
    // Reset acknowledgment flag
    ack_state.ack_received = false;
    
    // Wait for acknowledgment
    BaseType_t ret = xSemaphoreTake(ack_state.ack_semaphore, pdMS_TO_TICKS(timeout_ms));
    
    if (ret == pdTRUE) {
        ESP_LOGI(TAG, "Acknowledgment received from browser");
        return ESP_OK;
    } else {
        ESP_LOGW(TAG, "Acknowledgment timeout - browser may not have received result");
        return ESP_ERR_TIMEOUT;
    }
}
```

**Register /ack handler in wifi_http_server_start():**

```c
// Register acknowledgment handler
httpd_uri_t ack_uri = {
    .uri       = "/ack",
    .method    = HTTP_POST,
    .handler   = post_ack_handler,
    .user_ctx  = NULL
};
httpd_register_uri_handler(server, &ack_uri);
```

---

## Implementation Task 6: Modify JavaScript for Acknowledgment

### Task: Update browser JavaScript to send acknowledgment after displaying result

**Modify: `spiffs_image/setup.html`**

Update JavaScript form handler:

```javascript
form.onsubmit = async (e) => {
    e.preventDefault();
    const fd = new FormData(form);
    
    submitBtn.disabled = true;
    submitBtn.textContent = 'Testing...';
    status.className = 'status show info';
    status.textContent = 'Testing WiFi connection...';
    
    try {
        // Send credentials to /configure
        const res = await fetch('/configure', { method: 'POST', body: fd });
        const json = await res.json();
        
        if (json.status === 'success') {
            // Display success message
            status.className = 'status show success';
            status.innerHTML = json.message + 
                '<br><button class="restart-btn" onclick="handleRestart()">Restart Device</button>';
            
            // NEW: Send acknowledgment to ESP
            try {
                await fetch('/ack', { method: 'POST' });
                console.log('Acknowledgment sent to ESP');
            } catch (err) {
                console.warn('Failed to send acknowledgment:', err);
            }
            
        } else {
            // Display error message
            status.className = 'status show error';
            status.textContent = json.message;
            
            // NEW: Send acknowledgment even for errors
            try {
                await fetch('/ack', { method: 'POST' });
            } catch (err) {
                console.warn('Failed to send acknowledgment:', err);
            }
            
            // Re-enable form for retry
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

// NEW: Handle restart with proper timing
function handleRestart() {
    // Brief delay to ensure /ack is processed
    setTimeout(() => {
        location.href = '/restart';
    }, 200);
}
```

**Key changes:**
- After displaying result (success or error), send POST to `/ack`
- Don't block on acknowledgment (don't await it, fire and forget)
- Restart button calls `handleRestart()` which waits slightly before triggering restart
- Acknowledgment timeout is handled gracefully (ESP continues after timeout)

---

## Implementation Task 7: Modify /configure Handler to Wait for Acknowledgment

### Task: Make /configure handler wait for browser acknowledgment before returning

**Modify: `components/wifi_provisioning/wifi_http_server.c`**

Update POST /configure handler:

```c
/**
 * POST /configure handler - Credential submission with acknowledgment
 */
static esp_err_t post_configure_handler(httpd_req_t *req) {
    // Parse and validate credentials
    // (existing code - parse SSID and password from form)
    
    // Invoke callback to test WiFi
    credentials_callback(ssid, password);
    
    // Wait for test result
    bool success = false;
    const char* error = NULL;
    esp_err_t wait_ret = wifi_http_server_wait_connection_result(15000, &success, &error);
    
    // Build response JSON
    cJSON *response = cJSON_CreateObject();
    if (wait_ret == ESP_OK && success) {
        cJSON_AddStringToObject(response, "status", "success");
        cJSON_AddStringToObject(response, "message", 
            "Connected successfully. Click button to restart.");
    } else {
        cJSON_AddStringToObject(response, "status", "failed");
        cJSON_AddStringToObject(response, "message", 
            error ? error : "Connection failed");
    }
    
    // Send response
    char *json_str = cJSON_Print(response);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_send(req, json_str, strlen(json_str));
    
    // NEW: Wait for browser acknowledgment (max 10 seconds)
    // Browser must display result and send /ack before we continue
    esp_err_t ack_ret = wifi_http_server_wait_for_ack(10000);
    if (ack_ret == ESP_OK) {
        ESP_LOGI(TAG, "Browser acknowledged result");
    } else {
        ESP_LOGW(TAG, "Browser acknowledgment timeout - continuing anyway");
    }
    
    // Cleanup
    free(json_str);
    cJSON_Delete(response);
    
    return ESP_OK;
}
```

**Flow:**
1. Handler sends result JSON to browser
2. Browser receives and displays it
3. Browser sends acknowledgment to `/ack`
4. Handler receives acknowledgment via semaphore
5. Handler returns to client
6. Browser can now safely call `/restart`
7. `/restart` handler reboots device

---

## Implementation Task 8: Update CMakeLists.txt for SPIFFS

### Task: Configure build system for SPIFFS and cJSON

**Modify: `components/wifi_provisioning/CMakeLists.txt`**

```cmake
idf_component_register(
    SRCS
        "wifi_provisioning.c"
        "wifi_settings_storage.c"
        "wifi_http_server.c"
        "dns_server.c"
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
        "lwip"
        "spiffs"                        # NEW
        "cjson"                         # NEW (for JSON handling)
)

# Build SPIFFS filesystem image
set(SPIFFS_IMAGE_FLASHING_MODE raw)
spiffs_create_partition_image(spiffs spiffs_image FLASH_IN_BINARY)
```

---

## Summary of Changes

### Files Created:
- `components/wifi_provisioning/spiffs_image/setup.html` - External HTML/CSS/JS file

### Files Modified:
- `components/wifi_provisioning/wifi_http_server.h` - Add wait_for_ack() declaration
- `components/wifi_provisioning/wifi_http_server.c` - Add SPIFFS init, /ack handler, file serving
- `components/wifi_provisioning/CMakeLists.txt` - Add SPIFFS build configuration
- Project `partitions.csv` - Add SPIFFS partition (if not already present)

### New Functionality:
1. **HTML file in SPIFFS:**
   - Editable without recompiling C code
   - Can be previewed in browser
   - Version controlled separately

2. **Acknowledgment system:**
   - Browser confirms receipt of result
   - ESP waits for acknowledgment before restarting
   - Timeout protection (ESP continues after timeout)
   - Works for both success and error cases

---

## Testing Checklist

```
External HTML & Acknowledgment Testing
======================================

Part 1: External HTML File
□ SPIFFS partition added to partitions.csv
□ spiffs_image directory created with setup.html
□ Build succeeds: idf.py build
□ SPIFFS image included in firmware
□ SPIFFS initializes on startup
□ GET / returns HTML file (not inline string)
□ HTML displays correctly in browser
□ Form submission works
□ No size regression compared to inline HTML

Part 2: Acknowledgment System
□ /ack endpoint registered
□ Browser sends POST /ack after displaying result
□ ESP receives acknowledgment via semaphore
□ ESP logs acknowledgment receipt
□ Success message + restart: Browser acks, device restarts
□ Error message + retry: Browser acks, form remains
□ Timeout protection: ESP continues after 10s if no ack
□ Device doesn't restart if ack not received (for success case)
□ LED status correct through entire flow
□ No memory leaks

Complete Flow
□ User connects to AP
□ Setup page loads from SPIFFS
□ User submits credentials
□ Form disables, shows "Testing..."
□ After ~5 seconds: Shows success or error
□ Browser sends acknowledgment automatically
□ ESP receives acknowledgment
□ Restart button appears (or form resets)
□ Click restart → device reboots cleanly
□ Next boot: Auto-connects to WiFi
□ RFID starts normally
```

---

## Key Benefits

**From External HTML File:**
- Frontend developers can edit HTML without knowing C
- Can preview in browser before compiling
- CSS/JS changes don't require C recompilation
- Easier version control
- Professional separation of concerns

**From Acknowledgment System:**
- Reliable message delivery confirmation
- Browser can't restart device until result displayed
- Handles network hiccups gracefully
- Timeout protection prevents hang
- Works for both success and error cases

---

## Future Enhancements

1. **Multiple pages** - Add more HTML files to SPIFFS (status page, advanced settings, etc.)
2. **CSS/JS split** - Separate setup.css and setup.js if needed (current single-file approach preferred)
3. **Version info** - Display firmware version on setup page
4. **MQTT settings** - Extend form to include MQTT broker address
5. **Scan results** - Show list of available WiFi networks
