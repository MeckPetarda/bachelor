# Addendum 2: Relay Control & Dual Power Sensing

## Overview
Add relay control and post-relay power sensing to distinguish between power supply failure, relay control circuit failure, and relay mechanical failure.

## Hardware Configuration

**Relay Control (Active Low):**
```c
#define RFID_RELAY_CONTROL_PIN     GPIO_NUM_26  // Pin 19 - Relay control (active low)
```

**Power Sensing:**
```c
#define RFID_AUX_POWER_SENSE_PIN   GPIO_NUM_4   // Pin 25 - 3.3V aux supply (before relay)
#define RFID_READER_POWER_SENSE_PIN GPIO_NUM_27 // Pin 32 - Reader power (after relay)
```

**Rationale:**
- GPIO 26 (pin 19): Output capable, suitable for relay control signal
- GPIO 4 (pin 25): Input, aux rail feedback (supply side)
- GPIO 27 (pin 32): Input, reader rail feedback (relay output side), in 20-38 range

All three pins are currently unused and properly positioned for their functions.

## Initialization

```c
// Relay control (output, active low)
gpio_config_t relay_config = {
    .pin_bit_mask = (1ULL << RFID_RELAY_CONTROL_PIN),
    .mode = GPIO_MODE_OUTPUT,
    .pull_up_en = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_DISABLE,
    .intr_type = GPIO_INTR_DISABLE,
};
gpio_config(&relay_config);
gpio_set_level(RFID_RELAY_CONTROL_PIN, 1);  // Relay OFF (inactive) at startup

// Aux power sense (input)
gpio_config_t aux_pwr_config = {
    .pin_bit_mask = (1ULL << RFID_AUX_POWER_SENSE_PIN),
    .mode = GPIO_MODE_INPUT,
    .pull_up_en = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,
    .intr_type = GPIO_INTR_DISABLE,
};
gpio_config(&aux_pwr_config);

// Reader power sense (input)
gpio_config_t reader_pwr_config = {
    .pin_bit_mask = (1ULL << RFID_READER_POWER_SENSE_PIN),
    .mode = GPIO_MODE_INPUT,
    .pull_up_en = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,
    .intr_type = GPIO_INTR_DISABLE,
};
gpio_config(&reader_pwr_config);
```

## Error States & Diagnostics

| Aux Rail | Relay Ctrl | Reader Rail | Status | Diagnosis |
|----------|-----------|-------------|--------|-----------|
| 0 | 1 | 0 | ❌ | Power supply down |
| 0 | 0 | 0 | ❌ | Power supply down (relay state irrelevant) |
| 1 | 1 | 0 | ⚠️ | Relay OFF (expected when inactive) |
| 1 | 0 | 0 | ❌ | **Relay commanded ON but no output** — mechanical failure or stuck relay |
| 1 | 0 | 1 | ✓ | Reader powered, ready for handshake |
| 1 | 1 | 1 | ❌ | Relay OFF but reader still powered — control signal failure or capacitive holdover |

## State Machine Enhancement

### New Reader States
```c
typedef enum {
    RFID_STATE_SUPPLY_DOWN,           // Aux rail missing
    RFID_STATE_RELAY_CONTROL_ERROR,   // Can't control relay output
    RFID_STATE_POWERED_OFF,           // Reader power rail down (normal when idle)
    RFID_STATE_STARTUP_PENDING,       // Reader powered, waiting for boot
    RFID_STATE_RESPONSIVE,            // Handshake successful
    RFID_STATE_UNRESPONSIVE,          // Powered but no handshake response
} rfid_state_t;
```

### Enhanced State Transition Flow

**On System Startup:**
```
1. Check aux rail voltage
   ├─ LOW → State: SUPPLY_DOWN, log "auxiliary 3.3V supply unavailable"
   └─ HIGH → continue to step 2

2. Skip relay control (reader stays powered off at startup)
   └─ State: POWERED_OFF

3. Wait for activation trigger (button/IR sensor)
```

**On Reader Activation (Button Press / IR Sensor Trigger):**
```
1. Check aux rail voltage
   ├─ LOW → State: SUPPLY_DOWN, block activation
   └─ HIGH → continue to step 2

2. Assert relay control (active low → set to 0/LOW)
   └─ Wait 100ms for relay mechanical engage

3. Check reader power rail voltage
   ├─ LOW → State: RELAY_CONTROL_ERROR
   │         Log: "Relay commanded ON but reader power rail down"
   │         Block handshake, disable scanning
   │         Publish MQTT: {"reader_error": "relay_failure"}
   │         Recommend: Check relay mechanical contact, control signal path
   │
   └─ HIGH → continue to step 4

4. Begin handshake verification (get_firmware)
   ├─ Success → State: RESPONSIVE, proceed to start_inventory()
   │
   └─ Timeout/Error → State: UNRESPONSIVE
                     Log: "Reader powered but not responding to handshake"
                     Block scanning
                     Publish MQTT: {"reader_error": "no_response"}
```

**On Deactivation (Button Release / Idle):**
```
1. Stop inventory if running
2. Release relay control (set to 1/HIGH)
   └─ Wait 100ms for relay mechanical release
3. Verify reader power rail drops
   ├─ Falls → log "Reader powered down normally"
   └─ Stays HIGH → log "Warning: Reader still powered after relay release"
4. State: POWERED_OFF
```

**Periodic Health Check (every 60s):**
```
1. Check aux rail
   ├─ LOW → Log supply failure, mark in health status
   └─ HIGH → continue

2. If reader was RESPONSIVE and is still idle:
   ├─ Assert relay
   ├─ Wait boot grace period
   ├─ Run handshake
   ├─ Release relay
   └─ Log result

3. Publish MQTT health message including:
   {
     "aux_supply": "ok" | "down",
     "relay_control": "ok" | "error",
     "reader_power": "ok" | "down",
     "reader_status": "responsive" | "unresponsive" | "error",
     "fw_version": "x.x"
   }
```

## Health Structure Update

```c
typedef struct {
    uint32_t last_check_ms;
    uint8_t fw_major, fw_minor;
    esp_err_t last_handshake_error;
    
    // Power & relay status
    bool aux_supply_present;           // Aux rail before relay
    bool reader_power_present;         // Power rail after relay
    bool relay_control_ok;             // Relay responding to control
    
    // State machine
    rfid_state_t current_state;
    uint32_t state_change_time_ms;
    char last_error_msg[64];           // Human-readable error
} rfid_health_t;
```

## Relay Control Utilities

```c
// Enable reader power (assert active-low relay)
static inline void rfid_enable_power(void) {
    gpio_set_level(RFID_RELAY_CONTROL_PIN, 0);  // Pull to LOW
}

// Disable reader power (release active-low relay)
static inline void rfid_disable_power(void) {
    gpio_set_level(RFID_RELAY_CONTROL_PIN, 1);  // Release to HIGH
}

// Check power rail states
static void rfid_check_power_rails(bool* aux_ok, bool* reader_ok) {
    *aux_ok = gpio_get_level(RFID_AUX_POWER_SENSE_PIN) == 1;
    *reader_ok = gpio_get_level(RFID_READER_POWER_SENSE_PIN) == 1;
}
```

## Integration Points

1. **gpio_init():** Configure all three GPIO pins as shown above
2. **rfid_reader_start_inventory_wrapper():** Call `rfid_check_power_rails()` before relay activation, enforce state machine transitions
3. **Periodic task (60s):** Perform health check with power rail verification
4. **MQTT health message:** Include all three power/relay status fields
5. **Error logging:** Use new error state enum to provide specific, actionable diagnostics
