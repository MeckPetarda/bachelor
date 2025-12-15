/**
 * UART RFID Reader Implementation
 * 
 * Handles low-level UART communication with Y300 reader module including
 * frame parsing, CRC validation, and event queue management.
 */

#include "uart_reader.h"
#include <string.h>
#include <stdlib.h>
#include "esp_log.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/gpio.h"
#include "driver/uart.h"

static const char* TAG = "UART_READER";

// ============================================================================
// GLOBAL STATE
// ============================================================================

static QueueHandle_t rfid_event_queue = NULL;
static rfid_rx_buffer_t rx_buffer = {0};
static bool reader_initialized = false;
static bool inventory_running = false;
static TaskHandle_t uart_task_handle = NULL;

// ============================================================================
// CRC CALCULATION
// ============================================================================

/**
 * Calculate CRC16 for Y300 frames
 * 
 * Polynomial: CRC-CCITT (0x1021)
 * Initial: 0xFFFF
 * Reflected input/output per Y300 specification
 */
static uint16_t crc16_ccitt(const uint8_t* data, uint16_t length)
{
    uint16_t crc = 0xFFFF;
    
    for (uint16_t i = 0; i < length; i++) {
        crc ^= (uint16_t)data[i] << 8;
        
        for (int j = 0; j < 8; j++) {
            crc <<= 1;
            if (crc & 0x10000) {
                crc ^= 0x1021;
                crc &= 0xFFFF;
            }
        }
    }
    
    // Reflect output per Y300 spec
    uint16_t reflected = 0;
    for (int i = 0; i < 16; i++) {
        if (crc & (1 << i)) {
            reflected |= (1 << (15 - i));
        }
    }
    
    return reflected;
}

// ============================================================================
// CIRCULAR BUFFER MANAGEMENT
// ============================================================================

/**
 * Initialize circular RX buffer
 */
static esp_err_t rx_buffer_init(rfid_rx_buffer_t* buf, uint16_t size)
{
    buf->buffer = malloc(size);
    if (!buf->buffer) {
        ESP_LOGE(TAG, "Failed to allocate RX buffer (%d bytes)", size);
        return ESP_ERR_NO_MEM;
    }
    
    buf->size = size;
    buf->head = 0;
    buf->tail = 0;
    buf->count = 0;
    return ESP_OK;
}

/**
 * Free circular RX buffer
 */
static void rx_buffer_deinit(rfid_rx_buffer_t* buf)
{
    if (buf->buffer) {
        free(buf->buffer);
        buf->buffer = NULL;
    }
    memset(buf, 0, sizeof(rfid_rx_buffer_t));
}

/**
 * Add bytes to circular buffer
 */
static void rx_buffer_write(rfid_rx_buffer_t* buf, const uint8_t* data, uint16_t len)
{
    for (uint16_t i = 0; i < len && buf->count < buf->size; i++) {
        buf->buffer[buf->head] = data[i];
        buf->head = (buf->head + 1) % buf->size;
        buf->count++;
    }
}

/**
 * Read bytes from circular buffer without removing them
 */
static uint16_t rx_buffer_peek(rfid_rx_buffer_t* buf, uint8_t* data, uint16_t max_len)
{
    uint16_t len = (buf->count > max_len) ? max_len : buf->count;
    
    for (uint16_t i = 0; i < len; i++) {
        data[i] = buf->buffer[(buf->tail + i) % buf->size];
    }
    
    return len;
}

/**
 * Remove bytes from circular buffer
 */
static void rx_buffer_consume(rfid_rx_buffer_t* buf, uint16_t len)
{
    uint16_t consume = (len > buf->count) ? buf->count : len;
    buf->tail = (buf->tail + consume) % buf->size;
    buf->count -= consume;
}

/**
 * Clear circular buffer
 */
static void rx_buffer_clear(rfid_rx_buffer_t* buf)
{
    buf->head = 0;
    buf->tail = 0;
    buf->count = 0;
}

// ============================================================================
// FRAME PARSING AND VALIDATION
// ============================================================================

/**
 * Find and extract complete frame from RX buffer
 * 
 * Returns:
 *   - Bytes extracted (including frame), 0 if no complete frame available
 *   - Invalid frames (bad CRC/format) are skipped by advancing tail
 */
