/**
 * uart_reader.c - R300/Y300 UHF RFID Reader Implementation
 *
 * Implements R300 protocol V2.2 for polling-based tag detection
 * Version: 1.3 - Changed to command-based polling with configurable interval
 */

#include "uart_reader.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "hal/gpio_types.h"

static const char *TAG = "RFID";

// ============================================================================
// R300 PROTOCOL CONSTANTS
// ============================================================================

#define R300_FRAME_HEAD     0xA0
#define R300_ADDR_BROADCAST 0xFF

#define R300_CMD_RESET            0x70
#define R300_CMD_GET_FIRMWARE     0x72
#define R300_CMD_SET_POWER        0x76
#define R300_CMD_SET_FREQUENCY    0x78
#define R300_CMD_INVENTORY_SINGLE 0x8B
#define R300_CMD_STOP_INVENTORY   0x70

#define DEFAULT_READ_INTERVAL_MS 250
#define MIN_READ_INTERVAL_MS     50
#define HANDSHAKE_TIMEOUT_MS     1000
#define POWER_ON_GRACE_PERIOD_MS 500
#define HEALTH_CHECK_INTERVAL_MS 60000

#define R300_MAX_FRAME_SIZE        256
#define UART_RX_TASK_STACK         4096
#define UART_RX_TASK_PRIORITY      10
#define HEALTH_CHECK_TASK_STACK    3072
#define HEALTH_CHECK_TASK_PRIORITY 5

// ============================================================================
// MODULE STATE
// ============================================================================

static struct
{
    bool                initialized;
    bool                inventory_active;
    rfid_tag_callback_t tag_callback;
    rfid_stats_t        stats;
    TaskHandle_t        rx_task_handle;
    TaskHandle_t        health_check_task_handle;
    SemaphoreHandle_t   mutex;
    uint32_t            read_interval_ms;

    // State machine and health tracking
    rfid_reader_state_t state;
    rfid_health_t       health;
} rfid_state = {.state = RFID_STATE_UNINITIALIZED, .health = {0}};

// ============================================================================
// R300 PROTOCOL HELPERS
// ============================================================================

/**
 * Calculate R300 checksum
 * Per section 6, page 43: checksum = (~sum) + 1
 */
static uint8_t r300_checksum(const uint8_t *data, uint8_t len)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < len; i++)
    {
        sum += data[i];
    }
    return (~sum) + 1;
}

/**
 * Send R300 command frame
 * Frame format: [Head][Len][Address][Cmd][Data...][Check]
 */
static esp_err_t send_command(uint8_t cmd, const uint8_t *data, uint8_t data_len)
{
    uint8_t frame[R300_MAX_FRAME_SIZE];
    uint8_t frame_len = 0;

    // Build frame
    frame[frame_len++] = R300_FRAME_HEAD;
    frame[frame_len++] = 3 + data_len; // Len: Address + Cmd + Data
    frame[frame_len++] = R300_ADDR_BROADCAST;
    frame[frame_len++] = cmd;

    if (data && data_len > 0)
    {
        memcpy(&frame[frame_len], data, data_len);
        frame_len += data_len;
    }

    // Add checksum
    frame[frame_len] = r300_checksum(frame, frame_len);
    frame_len++;

    // Send
    int written = uart_write_bytes(RFID_UART_PORT, frame, frame_len);

    ESP_LOGD(TAG, "TX cmd=0x%02X, len=%d", cmd, frame_len);

    return (written == frame_len) ? ESP_OK : ESP_FAIL;
}

/**
 * Parse single inventory response
 * Per section 2.2.6 (command 0x8B):
 * [Head][Len][Address][Cmd][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]
 *
 * Validation per R300 protocol V2.2:
 * - Valid RSSI range: 31-98 (0x1F-0x62) representing -99 to -31 dBm
 * - Minimum EPC length: 8 bytes (standard C1G2)
 * - EPC length is extracted from PC word bits 15-11 (word count)
 */
