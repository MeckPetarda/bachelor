/**
 * battery_monitor.c - Battery voltage monitoring and power source detection
 *
 * Implements battery voltage sampling via ADC1_CH5 (GPIO33) using the
 * modern esp_adc oneshot driver (ESP-IDF v5.x). Noise is reduced through
 * 16-sample raw averaging before a single calibrated voltage conversion.
 * Sampling is gated to RFID-idle periods to avoid terminal voltage sag
 * under load. Shutdown is confirmatory: three consecutive readings below
 * the critical threshold are required before deep sleep is entered.
 *
 * All ADC code is compiled only when CONFIG_BATTERY_SENSE_ENABLED=y.
 * When disabled, all public functions return safe stub values.
 *
 * References:
 *   - ESP32 Datasheet Section 4.9.1: ADC characteristics (Table 4-3, Table 4-4)
 *   - ESP32 TRM Chapter 31 Section 31.3: SAR ADC architecture
 *   - DEVLOG_2026_02_25.md: Voltage divider specs (100kΩ/120kΩ, ratio 0.545)
 *   - ESP-IDF Migration Guide v4→v5: ADC oneshot driver
 */

#include "battery_monitor.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#if CONFIG_BATTERY_SENSE_ENABLED
#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_sleep.h"
#include "hal/gpio_types.h"
#include "uart_reader.h"
#endif

static const char *TAG = "BATTERY_MONITOR";

static battery_status_t s_battery_status = {0};

#if CONFIG_BATTERY_SENSE_ENABLED

static adc_oneshot_unit_handle_t s_adc_handle      = NULL;
static adc_cali_handle_t         s_adc_cali_handle = NULL;

// Consecutive readings below BATTERY_CRITICAL_THRESHOLD_MV (Task 4)
static int s_critical_count = 0;

// ============================================================================
// TASK 4 CONSTANTS: Confirmatory shutdown thresholds
// ============================================================================

// Shutdown arm threshold. Below this for N consecutive readings triggers shutdown.
// Set above TP4056/DW01HA hardware cutoff (~3.0V) to catch deep discharge before
// hardware protection activates. ±110mV divider-amplified ADC error provides
// the rationale for the 200mV margin above the hardware floor.
#define BATTERY_CRITICAL_THRESHOLD_MV 3400

// Hysteresis cancel level. A reading above this resets the consecutive counter.
// Must be strictly greater than BATTERY_CRITICAL_THRESHOLD_MV.
#define BATTERY_CRITICAL_CLEAR_MV 3500

// Consecutive readings required below BATTERY_CRITICAL_THRESHOLD_MV before shutdown.
// Each reading is taken at the normal polling interval, not back-to-back.
#define BATTERY_CRITICAL_CONSECUTIVE_COUNT 3

// ============================================================================
// TASK 3 CONSTANTS: Load-aware idle sampling gate
// ============================================================================

