/**
 * UART RFID Reader Interface
 * 
 * Communication with Y300 UHF RFID Reader Module via UART
 * 
 * DATASHEET REFERENCES:
 * - ESP32 Technical Reference Manual, Section 7.8: UART Controller
 *   - UART0 (GPIO1/GPIO3): Reserved for JTAG/console
 *   - UART1 (GPIO9/GPIO10): Primary UART interface
 *   - UART2 (GPIO16/GPIO17): Secondary available UART
 *   - Table 7-2 Pin Mux: UART peripheral pin assignments
 *   - Section 7.8.1.2: UART Clock and Baud Rate Configuration
 * 
 * - Y300/R300 Communication Interface Specification:
 *   - Standard RS232/TTL serial interface
 *   - Frame format: 8 data bits, 1 stop bit, no parity (8N1)
 *   - Default baud rate: 9600 bps (configurable via 0x71 command)
 *   - Command format: Header + Command + Length + Data + CRC
 *   - Response includes tag EPC data when inventory/read commands executed
 */

#ifndef UART_READER_H
#define UART_READER_H

#include <stdint.h>
#include <stdbool.h>
#include "driver/uart.h"
#include "freertos/queue.h"

// ============================================================================
// UART PORT CONFIGURATION
// ============================================================================

#define RFID_UART_PORT      UART_NUM_1      // UART1 for RFID reader
#define RFID_UART_TX_PIN    GPIO_NUM_17      // GPIO9  - TXD1 per Table 7-2
#define RFID_UART_RX_PIN    GPIO_NUM_16     // GPIO10 - RXD1 per Table 7-2
#define RFID_UART_BAUD      9600            // Default Y300 baud rate

#define RFID_RX_BUF_SIZE    512             // DMA buffer for RX
#define RFID_TX_BUF_SIZE    256             // TX buffer (driver allocated)

// ============================================================================
// FRAME STRUCTURE AND PROTOCOL
// ============================================================================

// Y300 command frame structure (from R300 Communication Interface Spec):
// [Header(2)] [Command(1)] [Length(2)] [Data(N)] [CRC(2)]
// Header: Always 0xBB, 0xBB (frame sync)
// Command: 0x70-0x8E for various operations (inventory, read, write, etc.)
// Length: Big-endian 16-bit value indicating data field length
// Data: Command-specific payload
// CRC: CRC16 checksum (polynomial based on Y300 specification)

#define RFID_FRAME_HEADER_BYTE1 0xBB
#define RFID_FRAME_HEADER_BYTE2 0xBB
#define RFID_FRAME_MIN_LENGTH   7           // Min: 2 header + 1 cmd + 2 len + 2 crc

typedef enum {
    RFID_CMD_RESET                  = 0x70,
    RFID_CMD_SET_UART_BAUD          = 0x71,
    RFID_CMD_GET_FIRMWARE           = 0x72,
    RFID_CMD_SET_READER_ADDRESS     = 0x73,
    RFID_CMD_SET_WORK_ANTENNA       = 0x74,
    RFID_CMD_GET_WORK_ANTENNA       = 0x75,
    RFID_CMD_SET_OUTPUT_POWER       = 0x76,
    RFID_CMD_GET_OUTPUT_POWER       = 0x77,
    RFID_CMD_SET_FREQUENCY_REGION   = 0x78,
    RFID_CMD_GET_FREQUENCY_REGION   = 0x79,
    RFID_CMD_GET_BEEPER_MODE        = 0x7A,
    RFID_CMD_GET_TEMP               = 0x7B,
    RFID_CMD_READ_GPIO              = 0x60,
    RFID_CMD_WRITE_GPIO             = 0x61,
    RFID_CMD_INVENTORY              = 0x80,
    RFID_CMD_READ_TAG               = 0x81,
    RFID_CMD_WRITE_TAG              = 0x82,
    RFID_CMD_LOCK_TAG               = 0x83,
    RFID_CMD_KILL_TAG               = 0x84,
    RFID_CMD_REAL_TIME_INVENTORY    = 0x89,
    RFID_CMD_GET_INVENTORY_BUFFER   = 0x90,
    RFID_CMD_RESET_INVENTORY_BUFFER = 0x93,
} rfid_command_t;