static bool parse_inventory_response(const uint8_t *data, uint16_t len, rfid_tag_event_t *event)
{
    // Minimum valid frame: Head(1) + Len(1) + Addr(1) + Cmd(1) +
    //                      Freq_Ant(1) + PC(2) + EPC(min 8) + RSSI(1) +
    //                      Check(1)
    // Total: 1+1+1+1+1+2+8+1+1 = 17 bytes minimum
    if (len < 17)
    {
        ESP_LOGD(TAG, "Frame too short: %d bytes (min 17)", len);
        return false;
    }

    // Verify header (accept both 0x8B and 0x89 for backwards compatibility)
    if (data[0] != R300_FRAME_HEAD || (data[3] != R300_CMD_INVENTORY_SINGLE))
    {
        ESP_LOGD(TAG, "Invalid header: 0x%02X or cmd: 0x%02X", data[0], data[3]);
        return false;
    }

    // Extract packet length from Len field to handle multiple packets in
    // buffer (e.g., tag response + completion packet) Len field = Address +
    // Cmd + Freq_Ant + PC(2) + EPC(N) + RSSI + Check
    uint8_t  packet_len_field = data[1];
    uint16_t packet_total_len = packet_len_field + 2; // +2 for Head and Len bytes

    // Check if we have at least one complete packet
    if (len < packet_total_len)
    {
        ESP_LOGD(TAG, "Incomplete packet: have %d bytes, need %d", len, packet_total_len);
        return false;
    }

    // Log raw frame for debugging (only the tag packet, not completion packet)
    ESP_LOGD(TAG, "Raw frame (%d bytes): %02X %02X %02X %02X %02X %02X %02X %02X...", packet_total_len, data[0],
             data[1], data[2], data[3], data[4], data[5], data[6], data[7]);

    // Verify checksum (only for the tag packet)
    uint8_t calc_check = r300_checksum(data, packet_total_len - 1);
    if (calc_check != data[packet_total_len - 1])
    {
        ESP_LOGW(TAG, "Checksum mismatch: calc=0x%02X, recv=0x%02X", calc_check, data[packet_total_len - 1]);
        return false;
    }

    // Parse fields
    uint8_t freq_ant  = data[4];
    event->frequency  = (freq_ant >> 2) & 0x3F; // High 6 bits
    event->antenna_id = freq_ant & 0x03;        // Low 2 bits

    event->pc[0] = data[5];
    event->pc[1] = data[6];

    // Extract EPC length from PC word
    // PC bits 15-11 contain EPC word count (1 word = 2 bytes)
    // PC is big-endian: PC[0] is MSB, PC[1] is LSB
    uint16_t pc_word        = (event->pc[0] << 8) | event->pc[1];
    uint8_t  epc_word_count = (pc_word >> 11) & 0x1F; // Extract bits 15-11
    event->epc_len          = epc_word_count * 2;     // Convert words to bytes

    // Validate EPC length
    if (event->epc_len < 8 || event->epc_len > sizeof(event->epc))
    {
        ESP_LOGW(TAG,
                 "Invalid EPC length from PC: %d bytes (word count: %d, "
                 "PC: 0x%04X)",
                 event->epc_len, epc_word_count, pc_word);
        return false;
    }

    // Verify packet length matches expected size
    uint16_t expected_len = 3 + 1 + 1 + 2 + event->epc_len + 1 + 1; // Addr+Cmd+Freq_Ant+PC+EPC+RSSI+Check
    if (packet_len_field != expected_len - 2)
    { // -2 because Len field doesn't include Head and Len itself
        ESP_LOGW(TAG,
                 "Packet length mismatch: Len field=%d, expected=%d for "
                 "%d-byte EPC",
                 packet_len_field, expected_len - 2, event->epc_len);
        // Continue anyway - some readers might have slight variations
    }

    // Extract EPC
    memcpy(event->epc, &data[7], event->epc_len);

    // Extract RSSI (positioned after EPC)
    uint8_t rssi_pos = 7 + event->epc_len;
    event->rssi      = data[rssi_pos];

    // Validate RSSI (valid range: 31-98 or 0x1F-0x62)
    // Per R300 protocol V2.2 section 5, page 42
    if (event->rssi < 31 || event->rssi > 98)
    {
        ESP_LOGW(TAG, "RSSI out of range: %d (valid: 31-98)", event->rssi);
        // Don't fail - just warn
    }

    // Check for all-zero EPC (false detection)
    bool all_zeros = true;
    for (int i = 0; i < event->epc_len; i++)
    {
        if (event->epc[i] != 0x00)
        {
            all_zeros = false;
            break;
        }
    }
    if (all_zeros)
    {
        ESP_LOGD(TAG, "EPC is all zeros - invalid tag");
        return false;
    }

    event->timestamp_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;

    return true;
}

