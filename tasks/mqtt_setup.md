# Task Plan: Add MQTT Broker Configuration to Setup Page

## Objective
Extend the ESP32 setup page to allow users to configure MQTT broker IP address and port alongside existing WiFi SSID/password configuration. Both fields should be required with defaults pre-filled, and changes should be persisted to NVS flash in the same partition as WiFi credentials.

---

## Requirements Summary

| Requirement | Specification |
|-------------|---------------|
| **Storage** | NVS partition (same as WiFi credentials) - two separate keys |
| **Fields** | MQTT Broker IP (IPv4 only) and Port (1-65535) |
| **Defaults** | Pre-filled in form; required to submit |
| **Visibility** | Readable/visible (not masked) in form fields |
| **Validation** | Client-side format validation; KISS approach |
| **Connection** | Attempt to connect after WiFi established; warn on failure, don't fail |
| **Testing** | Separate test buttons: WiFi test → MQTT test (conditional) |

---

## Implementation Components

### 1. NVS Storage Layer
**Scope:** Add two new NVS keys to store configuration

**Keys:**
- `mqtt_broker_ip` - String (max 15 chars for IPv4: "255.255.255.255")
- `mqtt_broker_port` - Unsigned 16-bit integer (uint16_t, range 0-65535)

**Location:** Existing NVS partition (24KB at 0x9000)

**Changes Required:**
- Define constants for key names and default values
- Create utility functions to read/write MQTT config from NVS
- Initialize defaults on first boot or if keys are missing

**Default Values:**
- IP: `"192.168.1.1"` (or make configurable via Kconfig)
- Port: `1883` (standard MQTT)

---

### 2. HTML Form Enhancement
**Scope:** Extend setup page form to include MQTT fields

**Form Fields to Add:**
```
1. MQTT Broker IP
   - Type: text input
   - Pattern: IPv4 validation (client-side)
   - Placeholder: "192.168.1.1"
   - Required: yes

2. MQTT Broker Port
   - Type: number input
   - Min: 1, Max: 65535
   - Placeholder: "1883"
   - Required: yes
```

**Form Behavior:**
- Pre-fill fields with current NVS values on page load (via template variable)
- Validate on form submission before POST
- Display validation errors inline (missing/invalid IP or port)

**Test Buttons:**
- WiFi Test Button (existing or new)
- MQTT Test Button (enabled only after WiFi test succeeds)

---

### 3. HTTP Endpoints
**Scope:** Modify form submission handling and add test endpoint

#### 3a. POST `/setup` (Form Submission)
**Current Behavior:** Accepts SSID and password

**New Behavior:**
- Accept four parameters: `ssid`, `password`, `mqtt_ip`, `mqtt_port`
- Validate all four fields
- Save SSID and password to NVS (existing flow)
- Save MQTT IP and port to NVS (new flow)
- Return success response
- **Response:** JSON with status and any validation errors

#### 3b. POST `/test/wifi` (WiFi Connectivity Test)
**New Endpoint or Existing?** Check current implementation

**Behavior:**
- Test WiFi connectivity (ping gateway or DNS lookup)
- Return JSON: `{"status": "ok|fail", "message": "..."}`

#### 3c. POST `/test/mqtt` (MQTT Broker Connectivity Test)
**New Endpoint**

**Behavior:**
- Only callable if WiFi is connected
- Read MQTT IP and port from NVS (or request body)
- Attempt MQTT connection with 3-5 second timeout
- Return JSON: `{"status": "ok|fail", "message": "...", "reason": "..."}`
- **Important:** Do not persist connection state; just test and disconnect

---

### 4. Configuration Usage in Main Firmware
**Scope:** Integrate MQTT config into existing MQTT initialization flow

**Changes Required:**
- Modify `mqtt_client_init()` to read IP and port from NVS instead of hardcoded values
- Update any Kconfig entries that currently hardcode broker address
- Ensure graceful fallback if keys are missing (use defaults)

**Reference:** Current implementation uses `CONFIG_MQTT_BROKER_IP` and `CONFIG_MQTT_BROKER_PORT` from menuconfig

---

## Validation Rules

### Client-Side (JavaScript)
- IPv4 format: Match regex `^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$`
- Each octet: 0-255 (can be added but KISS for now)
- Port: Integer, 1-65535
- Display error messages below each field if validation fails

### Server-Side (ESP32)
- IPv4: Validate with `inet_aton()` (already available in lwIP)
- Port: Validate 1-65535 range
- Return HTTP 400 with error details if validation fails

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│  Setup Page (HTTP GET /setup)                       │
│  ┌────────────────────────────────────────────────┐ │
│  │ WiFi SSID:       [_____________]              │ │
│  │ WiFi Password:   [_____________]              │ │
│  │ MQTT Broker IP:  [192.168.1.1_]  ← pre-filled │ │
│  │ MQTT Port:       [1883_____]      ← pre-filled │ │
│  │ [Test WiFi]  [Test MQTT (disabled)]           │ │
│  │ [Submit Setup]                                 │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
         │
         ├─ POST /setup ────────────→ Validate & Save to NVS
         │
         ├─ POST /test/wifi ───────→ Check WiFi connectivity
         │                           Response: ok/fail
         │
         └─ POST /test/mqtt ───────→ (if WiFi ok)
                                    Check MQTT reachability
                                    Response: ok/fail + reason
```

---

## Technical Considerations

### NVS Partition Constraints
- Total NVS size: 24KB (24,576 bytes)
- Overhead per entry: ~32 bytes (key + metadata)
- Current usage: SSID + password + WiFi retry count
- Available space: Sufficient for two additional entries

### String Storage in NVS
- IPv4 strings stored as null-terminated C strings
- Max length: 15 bytes ("255.255.255.255" + null terminator = 16 bytes)
- Use `nvs_set_str()` and `nvs_get_str()` for IP storage

### Integer Storage in NVS
- Port stored as `uint16_t`
- Use `nvs_set_u16()` and `nvs_get_u16()` for port storage

### Default Initialization
- Check if keys exist on startup
- If missing: Write defaults to NVS
- Read values at each boot and pass to MQTT init

---

## Testing Checklist

- [ ] MQTT config keys readable from NVS after submission
- [ ] Default values pre-fill form on page load
- [ ] Client-side validation prevents invalid IPv4/port submission
- [ ] Server-side validation rejects malformed submissions
- [ ] WiFi test succeeds when AP available
- [ ] MQTT test disabled until WiFi test passes
- [ ] MQTT test fails gracefully with timeout when broker unavailable
- [ ] MQTT test succeeds when broker available
- [ ] Device connects to MQTT using stored config after restart
- [ ] Connection failure to MQTT does not prevent device operation

---

## Implementation Order

1. **NVS Layer** - Add read/write functions for MQTT config
2. **Form HTML** - Add MQTT IP and port input fields with defaults
3. **Client Validation** - Add JavaScript validation for IPv4 and port
4. **Server Validation** - Update `/setup` endpoint to validate and store
5. **Test Endpoints** - Implement `/test/wifi` and `/test/mqtt`
6. **Integration** - Connect MQTT initialization to NVS config
7. **Testing** - Verify full flow from setup to connection
