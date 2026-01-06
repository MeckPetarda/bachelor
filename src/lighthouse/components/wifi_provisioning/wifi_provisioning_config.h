/**
 * wifi_provisioning_config.h - Configuration Constants
 *
 * Device-specific settings for WiFi provisioning.
 * Customize these values for each device build.
 *
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 3.3
 */

#ifndef WIFI_PROVISIONING_CONFIG_H
#define WIFI_PROVISIONING_CONFIG_H

// ============================================================================
// PROVISIONING AP CREDENTIALS (compile-time, device-specific)
// ============================================================================

/**
 * SSID for setup mode access point
 * Should be unique per device to avoid confusion when setting up multiple units
 * Max 31 characters
 * Example: "LIGHTHOUSE_SETUP_001"
 */
#define WIFI_SETUP_AP_SSID "LIGHTHOUSE_SETUP"

/**
 * Password for setup mode access point
 * Min 8 characters, max 63 characters (WPA2 requirement)
 * Should be unique per device (print on device or manual)
 * Example: "setup_key_001"
 */
#define WIFI_SETUP_AP_PASSWORD "lighthouse123"

/**
 * Maximum number of simultaneous connections to AP
 * Keep low to conserve resources (typically only one phone connects)
 */
#define WIFI_SETUP_AP_MAX_CONN 2

/**
 * WiFi channel for AP mode (1-13)
 * Using a fixed channel avoids scanning delay
 */
#define WIFI_SETUP_AP_CHANNEL 6

// ============================================================================
// ENCRYPTION KEY (device-specific)
// ============================================================================

/**
 * AES-128 encryption key for credential storage
 * 16 bytes (128 bits)
 * Each device should have a unique key
 *
 * Current value is placeholder - replace with actual key during device provisioning
 * Future: Generate per device during firmware build process
 */
#define WIFI_ENCRYPTION_KEY                                                                                            \
    {0x4C, 0x69, 0x67, 0x68, 0x74, 0x68, 0x6F, 0x75, 0x73, 0x65, 0x4B, 0x65, 0x79, 0x31, 0x32, 0x33}

// ============================================================================
// OPERATIONAL PARAMETERS
// ============================================================================

/**
 * WiFi connection timeout during provisioning (milliseconds)
 * How long to wait for device to connect to test network
 * Default: 10000 (10 seconds)
 * Reasonable range: 5000-15000
 */
#define WIFI_CONNECT_TIMEOUT_MS 10000

/**
 * LED blink interval during setup mode (milliseconds)
 * Period for LED on/off cycle
 * Default: 1000 (1 second total: 500ms on, 500ms off)
 */
#define WIFI_LED_SETUP_BLINK_MS 1000

/**
 * Polling interval for WiFi connection status (milliseconds)
 * How often to check if WiFi connection succeeded
 */
#define WIFI_CONNECT_POLL_INTERVAL_MS 200

/**
 * Default IP address for AP mode
 * This is the address users connect to for the provisioning webpage
 */
#define WIFI_AP_IP_ADDR "192.168.4.1"

#endif // WIFI_PROVISIONING_CONFIG_H
