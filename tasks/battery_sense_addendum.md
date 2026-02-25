# Addendum: Battery Monitor API Migration (esp_adc_cal → esp_adc)

**Date**: February 26, 2026  
**Issue**: `esp_adc_cal` component deprecated in ESP-IDF v5.0+  
**Solution**: Migrate to modern `esp_adc` and `esp_adc_cali` APIs

---

## Problem

The original implementation task uses the deprecated `esp_adc_cal` component which has been removed from ESP-IDF v5.0 and later. Build fails with:

```
HINT: The component 'esp_adc_cal' could not be found.
```

---

## Solution Overview

Replace deprecated API calls with modern equivalents:

| Deprecated (v4.x) | Modern (v5.x) |
|-------------------|---------------|
| `#include "driver/adc.h"` | `#include "esp_adc/adc_oneshot.h"` |
| `#include "esp_adc_cal.h"` | `#include "esp_adc/adc_cali.h"` |
| `adc1_config_width()` | `adc_oneshot_config_t` struct |
| `adc1_config_channel_atten()` | `adc_oneshot_chan_cfg_t` struct |
| `esp_adc_cal_characterize()` | `adc_cali_create_scheme_curve_fitting()` |
| `adc1_get_raw()` | `adc_oneshot_read()` |
| `esp_adc_cal_raw_to_voltage()` | `adc_cali_raw_to_voltage()` |

**Reference**: ESP-IDF Migration Guide (v4.x to v5.x)  
https://docs.espressif.com/projects/esp-idf/en/latest/esp32/migration-guides/release-5.x/5.0/peripherals.html#adc

---

## Required Changes

### Change 1: Update Header File

**File**: `src/lighthouse/main/battery_monitor.h`

**Find:**
```c
#define BATTERY_ADC_CHANNEL     ADC1_CHANNEL_5  // GPIO33
#define BATTERY_ADC_ATTEN       ADC_ATTEN_DB_11 // 150-2450mV range
#define BATTERY_ADC_WIDTH       ADC_WIDTH_BIT_12
```

**Replace with:**
```c
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"

#define BATTERY_ADC_UNIT        ADC_UNIT_1
#define BATTERY_ADC_CHANNEL     ADC_CHANNEL_5   // GPIO33
#define BATTERY_ADC_ATTEN       ADC_ATTEN_DB_12 // 0-3100mV range (was DB_11 in v4.x)
#define BATTERY_ADC_BITWIDTH    ADC_BITWIDTH_12
```

**Note**: `ADC_ATTEN_DB_11` renamed to `ADC_ATTEN_DB_12` in v5.x (same functionality)

---

### Change 2: Update Module Implementation

**File**: `src/lighthouse/main/battery_monitor.c`

#### A. Replace includes

**Find:**
```c
#include "battery_monitor.h"
#include "driver/adc.h"
#include "driver/gpio.h"
#include "esp_adc_cal.h"
#include "esp_log.h"
```

**Replace with:**
```c
#include "battery_monitor.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "driver/gpio.h"
#include "esp_log.h"
```

---

#### B. Replace static variables

**Find:**
```c
static const char* TAG = "battery_monitor";
static battery_status_t s_battery_status = {0};
static esp_adc_cal_characteristics_t s_adc_chars;
```

**Replace with:**
```c
static const char* TAG = "battery_monitor";
static battery_status_t s_battery_status = {0};

// Modern ADC API handles
static adc_oneshot_unit_handle_t s_adc_handle = NULL;
static adc_cali_handle_t s_adc_cali_handle = NULL;
```

---

#### C. Replace initialization function

**Find the entire `battery_monitor_init()` function and replace with:**

