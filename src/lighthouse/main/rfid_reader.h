/**
 * rfid_reader.h - R300/Y300 UHF RFID Reader Interface
 *
 * Implements R300 protocol V2.2 for attendance detection system.
 * Version: 1.2 - Added power and frequency configuration
 *
 * Key Commands Implemented:
 *   - 0x70: Reset module
 *   - 0x72: Get firmware version
 *   - 0x76: Set output power (NEW)
 *   - 0x78: Set frequency region (NEW)
 *   - 0x7A: Set beeper mode (NEW)
 *   - 0x8B: Single inventory (polling-based tag detection)
 *   - 0x89: Real-time inventory (deprecated - not used)
 *
 * Protocol Reference: R300_UHF_RFID_reader_module_protocol_.pdf
 *   - Section 1.2: Data Packet Definition
 *   - Section 2.1.1: Reset Command (page 7)
 *   - Section 2.1.3: Get Firmware (page 8)
 *   - Section 2.1.7: Set Output Power (page 12)
 *   - Section 2.1.9: Set Frequency Region (page 13)
 *   - Section 2.1.11: Set Beeper Mode (page 14-15)
 *   - Section 2.2.6: Single Inventory (command 0x8B)
 *
 * Hardware Reference: ESP32 Technical Reference Manual
 *   - Section 7.8: UART Controller
 *   - UART2 on GPIO16/17 (safe pins, no conflicts)
 */

#ifndef RFID_READER_H
#define RFID_READER_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// HARDWARE CONFIGURATION
// ============================================================================

#define RFID_UART_PORT   UART_NUM_2
#define RFID_UART_TX_PIN 17     // ESP32 TX → Y300 RX
#define RFID_UART_RX_PIN 16     // ESP32 RX → Y300 TX
#define RFID_UART_BAUD   115200 // R300 default (section 1.1)

// Power control and sensing pins
// GPIO2 was previously used but is a strapping pin that blocks firmware flashing
// Migrated to GPIO22 (sensing) and GPIO5 (control) per tasks/reader_power_task.md
// GPIO18 freed for SCANNING_LED per tasks/io_improvement_task.md
#define RFID_POWER_CONTROL_PIN      GPIO_NUM_5  // S9013 NPN transistor base (HIGH = reader ON)
#define RFID_POWER_SENSE_PIN        GPIO_NUM_18 // 3.3V rail feedback from reader power supply
#define RFID_POWER_STABILIZATION_MS 100         // Delay after power ON for reader stabilization

// ============================================================================
// FREQUENCY REGIONS (section 2.1.9, page 13)
// ============================================================================

#define RFID_REGION_FCC  0x01 // 902-928 MHz (USA) - best range
#define RFID_REGION_ETSI 0x02 // 865-868 MHz (Europe)
#define RFID_REGION_CHN  0x03 // 920-925 MHz (China)

// Frequency parameter values (see page 41 for full table)
#define RFID_FREQ_902MHZ 0x07
#define RFID_FREQ_915MHZ 0x21
#define RFID_FREQ_928MHZ 0x3B

// ============================================================================
// BEEPER MODES (Protocol V2.2, Section 2.1.11, page 14-15)
// ============================================================================

// Command byte for set beeper mode (cmd_name_set_beeper_mode)
#define R300_CMD_SET_BEEPER_MODE 0x7A

// Mode values persisted to internal flash on success (Section 2.1.11)
#define R300_BEEPER_MODE_QUIET     0x00 // Silent — no beep on any event
#define R300_BEEPER_MODE_PER_ROUND 0x01 // Beep once per inventory round
#define R300_BEEPER_MODE_PER_TAG   0x02 // Beep per tag (degrades anti-collision — do not use)

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * Reader State Machine
 * Tracks reader communication health and readiness
 */
typedef enum
{
    RFID_STATE_UNINITIALIZED,   // Not initialized yet
    RFID_STATE_POWERED_OFF,     // Powered off or disconnected
    RFID_STATE_STARTUP_PENDING, // Powering up, handshake pending
    RFID_STATE_SCANNING,        // Rail confirmed, inventory running, no handshake yet
    RFID_STATE_RESPONSIVE,      // Communication verified by handshake (periodic health check only)
    RFID_STATE_UNRESPONSIVE     // Communication failed
} rfid_reader_state_t;

/**
 * Reader Health Metrics
 * Used for diagnostics and MQTT health reporting
 */
typedef struct
{
    uint32_t  last_check_ms;      // Timestamp of last health check
    uint8_t   fw_major;           // Firmware major version
    uint8_t   fw_minor;           // Firmware minor version
    esp_err_t last_error;         // Last error code from handshake
    bool      is_responsive;      // True if reader is responsive
    bool      power_rail_present; // True if 3.3V power rail is present
} rfid_health_t;

/**
 * RFID Tag Detection Event
 *
 * Per section 2.2.8 (Real-Time Inventory Response):
 * [Head][Len][Address][Cmd][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]
 */
typedef struct
{
    uint8_t  pc[2];        // Protocol Control (2 bytes)
    uint8_t  epc[32];      // EPC tag ID (variable, max 32 bytes)
    uint8_t  epc_len;      // Actual EPC length
    uint8_t  rssi;         // Signal strength
    uint8_t  antenna_id;   // Antenna that detected (0-3)
    uint8_t  frequency;    // RF frequency parameter
    uint32_t timestamp_ms; // When detected (milliseconds)
} rfid_tag_event_t;

/**
 * Reader Statistics
 */
typedef struct
{
    uint32_t tags_detected;    // Unique tags seen
    uint32_t total_reads;      // Total detection events
    uint32_t errors;           // Communication errors
    bool     inventory_active; // Currently scanning
} rfid_stats_t;

