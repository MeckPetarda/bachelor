/**
 * uart_reader.c - R300/Y300 UHF RFID Reader Implementation
 * 
 * Implements R300 protocol V2.2 for real-time tag detection
 * Version: 1.2 - Fixed continuous inventory and added range optimization
 */

#include "uart_reader.h"
#include <string.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "driver/uart.h"
#include "esp_log.h"

static const char* TAG = "RFID";

// ============================================================================
// R300 PROTOCOL CONSTANTS
// ============================================================================

#define R300_FRAME_HEAD         0xA0
#define R300_ADDR_BROADCAST     0xFF

#define R300_CMD_RESET          0x70
#define R300_CMD_GET_FIRMWARE   0x72
#define R300_CMD_SET_POWER      0x76
#define R300_CMD_SET_FREQUENCY  0x78
#define R300_CMD_INVENTORY_RT   0x89
#define R300_CMD_STOP_INVENTORY 0x70

#define R300_MAX_FRAME_SIZE     256
#define UART_RX_TASK_STACK      4096
#define UART_RX_TASK_PRIORITY   10

// ============================================================================
// MODULE STATE
// ============================================================================

static struct {
    bool initialized;
    bool inventory_active;
    rfid_tag_callback_t tag_callback;
    rfid_stats_t stats;
    TaskHandle_t rx_task_handle;
    SemaphoreHandle_t mutex;
} rfid_state = {0};

// ============================================================================
// R300 PROTOCOL HELPERS
// ============================================================================

/**
 * Calculate R300 checksum
 * Per section 6, page 43: checksum = (~sum) + 1
 */
static uint8_t r300_checksum(const uint8_t* data, uint8_t len)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < len; i++) {
        sum += data[i];
    }
    return (~sum) + 1;
}

/**
 * Send R300 command frame
 * Frame format: [Head][Len][Address][Cmd][Data...][Check]
 */
static esp_err_t send_command(uint8_t cmd, const uint8_t* data, uint8_t data_len)
{
    uint8_t frame[R300_MAX_FRAME_SIZE];
    uint8_t frame_len = 0;
    
    // Build frame
    frame[frame_len++] = R300_FRAME_HEAD;
    frame[frame_len++] = 3 + data_len;  // Len: Address + Cmd + Data
    frame[frame_len++] = R300_ADDR_BROADCAST;
    frame[frame_len++] = cmd;
    
    if (data && data_len > 0) {
        memcpy(&frame[frame_len], data, data_len);
        frame_len += data_len;
    }
    
    // Add checksum
    frame[frame_len] = r300_checksum(frame, frame_len);
    frame_len++;
    
    // Send
    int written = uart_write_bytes(RFID_UART_PORT, frame, frame_len);
    
    ESP_LOGI(TAG, "TX cmd=0x%02X, len=%d", cmd, frame_len);
    
    return (written == frame_len) ? ESP_OK : ESP_FAIL;
}

/**
 * Parse real-time inventory response
 * Per section 2.2.8, page 27:
 * [Head][Len][Address][Cmd][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]
 */
static bool parse_inventory_response(const uint8_t* data, uint16_t len, 
                                     rfid_tag_event_t* event)
{
    // Minimum valid frame: Head(1) + Len(1) + Addr(1) + Cmd(1) + 
    //                      Freq_Ant(1) + PC(2) + EPC(min 2) + RSSI(1) + Check(1)
    if (len < 11) {
        return false;
    }
    
    // Verify header
    if (data[0] != R300_FRAME_HEAD || data[3] != R300_CMD_INVENTORY_RT) {
        return false;
    }
    
    // Verify checksum
    uint8_t calc_check = r300_checksum(data, len - 1);
    if (calc_check != data[len - 1]) {
        ESP_LOGW(TAG, "Checksum mismatch: calc=0x%02X, recv=0x%02X", 
                 calc_check, data[len - 1]);
        return false;
    }
    
    // Parse fields
    uint8_t freq_ant = data[4];
    event->frequency = (freq_ant >> 2) & 0x3F;  // High 6 bits
    event->antenna_id = freq_ant & 0x03;        // Low 2 bits
    
    event->pc[0] = data[5];
    event->pc[1] = data[6];
    
    // EPC length is remaining data minus RSSI and checksum
    event->epc_len = len - 11;
    if (event->epc_len > sizeof(event->epc)) {
        event->epc_len = sizeof(event->epc);
    }
    
    memcpy(event->epc, &data[7], event->epc_len);
    event->rssi = data[7 + event->epc_len];
    event->timestamp_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;
    
    return true;
}

/**
 * Check if frame is inventory completion packet
 * Per section 2.2.8, page 28:
 * [Head][Len=0x08][Address][Cmd][Ant_ID][Total_Read(4)][Check]
 */
static bool is_inventory_complete(const uint8_t* data, uint16_t len)
{
    return (len == 11 && 
            data[0] == R300_FRAME_HEAD && 
            data[1] == 0x08 && 
            data[3] == R300_CMD_INVENTORY_RT);
}

