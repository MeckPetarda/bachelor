/**
 * uart_reader.h - R300/Y300 UHF RFID Reader Interface
 * 
 * Implements R300 protocol V2.2 for attendance detection system.
 * Version: 1.2 - Added power and frequency configuration
 * 
 * Key Commands Implemented:
 *   - 0x70: Reset module
 *   - 0x72: Get firmware version
 *   - 0x76: Set output power (NEW)
 *   - 0x78: Set frequency region (NEW)
 *   - 0x89: Real-time inventory (continuous tag detection)
 * 
 * Protocol Reference: R300_UHF_RFID_reader_module_protocol_.pdf
 *   - Section 1.2: Data Packet Definition
 *   - Section 2.1.1: Reset Command (page 7)
 *   - Section 2.1.3: Get Firmware (page 8)
 *   - Section 2.1.7: Set Output Power (page 12)
 *   - Section 2.1.9: Set Frequency Region (page 13)
 *   - Section 2.2.8: Real-Time Inventory (page 27-28)
 * 
 * Hardware Reference: ESP32 Technical Reference Manual
 *   - Section 7.8: UART Controller
 *   - UART2 on GPIO16/17 (safe pins, no conflicts)
 */

#ifndef UART_READER_H
#define UART_READER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

// ============================================================================
// HARDWARE CONFIGURATION
// ============================================================================

#define RFID_UART_PORT      UART_NUM_2
#define RFID_UART_TX_PIN    17          // ESP32 TX → Y300 RX
#define RFID_UART_RX_PIN    16          // ESP32 RX → Y300 TX  
#define RFID_UART_BAUD      115200      // R300 default (section 1.1)

// ============================================================================
// FREQUENCY REGIONS (section 2.1.9, page 13)
// ============================================================================

#define RFID_REGION_FCC     0x01        // 902-928 MHz (USA) - best range
#define RFID_REGION_ETSI    0x02        // 865-868 MHz (Europe)
#define RFID_REGION_CHN     0x03        // 920-925 MHz (China)

// Frequency parameter values (see page 41 for full table)
#define RFID_FREQ_902MHZ    0x07
#define RFID_FREQ_915MHZ    0x21
#define RFID_FREQ_928MHZ    0x3B

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * RFID Tag Detection Event
 * 
 * Per section 2.2.8 (Real-Time Inventory Response):
 * [Head][Len][Address][Cmd][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]
 */
typedef struct {
    uint8_t  pc[2];                     // Protocol Control (2 bytes)
    uint8_t  epc[32];                   // EPC tag ID (variable, max 32 bytes)
    uint8_t  epc_len;                   // Actual EPC length
    uint8_t  rssi;                      // Signal strength
    uint8_t  antenna_id;                // Antenna that detected (0-3)
    uint8_t  frequency;                 // RF frequency parameter
    uint32_t timestamp_ms;              // When detected (milliseconds)
} rfid_tag_event_t;

/**
 * Reader Statistics
 */
typedef struct {
    uint32_t tags_detected;             // Unique tags seen
    uint32_t total_reads;               // Total detection events
    uint32_t errors;                    // Communication errors
    bool     inventory_active;          // Currently scanning
} rfid_stats_t;

/**
 * Tag Detection Callback
 * 
 * Called from UART task whenever a tag is detected.
 * Keep processing minimal - log tag and return quickly.
 */
typedef void (*rfid_tag_callback_t)(const rfid_tag_event_t* event);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize RFID reader
 * 
 * Sets up UART2, configures pins, starts background task.
 * 
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_init(void);

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
esp_err_t rfid_reader_get_firmware(uint8_t* major, uint8_t* minor);

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
 * Start real-time inventory (continuous tag detection)
 * 
 * Sends 0x89 command to start continuous tag scanning.
 * Callback will be invoked for each tag detection.
 * Automatically restarts after each inventory round completes.
 * 
 * This is the PRIMARY MODE for attendance tracking.
 * 
 * Per section 2.2.8, page 27-28:
 * - Tag data is transferred in real-time (not buffered)
 * - Includes RSSI and frequency data
 * - Continues until rfid_reader_stop_inventory() called
 * 
 * @param callback Function to call when tag detected
 * @return ESP_OK on success
 */
esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback);

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
esp_err_t rfid_reader_get_stats(rfid_stats_t* stats);

/**
 * Clear statistics counters
 */
void rfid_reader_clear_stats(void);

#endif // UART_READER_H
