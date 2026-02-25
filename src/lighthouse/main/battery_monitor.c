/**
 * battery_monitor.c - Battery voltage monitoring and power source detection
 *
 * Implements battery voltage sampling via ADC1_CH5 (GPIO33) using the
 * modern esp_adc oneshot driver (ESP-IDF v5.x). Noise is reduced through
 * multi-sample averaging with outlier rejection. USB power presence is
 * detected via GPIO32 digital input.
 *
 * Migration note: Replaced deprecated esp_adc_cal (v4.x) with esp_adc
 * oneshot + adc_cali_scheme_curve_fitting (v5.x).
 *
 * References:
 *   - ESP32 Datasheet Section 4.9.1: ADC characteristics (Table 4-3, Table 4-4)
 *   - ESP32 TRM Chapter 31 Section 31.3: SAR ADC architecture
 *   - DEVLOG_2026_02_25.md: Voltage divider specs (100kΩ/120kΩ, ratio 0.545)
 *   - ESP-IDF Migration Guide v4→v5: ADC oneshot driver
 */

#include "battery_monitor.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "battery_monitor";

static battery_status_t          s_battery_status  = {0};
static adc_oneshot_unit_handle_t s_adc_handle      = NULL;
static adc_cali_handle_t         s_adc_cali_handle = NULL;

// ============================================================================
// INITIALIZATION
// ============================================================================

esp_err_t battery_monitor_init(void)
{
    ESP_LOGI(TAG, "Initializing battery monitor");

    // ========================================================================
    // Configure ADC1 for battery voltage sensing (modern oneshot API)
    // Reference: ESP32 TRM Chapter 31 Section 31.3
    // ========================================================================

    adc_oneshot_unit_init_cfg_t init_config = {
        .unit_id  = BATTERY_ADC_UNIT,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };

    esp_err_t ret = adc_oneshot_new_unit(&init_config, &s_adc_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize ADC unit: %s", esp_err_to_name(ret));
        return ret;
    }

    // Configure ADC channel for GPIO33 (ADC1_CH5)
    // ADC_ATTEN_DB_12 covers 0-3100mV - sufficient for 1.75-2.29V divider output
    adc_oneshot_chan_cfg_t chan_config = {
        .atten    = BATTERY_ADC_ATTEN,
        .bitwidth = BATTERY_ADC_BITWIDTH,
    };

    ret = adc_oneshot_config_channel(s_adc_handle, BATTERY_ADC_CHANNEL, &chan_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure ADC channel: %s", esp_err_to_name(ret));
        adc_oneshot_del_unit(s_adc_handle);
        s_adc_handle = NULL;
        return ret;
    }

    // ========================================================================
    // ADC Calibration using curve fitting (eFuse Vref)
    // Reference: ESP32 Datasheet Table 4-4 (±60mV accuracy with calibration)
    // ========================================================================

    adc_cali_curve_fitting_config_t cali_config = {
        .unit_id  = BATTERY_ADC_UNIT,
        .chan     = BATTERY_ADC_CHANNEL,
        .atten    = BATTERY_ADC_ATTEN,
        .bitwidth = BATTERY_ADC_BITWIDTH,
    };

    ret = adc_cali_create_scheme_curve_fitting(&cali_config, &s_adc_cali_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "ADC calibration unavailable: %s (using linear fallback)",
                 esp_err_to_name(ret));
        // Acceptable - fallback to linear scaling (±100mV vs ±60mV calibrated)
        s_adc_cali_handle = NULL;
    }
    else
    {
        ESP_LOGI(TAG, "ADC calibration scheme: curve fitting");
    }

    // ========================================================================
    // Configure GPIO32 for USB 5V presence detection (digital input)
    // Reference: ESP32 Datasheet Table 5-3 (V_IH = 0.75×VDD = 2.475V)
    // Divider produces ~1.6V when USB present - detected as logic HIGH
    // ========================================================================

    gpio_config_t usb_detect_config = {
        .pin_bit_mask = (1ULL << USB_DETECT_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE, // Pull LOW when USB absent
        .intr_type    = GPIO_INTR_DISABLE,
    };

    ret = gpio_config(&usb_detect_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure USB detect pin: %s", esp_err_to_name(ret));
        if (s_adc_cali_handle)
        {
            adc_cali_delete_scheme_curve_fitting(s_adc_cali_handle);
            s_adc_cali_handle = NULL;
        }
        adc_oneshot_del_unit(s_adc_handle);
        s_adc_handle = NULL;
        return ret;
    }

    // Initialize status structure
    s_battery_status.health         = BATTERY_HEALTH_UNKNOWN;
    s_battery_status.last_update_ms = 0;

    ESP_LOGI(TAG, "Battery monitor initialized");
    ESP_LOGI(TAG, "  Battery ADC: GPIO33 (ADC1_CH5, 12dB attenuation)");
    ESP_LOGI(TAG, "  USB detect: GPIO32 (digital input, pull-down)");
    ESP_LOGI(TAG, "  Voltage divider: 100k/120k (ratio 0.545)");

    return ESP_OK;
}

