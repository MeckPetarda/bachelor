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

/**
 * Get human-readable error description
 *
 * @param err Error code from previous operation
 * @return String description (never NULL, always valid C string)
 */
const char *settings_storage_error_to_string(settings_storage_error_t err);

#endif // SETTINGS_STORAGE_H