/**
 * Restart inventory command
 * Called automatically when inventory round completes
 */
static void restart_inventory(void)
{
    if (rfid_state.inventory_active) {
        // Use 0xFF for fastest inventory (30-50ms per round)
        // Per section 2.2.8, page 27
        uint8_t channel = 0xFF;
        send_command(R300_CMD_INVENTORY_RT, &channel, 1);
    }
}

// ============================================================================
// UART RX TASK
// ============================================================================

static void uart_rx_task(void* arg)
{
    uint8_t rx_buf[R300_MAX_FRAME_SIZE];
    rfid_tag_event_t event;
    
    ESP_LOGI(TAG, "RX task started");
    
    while (1) {
        int len = uart_read_bytes(RFID_UART_PORT, rx_buf, sizeof(rx_buf),
                                  pdMS_TO_TICKS(100));
        
        if (len > 0) {
            // Check for inventory completion packet
            if (is_inventory_complete(rx_buf, len)) {
                uint32_t total_reads = (rx_buf[5] << 24) | (rx_buf[6] << 16) | 
                                      (rx_buf[7] << 8) | rx_buf[8];
                ESP_LOGD(TAG, "Inventory round complete, total_reads=%lu", total_reads);
                
                // Auto-restart for continuous operation
                vTaskDelay(pdMS_TO_TICKS(10));
                restart_inventory();
                continue;
            }
            
            // Process tag detection
            if (rfid_state.inventory_active && 
                rx_buf[0] == R300_FRAME_HEAD && 
                rx_buf[3] == R300_CMD_INVENTORY_RT) {
                
                if (parse_inventory_response(rx_buf, len, &event)) {
                    // Update stats
                    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
                    rfid_state.stats.total_reads++;
                    xSemaphoreGive(rfid_state.mutex);
                    
                    // Call user callback
                    if (rfid_state.tag_callback) {
                        rfid_state.tag_callback(&event);
                    }
                    
                    ESP_LOGI(TAG, "Tag detected: EPC_len=%d, RSSI=%d, Ant=%d",
                             event.epc_len, event.rssi, event.antenna_id);
                }
            }
        }
        
        // Allow other tasks to run
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t rfid_reader_init(void)
{
    if (rfid_state.initialized) {
        return ESP_OK;
    }
    
    ESP_LOGI(TAG, "Initializing RFID reader...");
    
    // Create mutex
    rfid_state.mutex = xSemaphoreCreateMutex();
    if (!rfid_state.mutex) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }
    
    // Configure UART
    uart_config_t uart_config = {
        .baud_rate = RFID_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_APB,
    };
    
    esp_err_t ret = uart_driver_install(RFID_UART_PORT, 
                                         R300_MAX_FRAME_SIZE * 2, 
                                         R300_MAX_FRAME_SIZE * 2, 
                                         0, NULL, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install UART driver: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ret = uart_param_config(RFID_UART_PORT, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure UART: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ret = uart_set_pin(RFID_UART_PORT, RFID_UART_TX_PIN, RFID_UART_RX_PIN,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set UART pins: %s", esp_err_to_name(ret));
        return ret;
    }
    
    // Flush any startup garbage
    uart_flush(RFID_UART_PORT);
    
    // Start RX task
    BaseType_t task_ret = xTaskCreate(uart_rx_task, "rfid_rx", 
                                       UART_RX_TASK_STACK, NULL, 
                                       UART_RX_TASK_PRIORITY, 
                                       &rfid_state.rx_task_handle);
    if (task_ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create RX task");
        uart_driver_delete(RFID_UART_PORT);
        return ESP_ERR_NO_MEM;
    }
    
    rfid_state.initialized = true;
    
    ESP_LOGI(TAG, "RFID reader initialized (UART%d, TX=%d, RX=%d, Baud=%d)",
             RFID_UART_PORT, RFID_UART_TX_PIN, RFID_UART_RX_PIN, RFID_UART_BAUD);
    
    return ESP_OK;
}

void rfid_reader_deinit(void)
{
    if (!rfid_state.initialized) {
        return;
    }
    
    rfid_reader_stop_inventory();
    
    if (rfid_state.rx_task_handle) {
        vTaskDelete(rfid_state.rx_task_handle);
        rfid_state.rx_task_handle = NULL;
    }
    
    uart_driver_delete(RFID_UART_PORT);
    
    if (rfid_state.mutex) {
        vSemaphoreDelete(rfid_state.mutex);
        rfid_state.mutex = NULL;
    }
    
    memset(&rfid_state, 0, sizeof(rfid_state));
    
    ESP_LOGI(TAG, "RFID reader deinitialized");
}

esp_err_t rfid_reader_reset(void)
{
    if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    ESP_LOGI(TAG, "Resetting reader module...");
    
    // Stop inventory if running
    rfid_reader_stop_inventory();
    
    // Send reset command (no data)
    esp_err_t ret = send_command(R300_CMD_RESET, NULL, 0);
    
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Reset sent (module will beep and restart)");
    }
    
    return ret;
}

esp_err_t rfid_reader_get_firmware(uint8_t* major, uint8_t* minor)
{
    if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (!major || !minor) {
        return ESP_ERR_INVALID_ARG;
    }
    
    // Flush RX buffer
    uart_flush(RFID_UART_PORT);
    
    // Send command
    esp_err_t ret = send_command(R300_CMD_GET_FIRMWARE, NULL, 0);
    if (ret != ESP_OK) {
        return ret;
    }
    
    // Wait for response
    // Expected: [0xA0][0x05][Address][0x72][Major][Minor][Check]
    uint8_t rx_buf[32];
    int len = uart_read_bytes(RFID_UART_PORT, rx_buf, sizeof(rx_buf),
                              pdMS_TO_TICKS(1000));
    
    if (len >= 7 && rx_buf[0] == R300_FRAME_HEAD && rx_buf[3] == R300_CMD_GET_FIRMWARE) {
        *major = rx_buf[4];
        *minor = rx_buf[5];
        ESP_LOGI(TAG, "Firmware version: %d.%d", *major, *minor);
        return ESP_OK;
    }
    
    ESP_LOGW(TAG, "No firmware response (len=%d)", len);
    return ESP_ERR_TIMEOUT;
}

esp_err_t rfid_reader_set_power(uint8_t power_dbm)
{
    if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    // Clamp to valid range (20-33 dBm)
    // Per section 2.1.7, page 12
    if (power_dbm < 20) power_dbm = 20;
    if (power_dbm > 33) power_dbm = 33;
    
    esp_err_t ret = send_command(R300_CMD_SET_POWER, &power_dbm, 1);
    
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Set power to %d dBm", power_dbm);
    }
    
    return ret;
}

esp_err_t rfid_reader_set_frequency_region(uint8_t region, uint8_t start_freq, uint8_t end_freq)
{
    if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    // Per section 2.1.9, page 13
    // region: 0x01=FCC, 0x02=ETSI, 0x03=CHN
    uint8_t data[3] = {region, start_freq, end_freq};
    
    esp_err_t ret = send_command(R300_CMD_SET_FREQUENCY, data, 3);
    
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Set frequency region=0x%02X, range=0x%02X-0x%02X", 
                 region, start_freq, end_freq);
    }
    
    return ret;
}

esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback)
{
    if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (rfid_state.inventory_active) {
        ESP_LOGW(TAG, "Inventory already active");
        return ESP_OK;
    }
    
    rfid_state.tag_callback = callback;
    
    // Send real-time inventory command
    // Per section 2.2.8: [0xA0][0x04][Address][0x89][Channel][Check]
    // Use 0xFF for fastest operation (30-50ms per round with few tags)
    uint8_t channel = 0xFF;  // CHANGED from 0x01 to 0xFF
    esp_err_t ret = send_command(R300_CMD_INVENTORY_RT, &channel, 1);
    
    if (ret == ESP_OK) {
        xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
        rfid_state.inventory_active = true;
        rfid_state.stats.inventory_active = true;
        xSemaphoreGive(rfid_state.mutex);
        
        ESP_LOGI(TAG, "Real-time inventory started (channel=0xFF for continuous operation)");
    }
    
    return ret;
}

esp_err_t rfid_reader_stop_inventory(void)
{
     if (!rfid_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (!rfid_state.inventory_active) {
        return ESP_OK;  // Already stopped
    }
    
    ESP_LOGI(TAG, "Stopping inventory...");
    
    // Set flag first to prevent auto-restart
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.inventory_active = false;
    rfid_state.stats.inventory_active = false;
    rfid_state.tag_callback = NULL;
    xSemaphoreGive(rfid_state.mutex);
    
    // Give RX task time to see the flag change
    vTaskDelay(pdMS_TO_TICKS(50));
    
    esp_err_t ret = send_command(R300_CMD_RESET, NULL, 0);

    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Reset sent (module will beep and restart)");
        ESP_LOGI(TAG, "Inventory stopped");

        return ESP_OK;
    }

    return ESP_ERR_INVALID_RESPONSE;
}

bool rfid_reader_is_inventory_active(void)
{
    return rfid_state.inventory_active;
}

esp_err_t rfid_reader_get_stats(rfid_stats_t* stats)
{
    if (!rfid_state.initialized || !stats) {
        return ESP_ERR_INVALID_ARG;
    }
    
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    memcpy(stats, &rfid_state.stats, sizeof(rfid_stats_t));
    xSemaphoreGive(rfid_state.mutex);
    
    return ESP_OK;
}

void rfid_reader_clear_stats(void)
{
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.stats.tags_detected = 0;
    rfid_state.stats.total_reads = 0;
    rfid_state.stats.errors = 0;
    xSemaphoreGive(rfid_state.mutex);
}
