# WiFi Provisioning System - Captive Portal Implementation Tasks

## Overview

This document breaks down the captive portal feature into discrete, implementable tasks. The captive portal allows automatic browser opening when users connect to the ESP32's AP, eliminating the need to manually navigate to http://192.168.4.1.

**Total estimated effort:** 4-6 hours

---

## Task 1: Create DNS Server Header File

**Objective:** Define the DNS server interface.

**File to create:**
- `components/wifi_provisioning/dns_server.h`

**What to define:**

Create a minimal header file with:

1. **Three public function declarations:**
   - `esp_err_t dns_server_start(void)`
   - `esp_err_t dns_server_stop(void)`
   - `bool dns_server_is_running(void)`

2. **Function documentation:**
   - Clear descriptions of what each does
   - Parameters and return values
   - Important notes (e.g., "Responds to ALL DNS queries with 192.168.4.1")

3. **No data structures or callbacks needed** (internal implementation detail)

**Documentation should explain:**
- DNS server listens on UDP port 53
- Responds to any domain query with AP IP address (192.168.4.1)
- Used for captive portal detection
- Start when entering AP_ACTIVE state
- Stop when exiting AP_ACTIVE state

**Reference:** WIFI_PROVISIONING_CAPTIVE_PORTAL.md "DNS Server Implementation Details"

**Verification:**
- File compiles with no errors
- Can be included by other modules
- Function signatures match usage in later tasks

---

## Task 2: Implement DNS Server

**Objective:** Implement DNS protocol handling for captive portal.

**File to create:**
- `components/wifi_provisioning/dns_server.c`

**What to implement:**

1. **Module state:**
   - UDP socket handle (for listening on port 53)
   - Running flag
   - Task handle (optional, if using separate task)

2. **dns_server_start() function:**
   - Create UDP socket listening on 0.0.0.0:53
   - Create FreeRTOS task to handle DNS queries (or use non-blocking socket with main loop)
   - Log startup: "DNS server started on port 53"
   - Return ESP_OK on success
   - Handle errors gracefully (socket creation failure, etc.)

3. **DNS query handler task/loop:**
   - Continuously receive DNS query packets on UDP port 53
   - For ANY query received:
     - Parse basic DNS header (extract query ID)
     - Build response packet:
       - Copy query ID from question
       - Set response flag (0x8000 in flags field)
       - Include A record answer with IP 192.168.4.1
       - Set TTL (e.g., 60 seconds)
     - Send response back to client
   - No need to parse domain name (respond to all with same IP)

4. **dns_server_stop() function:**
   - Close UDP socket
   - Delete task if using separate task
   - Clear running flag
   - Log shutdown

5. **dns_server_is_running() function:**
   - Return running flag status

**DNS Response Format (simplified):**

For any query, return:
- Query ID (from request)
- Standard response flags
- Answer section with:
  - A record type (IPv4 address)
  - IP: 192.168.4.1
  - TTL: 60 seconds

**Implementation Options:**

Option A: **Separate task (simpler)**
- Create task in start(), delete in stop()
- Task blocks on recvfrom() waiting for queries
- Process one at a time

Option B: **Non-blocking in main loop (more complex)**
- Create non-blocking socket
- Poll in wifi_provisioning_process()
- Handle multiple queued packets

**Recommendation:** Use Option A (separate task) - simpler, doesn't affect main loop timing.

**Key Implementation Details:**

```
UDP socket setup:
  - AF_INET, SOCK_DGRAM
  - Bind to 0.0.0.0:53
  - Enable SO_REUSEADDR to allow quick restart

DNS query handling loop:
  - recvfrom() to get query packet and client address
  - Extract query ID from packet (first 2 bytes)
  - Build response (copy query + add answer section)
  - sendto() response back to client address

Response packet structure (simplified):
  [ID: 2 bytes]
  [Flags: 2 bytes with response bit set]
  [Question count: 2 bytes]
  [Answer count: 2 bytes] = 1
  [Remaining counts: 4 bytes] = 0
  [Original query data]
  [Answer section: name + type (A) + class (IN) + TTL (60) + IP (192.168.4.1)]
```

**Error handling:**
- Socket creation failure → log error, return ESP_FAIL
- recvfrom failure → log warning, continue
- sendto failure → log warning, continue
- Graceful shutdown on task delete

