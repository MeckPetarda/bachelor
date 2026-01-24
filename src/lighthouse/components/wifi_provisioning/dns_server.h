/**
 * @file dns_server.h
 * @brief DNS Server for Captive Portal Detection
 *
 * This module implements a simple DNS server that responds to ALL DNS queries
 * with the AP's IP address (192.168.4.1). This enables captive portal detection
 * on mobile devices and computers, causing them to automatically open a browser
 * to the WiFi provisioning page.
 *
 * How it works:
 * - DNS server listens on UDP port 53
 * - When a device connects to the AP and tries to resolve any domain name
 *   (e.g., captive.apple.com, connectivitycheck.gstatic.com), this server
 *   responds with 192.168.4.1
 * - The device's OS detects that all DNS queries resolve to the same IP
 *   and triggers the captive portal UI (automatic browser popup)
 *
 * Lifecycle:
 * - Start when entering AP_ACTIVE state (after HTTP server starts)
 * - Stop when exiting AP_ACTIVE state (transitioning to CONNECTING/CONNECTED)
 *
 * @note This DNS server is only active during WiFi provisioning mode.
 *       Normal DNS resolution is not affected once the device is connected
 *       to a real WiFi network.
 */

#ifndef DNS_SERVER_H
#define DNS_SERVER_H

#include "esp_err.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Start the DNS server for captive portal detection
 *
 * Creates a UDP socket listening on port 53 and starts a FreeRTOS task
 * to handle incoming DNS queries. All DNS queries will be responded to
 * with the AP's IP address (192.168.4.1), enabling captive portal detection.
 *
 * @return
 *     - ESP_OK: DNS server started successfully
 *     - ESP_FAIL: Failed to create socket or start task
 *     - ESP_ERR_INVALID_STATE: DNS server already running
 */
esp_err_t dns_server_start(void);

/**
 * @brief Stop the DNS server
 *
 * Closes the UDP socket and terminates the DNS handler task.
 * Safe to call multiple times (idempotent).
 *
 * @return
 *     - ESP_OK: DNS server stopped successfully
 *     - ESP_ERR_INVALID_STATE: DNS server was not running
 */
esp_err_t dns_server_stop(void);

/**
 * @brief Check if the DNS server is currently running
 *
 * @return
 *     - true: DNS server is running and handling queries
 *     - false: DNS server is not running
 */
bool dns_server_is_running(void);

#ifdef __cplusplus
}
#endif

#endif /* DNS_SERVER_H */
