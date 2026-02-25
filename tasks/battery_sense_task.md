# Task: Battery Monitoring System Implementation

**Project**: ESP32 UHF RFID Attendance System  
**Date Created**: February 25, 2026  
**Status**: Ready for Implementation  

---

## Objective

Implement comprehensive battery monitoring and power management system to:
1. Monitor 18650 Li-ion cell voltage and calculate state of charge
2. Detect USB power presence vs battery backup operation
3. Report battery telemetry via MQTT health messages
4. Block RFID scanning at critical battery levels
5. Provide visual LED feedback for power status
6. Execute graceful shutdown before battery depletion

---

## Hardware Configuration

### Existing Components
- **Battery**: Single 18650 Li-ion cell (3.7V nominal, 3.2-4.2V range)
- **Battery voltage sense**: GPIO33 (ADC1_CH5)
  - Voltage divider: R1=100kΩ, R2=120kΩ
  - Scales 3.2-4.2V → 1.75-2.29V at ADC input
  - Reference: DEVLOG_2026_02_25.md
- **Charging circuit**: TP4056 + DW01HA protection IC
- **Power path**: Dual SS24A Schottky diode OR, SX1308 boost converter

### New Hardware Required
- **USB presence detection**: GPIO32 (digital input)
  - Voltage divider: R1=100kΩ, R2=47kΩ
  - Scales 5V USB → ~1.6V at GPIO (logic HIGH)
  - Digital sensing: HIGH=USB present, LOW=battery only
  - Pull-down enabled when USB absent

### Pin Assignment Summary
| GPIO | Function | Type | Hardware |
|------|----------|------|----------|
| GPIO33 | Battery voltage | ADC1_CH5 | 100kΩ/120kΩ divider |
| GPIO32 | USB detect | Digital input | 100kΩ/47kΩ divider |

---

## Datasheet References

### ESP32 Datasheet (v5.2)
- **Section 2.1**: Pin Layout - GPIO pin assignments (Figure 2-1)
- **Section 4.9.1**: ADC characteristics (Table 4-3, Table 4-4)
- **Table 4-4**: ADC Calibration Results - attenuation ranges and accuracy
  - ADC_ATTEN_DB_11: 150-2450mV range, ±60mV error
- **Table 5-3**: DC Characteristics - GPIO input voltage levels
  - V_IH = 0.75 × VDD = 2.475V minimum for logic HIGH

### ESP32 Technical Reference Manual (v5.6)
- **Chapter 31 Section 31.3**: SAR ADC architecture and operation
- **Table 31.3-1**: Inputs of SAR ADC - ADC channel mapping to GPIO
- **Section 31.3.3**: ADC1 vs ADC2 - ADC2 conflicts with WiFi RF subsystem
- **Chapter 9 Section 9.3.5**: Brownout detector (reference for power monitoring)

### Project Documentation
- **DEVLOG_2026_02_25.md**: Battery voltage divider specs, power architecture
- **DEVLOG_2026_02_10.md**: TP4056/DW01HA charging circuit details
- **tasks/mqtt_topics_task.md**: Health message format, MQTT topic structure
- **my_mqtt_client.h**: QoS levels, topic definitions, health publish API

---

## Implementation Steps

### Phase 1: Hardware Validation

#### Step 1.1: Install USB Detection Voltage Divider
**Hardware modification required on PCB/breadboard:**

```
USB 5V ─┬─── R1 (100kΩ) ───┬─── GPIO32
        │                  │
        │                  └─── R2 (47kΩ) ─── GND
        │
     (to diode OR)
```

**Expected voltages:**
- USB present: ~1.6V at GPIO32 (logic HIGH)
- USB absent: 0V at GPIO32 (logic LOW via pull-down)

**Validation procedure:**
1. With multimeter, measure voltage at GPIO32 pad
2. USB connected: Should read 1.5-1.7V
3. USB disconnected: Should read 0V
4. Verify resistor values with multimeter (100kΩ ±1%, 47kΩ ±1%)

**Acceptance criteria:**
- [ ] Voltage divider installed with correct resistor values
- [ ] GPIO32 voltage measures 1.5-1.7V with USB connected
- [ ] GPIO32 voltage measures 0V with USB disconnected
- [ ] No short circuits on power rails

---

#### Step 1.2: Verify Battery Voltage Divider
**Existing configuration (already installed per DEVLOG_2026_02_25):**

```
Battery+ ─── R1 (100kΩ) ───┬─── GPIO33 (ADC1_CH5)
                           │
                           └─── R2 (120kΩ) ─── GND
```

**Expected voltages:**
| Battery Voltage | GPIO33 Voltage | ADC Reading (12-bit) |
|-----------------|----------------|----------------------|
| 4.2V (full) | 2.29V | ~2867 |
| 3.7V (nominal) | 2.02V | ~2529 |
| 3.2V (empty) | 1.75V | ~2190 |

**Validation procedure:**
1. Measure battery voltage at terminals with multimeter
2. Measure voltage at GPIO33 pad
3. Calculate ratio: GPIO33_V / Battery_V ≈ 0.545 (120kΩ / 220kΩ)
4. Test at multiple battery charge states (full, half, low)

**Acceptance criteria:**
- [ ] Voltage divider ratio validated: ~0.545
- [ ] GPIO33 voltage scales correctly with battery voltage
- [ ] All measurements within expected ranges per table above
- [ ] Battery voltage between 3.2-4.2V