**Testing after this task:**
1. DNS server starts without crashing
2. Can verify with `nslookup` or `dig` commands from connected client:
   ```
   $ nslookup google.com 192.168.4.1
   Server:    192.168.4.1
   Address:   192.168.4.1#53
   
   Name:      google.com
   Address:   192.168.4.1
   ```
3. DNS server stops cleanly
4. No memory leaks (verify with `heap` command)

---

## Task 3: Add Wildcard HTTP Handler for Captive Portal Redirect

**Objective:** Intercept non-setup HTTP requests and redirect to setup page.

**File to modify:**
- `components/wifi_provisioning/wifi_http_server.c`

**What to implement:**

1. **New HTTP handler function:**
   ```
   captive_portal_handler(httpd_req_t *req)
   ```

   Behavior:
   - Receives ANY HTTP GET request not matching other routes
   - Returns HTTP 302 (Found) status
   - Sets Location header to "http://192.168.4.1/"
   - Sends empty body (standard for 302)
   - Returns ESP_OK

2. **HTTP response format:**
   ```
   HTTP/1.1 302 Found
   Location: http://192.168.4.1/
   Content-Length: 0
   [empty body]
   ```

3. **Handler registration in wifi_http_server_start():**
   - Register specific handlers FIRST:
     - GET "/" (root, returns HTML form)
     - POST "/configure" (form submission)
     - GET "/restart" (device restart)
   - Register wildcard handler LAST:
     - Wildcard route: "/*"
     - Method: HTTP_GET only
     - This ensures specific routes match before wildcard

4. **Why order matters:**
   - ESP-IDF HTTP server matches handlers in registration order
   - Specific routes must match first
   - Wildcard "/*" is lowest priority (catches everything else)
   - Without proper order, all requests hit wildcard (breaks setup form)

**Handler pseudocode:**

```c
static esp_err_t captive_portal_handler(httpd_req_t *req) {
    // Set response status to 302 Found
    httpd_resp_set_status(req, "302 Found");
    
    // Add Location header pointing to setup page
    httpd_resp_set_hdr(req, "Location", "http://192.168.4.1/");
    
    // Send response with empty body
    httpd_resp_send(req, NULL, 0);
    
    return ESP_OK;
}
```

**Registration in wifi_http_server_start():**

```c
// After registering specific handlers:
httpd_register_uri_handler(server, &get_root_uri);
httpd_register_uri_handler(server, &post_configure_uri);
httpd_register_uri_handler(server, &get_restart_uri);

// THEN register wildcard (lowest priority):
httpd_uri_t wildcard_uri = {
    .uri       = "/*",
    .method    = HTTP_GET,
    .handler   = captive_portal_handler,
    .user_ctx  = NULL
};
httpd_register_uri_handler(server, &wildcard_uri);
```

**What requests this handler catches:**

- `GET http://captive.apple.com/hotspot.html` → redirects to `/`
- `GET http://connectivitycheck.gstatic.com/generate_204` → redirects to `/`
- `GET http://windows.ipv6.msftncsi.com/ncsi.txt` → redirects to `/`
- `GET http://any-random-domain.com/any/path` → redirects to `/`
- Any GET request not matching "/" or other specific routes

**What requests this handler should NOT catch:**

- `POST /configure` (should match POST handler)
- `GET /restart` (should match specific handler)
- `GET /` (should match root handler)

**Testing after this task:**

1. From connected device, try accessing non-existent domain:
   ```
   $ curl -i http://test-nonexistent-domain.com/
   HTTP/1.1 302 Found
   Location: http://192.168.4.1/
   ```

2. Browser follows redirect (automatic)

3. Verify specific handlers still work:
   - `GET http://192.168.4.1/` → returns HTML form ✓
   - `POST http://192.168.4.1/configure` → handles form ✓
   - `GET http://192.168.4.1/restart` → restarts device ✓

4. Verify wildcard doesn't interfere with above

---

## Task 4: Integrate DNS Server with State Machine

**Objective:** Start/stop DNS server when entering/exiting AP mode.

**File to modify:**
- `components/wifi_provisioning/wifi_provisioning.c`

**What to implement:**

1. **Add includes:**
   ```c
   #include "dns_server.h"
   ```

2. **In AP_ACTIVE state entry:**
   - After starting HTTP server
   - Call `dns_server_start()`
   - Check return code
   - Log: "DNS server started - captive portal enabled"
   - Continue to HTTP server startup

3. **In state exits from AP_ACTIVE:**
   - When transitioning to CONNECTING, CONNECTED, or other states
   - Call `dns_server_stop()`
   - Log shutdown

