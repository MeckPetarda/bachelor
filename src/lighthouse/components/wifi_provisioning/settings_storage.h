/**
 * settings_storage.h - WiFi Credential Storage Interface
 *
 * Manages encrypted storage of WiFi credentials in NVS partition.
 * Credentials are decrypted only in RAM during use.
 *
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.1
 */

#ifndef SETTINGS_STORAGE_H
#define SETTINGS_STORAGE_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// ERROR CODES
// ============================================================================

typedef enum
{
    SETTINGS_STORAGE_OK               = 0,
    SETTINGS_STORAGE_NOT_FOUND        = 1,
    SETTINGS_STORAGE_CORRUPT          = 2,
    SETTINGS_STORAGE_ENCRYPTION_ERROR = 3,
    SETTINGS_STORAGE_WRITE_ERROR      = 4,
    SETTINGS_STORAGE_INVALID_PARAM    = 5,
} settings_storage_error_t;

// ============================================================================
// CONFIGURATION DEFAULTS
// ============================================================================

#define MQTT_DEFAULT_BROKER_IP     "192.168.1.1"
#define MQTT_DEFAULT_BROKER_PORT   1883
#define MQTT_DEFAULT_SCAN_BATCH_MS 150

#define MQTT_BROKER_IP_MAX_LEN 15 // "255.255.255.255"

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * WiFi Credentials (RAM only, never persisted in plaintext)
 */
typedef struct
{
    char    ssid[32];     // Network name (null-terminated)
    char    password[64]; // Network password (null-terminated)
    uint8_t configured;   // Flag from partition (0=no, 1=yes)
} wifi_credentials_t;

/**
 * MQTT Broker Configuration
 */
typedef struct
{
    char     broker_ip[16]; // IPv4 address (null-terminated)
    uint16_t broker_port;   // Port number (1-65535)
} mqtt_broker_config_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize WiFi settings storage system
 *
 * Opens nvs_settings partition, validates structure.
 * Safe to call multiple times.
 *
 * @return SETTINGS_STORAGE_OK on success
 *         SETTINGS_STORAGE_NOT_FOUND if partition missing
 */
settings_storage_error_t settings_storage_init(void);

/**
 * Check if device has been configured for WiFi
 *
 * Reads "configured" flag from NVS without decryption.
 * Fast, zero-copy operation.
 *
 * @return true if credentials have been saved, false otherwise
 */
bool wifi_settings_is_configured(void);

/**
 * Check if MQTT settings have been configured
 *
 * @return true if MQTT settings exist in NVS, false otherwise
 */
bool mqtt_settings_is_configured(void);

/**
 * Load WiFi credentials from partition
 *
 * Decrypts stored SSID and password from NVS partition.
 * Only call if wifi_settings_is_configured() returns true.
 *
 * Credentials stored in provided structure (RAM only).
 * Structure is NOT modified if function fails.
 *
 * @param creds Output: decrypted credentials (must not be NULL)
 * @return SETTINGS_STORAGE_OK on success
 *         SETTINGS_STORAGE_NOT_FOUND if not yet configured
 *         SETTINGS_STORAGE_ENCRYPTION_ERROR if decryption fails
 */
settings_storage_error_t wifi_settings_load(wifi_credentials_t *creds);

/**
 * Save WiFi credentials to partition
 *
 * Encrypts and stores SSID and password to NVS.
 * Sets "configured" flag to 1.
 *
 * IMPORTANT: After calling this function successfully,
 * caller MUST trigger esp_restart() to reload partition.
 * Code after this call will execute but partition won't be
 * used until reboot.
 *
 * Validation:
 * - SSID: non-empty, max 31 chars (32 with null terminator)
 * - Password: 8-63 chars (WPA2 requirement)
 *
 * @param ssid WiFi network name (null-terminated)
 * @param password WiFi password (null-terminated)
 * @return SETTINGS_STORAGE_OK on success
 *         SETTINGS_STORAGE_INVALID_PARAM if validation fails
 *         SETTINGS_STORAGE_WRITE_ERROR if write to NVS fails
 */
settings_storage_error_t wifi_settings_save(const char *ssid, const char *password);

/**
 * Factory reset - clear all WiFi configuration
 *
 * Erases encrypted credentials and sets "configured" flag to 0.
 * Device will return to unconfigured state on next boot.
 *
 * IMPORTANT: After calling this function successfully,
 * caller MUST trigger esp_restart() for changes to take effect.
 *
 * @return SETTINGS_STORAGE_OK on success
 *         SETTINGS_STORAGE_WRITE_ERROR if erase fails
 */
settings_storage_error_t wifi_settings_factory_reset(void);

/*
 * Load MQTT broker configuration from NVS
 *
 * Reads broker IP and port from NVS partition.
 * If keys don't exist, returns default values.
 *
 * @param config Output: broker configuration (must not be NULL)
 * @return MQTT_STORAGE_OK on success
 *         MQTT_STORAGE_INVALID_PARAM if config is NULL
 */
settings_storage_error_t mqtt_settings_load(mqtt_broker_config_t *config);

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
settings_storage_error_t mqtt_settings_save(const char *broker_ip, uint16_t broker_port);

/**
 * Load scan batch interval from NVS
 *
 * Reads the batch interval in milliseconds. If the key doesn't exist,
 * returns MQTT_DEFAULT_SCAN_BATCH_MS. Values are clamped to 50-2000ms.
 *
 * @param batch_ms Output: batch interval in milliseconds (must not be NULL)
 * @return SETTINGS_STORAGE_OK on success
 */
settings_storage_error_t scan_batch_settings_load(uint32_t *batch_ms);

/**
 * Save scan batch interval to NVS
 *
 * @param batch_ms Batch interval in milliseconds (must be 50-2000)
 * @return SETTINGS_STORAGE_OK on success
 *         SETTINGS_STORAGE_INVALID_PARAM if out of range
 *         SETTINGS_STORAGE_WRITE_ERROR if write fails
 */
settings_storage_error_t scan_batch_settings_save(uint32_t batch_ms);

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
 * @return String description (never NULL, always valid C string)
 */
const char *settings_storage_error_to_string(settings_storage_error_t err);

#endif // SETTINGS_STORAGE_H