---

#### Step 1.3: Test Under Load Conditions
**Purpose**: Validate voltage readings during ESP32 WiFi + RFID scanning

**Test procedure:**
1. Connect oscilloscope probes to:
   - Battery terminals (channel 1)
   - GPIO33 ADC input (channel 2)
   - ESP32 3.3V rail (channel 3 - reference)
2. Enable WiFi connection
3. Start RFID inventory scanning
4. Observe voltage sag during scan cycles

**Expected behavior (from DEVLOG_2026_02_25):**
- Healthy battery (4.2V full): <0.2V drop under load
- Degraded battery (3.5V): 0.2-0.5V drop under load
- RFID scan cycle: 18.8ms sustained high current every 30-50ms

**Acceptance criteria:**
- [ ] Battery voltage sag measured and documented
- [ ] GPIO33 ADC voltage tracks battery correctly under load
- [ ] No brownout resets during combined WiFi + RFID load
- [ ] Voltage recovers after scan cycle completes

---

### Phase 2: Firmware Core Implementation

#### Step 2.1: Create Battery Monitor Module Header
**File**: `src/lighthouse/main/battery_monitor.h`

**Required content:**

```c
/**
 * battery_monitor.h - Battery voltage monitoring and power source detection
 *
 * Monitors 18650 Li-ion cell voltage via GPIO33 (ADC1_CH5) and detects
 * USB power presence via GPIO32 digital input.
 *
 * Hardware:
 *   - GPIO33: Battery voltage sense (100kΩ/120kΩ divider, 3.2-4.2V → 1.75-2.29V)
 *   - GPIO32: USB 5V presence detect (100kΩ/47kΩ divider, digital)
 *
 * References:
 *   - ESP32 Datasheet Section 4.9.1: ADC characteristics
 *   - ESP32 TRM Chapter 31: SAR ADC operation
 *   - DEVLOG_2026_02_25.md: Voltage divider specifications
 */

#ifndef BATTERY_MONITOR_H
#define BATTERY_MONITOR_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// CONFIGURATION
// ============================================================================

#define BATTERY_ADC_CHANNEL     ADC1_CHANNEL_5  // GPIO33
#define BATTERY_ADC_ATTEN       ADC_ATTEN_DB_11 // 150-2450mV range
#define BATTERY_ADC_WIDTH       ADC_WIDTH_BIT_12

#define USB_DETECT_PIN          GPIO_NUM_32

// Voltage thresholds (millivolts)
#define BATTERY_VOLTAGE_FULL    4200  // 100%
#define BATTERY_VOLTAGE_NOMINAL 3700  // ~40%
#define BATTERY_VOLTAGE_LOW     3400  // 10% - warning level
#define BATTERY_VOLTAGE_CRITICAL 3300 // 5% - block scanning
#define BATTERY_VOLTAGE_EMPTY   3200  // 0% - shutdown

// ADC sampling
#define BATTERY_ADC_SAMPLE_COUNT 5    // Take 5 readings
#define BATTERY_ADC_SAMPLE_DELAY_MS 10 // 10ms between samples

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * Battery health status classification
 */
typedef enum {
    BATTERY_HEALTH_GOOD = 0,      // <0.2V drop under load
    BATTERY_HEALTH_DEGRADED,      // 0.2-0.5V drop under load
    BATTERY_HEALTH_CRITICAL,      // >0.5V drop under load
    BATTERY_HEALTH_UNKNOWN        // Not yet measured
} battery_health_t;

/**
 * Battery monitoring data
 */
typedef struct {
    uint16_t voltage_mv;          // Battery voltage (millivolts)
    uint16_t voltage_under_load_mv; // Voltage during RFID scan
    uint8_t  percentage;          // State of charge (0-100%)
    bool     is_usb_present;      // USB power connected
    battery_health_t health;      // Battery health status
    uint32_t last_update_ms;      // Timestamp of last update
} battery_status_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize battery monitoring system
 *
 * Configures:
 *   - ADC1 for GPIO33 battery voltage sensing
 *   - GPIO32 as digital input for USB detection
 *   - ADC calibration using eFuse Vref
 *
 * Reference: ESP32 TRM Chapter 31 Section 31.3
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t battery_monitor_init(void);

/**
 * Update battery status
 *
 * Samples ADC, calculates percentage, detects power source.
 * Should be called at health publish interval (~6 seconds).
 *
 * @param is_rfid_scanning True if RFID scan active (for under-load reading)
 * @return ESP_OK on success
 */
esp_err_t battery_monitor_update(bool is_rfid_scanning);

/**
 * Get current battery status
 *
 * @return Pointer to battery status structure (read-only)
 */
const battery_status_t* battery_monitor_get_status(void);

/**
 * Check if battery level is critical
 *
 * Used to block RFID scanning when battery too low.
 *
 * @return true if battery below critical threshold (3.3V)
 */
bool battery_monitor_is_critical(void);

/**
 * Check if USB power is present
 *
 * @return true if USB connected, false if running on battery
 */
bool battery_monitor_is_usb_present(void);

/**
 * Get power source string for telemetry
 *
 * @return "usb" or "battery"
 */
const char* battery_monitor_get_power_source(void);

#endif // BATTERY_MONITOR_H
```

**Acceptance criteria:**
- [ ] Header file created with all required declarations
- [ ] Pin definitions match hardware configuration
- [ ] Threshold constants defined (4.2V, 3.7V, 3.4V, 3.3V, 3.2V)
- [ ] Documentation includes datasheet references
- [ ] All function prototypes documented