static uint16_t extract_frame(uint8_t* frame_buffer, uint16_t max_len)
{
    uint8_t peek_buf[RFID_RX_BUF_SIZE];
    uint16_t available = rx_buffer_peek(&rx_buffer, peek_buf, sizeof(peek_buf));
    
    if (available < RFID_FRAME_MIN_LENGTH) {
        return 0;  // Not enough bytes for minimal frame
    }
    
    // Search for frame sync (0xBB, 0xBB)
    uint16_t sync_pos = 0xFFFF;
    for (uint16_t i = 0; i < available - 1; i++) {
        if (peek_buf[i] == RFID_FRAME_HEADER_BYTE1 && 
            peek_buf[i + 1] == RFID_FRAME_HEADER_BYTE2) {
            sync_pos = i;
            break;
        }
    }
    
    if (sync_pos == 0xFFFF) {
        // No sync found, clear everything except last byte (might be start of next frame)
        rx_buffer_consume(&rx_buffer, available > 1 ? available - 1 : 0);
        return 0;
    }
    
    if (sync_pos > 0) {
        // Skip bytes before sync
        rx_buffer_consume(&rx_buffer, sync_pos);
        
        // Re-peek after consuming
        available = rx_buffer_peek(&rx_buffer, peek_buf, sizeof(peek_buf));
        if (available < RFID_FRAME_MIN_LENGTH) {
            return 0;
        }
    }
    
    // Extract length field (big-endian, offset +3 and +4)
    if (available < 5) {
        return 0;
    }
    
    uint16_t data_len = ((uint16_t)peek_buf[3] << 8) | peek_buf[4];
    uint16_t frame_len = 2 + 1 + 2 + data_len + 2;  // Header + Cmd + Len + Data + CRC
    
    if (frame_len > max_len) {
        ESP_LOGW(TAG, "Frame too large: %d bytes", frame_len);
        rx_buffer_consume(&rx_buffer, 1);  // Skip this bad header
        return 0;
    }
    
    if (available < frame_len) {
        return 0;  // Incomplete frame
    }
    
    // Validate CRC (over header + command + length + data)
    uint16_t crc_field = ((uint16_t)peek_buf[frame_len - 2] << 8) | peek_buf[frame_len - 1];
    uint16_t crc_calc = crc16_ccitt(peek_buf, frame_len - 2);
    
    if (crc_calc != crc_field) {
        ESP_LOGW(TAG, "CRC mismatch: calculated=0x%04X, received=0x%04X", 
                 crc_calc, crc_field);
        rx_buffer_consume(&rx_buffer, 1);  // Skip this bad frame
        return 0;
    }
    
    // Copy valid frame to output buffer
    if (frame_len > max_len) {
        rx_buffer_consume(&rx_buffer, frame_len);
        return 0;
    }
    
    memcpy(frame_buffer, peek_buf, frame_len);
    rx_buffer_consume(&rx_buffer, frame_len);
    
    return frame_len;
}

// ============================================================================
// UART BACKGROUND TASK
// ============================================================================

/**
 * UART event handler task
 * 
 * Monitors UART0 RX FIFO, reads data into circular buffer, and parses
 * incoming frames. Posts RFID events to event queue.
 */