```c
esp_err_t battery_monitor_init(void)
{
    ESP_LOGI(TAG, "Initializing battery monitor");
    
    // ========================================================================
    // Configure ADC1 for battery voltage sensing (modern API)
    // Reference: ESP32 TRM Chapter 31 Section 31.3
    // ========================================================================
    
    // Initialize ADC unit
    adc_oneshot_unit_init_cfg_t init_config = {
        .unit_id = BATTERY_ADC_UNIT,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    
    esp_err_t ret = adc_oneshot_new_unit(&init_config, &s_adc_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize ADC unit: %s", esp_err_to_name(ret));
        return ret;
    }
    
    // Configure ADC channel
    adc_oneshot_chan_cfg_t chan_config = {
        .atten = BATTERY_ADC_ATTEN,
        .bitwidth = BATTERY_ADC_BITWIDTH,
    };
    
    ret = adc_oneshot_config_channel(s_adc_handle, BATTERY_ADC_CHANNEL, &chan_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure ADC channel: %s", esp_err_to_name(ret));
        adc_oneshot_del_unit(s_adc_handle);
        return ret;
    }
    
    // ========================================================================
    // ADC Calibration using eFuse Vref
    // Reference: ESP32 Datasheet Table 4-4 (±60mV accuracy with calibration)
    // ========================================================================
    
    adc_cali_curve_fitting_config_t cali_config = {
        .unit_id = BATTERY_ADC_UNIT,
        .chan = BATTERY_ADC_CHANNEL,
        .atten = BATTERY_ADC_ATTEN,
        .bitwidth = BATTERY_ADC_BITWIDTH,
    };
    
    ret = adc_cali_create_scheme_curve_fitting(&cali_config, &s_adc_cali_handle);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "ADC calibration failed: %s (will use raw values)", 
                 esp_err_to_name(ret));
        // Continue without calibration - will be less accurate but functional
        s_adc_cali_handle = NULL;
    } else {
        ESP_LOGI(TAG, "ADC calibration successful");
    }
    
    // ========================================================================
    // Configure GPIO32 for USB detection (digital input)
    // Reference: ESP32 Datasheet Table 5-3 (V_IH threshold)
    // ========================================================================
    
    gpio_config_t usb_detect_config = {
        .pin_bit_mask = (1ULL << USB_DETECT_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,  // Pull LOW when USB absent
        .intr_type    = GPIO_INTR_DISABLE,
    };
    
    ret = gpio_config(&usb_detect_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure USB detect pin: %s", 
                 esp_err_to_name(ret));
        adc_oneshot_del_unit(s_adc_handle);
        if (s_adc_cali_handle) {
            adc_cali_delete_scheme_curve_fitting(s_adc_cali_handle);
        }
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

---

#### D. Replace ADC sampling function

**Find the `battery_sample_adc_voltage()` function and replace with:**

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
    int raw_value;
    
    // Take multiple samples
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++) {
        // Read raw ADC value
        esp_err_t ret = adc_oneshot_read(s_adc_handle, BATTERY_ADC_CHANNEL, &raw_value);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "ADC read failed: %s", esp_err_to_name(ret));
            readings[i] = 0;
        } else {
            // Convert to voltage using calibration (if available)
            if (s_adc_cali_handle != NULL) {
                int voltage_mv;
                ret = adc_cali_raw_to_voltage(s_adc_cali_handle, raw_value, &voltage_mv);
                if (ret == ESP_OK) {
                    readings[i] = voltage_mv;
                } else {
                    // Fallback: simple linear scaling without calibration
                    // ADC_ATTEN_DB_12: 0-3100mV range, 12-bit = 0-4095
                    readings[i] = (raw_value * 3100) / 4095;
                }
            } else {
                // No calibration - use simple linear scaling
                readings[i] = (raw_value * 3100) / 4095;
            }
        }
        
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

---

### Change 3: Add Cleanup Function (Optional but Recommended)

**File**: `src/lighthouse/main/battery_monitor.h`

**Add to public API section:**
```c
/**
 * Deinitialize battery monitoring system
 *
 * Releases ADC resources. Call during shutdown if needed.
 *
 * @return ESP_OK on success
 */
esp_err_t battery_monitor_deinit(void);
```

**File**: `src/lighthouse/main/battery_monitor.c`

**Add implementation:**
```c
esp_err_t battery_monitor_deinit(void)
{
    ESP_LOGI(TAG, "Deinitializing battery monitor");
    
    if (s_adc_cali_handle) {
        adc_cali_delete_scheme_curve_fitting(s_adc_cali_handle);
        s_adc_cali_handle = NULL;
    }
    
    if (s_adc_handle) {
        adc_oneshot_del_unit(s_adc_handle);
        s_adc_handle = NULL;
    }
    
    return ESP_OK;
}
```

---

## Verification Checklist

After making these changes:

- [ ] Code compiles without errors (`idf.py build`)
- [ ] No warnings about deprecated APIs
- [ ] ADC initialization succeeds (check logs)
- [ ] Battery voltage readings are reasonable (3.2-4.2V range)
- [ ] USB detection still works (digital GPIO unchanged)
- [ ] Calibration warning in logs if calibration unavailable (acceptable)
- [ ] All other battery monitor functionality unchanged

---

## Key Differences to Note

### API Behavior Changes

1. **Attenuation naming**: `ADC_ATTEN_DB_11` → `ADC_ATTEN_DB_12` (same 0-2450mV range)
2. **Handle-based API**: Must keep `adc_oneshot_unit_handle_t` and `adc_cali_handle_t` handles
3. **Error handling**: Modern API returns errors more explicitly - handle them
4. **Calibration optional**: System works without calibration (reduced accuracy)

### Voltage Range Update

The modern API uses `ADC_ATTEN_DB_12` which provides 0-3100mV range (was 0-2450mV). Our voltage divider output (1.75-2.29V) is well within this range, so no hardware changes needed.

### Fallback Behavior

If calibration fails (no eFuse values programmed), the code falls back to linear scaling:
```c
voltage_mv = (raw_value * 3100) / 4095
```

This is less accurate (±100mV vs ±60mV with calibration) but functional.

---

## Testing After Migration

Run the same Phase 5 tests from original implementation task:

1. **Voltage reading validation**: Compare ADC readings to multimeter
2. **Percentage calculation**: Verify discharge curve still accurate
3. **Power source detection**: USB/battery switching still works
4. **Critical thresholds**: RFID blocking and shutdown still trigger correctly
5. **MQTT telemetry**: Battery data still published in health messages

---

## Reference Documentation

- **ESP-IDF ADC Oneshot Driver**: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/adc_oneshot.html
- **ESP-IDF ADC Calibration**: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/adc_calibration.html
- **Migration Guide (v4.x → v5.x)**: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/migration-guides/release-5.x/5.0/peripherals.html#adc

---

**End of Addendum**
