#ifndef IO_CONTROLLER_H
#define IO_CONTROLLER_H

#include "esp_err.h"
#include "hal/gpio_types.h"
#include "rfid_reader.h"
#include <stdbool.h>
#include <stdint.h>

/**
 * Initialize all GPIO: LEDs, buttons, IR sensor, ISR service.
 * Must be called once from app_main() before any other io_ function.
 */
void io_init(void);

/**
 * Process button state machines (debounce, combo gesture, mode toggle).
 * Call once per main loop iteration (~10 ms).
 */
void io_process_buttons(void);

/**
 * Process IR sensor trigger and burst expiry.
 * Call once per main loop iteration (~10 ms).
 */
void io_process_ir_sensor(void);

/**
 * Update LED1 and LED2 indicators based on connectivity and scan mode.
 * Call once per main loop iteration after processing buttons/IR.
 *
 * @param wifi_connected  true if WiFi STA is connected
 * @param mqtt_connected  true if MQTT broker session is active
 */
void io_update_status_leds(bool wifi_connected, bool mqtt_connected);

/**
 * Start the battery status LED background task.
 * Call once during init, after battery_monitor_init().
 */
void io_start_battery_led_task(void);

/**
 * Brief flash on the activity LED (tag detection feedback).
 * Blocks for ~100 ms. Safe to call from any task context.
 */
void io_flash_activity_led(void);

// =========================================================================
// State Getters / Setters
// =========================================================================

/** @return true if RFID inventory is currently active (IR or manual) */
bool io_is_scanning(void);

/** Set the scanning state. Called by lighthouse.c when it stops scanning externally. */
void io_set_scanning(bool active);

/** @return true if the combo gesture (dual-button hold) is in progress */
bool io_is_combo_active(void);

/**
 * Start the RFID inventory sequence (power on, handshake, start).
 * Sets scanning state and SCANNING_LED on success.
 * Requires a tag callback — register it first with io_set_tag_callback().
 */
void io_start_rfid_scan(void);

/**
 * Register the tag detection callback that will be passed to
 * rfid_reader_start_inventory(). Must be called before io_process_buttons()
 * or io_process_ir_sensor() can start a scan.
 */
typedef void (*io_tag_callback_t)(const rfid_tag_event_t *event);
void io_set_tag_callback(io_tag_callback_t cb);

/**
 * Register a callback invoked on Button 2 short press for health/diagnostics
 * publishing. Keeps io_controller free of MQTT dependencies.
 */
typedef void (*io_health_callback_t)(void);
void io_set_health_callback(io_health_callback_t cb);

// =========================================================================
// LED Helpers (for battery_critical_shutdown in lighthouse.c)
// =========================================================================

/** Set all four LEDs to the given state (on/off). */
void io_set_all_leds(bool state);

/** Get LED1 pin number (needed for wifi_provisioning_init). */
gpio_num_t io_get_led1_pin(void);

/** Get LED2 pin number (needed for wifi_provisioning_init). */
gpio_num_t io_get_led2_pin(void);

#endif // IO_CONTROLLER_H
