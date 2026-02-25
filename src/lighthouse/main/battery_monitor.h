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
 * Should be called at health publish interval (~60 seconds).
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