4. **Safe shutdown:**
   - DNS server stop should be idempotent (safe to call multiple times)
   - Check `dns_server_is_running()` before stopping (optional safety check)
   - Handle stop failures gracefully (log warning, continue)

**State machine flow with DNS:**

```c
// In wifi_provisioning_process()

case WIFI_STATE_AP_ACTIVE:
    // On first entry to this state
    if (first_entry) {
        // Start HTTP server (existing)
        wifi_http_server_start(WIFI_SETUP_AP_SSID, WIFI_SETUP_AP_PASSWORD);
        
        // NEW: Start DNS server
        esp_err_t dns_ret = dns_server_start();
        if (dns_ret != ESP_OK) {
            ESP_LOGE(TAG, "DNS server start failed: %s", esp_err_to_name(dns_ret));
        } else {
            ESP_LOGI(TAG, "Captive portal enabled - devices will see setup page automatically");
        }
        
        first_entry = false;
    }
    break;

case WIFI_STATE_CONNECTING:
case WIFI_STATE_CONNECTED:
case WIFI_STATE_OFFLINE:
    // On exit from AP_ACTIVE
    if (was_in_ap_active) {
        // Stop HTTP server (existing)
        wifi_http_server_stop();
        
        // NEW: Stop DNS server
        dns_server_stop();
        
        was_in_ap_active = false;
    }
    break;
```

**Key points:**

- DNS server must start BEFORE user connects (start on entry to AP_ACTIVE)
- DNS server must stop when AP is no longer needed (exit AP_ACTIVE)
- Device enters AP_ACTIVE when:
  - Unconfigured on boot
  - User presses BUTTON2 for 5 seconds
  - WiFi connection test fails (retry)
- Device exits AP_ACTIVE when:
  - WiFi connection succeeds (transition to CONNECTED)
  - Manual transition occurs (device restart)

**Logging:**
- Log DNS server start with "Captive portal enabled"
- Log DNS server stop when exiting AP mode
- Log any errors during start/stop

**Testing after this task:**

1. Device boots, enters AP mode
   - Serial log shows: "Captive portal enabled"
   - DNS server running

2. Connect device (phone/laptop) to AP
   - Connectivity check requests reach DNS server
   - DNS server responds with 192.168.4.1

3. Device exits AP mode (after successful WiFi connection)
   - Serial log shows DNS server stopped
   - DNS server no longer responding

4. Re-enter AP mode
   - DNS server starts again
   - Captive portal works again

---

## Task 5: Update Build Configuration

**Objective:** Add DNS server component to CMakeLists.txt and ensure all dependencies available.

**File to modify:**
- `components/wifi_provisioning/CMakeLists.txt`

**What to change:**

1. **Update SRCS list to include new DNS server implementation:**
   ```cmake
   SRCS
       "wifi_provisioning.c"
       "wifi_settings_storage.c"
       "wifi_http_server.c"
       "dns_server.c"           # NEW
   ```

2. **Add lwip to REQUIRES (for UDP socket):**
   ```cmake
   REQUIRES
       "nvs_flash"
       "mbedtls"
       "esp_common"
       "freertos"
       "esp_timer"
       "esp_wifi"
       "esp_http_server"
       "driver"
       "lwip"                   # NEW - for UDP socket API
   ```

3. **Verify includes:**
   - INCLUDE_DIRS should be "."
   - Allows other modules to include dns_server.h

**Complete updated CMakeLists.txt should look like:**

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
)
```

**What each dependency provides:**
- `lwip` - UDP socket API (socket(), sendto(), recvfrom(), bind())
- `freertos` - Task API (xTaskCreate(), xTaskDelete())
- `esp_http_server` - HTTP server (already present)

**Verification:**

1. Run `idf.py build`
2. No compilation errors
3. No missing dependencies
4. Executable size increased slightly (DNS server code ~200 bytes)

---

## Task 6: Test DNS Server Connectivity

**Objective:** Verify DNS server responds correctly to queries.

**Prerequisites:**
- Tasks 1-5 complete
- Device built and flashed with DNS server
- Device in AP mode (BUTTON2 5s press)
- Computer or phone connected to ESP32's AP

**Test procedure:**

### Test 6a: DNS Query from Linux/Mac

**From connected device terminal:**

```bash
# Query ESP32 DNS server for any domain
nslookup google.com 192.168.4.1