// ============================================================================
// ADC SAMPLING
// ============================================================================

/**
 * Sample ADC with averaging and outlier rejection
 *
 * Takes BATTERY_ADC_SAMPLE_COUNT readings, sorts them, discards the highest
 * and lowest, then averages the remaining middle samples.
 *
 * Calibrated path: adc_cali_raw_to_voltage() (±60mV per Table 4-4)
 * Fallback path:   linear scaling voltage_mv = raw * 3100 / 4095
 *
 * Reference: ESP32 Datasheet Table 4-3 (DNL/INL guidance)
 *
 * @return Averaged ADC voltage at GPIO33 in millivolts
 */
static uint32_t battery_sample_adc_voltage(void)
{
    uint32_t readings[BATTERY_ADC_SAMPLE_COUNT];
    int      raw_value;

    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++)
    {
        esp_err_t ret = adc_oneshot_read(s_adc_handle, BATTERY_ADC_CHANNEL, &raw_value);
        if (ret != ESP_OK)
        {
            ESP_LOGE(TAG, "ADC read failed: %s", esp_err_to_name(ret));
            readings[i] = 0;
        }
        else if (s_adc_cali_handle != NULL)
        {
            // Calibrated conversion (preferred)
            int voltage_mv;
            ret = adc_cali_raw_to_voltage(s_adc_cali_handle, raw_value, &voltage_mv);
            readings[i] = (ret == ESP_OK) ? (uint32_t)voltage_mv
                                          : (uint32_t)((raw_value * 3100) / 4095);
        }
        else
        {
            // Linear fallback: ADC_ATTEN_DB_12 → 0-3100mV, 12-bit → 0-4095
            readings[i] = (uint32_t)((raw_value * 3100) / 4095);
        }

        if (i < BATTERY_ADC_SAMPLE_COUNT - 1)
        {
            vTaskDelay(pdMS_TO_TICKS(BATTERY_ADC_SAMPLE_DELAY_MS));
        }
    }

    // Bubble sort to identify min/max for outlier rejection
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT - 1; i++)
    {
        for (int j = 0; j < BATTERY_ADC_SAMPLE_COUNT - i - 1; j++)
        {
            if (readings[j] > readings[j + 1])
            {
                uint32_t temp   = readings[j];
                readings[j]     = readings[j + 1];
                readings[j + 1] = temp;
            }
        }
    }

    // Average middle samples (discard min and max)
    uint32_t sum = 0;
    for (int i = 1; i < BATTERY_ADC_SAMPLE_COUNT - 1; i++)
    {
        sum += readings[i];
    }

    return sum / (BATTERY_ADC_SAMPLE_COUNT - 2);
}

// ============================================================================
// VOLTAGE TO PERCENTAGE CONVERSION
// ============================================================================

/**
 * Convert battery voltage to percentage using Li-ion discharge curve
 *
 * Voltage-to-percentage mapping (empirical for 18650 Li-ion):
 *   4.2V → 100%, 4.1V → 90%, 4.0V → 80%, 3.9V → 70%,
 *   3.8V → 55%,  3.7V → 40%, 3.6V → 25%, 3.5V → 15%,
 *   3.4V → 10%,  3.3V → 5%,  3.2V → 0%
 *
 * Uses linear interpolation between curve points.
 *
 * @param voltage_mv Battery voltage in millivolts
 * @return State of charge (0-100%)
 */
