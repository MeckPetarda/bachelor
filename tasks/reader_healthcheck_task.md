# Reader Handshake Implementation Plan

## Problem
Reader power-on produces only a warning when communication fails. System needs active verification that reader is responsive before enabling scanning.

## Solution
Implement handshake verification using `get_firmware_version` command (0x72) at three points:
1. System startup (before configuration)
2. Reader power-on events (IR sensor / button trigger)
3. Periodic health checks (background task)

## State Machine
Add reader state tracking:
- `UNINITIALIZED` → `POWERED_OFF` → `STARTUP_PENDING` → `RESPONSIVE` / `UNRESPONSIVE`

Block `start_inventory()` unless state is `RESPONSIVE`.

## API Changes

**New functions:**
- `rfid_reader_handshake(uint8_t* major, uint8_t* minor)` — verify communication
- `rfid_reader_get_state()` — return current reader state
- `rfid_reader_get_health(rfid_health_t* health)` — health metrics for MQTT

**New structures:**
```c
typedef struct {
    uint32_t last_check_ms;
    uint8_t fw_major, fw_minor;
    esp_err_t last_error;
    bool is_responsive;
} rfid_health_t;
```

**Modified:**
- `rfid_reader_start_inventory()` returns `ESP_ERR_INVALID_STATE` if reader not responsive

## Timing
- **Handshake timeout:** 1 second (fail-fast)
- **Power-on grace period:** 500ms (configurable)
- **Health check interval:** 60 seconds (configurable)

## Logging
- Log firmware version on successful startup handshake
- Log failure reason + error code on timeout/disconnect
- Include handshake result in MQTT health message

## Datasheet References
- R300 Protocol V2.2, Section 2.1.3 (page 8): `get_firmware_version` command/response format
- R300 Protocol V2.2, Section 3 (page 39): Error code reference for diagnostics