/**
 * Tag Detection Callback
 *
 * Called from UART task whenever a tag is detected.
 * Keep processing minimal - log tag and return quickly.
 */
typedef void (*rfid_tag_callback_t)(const rfid_tag_event_t *event);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize RFID reader
 *
 * Sets up UART2, configures pins, starts background task.
 * Reader power control pin is initialized LOW (reader OFF).
 *
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_init(void);

/**
 * Power ON the RFID reader
 *
 * Sets GPIO5 HIGH to enable the S9013 transistor, powering the reader.
 * Includes stabilization delay for reader power-up.
 * Call this before any RFID scanning/reading operations.
 *
 * Per YR300 datasheet: Operating current 300-380mA
 *
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_power_on(void);

/**
 * Power OFF the RFID reader
 *
 * Sets GPIO5 LOW to disable the S9013 transistor, cutting reader power.
 * Reader enters sleep mode (<100µA per YR300 datasheet).
 * Call after RFID operations complete to conserve power.
 *
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_power_off(void);

/**
 * Check if reader power is currently enabled
 *
 * @return true if power control GPIO is HIGH (reader powered)
 */
bool rfid_reader_is_powered(void);

/**
 * Deinitialize and cleanup
 */
void rfid_reader_deinit(void);

/**
 * Reset the reader module
 *
 * Sends 0x70 reset command. Module will beep and restart.
 * Wait ~2 seconds after calling before using other commands.
 *
 * Per section 2.1.1, page 7.
 *
 * @return ESP_OK if command sent successfully
 */
esp_err_t rfid_reader_reset(void);

/**
 * Perform handshake with reader
 *
 * Verifies reader communication using get_firmware_version (0x72).
 * Should be called at startup, power-on events, and during health checks.
 * Updates reader state to RESPONSIVE or UNRESPONSIVE based on result.
 *
 * @param major Output: firmware major version (optional, can be NULL)
 * @param minor Output: firmware minor version (optional, can be NULL)
 * @return ESP_OK if reader is responsive, ESP_ERR_TIMEOUT if unresponsive
 */
esp_err_t rfid_reader_handshake(uint8_t *major, uint8_t *minor);

/**
 * Get current reader state
 *
 * @return Current state from state machine
 */
rfid_reader_state_t rfid_reader_get_state(void);

/**
 * Get reader health metrics
 *
 * Retrieves health information for diagnostics and MQTT reporting.
 *
 * @param health Output: health metrics structure
 * @return ESP_OK on success, ESP_ERR_INVALID_ARG if health is NULL
 */
esp_err_t rfid_reader_get_health(rfid_health_t *health);

/**
 * Get firmware version
 *
 * Queries reader firmware version (command 0x72).
 * Useful for verifying communication is working.
 *
 * Per section 2.1.3, page 8.
 *
 * @param major Output: major version number
 * @param minor Output: minor version number
 * @return ESP_OK on success, ESP_ERR_TIMEOUT if no response
 */
esp_err_t rfid_reader_get_firmware(uint8_t *major, uint8_t *minor);

/**
 * Set reader buzzer mode
 *
 * Configures when the module beeps. The value is stored to internal flash
 * and persists across power cycles (Protocol V2.2, Section 2.1.11, page 14-15).
 *
 * Use R300_BEEPER_MODE_QUIET (0x00) at startup to suppress buzzing during
 * normal inventory operation. R300_BEEPER_MODE_PER_TAG (0x02) degrades
 * anti-collision performance and must not be used.
 *
 * @param mode R300_BEEPER_MODE_QUIET, R300_BEEPER_MODE_PER_ROUND, or R300_BEEPER_MODE_PER_TAG
 * @return ESP_OK on success, ESP_ERR_TIMEOUT if no valid response received
 */
esp_err_t rfid_reader_set_beeper_mode(uint8_t mode);

/**
 * Set RF output power
 *
 * Configure transmit power for maximum range.
 * Valid range: 20-33 dBm (will be clamped if out of range)
 *
 * Per section 2.1.7, page 12.
 *
 * @param power_dbm Power level in dBm (20-33)
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_set_power(uint8_t power_dbm);

/**
 * Set frequency region
 *
 * Configure RF spectrum for your region.
 *
 * Per section 2.1.9, page 13.
 * Frequency table on page 41.
 *
 * @param region RFID_REGION_FCC, RFID_REGION_ETSI, or RFID_REGION_CHN
 * @param start_freq Starting frequency parameter (see page 41)
 * @param end_freq Ending frequency parameter (see page 41)
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_set_frequency_region(uint8_t region, uint8_t start_freq, uint8_t end_freq);

/**
 * Start polling-based inventory (command-based tag detection)
 *
 * Sends 0x8B command at a configurable interval to poll for tags.
 * Callback will be invoked for each tag detection.
 * Interval defaults to 250ms but can be configured.
 *
 * This is the PRIMARY MODE for attendance tracking.
 *
 * Per section 2.2.6:
 * - Single inventory command per poll
 * - Tag data retrieved after each read operation
 * - Continues until rfid_reader_stop_inventory() called
 *
 * @param callback Function to call when tag detected
 * @param interval_ms Polling interval in milliseconds (default: 250ms, min: 50ms)
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback, uint32_t interval_ms);

/**
 * Stop inventory mode
 *
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_stop_inventory(void);

/**
 * Check if inventory is currently running
 *
 * @return true if actively scanning for tags
 */
bool rfid_reader_is_inventory_active(void);

/**
 * Get current statistics
 *
 * @param stats Output: current reader statistics
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_get_stats(rfid_stats_t *stats);

/**
 * Clear statistics counters
 */
void rfid_reader_clear_stats(void);

#endif // RFID_READER_H