# Expected output:
# Server:    192.168.4.1
# Address:   192.168.4.1#53
# 
# Name:      google.com
# Address:   192.168.4.1
```

Alternative using dig:
```bash
dig @192.168.4.1 google.com

# Expected:
# ... ANSWER SECTION:
# google.com.        60    IN    A    192.168.4.1
```

**Pass criteria:**
- ✓ Receives response (doesn't timeout)
- ✓ Response shows 192.168.4.1 as answer
- ✓ TTL shows 60 (or configured value)

### Test 6b: Device Connectivity Check

**From connected device browser:**

1. Open HTTP request to non-192.168.4.1 domain:
   ```
   http://captive.apple.com/hotspot.html
   ```

2. Expected behavior:
   - Browser shows setup page (from 192.168.4.1)
   - OR browser shows redirect notification

3. Check if automatic captive portal popup appears:
   - iPhone: Safari opens automatically (if system detects)
   - Android: Notification appears (tap to open)
   - Windows: "Sign in to network" popup

### Test 6c: Serial Log Verification

**Monitor serial output while testing:**

```
I (XXX) DNS_SERVER: DNS server started on port 53
I (XXX) DNS_SERVER: Received DNS query from 192.168.4.X
I (XXX) DNS_SERVER: Responding with 192.168.4.1
```

**Pass criteria:**
- ✓ Log shows DNS queries received
- ✓ Log shows responses sent
- ✓ No crashes or exceptions
- ✓ Device remains stable

### Test 6d: Connection Performance

**Test that setup still works with DNS server:**

1. Open http://192.168.4.1 in browser
2. Submit WiFi credentials
3. Form response received (should still work)
4. Device reboots successfully
5. Device connects to configured WiFi

**Pass criteria:**
- ✓ All provisioning steps work
- ✓ No slowness (DNS doesn't add noticeable latency)
- ✓ Credentials saved correctly

---

## Task 7: Integration Testing - Captive Portal on Different Devices

**Objective:** Verify captive portal works on actual devices (iPhone, Android, Windows, Mac).

**Setup:**
- Device in AP mode
- DNS server running
- HTTP server with wildcard handler running
- Connected test devices

### Test 7a: iPhone/iPad (iOS)

**Steps:**
1. Settings → WiFi → Forget "LIGHTHOUSE_SETUP"
2. Scan networks, find "LIGHTHOUSE_SETUP"
3. Tap to connect
4. Enter AP password
5. Observe: Does Safari open automatically?

**Expected result:**
- ✓ After connecting, Safari opens automatically
- ✓ Shows setup form
- ✓ Can submit credentials
- ✓ Sees success message
- ✓ Can restart device

**If not automatic:**
- Settings → WiFi → "LIGHTHOUSE_SETUP" → "Other"
- Tap "Sign in to network" when prompted

### Test 7b: Android

**Steps:**
1. Settings → WiFi → Forget "LIGHTHOUSE_SETUP"
2. Scan networks, find "LIGHTHOUSE_SETUP"
3. Tap to connect
4. Enter AP password
5. Observe: Does notification appear?

**Expected result:**
- ✓ After connecting, notification appears: "Sign in to network"
- ✓ Tap notification → browser opens
- ✓ Shows setup form
- ✓ Can complete provisioning

**If not automatic:**
- Open browser manually
- Navigate to any HTTP URL (not HTTPS)
- Should redirect to setup page

### Test 7c: Windows

**Steps:**
1. Settings → WiFi → Forget "LIGHTHOUSE_SETUP"
2. Available networks list, find "LIGHTHOUSE_SETUP"
3. Click to connect
4. Enter AP password
5. Observe: Does popup appear?

**Expected result:**
- ✓ After connecting, "Sign in to this network" popup appears
- ✓ Opens browser automatically
- ✓ Shows setup form
- ✓ Can complete provisioning

### Test 7d: MacOS

**Steps:**
1. WiFi menu → Forget "LIGHTHOUSE_SETUP"
2. WiFi menu → Select "LIGHTHOUSE_SETUP"
3. Enter AP password
4. Observe: Does browser open?

**Expected result:**
- ✓ Safari opens automatically after connection
- ✓ Shows setup form
- ✓ Can complete provisioning

### Test 7e: Linux (no auto-detect expected)

**Steps:**
1. Connect to "LIGHTHOUSE_SETUP" AP
2. Verify connectivity: `ping 192.168.4.1`
3. Manually open browser
4. Navigate to `http://192.168.4.1`

