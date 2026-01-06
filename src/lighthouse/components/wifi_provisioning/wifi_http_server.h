/**
 * wifi_http_server.h - WiFi Provisioning HTTP Server
 *
 * Provides:
 * - HTTP server on port 80
 * - GET "/" - provisioning webpage
 * - POST "/configure" - credential submission
 * - GET "/restart" - device restart
 *
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.3
 */

#ifndef WIFI_HTTP_SERVER_H
#define WIFI_HTTP_SERVER_H

#include "esp_err.h"
#include <stdbool.h>

// ============================================================================
// CALLBACK TYPE
// ============================================================================

/**
 * Callback when user submits provisioning form
 *
 * Called from HTTP handler when POST /configure received with valid data.
 * Receives SSID and password to test/save.
 *
 * Implementation should:
 * - Store credentials in provisioning state
 * - Trigger WiFi connection attempt
 * - Call wifi_http_server_set_connection_result() after test completes
 *
 * @param ssid WiFi network name (null-terminated)
 * @param password WiFi password (null-terminated)
 */
typedef void (*wifi_credentials_callback_t)(const char *ssid, const char *password);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Start HTTP server in AP mode
 *
 * Call only when in AP_ACTIVE state (after WiFi AP is broadcasting).
 *
 * Registers URI handlers for:
 * - GET "/" -> Returns provisioning webpage HTML
 * - POST "/configure" -> Handles form submission
 * - GET "/restart" -> Restarts device
 *
 * @param ap_ssid Access point SSID (displayed on webpage, informational)
 * @param ap_password Access point password (not displayed)
 * @return ESP_OK on success
 *         ESP_ERR_HTTPD_ALLOC_MEM if memory allocation fails
 *         ESP_FAIL if server already running or other error
 */
esp_err_t wifi_http_server_start(const char *ap_ssid, const char *ap_password);

/**
 * Stop HTTP server
 *
 * Safe to call even if not running.
 *
 * @return ESP_OK on success
 */
esp_err_t wifi_http_server_stop(void);

/**
 * Register callback for credential submission
 *
 * MUST be called BEFORE wifi_http_server_start().
 *
 * When user submits form with SSID/password, this callback is invoked.
 * Callback should test WiFi connection and call wifi_http_server_set_connection_result()
 * to notify webpage of success/failure.
 *
 * @param callback Function to invoke on form submission (can be NULL to clear)
 */
void wifi_http_server_set_credentials_callback(wifi_credentials_callback_t callback);

/**
 * Report WiFi connection test result to webpage
 *
 * Called after credentials callback tests WiFi connection.
 * Updates internal state so POST handler can return result to browser.
 *
 * @param success true if connection succeeded
 * @param error_message Error description if success=false (can be NULL for success)
 *                      String is copied internally (max 127 chars)
 */
void wifi_http_server_set_connection_result(bool success, const char *error_message);

/**
 * Check if connection result is available
 *
 * Used by POST handler to determine if it should wait or return result.
 *
 * @return true if connection result has been set
 */
bool wifi_http_server_is_result_ready(void);

/**
 * Get connection result success status
 *
 * @return true if last connection test succeeded
 */
bool wifi_http_server_get_result_success(void);

/**
 * Get connection error message
 *
 * @return Error message string, or NULL if success or no error set
 */
const char *wifi_http_server_get_result_error(void);

/**
 * Clear connection result (reset for next attempt)
 *
 * Call before starting new connection test.
 */
void wifi_http_server_clear_result(void);

/**
 * Check if HTTP server is running
 *
 * @return true if server is active
 */
bool wifi_http_server_is_running(void);

#endif // WIFI_HTTP_SERVER_H