#define BATTERY_IDLE_WAIT_TIMEOUT_MS 2000 // max wait for RFID to go idle
#define BATTERY_IDLE_SETTLE_DELAY_MS 50   // settle time after reader goes idle

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

    adc_cali_line_fitting_config_t cali_config = {
        .unit_id  = BATTERY_ADC_UNIT,
        .atten    = BATTERY_ADC_ATTEN,
        .bitwidth = BATTERY_ADC_BITWIDTH,
    };

    ret = adc_cali_create_scheme_line_fitting(&cali_config, &s_adc_cali_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "ADC calibration unavailable: %s (using linear fallback)", esp_err_to_name(ret));
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
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };

    ret = gpio_config(&usb_detect_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure USB detect pin: %s", esp_err_to_name(ret));
        if (s_adc_cali_handle)
        {
            adc_cali_delete_scheme_line_fitting(s_adc_cali_handle);
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
    ESP_LOGI(TAG, "  Battery ADC: GPIO33 (ADC1_CH5, 12dB attenuation, %d-sample average)", BATTERY_ADC_SAMPLE_COUNT);
    ESP_LOGI(TAG, "  USB detect: GPIO32 (digital input)");
    ESP_LOGI(TAG, "  Voltage divider: 100k/120k (ratio 0.545)");

    return ESP_OK;
}

// ============================================================================
// TASK 2: ADC SAMPLING — 16-sample raw average before voltage conversion
// ============================================================================

/**
 * Sample ADC with raw-level averaging
 *
 * Takes BATTERY_ADC_SAMPLE_COUNT raw readings, sums them at raw count level,
 * computes the average raw value, then performs a single calibrated voltage
 * conversion. Averaging at raw level avoids accumulated rounding error that
 * would occur from converting each sample individually.
 *
 * Calibrated path: adc_cali_raw_to_voltage() (±60mV per Table 4-4)
 * Fallback path:   linear scaling voltage_mv = raw * 3100 / 4095
 *
 * Reference: ESP32 Datasheet Table 4-3 (DNL improvement via oversampling)
 *
 * @return Averaged ADC voltage at GPIO33 in millivolts
 */
static uint32_t battery_sample_adc_voltage(void)
{
    uint32_t raw_sum = 0;
    int      raw_value;

    for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++)
    {
        esp_err_t ret = adc_oneshot_read(s_adc_handle, BATTERY_ADC_CHANNEL, &raw_value);
        if (ret != ESP_OK)
        {
            ESP_LOGE(TAG, "ADC read failed: %s", esp_err_to_name(ret));
            raw_value = 0;
        }
        raw_sum += (uint32_t)raw_value;
    }

    uint32_t raw_avg = raw_sum / BATTERY_ADC_SAMPLE_COUNT;

    // Single calibrated conversion on the averaged raw value
    uint32_t voltage_mv;
    if (s_adc_cali_handle != NULL)
    {
        int       cal_mv;
        esp_err_t ret = adc_cali_raw_to_voltage(s_adc_cali_handle, (int)raw_avg, &cal_mv);
        voltage_mv    = (ret == ESP_OK) ? (uint32_t)cal_mv : (raw_avg * 3100) / 4095;
    }
    else
    {
        // Linear fallback: ADC_ATTEN_DB_12 → 0-3100mV, 12-bit → 0-4095
        voltage_mv = (raw_avg * 3100) / 4095;
    }

    return voltage_mv;
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
    } curve[]              = {{4200, 100}, {4100, 90}, {4000, 80}, {3900, 70}, {3800, 55}, {3700, 40},
                              {3600, 25},  {3500, 15}, {3400, 10}, {3300, 5},  {3200, 0}};
    const int curve_points = sizeof(curve) / sizeof(curve[0]);

    if (voltage_mv >= curve[0].voltage_mv)
        return 100;
    if (voltage_mv <= curve[curve_points - 1].voltage_mv)
        return 0;

    for (int i = 0; i < curve_points - 1; i++)
    {
        if (voltage_mv >= curve[i + 1].voltage_mv)
        {
            uint16_t v1 = curve[i].voltage_mv;
            uint16_t v2 = curve[i + 1].voltage_mv;
            uint8_t  p1 = curve[i].percentage;
            uint8_t  p2 = curve[i + 1].percentage;

            // p = p1 + (p2 - p1) * (v - v1) / (v2 - v1)
            int32_t pct = p1 + ((int32_t)(p2 - p1) * (int32_t)(voltage_mv - v1)) / (int32_t)(v2 - v1);
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
static battery_health_t battery_estimate_health(uint16_t no_load_mv, uint16_t under_load_mv)
{
    if (under_load_mv == 0)
        return BATTERY_HEALTH_UNKNOWN;

    int16_t drop_mv = (int16_t)no_load_mv - (int16_t)under_load_mv;

    if (drop_mv < 0)
        return BATTERY_HEALTH_UNKNOWN;
    if (drop_mv < 200)
        return BATTERY_HEALTH_GOOD;
    if (drop_mv < 500)
        return BATTERY_HEALTH_DEGRADED;
    return BATTERY_HEALTH_CRITICAL;
}

// ============================================================================
// MAIN UPDATE FUNCTION (Tasks 2, 3, 4 integrated)
// ============================================================================

esp_err_t battery_monitor_update(bool is_rfid_scanning)
{
    // ========================================================================
    // TASK 3: Load-aware idle sampling gate
    //
    // Battery terminal voltage collapses under combined ESP32 WiFi + RFID load
    // (confirmed scope measurement: 3.5V resting → 2.7-3.0V under load per
    // DEVLOG_2026_02_25 §3). Gate sampling to RFID-idle periods only.
    // ========================================================================

    uint32_t waited_ms = 0;
    while (rfid_reader_is_inventory_active() && waited_ms < BATTERY_IDLE_WAIT_TIMEOUT_MS)
    {
        vTaskDelay(pdMS_TO_TICKS(10));
        waited_ms += 10;
    }

    if (rfid_reader_is_inventory_active())
    {
        ESP_LOGW(TAG, "Battery sample skipped - RFID reader still active after %d ms", BATTERY_IDLE_WAIT_TIMEOUT_MS);
        return ESP_OK;
    }

    // Settle delay: allows WiFi beaconing transients to clear (typically 100ms beacon period)
    vTaskDelay(pdMS_TO_TICKS(BATTERY_IDLE_SETTLE_DELAY_MS));

    // ========================================================================
    // TASK 2: Sample voltage with 16-sample raw average
    // ========================================================================

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
        s_battery_status.health =
            battery_estimate_health(s_battery_status.voltage_mv, s_battery_status.voltage_under_load_mv);
    }

    s_battery_status.last_update_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;

    ESP_LOGI(TAG, "Battery: %umV (%u%%), USB: %s, Health: %d", battery_voltage_mv, s_battery_status.percentage,
             usb_present ? "present" : "absent", (int)s_battery_status.health);

    // ========================================================================
    // TASK 4: Confirmatory shutdown with hysteresis
    //
    // A single ADC reading below the critical threshold is insufficient grounds
    // for an irreversible deep-sleep action given ±110mV effective error at
    // cell level (±60mV ADC × 220/120 divider ratio). Three consecutive
    // readings are required. A reading above BATTERY_CRITICAL_CLEAR_MV resets
    // the counter (hysteresis band prevents chattering near the threshold).
    // ========================================================================

    if (battery_voltage_mv < BATTERY_CRITICAL_THRESHOLD_MV)
    {
        s_critical_count++;
        ESP_LOGW(TAG, "Battery critical reading %d/%d: %d mV", s_critical_count, BATTERY_CRITICAL_CONSECUTIVE_COUNT,
                 battery_voltage_mv);

        if (s_critical_count >= BATTERY_CRITICAL_CONSECUTIVE_COUNT)
        {
            ESP_LOGE(TAG,
                     "Battery critical shutdown triggered: %d consecutive readings "
                     "below %d mV (last: %d mV)",
                     BATTERY_CRITICAL_CONSECUTIVE_COUNT, BATTERY_CRITICAL_THRESHOLD_MV, battery_voltage_mv);
            // Allow log buffer to flush before entering deep sleep
            vTaskDelay(pdMS_TO_TICKS(100));
            esp_deep_sleep_start();
        }
    }
    else if (battery_voltage_mv > BATTERY_CRITICAL_CLEAR_MV)
    {
        if (s_critical_count > 0)
        {
            ESP_LOGI(TAG, "Battery critical counter reset (%d mV above clear threshold)", battery_voltage_mv);
        }
        s_critical_count = 0;
    }
    // Readings between BATTERY_CRITICAL_THRESHOLD_MV and BATTERY_CRITICAL_CLEAR_MV
    // do not increment or reset the counter (hysteresis dead-band).

    return ESP_OK;
}

// ============================================================================
// GETTER FUNCTIONS
// ============================================================================

const battery_status_t *battery_monitor_get_status(void)
{
    return &s_battery_status;
}

battery_state_t battery_monitor_get_state(void)
{
    if (s_critical_count >= BATTERY_CRITICAL_CONSECUTIVE_COUNT)
        return BATTERY_STATE_CRITICAL;
    if (s_battery_status.voltage_mv > 0 && s_battery_status.voltage_mv < BATTERY_VOLTAGE_LOW)
        return BATTERY_STATE_LOW;
    return BATTERY_STATE_NORMAL;
}

bool battery_monitor_is_critical(void)
{
    return s_critical_count >= BATTERY_CRITICAL_CONSECUTIVE_COUNT;
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
        adc_cali_delete_scheme_line_fitting(s_adc_cali_handle);
        s_adc_cali_handle = NULL;
    }

    if (s_adc_handle)
    {
        adc_oneshot_del_unit(s_adc_handle);
        s_adc_handle = NULL;
    }

    return ESP_OK;
}