---

#### Step 2.2: Implement Battery Monitor Module
**File**: `src/lighthouse/main/battery_monitor.c`

**Implementation requirements:**

**A. ADC Configuration and Calibration**
```c
#include "battery_monitor.h"
#include "driver/adc.h"
#include "driver/gpio.h"
#include "esp_adc_cal.h"
#include "esp_log.h"

static const char* TAG = "battery_monitor";
static battery_status_t s_battery_status = {0};
static esp_adc_cal_characteristics_t s_adc_chars;

esp_err_t battery_monitor_init(void)
{
    ESP_LOGI(TAG, "Initializing battery monitor");
    
    // Configure ADC1 for battery voltage sensing
    // Reference: ESP32 TRM Chapter 31 Section 31.3
    adc1_config_width(BATTERY_ADC_WIDTH);
    adc1_config_channel_atten(BATTERY_ADC_CHANNEL, BATTERY_ADC_ATTEN);
    
    // Characterize ADC using eFuse Vref for calibration
    // Reference: ESP32 Datasheet Table 4-4 (±60mV accuracy with calibration)
    esp_adc_cal_characterize(ADC_UNIT_1, BATTERY_ADC_ATTEN, 
                             BATTERY_ADC_WIDTH, 1100, &s_adc_chars);
    
    // Configure GPIO32 for USB detection (digital input)
    // Reference: ESP32 Datasheet Table 5-3 (V_IH threshold)
    gpio_config_t usb_detect_config = {
        .pin_bit_mask = (1ULL << USB_DETECT_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,  // Pull LOW when USB absent
        .intr_type    = GPIO_INTR_DISABLE,
    };
    esp_err_t ret = gpio_config(&usb_detect_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure USB detect pin: %s", 
                 esp_err_to_name(ret));
        return ret;
    }
    
    // Initialize status structure
    s_battery_status.health = BATTERY_HEALTH_UNKNOWN;
    s_battery_status.last_update_ms = 0;
    
    ESP_LOGI(TAG, "Battery monitor initialized");
    ESP_LOGI(TAG, "  Battery ADC: GPIO33 (ADC1_CH5)");
    ESP_LOGI(TAG, "  USB detect: GPIO32 (digital)");
    
    return ESP_OK;
}
```

**B. ADC Sampling with Noise Reduction**
```c
/**
 * Sample ADC with averaging and outlier rejection
 *
 * Takes BATTERY_ADC_SAMPLE_COUNT readings, discards highest and lowest,
 * averages remaining samples.
 *
 * Reference: ESP32 Datasheet Table 4-3 (DNL/INL guidance)
 *
 * @return Averaged ADC voltage in millivolts
 */
static uint32_t battery_sample_adc_voltage(void)
{
    uint32_t readings[BATTERY_ADC_SAMPLE_COUNT];
    
    // Take multiple samples
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++) {
        readings[i] = esp_adc_cal_raw_to_voltage(
            adc1_get_raw(BATTERY_ADC_CHANNEL), &s_adc_chars);
        if (i < BATTERY_ADC_SAMPLE_COUNT - 1) {
            vTaskDelay(pdMS_TO_TICKS(BATTERY_ADC_SAMPLE_DELAY_MS));
        }
    }
    
    // Simple bubble sort for finding min/max
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT - 1; i++) {
        for (int j = 0; j < BATTERY_ADC_SAMPLE_COUNT - i - 1; j++) {
            if (readings[j] > readings[j + 1]) {
                uint32_t temp = readings[j];
                readings[j] = readings[j + 1];
                readings[j + 1] = temp;
            }
        }
    }
    
    // Average middle 3 samples (discard min and max)
    uint32_t sum = 0;
    for (int i = 1; i < BATTERY_ADC_SAMPLE_COUNT - 1; i++) {
        sum += readings[i];
    }
    
    return sum / (BATTERY_ADC_SAMPLE_COUNT - 2);
}
```

**C. Voltage to Percentage Conversion**
```c
/**
 * Convert battery voltage to percentage using Li-ion discharge curve
 *
 * Voltage-to-percentage mapping (empirical for 18650 Li-ion):
 *   4.2V → 100%
 *   4.1V → 90%
 *   4.0V → 80%
 *   3.9V → 70%
 *   3.8V → 55%
 *   3.7V → 40%
 *   3.6V → 25%
 *   3.5V → 15%
 *   3.4V → 10%
 *   3.3V → 5%
 *   3.2V → 0%
 *
 * Uses linear interpolation between points.
 *
 * @param voltage_mv Battery voltage in millivolts
 * @return State of charge (0-100%)
 */
static uint8_t battery_voltage_to_percentage(uint16_t voltage_mv)
{
    // Discharge curve lookup table (voltage, percentage)
    const struct {
        uint16_t voltage_mv;
        uint8_t percentage;
    } curve[] = {
        {4200, 100}, {4100, 90}, {4000, 80}, {3900, 70},
        {3800, 55},  {3700, 40}, {3600, 25}, {3500, 15},
        {3400, 10},  {3300, 5},  {3200, 0}
    };
    const int curve_points = sizeof(curve) / sizeof(curve[0]);
    
    // Clamp to valid range
    if (voltage_mv >= curve[0].voltage_mv) return 100;
    if (voltage_mv <= curve[curve_points - 1].voltage_mv) return 0;
    
    // Linear interpolation between curve points
    for (int i = 0; i < curve_points - 1; i++) {
        if (voltage_mv >= curve[i + 1].voltage_mv) {
            uint16_t v1 = curve[i].voltage_mv;
            uint16_t v2 = curve[i + 1].voltage_mv;
            uint8_t p1 = curve[i].percentage;
            uint8_t p2 = curve[i + 1].percentage;
            
            // Linear interpolation: p = p1 + (p2-p1) * (v-v1) / (v2-v1)
            int32_t percentage = p1 + ((int32_t)(p2 - p1) * 
                                 (voltage_mv - v1)) / (v2 - v1);
            return (uint8_t)percentage;
        }
    }
    
    return 0; // Should never reach here
}
```