/**
 * Send single inventory command
 * Per section 2.2.6 (command 0x8B):
 * Performs a single read operation and returns the result
 */
static void send_inventory_command(void)
{
    if (rfid_state.inventory_active)
    {
        // Single inventory command:
        // [0xA0][0x06][0x01][0x8B][0x00][0x00][0x01][Check] Parameters:
        // antenna mask (0x00), read time (0x00), Q value (0x01)
        uint8_t params[3] = {0x00, 0x00, 0x01};
        send_command(R300_CMD_INVENTORY_SINGLE, params, 3);
    }
}

// ============================================================================
// HEALTH CHECK TASK
// ============================================================================

static void health_check_task(void *arg)
{
    ESP_LOGI(TAG, "Health check task started (interval=%d ms)", HEALTH_CHECK_INTERVAL_MS);

    while (1)
    {
        // Wait for the health check interval
        vTaskDelay(pdMS_TO_TICKS(HEALTH_CHECK_INTERVAL_MS));

        // Perform handshake to verify reader responsiveness
        ESP_LOGD(TAG, "Performing periodic health check...");
        rfid_reader_handshake(NULL, NULL);
    }
}

// ============================================================================
// UART RX TASK
// ============================================================================

static void uart_rx_task(void *arg)
{
    uint8_t          rx_buf[R300_MAX_FRAME_SIZE];
    rfid_tag_event_t event;
    uint32_t         last_read_time = 0;

    ESP_LOGI(TAG, "RX task started (polling mode)");

    while (1)
    {
        // Send inventory command at configured interval
        if (rfid_state.inventory_active)
        {
            uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
            uint32_t interval     = rfid_state.read_interval_ms;

            if ((current_time - last_read_time) >= interval)
            {
                send_inventory_command();
                last_read_time = current_time;
            }
        }

        // Check for incoming data with longer timeout to get complete
        // frames
        int len = uart_read_bytes(RFID_UART_PORT, rx_buf, sizeof(rx_buf), pdMS_TO_TICKS(50));

        if (len > 0)
        {
            // Log raw response for debugging
            ESP_LOGD(TAG, "RX raw (%d bytes):", len);

            // Wait a bit more if we got a frame header but frame seems
            // incomplete
            if (len >= 2 && rx_buf[0] == R300_FRAME_HEAD)
            {
                uint8_t expected_len = rx_buf[1] + 2; // Len field + Head + Len bytes
                if (len < expected_len)
                {
                    ESP_LOGD(TAG,
                             "Incomplete frame: got %d "
                             "bytes, expected %d - "
                             "waiting for "
                             "more data",
                             len, expected_len);
                    vTaskDelay(pdMS_TO_TICKS(20));
                    // Try to read remaining bytes
                    int additional =
                        uart_read_bytes(RFID_UART_PORT, &rx_buf[len], sizeof(rx_buf) - len, pdMS_TO_TICKS(30));
                    if (additional > 0)
                    {
                        ESP_LOGD(TAG, "Read %d additional bytes", additional);
                        len += additional;
                        // Log updated frame
                        ESP_LOGD(TAG, "RX complete (%d bytes):", len);
                        printf("    ");
                        for (int i = 0; i < len && i < 64; i++)
                        {
                            printf("%02X ", rx_buf[i]);
                        }
                        if (len > 64)
                        {
                            printf("...");
                        }
                        printf("\n");
                    }
                }
            }

            // Process tag detection response
            if (rfid_state.inventory_active && len >= 4 && rx_buf[0] == R300_FRAME_HEAD &&
                (rx_buf[3] == R300_CMD_INVENTORY_SINGLE))
            {
                if (parse_inventory_response(rx_buf, len, &event))
                {
                    // Update stats
                    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
                    rfid_state.stats.total_reads++;
                    xSemaphoreGive(rfid_state.mutex);

                    // Call user callback
                    if (rfid_state.tag_callback)
                    {
                        rfid_state.tag_callback(&event);
                    }

                    // Convert RSSI to dBm for logging
                    // Per R300 protocol: RSSI value range
                    // 31-98 maps to -99 to -31 dBm
                    int rssi_dbm = event.rssi - 129;
                    ESP_LOGI(TAG,
                             "✓ Valid tag: EPC_len=%d, "
                             "RSSI=%d (%d dBm), Ant=%d",
                             event.epc_len, event.rssi, rssi_dbm, event.antenna_id);
                }
                else
                {
                    ESP_LOGD(TAG, "✗ Invalid tag response "
                                  "(filtered out)");
                }
            }
        }

        // Small delay to allow other tasks to run
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t rfid_reader_init(void)
{
    if (rfid_state.initialized)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing RFID reader...");

    // Create mutex
    rfid_state.mutex = xSemaphoreCreateMutex();
    if (!rfid_state.mutex)
    {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    // Configure UART
    uart_config_t uart_config = {
        .baud_rate  = RFID_UART_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_APB,
    };

    esp_err_t ret = uart_driver_install(RFID_UART_PORT, R300_MAX_FRAME_SIZE * 2, R300_MAX_FRAME_SIZE * 2, 0, NULL, 0);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to install UART driver: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = uart_param_config(RFID_UART_PORT, &uart_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure UART: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = uart_set_pin(RFID_UART_PORT, RFID_UART_TX_PIN, RFID_UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set UART pins: %s", esp_err_to_name(ret));
        return ret;
    }

    // Configure GPIO5 for reader power control (transistor base)
    // Per tasks/reader_power_task.md: S9013 NPN transistor, 240Ω base resistor
    // Logic: GPIO HIGH = reader powered, GPIO LOW = reader disabled
    gpio_config_t pwr_ctrl_config = {
        .pin_bit_mask = (1ULL << RFID_POWER_CONTROL_PIN),
        .mode         = GPIO_MODE_INPUT_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    ret = gpio_config(&pwr_ctrl_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure power control GPIO: %s", esp_err_to_name(ret));
        uart_driver_delete(RFID_UART_PORT);
        return ret;
    }
    // Initialize power control pin LOW (reader OFF at startup)
    gpio_set_level(RFID_POWER_CONTROL_PIN, 0);
    ESP_LOGI(TAG, "Power control configured on GPIO%d (initial: OFF)", RFID_POWER_CONTROL_PIN);

    // Configure GPIO22 for power rail sensing (voltage monitoring)
    // Migrated from GPIO2 (strapping pin) per tasks/reader_power_task.md
    gpio_config_t pwr_sense_config = {
        .pin_bit_mask = (1ULL << RFID_POWER_SENSE_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE, // Safe default when unpowered
        .intr_type    = GPIO_INTR_DISABLE,
    };
    ret = gpio_config(&pwr_sense_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to configure power sense GPIO: %s", esp_err_to_name(ret));
        uart_driver_delete(RFID_UART_PORT);
        return ret;
    }
    ESP_LOGI(TAG, "Power sense configured on GPIO%d", RFID_POWER_SENSE_PIN);

    // Flush any startup garbage
    uart_flush(RFID_UART_PORT);

    // Start RX task
    BaseType_t task_ret = xTaskCreate(uart_rx_task, "rfid_rx", UART_RX_TASK_STACK, NULL, UART_RX_TASK_PRIORITY,
                                      &rfid_state.rx_task_handle);
    if (task_ret != pdPASS)
    {
        ESP_LOGE(TAG, "Failed to create RX task");
        uart_driver_delete(RFID_UART_PORT);
        return ESP_ERR_NO_MEM;
    }

    // Start health check task
    task_ret = xTaskCreate(health_check_task, "rfid_health", HEALTH_CHECK_TASK_STACK, NULL, HEALTH_CHECK_TASK_PRIORITY,
                           &rfid_state.health_check_task_handle);
    if (task_ret != pdPASS)
    {
        ESP_LOGE(TAG, "Failed to create health check task");
        vTaskDelete(rfid_state.rx_task_handle);
        uart_driver_delete(RFID_UART_PORT);
        return ESP_ERR_NO_MEM;
    }

    rfid_state.initialized = true;
    rfid_state.state       = RFID_STATE_STARTUP_PENDING;

    ESP_LOGI(TAG, "RFID reader initialized (UART%d, TX=%d, RX=%d, Baud=%d)", RFID_UART_PORT, RFID_UART_TX_PIN,
             RFID_UART_RX_PIN, RFID_UART_BAUD);

    rfid_reader_power_on();
    vTaskDelay(pdMS_TO_TICKS(100));

    // Perform initial handshake to verify reader is responsive
    ESP_LOGI(TAG, "Performing startup handshake...");
    vTaskDelay(pdMS_TO_TICKS(POWER_ON_GRACE_PERIOD_MS));
    esp_err_t hs_ret = rfid_reader_handshake(NULL, NULL);

    if (hs_ret == ESP_OK)
    {

        ESP_LOGI(TAG, "Correctly performed version handshake");
        esp_err_t beeper_ret = rfid_reader_set_beeper_mode(R300_BEEPER_MODE_PER_TAG);
        if (beeper_ret != ESP_OK)
        {
            ESP_LOGW(TAG, "Failed to set beeper mode (non-fatal): %s", esp_err_to_name(beeper_ret));
        }
        else
        {
            ESP_LOGI(TAG, "Correctly set beeper mode");
        }
    }
    else
    {
        ESP_LOGW(TAG, "Failed to perform handshake: %s", esp_err_to_name(hs_ret));
    }

    rfid_reader_power_off();
    vTaskDelay(pdMS_TO_TICKS(100));

    return ESP_OK;
}

void rfid_reader_deinit(void)
{
    if (!rfid_state.initialized)
    {
        return;
    }

    rfid_reader_stop_inventory();

    // Power off reader before cleanup
    gpio_set_level(RFID_POWER_CONTROL_PIN, 0);
    ESP_LOGI(TAG, "Reader power disabled during deinit");

    if (rfid_state.rx_task_handle)
    {
        vTaskDelete(rfid_state.rx_task_handle);
        rfid_state.rx_task_handle = NULL;
    }

    if (rfid_state.health_check_task_handle)
    {
        vTaskDelete(rfid_state.health_check_task_handle);
        rfid_state.health_check_task_handle = NULL;
    }

    uart_driver_delete(RFID_UART_PORT);

    if (rfid_state.mutex)
    {
        vSemaphoreDelete(rfid_state.mutex);
        rfid_state.mutex = NULL;
    }

    memset(&rfid_state, 0, sizeof(rfid_state));
    rfid_state.state = RFID_STATE_UNINITIALIZED;

    ESP_LOGI(TAG, "RFID reader deinitialized");
}

esp_err_t rfid_reader_reset(void)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Resetting reader module...");

    // Stop inventory if running
    rfid_reader_stop_inventory();

    // Send reset command (no data)
    esp_err_t ret = send_command(R300_CMD_RESET, NULL, 0);

    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "Reset sent (module will beep and restart)");
    }

    return ret;
}

esp_err_t rfid_reader_power_on(void)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Powering ON RFID reader (GPIO%d HIGH)...", RFID_POWER_CONTROL_PIN);

    // Assert reader power rail — returns immediately; caller is responsible for
    // confirming the rail via GPIO22 poll before issuing any commands.
    gpio_set_level(RFID_POWER_CONTROL_PIN, 1);

    // Update state machine
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.state = RFID_STATE_STARTUP_PENDING;
    xSemaphoreGive(rfid_state.mutex);

    return ESP_OK;
}

esp_err_t rfid_reader_power_off(void)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Stop inventory before powering off
    if (rfid_state.inventory_active)
    {
        rfid_reader_stop_inventory();
    }

    ESP_LOGI(TAG, "Powering OFF RFID reader (GPIO%d LOW)...", RFID_POWER_CONTROL_PIN);

    // Set transistor base LOW to disable reader power
    gpio_set_level(RFID_POWER_CONTROL_PIN, 0);

    // Update state machine
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.state                     = RFID_STATE_POWERED_OFF;
    rfid_state.health.power_rail_present = false;
    rfid_state.health.is_responsive      = false;
    xSemaphoreGive(rfid_state.mutex);

    ESP_LOGI(TAG, "✓ Reader powered OFF (sleep mode <100µA)");

    return ESP_OK;
}

bool rfid_reader_is_powered(void)
{
    return gpio_get_level(RFID_POWER_CONTROL_PIN) == 1;
}

esp_err_t rfid_reader_get_firmware(uint8_t *major, uint8_t *minor)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    if (!major || !minor)
    {
        return ESP_ERR_INVALID_ARG;
    }

    // Flush RX buffer
    uart_flush(RFID_UART_PORT);

    // Send command
    esp_err_t ret = send_command(R300_CMD_GET_FIRMWARE, NULL, 0);
    if (ret != ESP_OK)
    {
        return ret;
    }

    // Wait for response
    // Expected: [0xA0][0x05][Address][0x72][Major][Minor][Check]
    uint8_t rx_buf[32];
    int     len = uart_read_bytes(RFID_UART_PORT, rx_buf, sizeof(rx_buf), pdMS_TO_TICKS(1000));

    if (len >= 7 && rx_buf[0] == R300_FRAME_HEAD && rx_buf[3] == R300_CMD_GET_FIRMWARE)
    {
        *major = rx_buf[4];
        *minor = rx_buf[5];
        ESP_LOGI(TAG, "Firmware version: %d.%d", *major, *minor);
        return ESP_OK;
    }

    ESP_LOGW(TAG, "No firmware response (len=%d)", len);
    return ESP_ERR_TIMEOUT;
}