static void uart_event_task(void* arg)
{
    uart_event_t uart_event;
    uint8_t frame_buffer[RFID_RX_BUF_SIZE];
    uint8_t raw_data[256];
    
    ESP_LOGI(TAG, "UART event task started");
    
    while (reader_initialized) {
        // Wait for UART events with 100ms timeout to allow checking inventory state
        if (uart_wait_tx_done(RFID_UART_PORT, pdMS_TO_TICKS(100)) == ESP_OK) {
            // Check for data in RX FIFO
            size_t available = 0;
            uart_get_buffered_data_len(RFID_UART_PORT, &available);
            
            if (available > 0) {
                size_t read_len = uart_read_bytes(RFID_UART_PORT, raw_data, 
                                                    sizeof(raw_data), pdMS_TO_TICKS(10));
                if (read_len > 0) {
                    ESP_LOGV(TAG, "Received %d bytes from UART", read_len);
                    rx_buffer_write(&rx_buffer, raw_data, read_len);
                }
            }
        }
        
        // Try to extract complete frames from buffer
        uint16_t frame_len;
        while ((frame_len = extract_frame(frame_buffer, sizeof(frame_buffer))) > 0) {
            // Parse frame
            uint16_t data_len = ((uint16_t)frame_buffer[3] << 8) | frame_buffer[4];
            uint8_t command = frame_buffer[2];
            
            ESP_LOGD(TAG, "Frame received: cmd=0x%02X, len=%d", command, data_len);
            
            // Create event for tag data (if this is an inventory response)
            if (inventory_running && command == RFID_CMD_REAL_TIME_INVENTORY) {
                // Response format: [status] [EPC_len] [EPC(96-bit)] [antenna] [rssi]
                // This is a simplified handler - actual parsing depends on response format
                
                if (data_len >= 2) {
                    rfid_event_t event = {
                        .type = RFID_EVENT_TAG_READ,
                        .timestamp = xTaskGetTickCount() * portTICK_PERIOD_MS,
                    };
                    
                    // Copy EPC data (location and length vary by response format)
                    uint8_t epc_len = (data_len > 1) ? frame_buffer[5 + 1] : 12;
                    if (epc_len > sizeof(event.tag_epc)) {
                        epc_len = sizeof(event.tag_epc);
                    }
                    
                    memcpy(event.tag_epc, &frame_buffer[6], epc_len);
                    event.epc_length = epc_len;
                    
                    if (rfid_event_queue) {
                        xQueueSend(rfid_event_queue, &event, 0);
                    }
                }
            }
        }
        
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    
    ESP_LOGI(TAG, "UART event task ended");
    uart_task_handle = NULL;
    vTaskDelete(NULL);
}

// ============================================================================
// INITIALIZATION
// ============================================================================

/**
 * Initialize UART peripheral and FreeRTOS infrastructure
 */
esp_err_t uart_reader_init(void)
{
    if (reader_initialized) {
        ESP_LOGW(TAG, "UART reader already initialized");
        return ESP_OK;
    }
    
    // Initialize RX circular buffer
    esp_err_t ret = rx_buffer_init(&rx_buffer, RFID_RX_BUF_SIZE);
    if (ret != ESP_OK) {
        return ret;
    }
    
    // Configure UART parameters
    // DATASHEET REF: Section 7.8.1.2 - Baud Rate = FREQ / (16 * divisor)
    // For 9600 baud with 80MHz APB clock: divisor = 80000000 / (16 * 9600) ≈ 520
    uart_config_t uart_config = {
        .baud_rate = RFID_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_APB,
    };
    
    ret = uart_driver_install(RFID_UART_PORT, RFID_RX_BUF_SIZE, 
                              RFID_TX_BUF_SIZE, 0, NULL, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_driver_install failed: %s", esp_err_to_name(ret));
        rx_buffer_deinit(&rx_buffer);
        return ret;
    }
    
    ret = uart_param_config(RFID_UART_PORT, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_param_config failed: %s", esp_err_to_name(ret));
        uart_driver_delete(RFID_UART_PORT);
        rx_buffer_deinit(&rx_buffer);
        return ret;
    }
    
    // Set UART pins
    // DATASHEET REF: Table 7-2 IO_MUX for UART1 pin assignment
    ret = uart_set_pin(RFID_UART_PORT, RFID_UART_TX_PIN, RFID_UART_RX_PIN, 
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_set_pin failed: %s", esp_err_to_name(ret));
        uart_driver_delete(RFID_UART_PORT);
        rx_buffer_deinit(&rx_buffer);
        return ret;
    }
    
    // Create event queue
    rfid_event_queue = xQueueCreate(16, sizeof(rfid_event_t));
    if (!rfid_event_queue) {
        ESP_LOGE(TAG, "Failed to create event queue");
        uart_driver_delete(RFID_UART_PORT);
        rx_buffer_deinit(&rx_buffer);
        return ESP_ERR_NO_MEM;
    }
    
    reader_initialized = true;
    
    // Create background UART task (FreeRTOS Section 2.1.2 - Task Management)
    ret = xTaskCreate(uart_event_task, "uart_reader_task", 4096, NULL, 5, &uart_task_handle);
    if (ret == pdPASS) {
        ESP_LOGI(TAG, "UART reader initialized on UART%d (TX=%d, RX=%d, Baud=%d)",
                 RFID_UART_PORT, RFID_UART_TX_PIN, RFID_UART_RX_PIN, RFID_UART_BAUD);
        return ESP_OK;
    }
    
    ESP_LOGE(TAG, "Failed to create UART task");
    reader_initialized = false;
    uart_driver_delete(RFID_UART_PORT);
    rx_buffer_deinit(&rx_buffer);
    vQueueDelete(rfid_event_queue);
    rfid_event_queue = NULL;
    
    return ESP_FAIL;
}

/**
 * Cleanup UART and FreeRTOS resources
 */
void uart_reader_deinit(void)
{
    if (!reader_initialized) {
        return;
    }
    
    reader_initialized = false;
    inventory_running = false;
    
    // Wait for task to finish (it checks reader_initialized flag)
    if (uart_task_handle) {
        for (int i = 0; i < 10; i++) {
            if (!uart_task_handle) break;
            vTaskDelay(pdMS_TO_TICKS(100));
        }
    }
    
    uart_driver_delete(RFID_UART_PORT);
    rx_buffer_deinit(&rx_buffer);
    
    if (rfid_event_queue) {
        vQueueDelete(rfid_event_queue);
        rfid_event_queue = NULL;
    }
    
    ESP_LOGI(TAG, "UART reader deinitialized");
}

// ============================================================================
// PUBLIC API
// ============================================================================

QueueHandle_t uart_reader_get_event_queue(void)
{
    return rfid_event_queue;
}

int uart_reader_send_command(rfid_command_t cmd, const uint8_t* data, 
                              uint8_t data_len, uint32_t timeout_ms)
{
    if (!reader_initialized) {
        ESP_LOGE(TAG, "Reader not initialized");
        return -1;
    }
    
    // Build frame: [0xBB] [0xBB] [CMD] [LEN_HI] [LEN_LO] [DATA] [CRC_HI] [CRC_LO]
    uint16_t frame_size = 2 + 1 + 2 + data_len + 2;
    uint8_t* frame = malloc(frame_size);
    if (!frame) {
        ESP_LOGE(TAG, "Failed to allocate frame buffer");
        return -1;
    }
    
    frame[0] = RFID_FRAME_HEADER_BYTE1;
    frame[1] = RFID_FRAME_HEADER_BYTE2;
    frame[2] = (uint8_t)cmd;
    frame[3] = (data_len >> 8) & 0xFF;
    frame[4] = data_len & 0xFF;
    
    if (data && data_len > 0) {
        memcpy(&frame[5], data, data_len);
    }
    
    // Calculate CRC over [header + cmd + len + data] (everything except CRC field)
    uint16_t crc = crc16_ccitt(frame, frame_size - 2);
    frame[frame_size - 2] = (crc >> 8) & 0xFF;
    frame[frame_size - 1] = crc & 0xFF;
    
    // Send frame
    int bytes_written = uart_write_bytes(RFID_UART_PORT, frame, frame_size);
    free(frame);
    
    if (bytes_written < 0) {
        ESP_LOGE(TAG, "uart_write_bytes failed");
        return -1;
    }
    
    ESP_LOGD(TAG, "Sent command 0x%02X (%d bytes)", cmd, bytes_written);
    
    // Wait for response (simple timeout-based approach)
    // Production code should use reader-specific response formats
    uint32_t elapsed = 0;
    while (elapsed < timeout_ms) {
        if (rx_buffer.count > 0) {
            uint8_t response_buf[256];
            uint16_t response_len = rx_buffer_peek(&rx_buffer, response_buf, sizeof(response_buf));
            return response_len;
        }
        
        vTaskDelay(pdMS_TO_TICKS(10));
        elapsed += 10;
    }
    
    return 0;  // Timeout
}

esp_err_t uart_reader_start_inventory(bool realtime)
{
    if (!reader_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    inventory_running = true;
    rfid_command_t cmd = realtime ? RFID_CMD_REAL_TIME_INVENTORY : RFID_CMD_INVENTORY;
    
    // Real-time inventory: no additional data needed
    // Standard inventory: [session] [target] - using defaults
    uint8_t inventory_data[] = {0x00, 0x00};
    
    int result = uart_reader_send_command(cmd, inventory_data, sizeof(inventory_data), 1000);
    if (result <= 0) {
        inventory_running = false;
        return ESP_FAIL;
    }
    
    ESP_LOGI(TAG, "Inventory started (realtime=%d)", realtime);
    return ESP_OK;
}

void uart_reader_stop_inventory(void)
{
    inventory_running = false;
    ESP_LOGI(TAG, "Inventory stopped");
}

int uart_reader_read_response(uint8_t* buffer, uint16_t max_len, uint32_t timeout_ms)
{
    if (!reader_initialized || !buffer) {
        return -1;
    }
    
    uint32_t elapsed = 0;
    while (elapsed < timeout_ms) {
        if (rx_buffer.count > 0) {
            uint16_t len = rx_buffer_peek(&rx_buffer, buffer, max_len);
            rx_buffer_consume(&rx_buffer, len);
            return len;
        }
        
        vTaskDelay(pdMS_TO_TICKS(10));
        elapsed += 10;
    }
    
    return 0;  // Timeout
}
