/**
 * wifi_provisioning.h - WiFi Provisioning State Machine Interface
 *
 * Manages the WiFi provisioning lifecycle including:
 * - Setup mode entry (5-second button press)
 * - AP mode for web-based configuration
 * - Connection testing and state transitions
 * - LED status indication
 *
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2
 */

#ifndef WIFI_PROVISIONING_H
#define WIFI_PROVISIONING_H

#include "driver/gpio.h"
#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// STATE DEFINITIONS
// ============================================================================

/**
 * WiFi Provisioning State Machine States
 *
 * State transitions:
 *   UNCONFIGURED -> (5s button) -> SETUP_REQUESTED -> (reboot) -> AP_ACTIVE
 *   AP_ACTIVE -> (creds submitted) -> CONNECTING
 *   CONNECTING -> (success) -> CONNECTED
 *   CONNECTING -> (failure) -> AP_ACTIVE (retry)
 *   UNCONFIGURED -> (boot with config) -> CONNECTING -> CONNECTED/OFFLINE
 */
typedef enum
{
    WIFI_STATE_UNCONFIGURED    = 0, // No config saved; waiting for user action
    WIFI_STATE_SETUP_REQUESTED = 1, // User triggered setup; reboot flag set
    WIFI_STATE_AP_ACTIVE       = 2, // Broadcasting AP, serving provisioning page
    WIFI_STATE_CONNECTING      = 3, // Attempting STA connection with credentials
    WIFI_STATE_CONNECTED       = 4, // Successfully connected to WiFi network
    WIFI_STATE_OFFLINE         = 5, // Connection failed; running in offline mode
} wifi_state_t;

/**
 * WiFi Provisioning Events
 *
 * Events drive state transitions in the provisioning state machine.
 * Note: Named wifi_prov_event_t to avoid conflict with ESP-IDF's wifi_event_t
 */
typedef enum
{
    WIFI_PROV_EVENT_NONE                 = 0, // No event pending
    WIFI_PROV_EVENT_CONFIG_LOADED        = 1, // Credentials loaded from NVS partition
    WIFI_PROV_EVENT_SETUP_BUTTON_PRESSED = 2, // User held BUTTON2 for 5 seconds
    WIFI_PROV_EVENT_CREDS_SUBMITTED      = 3, // Provisioning form submitted via HTTP
    WIFI_PROV_EVENT_CONNECTION_SUCCESS   = 4, // WiFi STA connection succeeded
    WIFI_PROV_EVENT_CONNECTION_FAILED    = 5, // WiFi STA connection timed out
    WIFI_PROV_EVENT_REBOOT_REQUESTED     = 6, // User clicked restart button on webpage
} wifi_prov_event_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize WiFi provisioning system
 *
 * Call this early in app_main(), before RFID initialization.
 * Initializes NVS storage, checks configuration status, and
 * determines initial state.
 *
 * @param led_pin GPIO pin for WiFi status LED (LED1_PIN)
 *                LED blinks at 1s interval during AP mode
 * @param connection_timeout_ms How long to wait for WiFi connection
 *                              Default: 10000 (10 seconds)
 *
 * @return ESP_OK on success
 *         ESP_ERR_INVALID_ARG if led_pin is invalid
 *         ESP_ERR_NO_MEM if memory allocation fails
 *         ESP_FAIL on other errors (logged)
 */
esp_err_t wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms);

/**
 * Report that BUTTON2 was held for 5 seconds
 *
 * Called from process_buttons() in main_task when user holds
 * BUTTON2 for 5+ seconds to enter setup mode.
 *
 * IMPORTANT: This function triggers esp_restart() internally.
 * Code after calling this function will NOT execute.
 *
 * The device will reboot and enter AP mode on next boot,
 * broadcasting the provisioning access point.
 */
void wifi_provisioning_setup_button_pressed(void);

/**
 * Process WiFi provisioning state machine
 *
 * Call from main loop (main_task) every ~10ms.
 * Handles:
 * - LED blinking during AP mode (1 second interval)
 * - State-specific processing
 * - Connection monitoring
 *
 * Low CPU cost: mostly flag checks, minimal WiFi operations.
 * Non-blocking: returns immediately.
 */
void wifi_provisioning_process(void);

/**
 * Get current WiFi provisioning state
 *
 * Useful for main application to decide behavior based on
 * WiFi connectivity status.
 *
 * @return Current state from wifi_state_t enum
 */
wifi_state_t wifi_provisioning_get_state(void);

/**
 * Check if device is ready for normal operation
 *
 * Returns true when either:
 * - WiFi is connected (WIFI_STATE_CONNECTED)
 * - Running in offline mode (WIFI_STATE_OFFLINE)
 *
 * Use this to gate RFID initialization - wait until ready
 * before starting main application functionality.
 *
 * @return true if device is ready for RFID operation
 *         false if still in provisioning/connecting state
 */
bool wifi_provisioning_is_ready(void);

/**
 * Get human-readable state description
 *
 * Useful for logging and debugging state transitions.
 *
 * @param state State value from wifi_state_t
 * @return String like "CONNECTED", "OFFLINE", "AP_ACTIVE", etc.
 *         Never returns NULL.
 */
const char *wifi_provisioning_state_to_string(wifi_state_t state);

/**
 * Set connection test result (called from HTTP server)
 *
 * After user submits credentials via HTTP form, the provisioning
 * system tests the WiFi connection. This function reports the
 * result back to the state machine.
 *
 * @param success true if WiFi connection succeeded
 * @param error_message Human-readable error if success=false
 *                      Pass NULL on success
 *                      String is copied internally
 */
void wifi_provisioning_set_connection_result(bool success, const char *error_message);

/**
 * Submit credentials for connection test (called from HTTP server)
 *
 * After user fills the provisioning form, HTTP server calls this
 * to provide the SSID and password for testing.
 *
 * @param ssid WiFi network name (null-terminated, max 31 chars)
 * @param password WiFi password (null-terminated, 8-63 chars)
 *
 * @return ESP_OK if credentials accepted for testing
 *         ESP_ERR_INVALID_ARG if validation fails
 *         ESP_ERR_INVALID_STATE if not in AP_ACTIVE state
 */
esp_err_t wifi_provisioning_submit_credentials(const char *ssid, const char *password);

/**
 * Get pending error message from connection test
 *
 * If connection test failed, returns the error message.
 * Useful for HTTP server to display error to user.
 *
 * @return Error message string, or NULL if no error
 */
const char *wifi_provisioning_get_error_message(void);

/**
 * Trigger device restart
 *
 * Called from HTTP server when user clicks "Restart" button
 * after successful configuration.
 *
 * IMPORTANT: This function triggers esp_restart() internally.
 * Code after calling this function will NOT execute.
 */
void wifi_provisioning_restart_device(void);

#endif // WIFI_PROVISIONING_H