esp_err_t rfid_reader_set_beeper_mode(uint8_t mode)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Flush RX buffer before sending command
    uart_flush(RFID_UART_PORT);

    // Send set beeper mode command with 1-byte payload
    esp_err_t ret = send_command(R300_CMD_SET_BEEPER_MODE, &mode, 1);
    if (ret != ESP_OK)
    {
        return ret;
    }

    // Wait for response with 1-second timeout
    // Expected: [Head][Len][Address][0x7A][Check]
    uint8_t rx_buf[32];
    int     len = uart_read_bytes(RFID_UART_PORT, rx_buf, sizeof(rx_buf), pdMS_TO_TICKS(1000));

    if (len >= 4 && rx_buf[0] == R300_FRAME_HEAD && rx_buf[3] == R300_CMD_SET_BEEPER_MODE)
    {
        ESP_LOGI(TAG, "Beeper mode set to 0x%02X (persisted to flash)", mode);
        return ESP_OK;
    }

    ESP_LOGW(TAG, "No beeper mode response (len=%d)", len);
    return ESP_ERR_TIMEOUT;
}

esp_err_t rfid_reader_handshake(uint8_t *major, uint8_t *minor)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    bool is_powered = rfid_reader_is_powered();

    if (!is_powered)
    {
        ESP_LOGI(TAG, "Reader unpowered, powering on to perform handshake");
        rfid_reader_power_on();
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    // Check power rail status (GPIO22 - active low)
    bool power_present = !gpio_get_level(RFID_POWER_SENSE_PIN);

    // Update health metrics with power status
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.health.last_check_ms      = xTaskGetTickCount() * portTICK_PERIOD_MS;
    rfid_state.health.power_rail_present = power_present;
    xSemaphoreGive(rfid_state.mutex);

    if (!power_present)
    {
        // Power rail is down - skip handshake attempt
        ESP_LOGW(TAG, "✗ RFID power rail down - skipping handshake");

        xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
        rfid_state.health.is_responsive = false;
        rfid_state.health.last_error    = ESP_ERR_INVALID_STATE;
        rfid_state.state                = RFID_STATE_POWERED_OFF;
        xSemaphoreGive(rfid_state.mutex);

        return ESP_ERR_INVALID_STATE;
    }

    // Power is present - attempt handshake
    uint8_t   fw_major = 0, fw_minor = 0;
    esp_err_t ret = rfid_reader_get_firmware(&fw_major, &fw_minor);

    // Update health metrics with handshake result
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.health.last_error = ret;

    if (ret == ESP_OK)
    {
        // Handshake successful
        rfid_state.health.fw_major      = fw_major;
        rfid_state.health.fw_minor      = fw_minor;
        rfid_state.health.is_responsive = true;
        rfid_state.state                = RFID_STATE_RESPONSIVE;

        ESP_LOGI(TAG, "✓ Reader handshake successful - firmware v%d.%d", fw_major, fw_minor);

        // Return firmware version if requested
        if (major)
            *major = fw_major;
        if (minor)
            *minor = fw_minor;
    }
    else
    {
        // Handshake failed - power present but reader unresponsive
        rfid_state.health.is_responsive = false;
        rfid_state.state                = RFID_STATE_UNRESPONSIVE;

        ESP_LOGW(TAG, "✗ Reader powered but unresponsive - error: %s (0x%X)", esp_err_to_name(ret), ret);
    }

    xSemaphoreGive(rfid_state.mutex);

    if (!is_powered)
    {
        ESP_LOGI(TAG, "Powering off after standalone handshake");
        rfid_reader_power_off();
    }

    return ret;
}