**D. Battery Health Estimation**
```c
/**
 * Estimate battery health from voltage drop under load
 *
 * Compares no-load voltage to under-load voltage during RFID scan.
 *
 * Classification:
 *   - GOOD: <0.2V drop (healthy cell)
 *   - DEGRADED: 0.2-0.5V drop (aging cell)
 *   - CRITICAL: >0.5V drop (failing cell)
 *
 * @param no_load_mv Voltage without load
 * @param under_load_mv Voltage during RFID scan
 * @return Battery health classification
 */
static battery_health_t battery_estimate_health(uint16_t no_load_mv, 
                                                uint16_t under_load_mv)
{
    if (under_load_mv == 0) {
        return BATTERY_HEALTH_UNKNOWN; // No load measurement yet
    }
    
    int16_t drop_mv = no_load_mv - under_load_mv;
    
    if (drop_mv < 0) {
        // Under-load higher than no-load shouldn't happen, use unknown
        return BATTERY_HEALTH_UNKNOWN;
    }
    
    if (drop_mv < 200) {
        return BATTERY_HEALTH_GOOD;
    } else if (drop_mv < 500) {
        return BATTERY_HEALTH_DEGRADED;
    } else {
        return BATTERY_HEALTH_CRITICAL;
    }
}
```

**E. Main Update Function**
```c
esp_err_t battery_monitor_update(bool is_rfid_scanning)
{
    // Sample battery voltage at ADC input (1.75-2.29V range)
    uint32_t adc_voltage_mv = battery_sample_adc_voltage();
    
    // Convert to actual battery voltage using divider ratio
    // Ratio = R2 / (R1 + R2) = 120kΩ / 220kΩ = 0.545
    // Battery_V = ADC_V / 0.545
    uint16_t battery_voltage_mv = (adc_voltage_mv * 220) / 120;
    
    // Check USB presence (digital read)
    bool usb_present = (gpio_get_level(USB_DETECT_PIN) == 1);
    
    // Update status structure
    s_battery_status.voltage_mv = battery_voltage_mv;
    s_battery_status.is_usb_present = usb_present;
    s_battery_status.percentage = 
        battery_voltage_to_percentage(battery_voltage_mv);
    
    // Update under-load voltage if RFID scanning
    if (is_rfid_scanning) {
        s_battery_status.voltage_under_load_mv = battery_voltage_mv;
        s_battery_status.health = battery_estimate_health(
            s_battery_status.voltage_mv,
            s_battery_status.voltage_under_load_mv
        );
    }
    
    s_battery_status.last_update_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;
    
    ESP_LOGD(TAG, "Battery: %dmV (%d%%), USB: %s, Health: %d",
             battery_voltage_mv, s_battery_status.percentage,
             usb_present ? "present" : "absent", s_battery_status.health);
    
    return ESP_OK;
}
```

**F. Getter Functions**
```c
const battery_status_t* battery_monitor_get_status(void)
{
    return &s_battery_status;
}

bool battery_monitor_is_critical(void)
{
    return s_battery_status.voltage_mv < BATTERY_VOLTAGE_CRITICAL;
}

bool battery_monitor_is_usb_present(void)
{
    return s_battery_status.is_usb_present;
}

const char* battery_monitor_get_power_source(void)
{
    return s_battery_status.is_usb_present ? "usb" : "battery";
}
```

**Acceptance criteria:**
- [ ] All functions implemented per specifications above
- [ ] ADC sampling uses averaging and outlier rejection
- [ ] Voltage divider ratio correctly applied (220/120)
- [ ] Discharge curve interpolation working correctly
- [ ] Health estimation logic implemented
- [ ] USB detection reads GPIO32 digital state
- [ ] Logging statements added for debugging

---

#### Step 2.3: Extend MQTT Health Message
**File**: `src/lighthouse/main/my_mqtt_client.c`

**Modification required in `mqtt_client_publish_health_metrics()` function:**

**Find existing code:**
```c
int len = snprintf(payload, sizeof(payload),
    "{"
    "\"uptime_sec\":%lu,"
    "\"free_heap_bytes\":%lu,"
    "\"min_free_heap_bytes\":%lu,"
    "\"wifi_rssi_dbm\":%d,"
    "\"rfid\":{"
        "\"state\":\"%s\","
        "\"is_responsive\":%s,"
        "\"power_rail_present\":%s,"
        "\"fw_version\":\"%s\","
        "\"last_error\":%u"
    "}"
    "}",
    // ... existing values ...
);
```