static uint8_t battery_voltage_to_percentage(uint16_t voltage_mv)
{
    static const struct
    {
        uint16_t voltage_mv;
        uint8_t  percentage;
    } curve[] = {
        {4200, 100}, {4100, 90}, {4000, 80}, {3900, 70},
        {3800, 55},  {3700, 40}, {3600, 25}, {3500, 15},
        {3400, 10},  {3300, 5},  {3200, 0}
    };
    const int curve_points = sizeof(curve) / sizeof(curve[0]);

    if (voltage_mv >= curve[0].voltage_mv) return 100;
    if (voltage_mv <= curve[curve_points - 1].voltage_mv) return 0;

    for (int i = 0; i < curve_points - 1; i++)
    {
        if (voltage_mv >= curve[i + 1].voltage_mv)
        {
            uint16_t v1 = curve[i].voltage_mv;
            uint16_t v2 = curve[i + 1].voltage_mv;
            uint8_t  p1 = curve[i].percentage;
            uint8_t  p2 = curve[i + 1].percentage;

            // p = p1 + (p2 - p1) * (v - v1) / (v2 - v1)
            int32_t pct = p1 + ((int32_t)(p2 - p1) *
                          (int32_t)(voltage_mv - v1)) / (int32_t)(v2 - v1);
            return (uint8_t)pct;
        }
    }

    return 0;
}

// ============================================================================
// BATTERY HEALTH ESTIMATION
// ============================================================================

/**
 * Estimate battery health from voltage drop under RFID load
 *
 * Classification (per DEVLOG_2026_02_25):
 *   - GOOD:     <200mV drop (healthy cell)
 *   - DEGRADED: 200-500mV drop (aging cell)
 *   - CRITICAL: >500mV drop (failing cell)
 *
 * @param no_load_mv    Voltage without RFID load (millivolts)
 * @param under_load_mv Voltage during RFID scan (millivolts)
 * @return Battery health classification
 */
static battery_health_t battery_estimate_health(uint16_t no_load_mv,
                                                uint16_t under_load_mv)
{
    if (under_load_mv == 0) return BATTERY_HEALTH_UNKNOWN;

    int16_t drop_mv = (int16_t)no_load_mv - (int16_t)under_load_mv;

    if (drop_mv < 0)   return BATTERY_HEALTH_UNKNOWN;
    if (drop_mv < 200) return BATTERY_HEALTH_GOOD;
    if (drop_mv < 500) return BATTERY_HEALTH_DEGRADED;
    return BATTERY_HEALTH_CRITICAL;
}

// ============================================================================
// MAIN UPDATE FUNCTION
// ============================================================================

esp_err_t battery_monitor_update(bool is_rfid_scanning)
{
    // Sample voltage at ADC input (1.75-2.29V after divider)
    uint32_t adc_voltage_mv = battery_sample_adc_voltage();

    // Scale to actual battery voltage
    // Divider ratio: R2 / (R1 + R2) = 120k / 220k
    // Battery_V = ADC_V × (220 / 120)
    uint16_t battery_voltage_mv = (uint16_t)((adc_voltage_mv * 220) / 120);

    bool usb_present = (gpio_get_level(USB_DETECT_PIN) == 1);

    s_battery_status.voltage_mv     = battery_voltage_mv;
    s_battery_status.is_usb_present = usb_present;
    s_battery_status.percentage     = battery_voltage_to_percentage(battery_voltage_mv);

    if (is_rfid_scanning)
    {
        s_battery_status.voltage_under_load_mv = battery_voltage_mv;
        s_battery_status.health = battery_estimate_health(
            s_battery_status.voltage_mv,
            s_battery_status.voltage_under_load_mv);
    }

    s_battery_status.last_update_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;

    ESP_LOGD(TAG, "Battery: %umV (%u%%), USB: %s, Health: %d",
             battery_voltage_mv, s_battery_status.percentage,
             usb_present ? "present" : "absent",
             (int)s_battery_status.health);

    return ESP_OK;
}

// ============================================================================
// GETTER FUNCTIONS
// ============================================================================

const battery_status_t *battery_monitor_get_status(void)
{
    return &s_battery_status;
}

bool battery_monitor_is_critical(void)
{
    return s_battery_status.voltage_mv > 0 &&
           s_battery_status.voltage_mv < BATTERY_VOLTAGE_CRITICAL;
}

bool battery_monitor_is_usb_present(void)
{
    return s_battery_status.is_usb_present;
}

const char *battery_monitor_get_power_source(void)
{
    return s_battery_status.is_usb_present ? "usb" : "battery";
}

// ============================================================================
// DEINITIALIZATION
// ============================================================================

esp_err_t battery_monitor_deinit(void)
{
    ESP_LOGI(TAG, "Deinitializing battery monitor");

    if (s_adc_cali_handle)
    {
        adc_cali_delete_scheme_curve_fitting(s_adc_cali_handle);
        s_adc_cali_handle = NULL;
    }

    if (s_adc_handle)
    {
        adc_oneshot_del_unit(s_adc_handle);
        s_adc_handle = NULL;
    }

    return ESP_OK;
}