**Expected result:**
- ✓ Can connect successfully
- ✓ Manual navigation works
- ✓ Setup form loads
- ✓ Can complete provisioning
- Note: No automatic popup (Linux doesn't support captive portal detection)

### Test 7f: Different DNS Queries

**Verify DNS server responds to different domain checks:**

From connected device:
```bash
# Apple connectivity check
nslookup captive.apple.com 192.168.4.1
# Should return: 192.168.4.1

# Android connectivity check
nslookup connectivitycheck.gstatic.com 192.168.4.1
# Should return: 192.168.4.1

# Windows connectivity check
nslookup windows.ipv6.msftncsi.com 192.168.4.1
# Should return: 192.168.4.1

# Generic check
nslookup google.com 192.168.4.1
# Should return: 192.168.4.1
```

**Pass criteria:**
- ✓ All queries return 192.168.4.1
- ✓ No failures or timeouts

---

## Task 8: Final Integration & Documentation

**Objective:** Ensure captive portal works seamlessly with existing provisioning system.

**What to verify:**

1. **Complete flow works:**
   - Device boots unconfigured
   - User presses BUTTON2 5 seconds
   - Device enters AP mode
   - DNS server starts
   - HTTP server starts
   - User connects from phone
   - Captive portal opens automatically (or user taps notification)
   - Setup page loads
   - User submits valid credentials
   - Page shows success message
   - User clicks restart
   - Device reboots
   - Next boot: device auto-connects to provisioned WiFi
   - RFID system starts
   - ✓ Everything works

2. **No regressions:**
   - Short BUTTON2 press still shows statistics ✓
   - Manual HTTP access (http://192.168.4.1) still works ✓
   - Form submission still works ✓
   - Device restart still works ✓
   - Configuration persistence works ✓
   - WiFi connection succeeds ✓
   - Auto-connect on next boot works ✓

3. **Documentation updates:**
   - Add note to user guide: "Setup page opens automatically when connecting to AP"
   - Document device-specific behavior (iPhone auto, Android notification, etc.)
   - Add troubleshooting section for captive portal
   - Document that Linux requires manual browser open

4. **Code comments:**
   - DNS server.c should have comments explaining DNS protocol basics
   - HTTP wildcard handler should explain why it's needed
   - State machine should have comments about DNS server lifecycle

**Verification checklist:**

```
Final Integration Checklist
===========================

□ DNS server starts in AP_ACTIVE state
□ DNS server stops when exiting AP_ACTIVE
□ HTTP wildcard handler catches non-setup requests
□ HTTP wildcard handler returns proper 302 redirect
□ Specific HTTP handlers still work (not caught by wildcard)
□ iPhone: Safari opens automatically ✓
□ Android: Notification appears ✓
□ Windows: Popup appears ✓
□ MacOS: Browser opens ✓
□ Linux: Manual navigation works ✓
□ Complete provisioning flow works ✓
□ No regressions in existing features ✓
□ Device reboots cleanly ✓
□ Next boot auto-connects to WiFi ✓
□ RFID system starts after WiFi ready ✓
□ Build succeeds without errors ✓
□ No memory leaks detected ✓
```

**Expected outcome:**
- User connects to AP
- Setup page appears automatically (no manual URL entry needed)
- Complete provisioning works
- Device functions normally after provisioning
- All existing features still work

---

## Summary

**Tasks in order:**
1. Create DNS server header (1-2 hours)
2. Implement DNS server (2-3 hours)
3. Add wildcard HTTP handler (30 minutes)
4. Integrate with state machine (30 minutes)
5. Update build configuration (15 minutes)
6. Test DNS connectivity (30 minutes)
7. Integration testing on devices (1-2 hours)
8. Final verification and documentation (30 minutes)

**Total time:** 6-9 hours (mostly testing on real devices)

**Files created:**
- `dns_server.h` (header)
- `dns_server.c` (implementation)

**Files modified:**
- `wifi_http_server.c` (add wildcard handler)
- `wifi_provisioning.c` (DNS server lifecycle)
- `CMakeLists.txt` (add DNS source and dependency)

**Key concepts:**
- DNS intercepts all domain queries, responds with AP IP
- HTTP wildcard handler redirects non-setup requests to setup page
- OS detects this pattern and opens browser automatically
- Works on all modern devices (iPhone, Android, Windows, Mac)