**Replace with extended version:**
```c
#include "battery_monitor.h"  // Add at top of file

// In mqtt_client_publish_health_metrics():

// Get battery status
const battery_status_t* battery = battery_monitor_get_status();
const char* power_source = battery_monitor_get_power_source();
const char* health_str = "unknown";
switch (battery->health) {
    case BATTERY_HEALTH_GOOD: health_str = "good"; break;
    case BATTERY_HEALTH_DEGRADED: health_str = "degraded"; break;
    case BATTERY_HEALTH_CRITICAL: health_str = "critical"; break;
    default: health_str = "unknown"; break;
}

int len = snprintf(payload, sizeof(payload),
    "{"
    "\"uptime_sec\":%lu,"
    "\"free_heap_bytes\":%lu,"
    "\"min_free_heap_bytes\":%lu,"
    "\"wifi_rssi_dbm\":%d,"
    "\"rfid\":{"
        "\"state\":\"%s\","
        "\"is_responsive\":%s,"
        "\"power_rail_present\":%s,"
        "\"fw_version\":\"%s\","
        "\"last_error\":%u"
    "},"
    "\"battery\":{"
        "\"voltage_mv\":%u,"
        "\"percentage\":%u,"
        "\"is_charging\":%s,"
        "\"power_source\":\"%s\","
        "\"health_status\":\"%s\","
        "\"voltage_under_load_mv\":%u"
    "}"
    "}",
    // ... existing values ...,
    // New battery values:
    battery->voltage_mv,
    battery->percentage,
    "false",  // TODO: Add TP4056 CHRG pin detection if needed
    power_source,
    health_str,
    battery->voltage_under_load_mv
);
```

**Acceptance criteria:**
- [ ] Battery section added to JSON payload
- [ ] All battery fields included (voltage, percentage, power_source, etc.)
- [ ] JSON syntax valid (test with parser)
- [ ] Buffer size sufficient for extended payload (~450 bytes)
- [ ] Compiles without errors

---

#### Step 2.4: Integrate into Main Application
**File**: `src/lighthouse/main/lighthouse.c`

**A. Add Header Include**
```c
#include "battery_monitor.h"
```

**B. Initialize in `app_main()`**
```c
void app_main(void)
{
    // ... existing initialization ...
    
    // Initialize battery monitor AFTER gpio_init() but BEFORE main loop
    esp_err_t ret = battery_monitor_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize battery monitor: %s", 
                 esp_err_to_name(ret));
        // Continue anyway - non-critical failure
    }
    
    // ... rest of initialization ...
}
```

**C. Update Battery Status Before Health Publish**

Find the health publishing code (around line 646):
```c
// Publish health metrics periodically
if (mqtt_connected && 
    (current_time - last_health_publish) >= HEALTH_PUBLISH_INTERVAL)
{
    // NEW: Update battery status before publishing
    battery_monitor_update(rfid_scanning);
    
    mqtt_client_publish_health_metrics();
    last_health_publish = current_time;
}
```

**D. Block RFID Scanning at Critical Battery**

Modify `rfid_reader_start_inventory_wrapper()`:
```c
static void rfid_reader_start_inventory_wrapper(void)
{
    ESP_LOGI(TAG, "Attempting to start RFID scan...");
    
    // NEW: Check battery level before allowing scan
    if (battery_monitor_is_critical()) {
        ESP_LOGW(TAG, "Cannot start RFID scan - battery critical (<%dmV)",
                 BATTERY_VOLTAGE_CRITICAL);
        
        // Flash error pattern on scanning LED
        for (int i = 0; i < 3; i++) {
            gpio_set_level(SCANNING_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(100));
            gpio_set_level(SCANNING_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        return;
    }
    
    // Existing power-on and scan logic...
    if (!rfid_reader_is_powered()) {
        // ... existing code ...
    }
    // ... rest of function ...
}
```

**E. Stop Scanning if Battery Becomes Critical**

In main loop, after RFID operations:
```c
// Monitor battery during scanning
if (rfid_scanning && battery_monitor_is_critical()) {
    ESP_LOGW(TAG, "Battery critical during scan - stopping");
    rfid_reader_stop_inventory();
    rfid_reader_power_off();
    gpio_set_level(SCANNING_LED, 0);
    rfid_scanning = false;
}
```

**Acceptance criteria:**
- [ ] battery_monitor_init() called during startup
- [ ] battery_monitor_update() called before health publish
- [ ] RFID scan blocked when battery critical
- [ ] Active scan stops if battery becomes critical
- [ ] LED feedback provided when scan blocked
- [ ] Compiles without errors

---

### Phase 3: LED Status Indicators

#### Step 3.1: Implement Battery Status LED Task
**File**: `src/lighthouse/main/lighthouse.c`

**Add new task for battery LED patterns:**

