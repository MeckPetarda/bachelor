/**
 * WiFi Manager - ESP32 WiFi Station Mode Manager
 *
 * Provides WiFi connectivity management for the ESP32 attendance system.
 * Handles connection, disconnection, and reconnection logic.
 *
 * DATASHEET REFERENCES:
 * - ESP32 Datasheet v5.2: Section 3.2.1 (Wi-Fi Features)
 * - ESP-IDF v5.5.1 Wi-Fi Driver Guide
 */

#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "esp_err.h"
#include "esp_netif.h"
#include <stdbool.h>

// ============================================================================
// CONFIGURATION
// ============================================================================

/**
 * WiFi credentials configured via menuconfig (idf.py menuconfig)
 * See main/Kconfig.projbuild for configuration options
 *
 * To configure for production:
 *   1. Run: idf.py menuconfig
 *   2. Navigate to: WiFi Configuration
 *   3. Set SSID and password
 *   4. Save and exit
 *   5. Build: idf.py build
 *
 * Credentials are stored encrypted in flash and not visible in logs.
 */
#define WIFI_SSID               CONFIG_WIFI_SSID
#define WIFI_PASSWORD           CONFIG_WIFI_PASSWORD
#define WIFI_MAX_RETRY_ATTEMPTS CONFIG_WIFI_MAXIMUM_RETRY

// ============================================================================
// EVENT BITS (FreeRTOS Event Groups)
// ============================================================================

/**
 * Event bit indicating successful WiFi connection
 */
#define WIFI_CONNECTED_BIT BIT0

/**
 * Event bit indicating WiFi connection failure
 */
#define WIFI_FAIL_BIT BIT1

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize WiFi in Station (STA) mode
 *
 * Performs the following initialization sequence:
 * 1. Initialize NVS flash
 * 2. Initialize TCP/IP stack (lwIP + ESP-NETIF)
 * 3. Create default event loop
 * 4. Initialize WiFi driver
 * 5. Register event handlers
 * 6. Configure WiFi credentials
 * 7. Start WiFi driver
 *
 * @return ESP_OK on success, error code otherwise
 *
 * CRITICAL NOTES (per ESP-IDF docs):
 * - Must call nvs_flash_init() before any WiFi operations
 * - Event loop must be created before WiFi start
 * - Event handlers should not block (use queues for processing)
 */
esp_err_t wifi_manager_init(void);

/**
 * Connect to configured WiFi access point
 *
 * Initiates connection to the AP specified in WIFI_SSID.
 * This function is non-blocking - use wifi_manager_wait_for_connection()
 * to wait for connection completion.
 *
 * @return ESP_OK on success, error code otherwise
 *
 * DATASHEET REFERENCE:
 * - ESP32 supports 802.11 b/g/n @ 2.4 GHz (Datasheet Section 3.2.1)
 * - Maximum throughput: 150 Mbps
 */
esp_err_t wifi_manager_connect(void);

/**
 * Wait for WiFi connection to complete
 *
 * Blocks until one of the following occurs:
 * - WiFi successfully connects and obtains IP address (returns ESP_OK)
 * - Connection fails after max retry attempts (returns ESP_FAIL)
 *
 * @param timeout_ms Maximum time to wait in milliseconds (0 = wait forever)
 * @return ESP_OK if connected, ESP_FAIL if connection failed
 */
esp_err_t wifi_manager_wait_for_connection(uint32_t timeout_ms);

/**
 * Check if WiFi is currently connected
 *
 * @return true if connected and has IP address, false otherwise
 */
bool wifi_manager_is_connected(void);

/**
 * Disconnect from WiFi access point
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t wifi_manager_disconnect(void);

/**
 * Get current IP address
 *
 * @param ip_info Pointer to structure to receive IP information
 * @return ESP_OK on success, ESP_FAIL if not connected
 */
esp_err_t wifi_manager_get_ip_info(esp_netif_ip_info_t *ip_info);

/**
 * Get WiFi RSSI (signal strength)
 *
 * @param rssi Pointer to receive RSSI value in dBm
 * @return ESP_OK on success, error code otherwise
 *
 * Typical RSSI values:
 * - Excellent: -30 to -50 dBm
 * - Good: -50 to -60 dBm
 * - Fair: -60 to -70 dBm
 * - Poor: -70 dBm and below
 */
esp_err_t wifi_manager_get_rssi(int8_t *rssi);

#endif // WIFI_MANAGER_H