#else  // CONFIG_BATTERY_SENSE_ENABLED=n — stub implementations

// ============================================================================
// STUB IMPLEMENTATIONS (CONFIG_BATTERY_SENSE_ENABLED=n)
//
// All public functions compile and return safe values.
// No ADC initialisation, GPIO config, or sampling occurs.
// ============================================================================

esp_err_t battery_monitor_init(void)
{
    ESP_LOGI(TAG, "Battery sense disabled (CONFIG_BATTERY_SENSE_ENABLED=n) — init skipped");
    return ESP_OK;
}

esp_err_t battery_monitor_update(bool is_rfid_scanning)
{
    (void)is_rfid_scanning;
    return ESP_OK;
}

const battery_status_t *battery_monitor_get_status(void)
{
    return &s_battery_status; // zero-initialised
}

battery_state_t battery_monitor_get_state(void)
{
    return BATTERY_STATE_SENSE_DISABLED;
}

bool battery_monitor_is_critical(void)
{
    return false;
}

bool battery_monitor_is_usb_present(void)
{
    return false;
}

const char *battery_monitor_get_power_source(void)
{
    return "battery";
}

esp_err_t battery_monitor_deinit(void)
{
    return ESP_OK;
}

#endif // CONFIG_BATTERY_SENSE_ENABLED