```c
/**
 * Battery status LED task
 *
 * Uses GPIO19 (ACTIVITY_LED) to show battery status when not flashing
 * for tag detection.
 *
 * Patterns:
 *   - USB powered: Solid OFF
 *   - Battery >10%: Brief flash every 5 seconds
 *   - Battery 5-10%: Pulsing (500ms on/off)
 *   - Battery <5%: Rapid pulsing (200ms on/off)
 */
static void battery_status_led_task(void* pvParameters)
{
    const uint32_t FLASH_INTERVAL_MS = 5000;
    const uint32_t FLASH_DURATION_MS = 100;
    uint32_t last_flash = 0;
    
    while (1) {
        const battery_status_t* battery = battery_monitor_get_status();
        uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
        
        // Don't interfere with tag detection flashes
        // (Tag detection sets LED HIGH briefly, we only control when LOW)
        
        if (battery->is_usb_present) {
            // USB powered - keep LED off
            // (unless tag detection is flashing it)
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }
        
        // Battery powered - show status patterns
        if (battery->percentage >= 10) {
            // >10% - brief flash every 5 seconds
            if ((current_time - last_flash) >= FLASH_INTERVAL_MS) {
                gpio_set_level(ACTIVITY_LED, 1);
                vTaskDelay(pdMS_TO_TICKS(FLASH_DURATION_MS));
                gpio_set_level(ACTIVITY_LED, 0);
                last_flash = current_time;
            }
            vTaskDelay(pdMS_TO_TICKS(100));
            
        } else if (battery->percentage >= 5) {
            // 5-10% - pulsing pattern
            gpio_set_level(ACTIVITY_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(500));
            gpio_set_level(ACTIVITY_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(500));
            
        } else {
            // <5% - rapid pulsing (critical)
            gpio_set_level(ACTIVITY_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(200));
            gpio_set_level(ACTIVITY_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(200));
        }
    }
}
```

**Start task in `app_main()`:**
```c
void app_main(void)
{
    // ... existing initialization ...
    
    // Create battery status LED task
    xTaskCreate(battery_status_led_task, "battery_led", 
                2048, NULL, 5, NULL);
    
    // ... rest of initialization ...
}
```

**Acceptance criteria:**
- [ ] LED task created and running
- [ ] USB powered: LED stays off
- [ ] Battery >10%: Flashes every 5 seconds
- [ ] Battery 5-10%: Pulses at 500ms
- [ ] Battery <5%: Rapid pulses at 200ms
- [ ] Does not interfere with tag detection flashes

---

### Phase 4: Critical Battery Shutdown

#### Step 4.1: Implement Graceful Shutdown
**File**: `src/lighthouse/main/lighthouse.c`

**Add shutdown function:**

```c
#include "esp_sleep.h"

/**
 * Execute graceful shutdown at critical battery level
 *
 * Steps:
 *   1. Publish offline status to MQTT
 *   2. Flush offline event cache to storage
 *   3. Stop all operations
 *   4. Enter deep sleep to preserve battery
 *
 * Reference: ESP32 TRM Chapter 9 (Low-Power Management)
 */
static void battery_critical_shutdown(void)
{
    ESP_LOGW(TAG, "====================================");
    ESP_LOGW(TAG, "CRITICAL BATTERY - INITIATING SHUTDOWN");
    ESP_LOGW(TAG, "====================================");
    
    // Flash all LEDs as warning
    gpio_set_level(WIFI_STATUS_LED, 1);
    gpio_set_level(MQTT_STATUS_LED, 1);
    gpio_set_level(SCANNING_LED, 1);
    gpio_set_level(ACTIVITY_LED, 1);
    vTaskDelay(pdMS_TO_TICKS(500));
    
    // Stop RFID if active
    if (rfid_scanning) {
        rfid_reader_stop_inventory();
        rfid_reader_power_off();
    }
    
    // Publish offline status (best effort)
    mqtt_client_disconnect();
    vTaskDelay(pdMS_TO_TICKS(1000));  // Allow disconnect to complete
    
    // Flush offline event cache
    offline_event_logger_flush();
    
    // All LEDs off
    gpio_set_level(WIFI_STATUS_LED, 0);
    gpio_set_level(MQTT_STATUS_LED, 0);
    gpio_set_level(SCANNING_LED, 0);
    gpio_set_level(ACTIVITY_LED, 0);
    
    ESP_LOGW(TAG, "Entering deep sleep to preserve battery");
    ESP_LOGW(TAG, "Device will restart when USB power connected");
    
    vTaskDelay(pdMS_TO_TICKS(100));  // Allow log to flush
    
    // Enter deep sleep (will wake on power cycle)
    esp_deep_sleep_start();
}
```

**Add shutdown check in main loop:**

```c
// Main application loop
while (1) {
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
    
    // NEW: Check for shutdown battery level (3.2V)
    const battery_status_t* battery = battery_monitor_get_status();
    if (battery->voltage_mv <= BATTERY_VOLTAGE_EMPTY) {
        battery_critical_shutdown();
        // Function never returns (enters deep sleep)
    }
    
    // ... rest of main loop ...
}
```

**Acceptance criteria:**
- [ ] Shutdown function implemented with all steps
- [ ] Check added to main loop for BATTERY_VOLTAGE_EMPTY (3.2V)
- [ ] MQTT disconnect called before sleep
- [ ] Offline cache flushed before sleep
- [ ] LEDs provide visual warning before shutdown
- [ ] Deep sleep entered successfully

---

### Phase 5: Testing and Calibration

#### Step 5.1: Voltage-to-Percentage Calibration
**Purpose**: Validate discharge curve against actual battery behavior

**Test procedure:**
1. Fully charge 18650 cell to 4.2V (verify with multimeter)
2. Power lighthouse, record voltage and calculated percentage
3. Run combined WiFi + RFID scanning load for 10 minutes
4. Record voltage and percentage after load
5. Repeat steps 3-4 until battery reaches 3.2V
6. Plot measured voltage vs reported percentage
7. Adjust discharge curve if needed

**Expected results:**
- Percentage should decrease monotonically with voltage
- Percentage should reach 0% at 3.2V, 100% at 4.2V
- Curve should roughly match Li-ion discharge profile