typedef struct {
    uint8_t header1;                // Always 0xBB
    uint8_t header2;                // Always 0xBB
    uint8_t command;                // Command code
    uint8_t length_hi;              // Data length (big-endian)
    uint8_t length_lo;              // Data length (big-endian)
    uint8_t* data;                  // Dynamic data field
    uint16_t crc;                   // CRC16 checksum
} rfid_frame_t;

typedef struct {
    uint8_t* buffer;                // Circular buffer
    uint16_t size;                  // Buffer capacity
    uint16_t head;                  // Write pointer
    uint16_t tail;                  // Read pointer
    uint16_t count;                 // Bytes available
} rfid_rx_buffer_t;

// ============================================================================
// EVENT HANDLING
// ============================================================================

typedef enum {
    RFID_EVENT_TAG_READ,            // Tag successfully read
    RFID_EVENT_INVENTORY_COMPLETE,  // Inventory scan finished
    RFID_EVENT_ERROR_FRAME,         // Frame format/CRC error
    RFID_EVENT_ERROR_TIMEOUT,       // Response timeout
    RFID_EVENT_COMM_ERROR,          // UART communication error
} rfid_event_type_t;

typedef struct {
    rfid_event_type_t type;
    uint32_t timestamp;             // Milliseconds when event occurred
    uint8_t tag_epc[16];            // EPC data for tag reads (96-bit max)
    uint8_t epc_length;             // Actual EPC length
    uint8_t antenna_port;           // Which antenna detected tag
    int16_t rssi;                   // Signal strength (if available)
} rfid_event_t;

// ============================================================================
// INITIALIZATION AND CONTROL
// ============================================================================

/**
 * Initialize UART1 for RFID reader communication
 * 
 * Configures GPIO9/GPIO10, sets baud rate, enables FreeRTOS tasks for
 * background UART handling and event queue processing.
 * 
 * DATASHEET REFS:
 * - uart_driver_install: Section 7.8.1.3 Interrupt Handling
 * - uart_param_config: Baud rate calculation per Section 7.8.1.2
 * 
 * Returns:
 *   - ESP_OK if successful
 *   - Error code from esp_err_t if init fails
 */
esp_err_t uart_reader_init(void);

/**
 * Deinitialize UART reader and cleanup resources
 */
void uart_reader_deinit(void);

/**
 * Get the FreeRTOS queue for RFID events
 * 
 * Returns queue handle for uxQueueReceive() calls. Events are posted
 * whenever reader delivers tag data or encounters errors.
 */
QueueHandle_t uart_reader_get_event_queue(void);

// ============================================================================
// COMMAND TRANSMISSION
// ============================================================================

/**
 * Send raw command frame to RFID reader
 * 
 * Constructs frame with header, command, data, and CRC, then transmits
 * via UART1. Automatically waits for response within timeout period.
 * 
 * Args:
 *   cmd: Command code (e.g., RFID_CMD_INVENTORY)
 *   data: Payload bytes (can be NULL if no data)
 *   data_len: Payload length
 *   timeout_ms: Maximum time to wait for response
 * 
 * Returns:
 *   - Number of bytes received in response (0 if timeout)
 *   - Negative value on error
 */
int uart_reader_send_command(rfid_command_t cmd, const uint8_t* data, 
                              uint8_t data_len, uint32_t timeout_ms);

/**
 * Start inventory scan (tag detection)
 * 
 * Sends 0x80 or 0x89 (real-time inventory) command to detect and report
 * tags within RF range. For real-time mode, tags are posted to event
 * queue as they're detected; call uart_reader_stop_inventory() to stop.
 * 
 * Args:
 *   realtime: true=continuous stream, false=single scan
 */
esp_err_t uart_reader_start_inventory(bool realtime);

/**
 * Stop ongoing inventory/scan operation
 */
void uart_reader_stop_inventory(void);

/**
 * Get single response from reader (for non-event modes)
 */
int uart_reader_read_response(uint8_t* buffer, uint16_t max_len, 
                               uint32_t timeout_ms);

#endif // UART_READER_H
