/**
 * battery_monitor.c - Battery voltage monitoring and power source detection
 *
 * Implements battery voltage sampling via ADC1_CH5 (GPIO33) with noise
 * reduction through multi-sample averaging and outlier rejection.
 * Detects USB power presence via GPIO32 digital input.
 *
 * References:
 *   - ESP32 Datasheet Section 4.9.1: ADC characteristics (Table 4-3, Table 4-4)
 *   - ESP32 TRM Chapter 31 Section 31.3: SAR ADC architecture
 *   - DEVLOG_2026_02_25.md: Voltage divider specs (100kΩ/120kΩ, ratio 0.545)
 */

#include "battery_monitor.h"
#include "driver/adc.h"
#include "driver/gpio.h"
#include "esp_adc_cal.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "battery_monitor";

static battery_status_t             s_battery_status = {0};
static esp_adc_cal_characteristics_t s_adc_chars;

// ============================================================================
// INITIALIZATION
// ============================================================================

esp_err_t battery_monitor_init(void)
{
    ESP_LOGI(TAG, "Initializing battery monitor");

    // Configure ADC1 for battery voltage sensing on GPIO33 (ADC1_CH5)
    // Reference: ESP32 TRM Chapter 31 Section 31.3
    // ADC_ATTEN_DB_11 covers 150-2450mV - needed for 1.75-2.29V divider output
    adc1_config_width(BATTERY_ADC_WIDTH);
    adc1_config_channel_atten(BATTERY_ADC_CHANNEL, BATTERY_ADC_ATTEN);

    // Characterize ADC using eFuse Vref for calibration
    // Reference: ESP32 Datasheet Table 4-4 (±60mV accuracy with calibration)
    esp_adc_cal_characterize(ADC_UNIT_1, BATTERY_ADC_ATTEN,
                             BATTERY_ADC_WIDTH, 1100, &s_adc_chars);

    // Configure GPIO32 as digital input for USB 5V presence detection
    // Reference: ESP32 Datasheet Table 5-3 (V_IH = 0.75×VDD = 2.475V)
    // Divider produces ~1.6V when USB present - read as logic HIGH
    gpio_config_t usb_detect_config = {
        .pin_bit_mask = (1ULL << USB_DETECT_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,  // Pull LOW when USB absent
        .intr_type    = GPIO_INTR_DISABLE,
    };
    esp_err_t ret = gpio_config(&usb_detect_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure USB detect pin: %s", esp_err_to_name(ret));
        return ret;
    }

    // Initialize status structure
    s_battery_status.health         = BATTERY_HEALTH_UNKNOWN;
    s_battery_status.last_update_ms = 0;

    ESP_LOGI(TAG, "Battery monitor initialized");
    ESP_LOGI(TAG, "  Battery ADC: GPIO33 (ADC1_CH5, 11dB attenuation)");
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
 * Takes BATTERY_ADC_SAMPLE_COUNT readings, sorts them, discards the
 * highest and lowest, then averages the remaining middle samples.
 *
 * Reference: ESP32 Datasheet Table 4-3 (DNL/INL guidance)
 *
 * @return Averaged ADC voltage in millivolts
 */
static uint32_t battery_sample_adc_voltage(void)
{
    uint32_t readings[BATTERY_ADC_SAMPLE_COUNT];

    // Take multiple samples with delay between each
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++)
    {
        readings[i] = esp_adc_cal_raw_to_voltage(
            adc1_get_raw(BATTERY_ADC_CHANNEL), &s_adc_chars);
        if (i < BATTERY_ADC_SAMPLE_COUNT - 1)
        {
            vTaskDelay(pdMS_TO_TICKS(BATTERY_ADC_SAMPLE_DELAY_MS));
        }
    }

    // Bubble sort to find min/max for outlier rejection
    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT - 1; i++)
    {
        for (int j = 0; j < BATTERY_ADC_SAMPLE_COUNT - i - 1; j++)
        {
            if (readings[j] > readings[j + 1])
            {
                uint32_t temp    = readings[j];
                readings[j]      = readings[j + 1];
                readings[j + 1]  = temp;
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
    // Discharge curve lookup table (descending voltage order)
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

    // Clamp to valid range
    if (voltage_mv >= curve[0].voltage_mv) return 100;
    if (voltage_mv <= curve[curve_points - 1].voltage_mv) return 0;

    // Linear interpolation between adjacent curve points
    for (int i = 0; i < curve_points - 1; i++)
    {
        if (voltage_mv >= curve[i + 1].voltage_mv)
        {
            uint16_t v1 = curve[i].voltage_mv;
            uint16_t v2 = curve[i + 1].voltage_mv;
            uint8_t  p1 = curve[i].percentage;
            uint8_t  p2 = curve[i + 1].percentage;

            // p = p1 + (p2 - p1) * (v - v1) / (v2 - v1)
            int32_t percentage = p1 + ((int32_t)(p2 - p1) *
                                 (int32_t)(voltage_mv - v1)) / (int32_t)(v2 - v1);
            return (uint8_t)percentage;
        }
    }

    return 0;
}

// ============================================================================
// BATTERY HEALTH ESTIMATION
// ============================================================================

/**
 * Estimate battery health from voltage drop under load
 *
 * Compares idle voltage to under-load voltage during RFID scan.
 *
 * Classification:
 *   - GOOD:     <200mV drop (healthy cell, per DEVLOG_2026_02_25)
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
    if (under_load_mv == 0)
    {
        return BATTERY_HEALTH_UNKNOWN;
    }

    int16_t drop_mv = (int16_t)no_load_mv - (int16_t)under_load_mv;

    if (drop_mv < 0)
    {
        // Under-load higher than no-load is unexpected
        return BATTERY_HEALTH_UNKNOWN;
    }

    if (drop_mv < 200)
    {
        return BATTERY_HEALTH_GOOD;
    }
    else if (drop_mv < 500)
    {
        return BATTERY_HEALTH_DEGRADED;
    }
    else
    {
        return BATTERY_HEALTH_CRITICAL;
    }
}

// ============================================================================
// MAIN UPDATE FUNCTION
// ============================================================================

esp_err_t battery_monitor_update(bool is_rfid_scanning)
{
    // Sample battery voltage at the ADC input (1.75-2.29V range after divider)
    uint32_t adc_voltage_mv = battery_sample_adc_voltage();

    // Convert ADC voltage to actual battery voltage using divider ratio inverse
    // Divider ratio: R2 / (R1 + R2) = 120kΩ / (100kΩ + 120kΩ) = 120/220
    // Battery_V = ADC_V × (220 / 120)
    uint16_t battery_voltage_mv = (uint16_t)((adc_voltage_mv * 220) / 120);

    // Read USB presence from GPIO32 digital input
    bool usb_present = (gpio_get_level(USB_DETECT_PIN) == 1);

    // Update status
    s_battery_status.voltage_mv    = battery_voltage_mv;
    s_battery_status.is_usb_present = usb_present;
    s_battery_status.percentage    = battery_voltage_to_percentage(battery_voltage_mv);

    // Update under-load voltage and health estimate when RFID is scanning
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