**Documentation required:**
- Create `/logbook/battery_calibration_YYYYMMDD.md`
- Include voltage/percentage measurements table
- Note any deviations from expected curve
- Update BATTERY_VOLTAGE_* constants if needed

**Acceptance criteria:**
- [ ] Full discharge test completed
- [ ] Voltage-to-percentage mapping validated
- [ ] Discharge curve adjusted if needed
- [ ] Calibration documented in logbook

---

#### Step 5.2: Critical Threshold Validation
**Purpose**: Determine empirical critical threshold (currently 3.3V)

**Test procedure:**
1. Discharge battery to ~3.4V
2. Start RFID scanning with WiFi active
3. Monitor battery voltage under load
4. Identify voltage where system becomes unstable:
   - WiFi disconnections
   - RFID reader failures
   - ESP32 brownout symptoms (even with brownout disabled)
5. Set critical threshold 100-200mV above instability point

**Safety note**: TP4056 DW01HA should prevent discharge below ~2.4V

**Expected critical threshold**: 3.3V (current spec) ± 0.1V

**Documentation required:**
- Record instability symptoms and voltage
- Document final critical threshold selection
- Update `BATTERY_VOLTAGE_CRITICAL` if needed

**Acceptance criteria:**
- [ ] Instability threshold identified under load
- [ ] Critical threshold set with safety margin
- [ ] Threshold prevents unstable operation
- [ ] Hardware protection (DW01HA) validated as backup

---

#### Step 5.3: Battery Health Estimation Validation
**Purpose**: Verify voltage drop under load correlates with battery condition

**Test procedure:**
1. Test with fresh 18650 cell (new or recently cycled):
   - Measure no-load voltage
   - Measure voltage during RFID scan
   - Calculate drop, verify "good" classification
2. Test with aged cell (if available):
   - Repeat measurements
   - Verify "degraded" or "critical" classification
3. Document correlation between measured drop and battery condition

**Expected health classifications:**
- Fresh cell: <0.2V drop (GOOD)
- Aged cell: 0.2-0.5V drop (DEGRADED)
- Failing cell: >0.5V drop (CRITICAL)

**Acceptance criteria:**
- [ ] Health estimation tested with known battery conditions
- [ ] Classifications align with measured behavior
- [ ] Thresholds adjusted if needed (200mV, 500mV)
- [ ] Results documented

---

#### Step 5.4: Power Source Switching Validation
**Purpose**: Verify correct USB/battery detection and seamless switching

**Test procedure:**
1. **USB to Battery transition:**
   - Connect USB, verify "usb" reported in health message
   - Monitor battery voltage (should not be supplying current)
   - Disconnect USB during RFID scan
   - Verify immediate switch to "battery" source
   - Confirm no brownout or reset
   - Verify battery voltage drops under load

2. **Battery to USB transition:**
   - Running on battery with RFID scanning
   - Connect USB power
   - Verify immediate switch to "usb" source
   - Confirm battery voltage stops dropping
   - Verify no interruption to operation

3. **Edge cases:**
   - Connect/disconnect USB rapidly (5 times)
   - Verify GPIO32 detection remains stable
   - Check for spurious power source changes in logs

**Acceptance criteria:**
- [ ] USB connection detected correctly (GPIO32 HIGH)
- [ ] Battery operation detected correctly (GPIO32 LOW)
- [ ] Switching between sources is seamless
- [ ] No brownouts or resets during transitions
- [ ] Health messages report correct power source

---

#### Step 5.5: MQTT Health Message Validation
**Purpose**: Verify battery telemetry in MQTT messages

**Test procedure:**
1. Connect to MQTT broker
2. Subscribe to `attendance/lighthouse/{MAC}/health`
3. Observe health messages published every 6 seconds
4. Verify battery section present with all fields
5. Test at different battery levels and power sources

**Expected message format:**
```json
{
  "uptime_sec": 3600,
  "free_heap_bytes": 45000,
  "min_free_heap_bytes": 38000,
  "wifi_rssi_dbm": -52,
  "rfid": {
    "state": "RESPONSIVE",
    "is_responsive": true,
    "power_rail_present": true,
    "fw_version": "1.2",
    "last_error": 0
  },
  "battery": {
    "voltage_mv": 3850,
    "percentage": 55,
    "is_charging": false,
    "power_source": "battery",
    "health_status": "good",
    "voltage_under_load_mv": 3780
  }
}
```

**Validation checks:**
- [ ] Battery section present in all messages
- [ ] All fields populated with valid values
- [ ] voltage_mv matches multimeter reading (±60mV)
- [ ] percentage reasonable for voltage
- [ ] power_source correct ("usb" or "battery")
- [ ] health_status updates when scanning
- [ ] voltage_under_load_mv only updates during scans

---

#### Step 5.6: Critical Battery Behavior Testing
**Purpose**: Validate RFID blocking and shutdown at low battery

**Test procedure:**
1. **Warning level (3.4V / 10%):**
   - Discharge to warning level
   - Verify normal operation continues
   - Check LED pattern changes (pulsing)
   - Verify health message reports low battery

2. **Critical level (3.3V / 5%):**
   - Discharge to critical level
   - Attempt to start RFID scan (Button 1)
   - Verify scan is blocked
   - Verify LED error pattern (3 flashes)
   - Check log message explains blocking
   - If scan was active, verify it stops

