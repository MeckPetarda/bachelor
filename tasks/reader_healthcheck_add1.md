# Addendum: RFID Reader Power Status Feedback

## Overview
The 3.3V power rail supplying the reader can be monitored via GPIO to distinguish between power supply failure and board unresponsiveness before attempting handshake.

## Diagnostic Flow
1. Check GPIO power feedback → power rail missing → log "power supply disconnected"
2. Check GPIO power feedback → power rail present → attempt handshake
3. Handshake fails → log "reader powered but unresponsive"

This provides clear diagnostic information in health checks and logs.

## GPIO Pin Selection

**Current usage:**
- GPIO 5: LED1
- GPIO 18: LED2
- GPIO 2: PIR sensor
- GPIO 16, 17: UART2 (RFID reader)
- GPIO 34, 35: Buttons

**Recommended pin: GPIO 2**

**Rationale:**
- Pin 24 on ESP32-WROOM-32, located in pins 20-38 range (proximity to power rail)
- Currently unused (PIR sensor not deployed)
- Has internal pull-down by default (safe for logic low when power absent)
- Close physical proximity to 3.3V supply rail on development board for signal integrity
- No strapping pin conflicts; safe to use as input-only

## Implementation
```c
#define RFID_POWER_STATUS_PIN  GPIO_NUM_2  // 3.3V rail feedback from reader power supply (pin 24)

// In gpio_init():
gpio_config_t pwr_config = {
    .pin_bit_mask = (1ULL << RFID_POWER_STATUS_PIN),
    .mode = GPIO_MODE_INPUT,
    .pull_up_en = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,  // Safe default when unpowered
    .intr_type = GPIO_INTR_DISABLE,
};
gpio_config(&pwr_config);

// In handshake verification:
if (!gpio_get_level(RFID_POWER_STATUS_PIN)) {
    ESP_LOGW(TAG, "RFID power rail down - skipping handshake");
    return ESP_ERR_INVALID_STATE;
}
```

## Health Check Enhancement
Extend `rfid_health_t` to include:
```c
typedef struct {
    uint32_t last_check_ms;
    uint8_t fw_major, fw_minor;
    esp_err_t last_error;
    bool is_responsive;
    bool power_rail_present;  // NEW: 3.3V feedback status
} rfid_health_t;
```

MQTT health message now distinguishes:
- `{"reader": "no_power"}` — power supply issue
- `{"reader": "no_response"}` — powered but unresponsive
- `{"reader": "ok", "fw": "x.x"}` — healthy
