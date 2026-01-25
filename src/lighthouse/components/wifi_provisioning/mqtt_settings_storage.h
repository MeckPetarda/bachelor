/**
 * mqtt_settings_storage.h - MQTT Broker Configuration Storage Interface
 *
 * Manages storage of MQTT broker settings in NVS partition.
 * Uses the same partition as WiFi credentials (nvs_settings).
 *
 * Reference: tasks/mqtt_setup.md
 */

#ifndef MQTT_SETTINGS_STORAGE_H
#define MQTT_SETTINGS_STORAGE_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// CONFIGURATION DEFAULTS
// ============================================================================

#define MQTT_DEFAULT_BROKER_IP   "192.168.1.1"
#define MQTT_DEFAULT_BROKER_PORT 1883

#define MQTT_BROKER_IP_MAX_LEN 15  // "255.255.255.255"

// ============================================================================
// ERROR CODES
// ============================================================================

typedef enum
{
    MQTT_STORAGE_OK            = 0,
    MQTT_STORAGE_NOT_FOUND     = 1,
    MQTT_STORAGE_WRITE_ERROR   = 2,
    MQTT_STORAGE_INVALID_PARAM = 3,
} mqtt_storage_error_t;

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * MQTT Broker Configuration
 */
typedef struct
{
    char     broker_ip[16];  // IPv4 address (null-terminated)
    uint16_t broker_port;    // Port number (1-65535)
} mqtt_broker_config_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize MQTT settings storage system
 *
 * Opens nvs_settings partition for MQTT configuration.
 * Initializes default values if keys don't exist.
 * Safe to call multiple times.
 *
 * @return MQTT_STORAGE_OK on success
 */
mqtt_storage_error_t mqtt_settings_init(void);

/**
 * Load MQTT broker configuration from NVS
 *
 * Reads broker IP and port from NVS partition.
 * If keys don't exist, returns default values.
 *
 * @param config Output: broker configuration (must not be NULL)
 * @return MQTT_STORAGE_OK on success
 *         MQTT_STORAGE_INVALID_PARAM if config is NULL
 */
mqtt_storage_error_t mqtt_settings_load(mqtt_broker_config_t *config);

/**
 * Save MQTT broker configuration to NVS
 *
 * Validates and stores broker IP and port to NVS.
 *
 * Validation:
 * - IP: Valid IPv4 format (uses inet_aton)
 * - Port: 1-65535 range
 *
 * @param broker_ip IPv4 address string (null-terminated)
 * @param broker_port Port number (1-65535)
 * @return MQTT_STORAGE_OK on success
 *         MQTT_STORAGE_INVALID_PARAM if validation fails
 *         MQTT_STORAGE_WRITE_ERROR if write to NVS fails
 */
mqtt_storage_error_t mqtt_settings_save(const char *broker_ip, uint16_t broker_port);

/**
 * Check if MQTT settings have been configured
 *
 * @return true if MQTT settings exist in NVS, false otherwise
 */
bool mqtt_settings_is_configured(void);

/**
 * Reset MQTT settings to defaults
 *
 * Erases stored MQTT configuration and writes default values.
 *
 * @return MQTT_STORAGE_OK on success
 */
mqtt_storage_error_t mqtt_settings_reset_to_defaults(void);

/**
 * Validate IPv4 address format
 *
 * @param ip IPv4 address string to validate
 * @return true if valid IPv4 format, false otherwise
 */
bool mqtt_settings_validate_ip(const char *ip);

/**
 * Validate port number
 *
 * @param port Port number to validate
 * @return true if port is in valid range (1-65535), false otherwise
 */
bool mqtt_settings_validate_port(uint16_t port);

/**
 * Get human-readable error description
 *
 * @param err Error code from previous operation
 * @return String description (never NULL)
 */
const char *mqtt_settings_error_to_string(mqtt_storage_error_t err);

#endif // MQTT_SETTINGS_STORAGE_H