3. **Shutdown level (3.2V / 0%):**
   - Discharge to shutdown level
   - Verify graceful shutdown sequence:
     - All LEDs flash as warning
     - RFID stops if active
     - MQTT offline message sent
     - Deep sleep entered
   - Connect USB, verify device boots normally

**Acceptance criteria:**
- [ ] Warning level: operation continues, LED pattern changes
- [ ] Critical level: RFID scan blocked, error feedback given
- [ ] Shutdown level: graceful shutdown executes
- [ ] Device recovers normally after USB reconnection
- [ ] No unexpected resets or crashes

---

## Implementation Checklist

### Phase 1: Hardware Validation
- [ ] 1.1: USB detection voltage divider installed and validated
- [ ] 1.2: Battery voltage divider verified
- [ ] 1.3: Under-load voltage measurements completed

### Phase 2: Firmware Core
- [ ] 2.1: `battery_monitor.h` created with all declarations
- [ ] 2.2: `battery_monitor.c` implemented:
  - [ ] ADC initialization and calibration
  - [ ] ADC sampling with noise reduction
  - [ ] Voltage-to-percentage conversion
  - [ ] Battery health estimation
  - [ ] USB detection (digital GPIO)
  - [ ] All getter functions
- [ ] 2.3: MQTT health message extended with battery section
- [ ] 2.4: Integration into `lighthouse.c`:
  - [ ] Initialization call added
  - [ ] Update before health publish
  - [ ] RFID blocking at critical battery
  - [ ] Stop scanning if battery becomes critical

### Phase 3: LED Indicators
- [ ] 3.1: Battery status LED task implemented
- [ ] 3.1: LED patterns working for all battery levels
- [ ] 3.1: Does not interfere with tag detection

### Phase 4: Critical Shutdown
- [ ] 4.1: Graceful shutdown function implemented
- [ ] 4.1: Shutdown check added to main loop
- [ ] 4.1: Deep sleep entered at empty battery

### Phase 5: Testing & Calibration
- [ ] 5.1: Voltage-to-percentage curve calibrated
- [ ] 5.2: Critical threshold validated empirically
- [ ] 5.3: Battery health estimation validated
- [ ] 5.4: Power source switching validated
- [ ] 5.5: MQTT health messages validated
- [ ] 5.6: Critical battery behavior tested

### Documentation
- [ ] Calibration results documented in logbook
- [ ] Final threshold values documented
- [ ] Test results recorded
- [ ] Any deviations from plan explained

---

## Risk Mitigation

### ADC Accuracy (±60mV error)
**Risk**: Battery percentage calculations may be inaccurate  
**Mitigation**: 
- Use averaging and outlier rejection in sampling
- Add hysteresis near threshold boundaries
- Calibrate using eFuse Vref values
- Validate against multimeter during testing

### Voltage Divider Tolerance
**Risk**: Resistor tolerance causes measurement error  
**Mitigation**:
- Use 1% resistors for both dividers
- Measure actual resistance with multimeter
- Adjust divider ratio in code if needed

### Battery Voltage Drop Under Load
**Risk**: Voltage drop varies with cell condition  
**Mitigation**:
- Empirical testing across discharge range
- Set critical threshold with safety margin
- Hardware protection (DW01HA) as backup
- Health estimation tracks degradation

### Brownout During WiFi Transmit
**Risk**: Battery sag during WiFi causes reset  
**Mitigation**:
- Critical threshold set above brownout point
- Testing includes WiFi active during discharge
- Bulk capacitance on power rails (already present)

### TP4056 Protection Coordination
**Risk**: Hardware and software thresholds misaligned  
**Mitigation**:
- Software threshold (3.2V) well above DW01HA cutoff (~2.4V)
- Hardware protection always active
- Software shutdown preserves data before hardware cutoff

---

## Success Criteria

Implementation is complete when:

1. **Hardware validated**: All voltage dividers installed and measurements correct
2. **Battery monitoring functional**: Voltage, percentage, power source, health all reporting correctly
3. **MQTT telemetry working**: Battery data included in health messages
4. **RFID blocking active**: Scanning prevented at critical battery level
5. **LED feedback clear**: Visual indication of battery status
6. **Graceful shutdown working**: Device enters deep sleep at empty battery
7. **Testing complete**: All test procedures passed
8. **Documentation current**: Logbook updated with results and calibration data

---

## References

### Primary Documentation
- ESP32 Datasheet v5.2: Sections 2.1, 4.9.1, 5.3, Table 4-3, Table 4-4, Table 5-3
- ESP32 Technical Reference Manual v5.6: Chapter 31 (SAR ADC), Chapter 9 (Low-Power)
- DEVLOG_2026_02_25.md: Power architecture, voltage dividers
- DEVLOG_2026_02_10.md: TP4056/DW01HA charging circuit
- tasks/mqtt_topics_task.md: Health message format

### Component Datasheets
- SS24A Schottky Diode: 2A 40V, ~0.3-0.4V forward drop
- SX1308 Boost Converter: 50mV ripple, PFM mode at light loads
- TP4056: Li-ion charge controller
- DW01HA: Battery protection IC, ~2.4V undervoltage cutoff

---

## Notes for Implementation

- Follow steps in order - hardware validation before firmware
- Test incrementally - validate each module before integration
- Document deviations or issues in logbook
- Update thresholds based on empirical testing
- Commit code after each phase completion
- Create git branch: `feature/battery-monitoring`

---

**End of Implementation Task Document**