rfid_reader_state_t rfid_reader_get_state(void)
{
    return rfid_state.state;
}

esp_err_t rfid_reader_get_health(rfid_health_t *health)
{
    if (!health)
    {
        return ESP_ERR_INVALID_ARG;
    }

    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    memcpy(health, &rfid_state.health, sizeof(rfid_health_t));
    xSemaphoreGive(rfid_state.mutex);

    return ESP_OK;
}

esp_err_t rfid_reader_set_power(uint8_t power_dbm)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Clamp to valid range (20-33 dBm)
    // Per section 2.1.7, page 12
    if (power_dbm < 20)
        power_dbm = 20;
    if (power_dbm > 33)
        power_dbm = 33;

    esp_err_t ret = send_command(R300_CMD_SET_POWER, &power_dbm, 1);

    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "Set power to %d dBm", power_dbm);
    }

    return ret;
}

esp_err_t rfid_reader_set_frequency_region(uint8_t region, uint8_t start_freq, uint8_t end_freq)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Per section 2.1.9, page 13
    // region: 0x01=FCC, 0x02=ETSI, 0x03=CHN
    uint8_t data[3] = {region, start_freq, end_freq};

    esp_err_t ret = send_command(R300_CMD_SET_FREQUENCY, data, 3);

    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "Set frequency region=0x%02X, range=0x%02X-0x%02X", region, start_freq, end_freq);
    }

    return ret;
}

esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback, uint32_t interval_ms)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Require the power rail to be up; reject if reader is off, uninitialized,
    // or known-unresponsive.  STARTUP_PENDING (IR poll-to-ready path) and
    // SCANNING/RESPONSIVE are all valid entry states.
    if (rfid_state.state == RFID_STATE_POWERED_OFF || rfid_state.state == RFID_STATE_UNINITIALIZED ||
        rfid_state.state == RFID_STATE_UNRESPONSIVE)
    {
        ESP_LOGE(TAG, "Cannot start inventory - reader state is %d (not ready)", rfid_state.state);
        return ESP_ERR_INVALID_STATE;
    }

    if (rfid_state.inventory_active)
    {
        ESP_LOGW(TAG, "Inventory already active");
        return ESP_OK;
    }

    // Set interval with validation
    if (interval_ms == 0)
    {
        interval_ms = DEFAULT_READ_INTERVAL_MS;
    }
    else if (interval_ms < MIN_READ_INTERVAL_MS)
    {
        ESP_LOGW(TAG, "Interval %lu ms too low, using minimum %d ms", interval_ms, MIN_READ_INTERVAL_MS);
        interval_ms = MIN_READ_INTERVAL_MS;
    }

    rfid_state.tag_callback     = callback;
    rfid_state.read_interval_ms = interval_ms;

    // Activate polling mode
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.inventory_active       = true;
    rfid_state.stats.inventory_active = true;
    // IR poll-to-ready path: rail confirmed but no handshake yet → SCANNING
    if (rfid_state.state == RFID_STATE_STARTUP_PENDING)
    {
        rfid_state.state = RFID_STATE_SCANNING;
    }
    xSemaphoreGive(rfid_state.mutex);

    ESP_LOGI(TAG, "Polling-based inventory started (interval=%lu ms)", interval_ms);

    // Send first command immediately
    send_inventory_command();

    return ESP_OK;
}

esp_err_t rfid_reader_stop_inventory(void)
{
    if (!rfid_state.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    if (!rfid_state.inventory_active)
    {
        return ESP_OK; // Already stopped
    }

    ESP_LOGI(TAG, "Stopping inventory...");

    // Set flag to stop polling
    xSemaphoreTake(rfid_state.mutex, portMAX_DELAY);
    rfid_state.inventory_active       = false;
    rfid_state.stats.inventory_active = false;
    rfid_state.tag_callback           = NULL;
    rfid_state.read_interval_ms       = 0;
    xSemaphoreGive(rfid_state.mutex);

    // Give RX task time to see the flag change
    vTaskDelay(pdMS_TO_TICKS(50));

    ESP_LOGI(TAG, "Inventory stopped");

    return ESP_OK;
}

bool rfid_reader_is_inventory_active(void)
{
    return rfid_state.inventory_active;
}

esp_err_t rfid_reader_get_stats(rfid_stats_t *stats)
{
    if (!rfid_state.initialized || !stats)
    {
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
    rfid_state.stats.total_reads   = 0;
    rfid_state.stats.errors        = 0;
    xSemaphoreGive(rfid_state.mutex);
}
