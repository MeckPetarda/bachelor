/**
 * ESP32 Attendance System - Main Application
 *
 * Integrates:
 *   - GPIO: Buttons, LEDs, RFID power control
 *   - RFID: Y300 UHF RFID reader for contactless tag detection
 *
 * GPIO Pin Assignments:
 *   - GPIO4:  WiFi status LED (moved from GPIO5)
 *   - GPIO5:  RFID reader power control (S9013 transistor base)
 *   - GPIO22: RFID power rail sense (moved from GPIO2 strapping pin)
 *   - GPIO18: Scanning LED
 *   - GPIO19: Activity LED
 *   - GPIO23: MQTT status LED
 *   - GPIO34: Button 1 (Start/Stop scanning)
 *   - GPIO35: Button 2 (Statistics / WiFi setup)
 *
 * Press BUTTON1 to start/stop RFID scanning
 * Press BUTTON2 to show statistics
 *
 * DATASHEET REFERENCES:
 * - ESP32 Datasheet: Section 4.8.1 (GPIO Interface)
 * - ESP32 TRM: Section 7.8 (UART Controller)
 * - R300 Protocol: R300_UHF_RFID_reader_module_protocol_.pdf
 */

#include "driver/gpio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_log_level.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "battery_monitor.h"
#include "esp_sleep.h"
#include "hal/gpio_types.h"
#include "my_mqtt_client.h"
#include "offline_event_logger.h"
#include "uart_reader.h"
#include "wifi_manager.h"
#include "wifi_provisioning.h"

// ============================================================================
// GPIO CONFIGURATION
// ============================================================================

// NOTE: GPIO5 was moved to RFID reader power control (uart_reader.c)
// WiFi status LED relocated to GPIO4 per tasks/reader_power_task.md
#define WIFI_STATUS_LED     GPIO_NUM_5  // WiFi connection status (ON = connected)
#define MQTT_STATUS_LED     GPIO_NUM_23 // MQTT broker status (ON = connected)
#define ACTIVITY_LED        GPIO_NUM_19 // Tag detection activity (flashes on detection)
#define SCANNING_LED        GPIO_NUM_18 // RFID scanning active (ON = scanning)
#define BUTTON1_PIN         GPIO_NUM_34 // Start/Stop RFID scanning
#define BUTTON2_PIN         GPIO_NUM_35 // Show statistics
#define IR_SENSOR_PIN       GPIO_NUM_25
#define IR_SCAN_DURATION_MS 5000        // Duration of IR-triggered scan burst (ms)

#define DEBOUNCE_TIME_MS 50

static const char *TAG = "MAIN";

// ============================================================================
// STATE TRACKING
// ============================================================================

typedef struct
{
    uint32_t last_press_time;
    uint8_t  last_stable_state;
    uint8_t  press_count;
} button_state_t;

static button_state_t button_states[2] = {0};
static bool           rfid_scanning    = false;
static bool           mqtt_initialized = false;

static volatile bool ir_trigger_pending  = false; // Set in ISR, cleared in main loop
static bool          ir_scan_active      = false; // true = current scan was IR-initiated
static uint32_t      ir_scan_end_time_ms = 0;     // Tick timestamp when burst should stop

// ============================================================================
// MQTT CONFIGURATION CALLBACK
// ============================================================================

/**
 * Extract config key from topic string
 *
 * Topic format: attendance/lighthouse/{MAC}/config/{key}
 * Returns pointer to key portion or NULL if not found
 */
static const char *extract_config_key(const char *topic)
{
    // Find "/config/" in the topic and return the key after it
    const char *config_marker = strstr(topic, "/config/");
    if (config_marker != NULL)
    {
        return config_marker + 8; // Skip "/config/"
    }
    return NULL;
}

/**
 * Parse integer value from config JSON payload
 *
 * Expected format: {"value": 60, "timestamp": "..."}
 *
 * @param payload JSON payload string
 * @param out_value Pointer to store parsed integer value
 * @return 0 on success, -1 on parse failure
 */
static int parse_config_int_value(const char *payload, int *out_value)
{
    const char *value_key = strstr(payload, "\"value\":");
    if (value_key == NULL)
    {
        return -1;
    }

    // Skip past "value":
    const char *value_start = value_key + 8; // strlen("\"value\":")

    // Skip whitespace
    while (*value_start == ' ')
        value_start++;

    char *end;
    long  val = strtol(value_start, &end, 10);
    if (end == value_start)
    {
        return -1; // No valid number found
    }

    *out_value = (int)val;
    return 0;
}

/**
 * Parse string value from config JSON payload
 *
 * Expected format: {"value": "some_string", "timestamp": "..."}
 *
 * @param payload JSON payload string
 * @param out_buffer Buffer to store parsed string value
 * @param buffer_size Size of output buffer
 * @return 0 on success, -1 on parse failure
 */
static int parse_config_string_value(const char *payload, char *out_buffer, size_t buffer_size)
{
    const char *value_key = strstr(payload, "\"value\":");
    if (value_key == NULL)
    {
        return -1;
    }

    // Skip past "value":
    const char *value_start = value_key + 8; // strlen("\"value\":")

    // Skip whitespace
    while (*value_start == ' ')
        value_start++;

    // Check if it's a string (starts with quote)
    if (*value_start != '"')
    {
        return -1; // Not a string value
    }

    value_start++; // Skip opening quote

    // Find closing quote
    const char *value_end = strchr(value_start, '"');
    if (value_end == NULL)
    {
        return -1; // No closing quote found
    }

    // Calculate length and copy
    size_t len = value_end - value_start;
    if (len >= buffer_size)
    {
        len = buffer_size - 1; // Truncate to fit buffer
    }

    strncpy(out_buffer, value_start, len);
    out_buffer[len] = '\0';

    return 0;
}

/**
 * Parse boolean value from config JSON payload
 *
 * Expected format: {"value": true, "timestamp": "..."} or {"value": false, ...}
 *
 * @param payload JSON payload string
 * @param out_value Pointer to store parsed boolean value
 * @return 0 on success, -1 on parse failure
 */
static int parse_config_bool_value(const char *payload, bool *out_value)
{
    const char *value_key = strstr(payload, "\"value\":");
    if (value_key == NULL)
    {
        return -1;
    }

    // Skip past "value":
    const char *value_start = value_key + 8; // strlen("\"value\":")

    // Skip whitespace
    while (*value_start == ' ')
        value_start++;

    if (strncmp(value_start, "true", 4) == 0)
    {
        *out_value = true;
        return 0;
    }
    else if (strncmp(value_start, "false", 5) == 0)
    {
        *out_value = false;
        return 0;
    }

    return -1; // Not a boolean value
}

/**
 * Detect value type in config JSON payload
 *
 * @param payload JSON payload string
 * @return 'i' for integer, 's' for string, 'b' for boolean, '?' for unknown
 */
static char detect_config_value_type(const char *payload)
{
    const char *value_key = strstr(payload, "\"value\":");
    if (value_key == NULL)
    {
        return '?';
    }

    // Skip past "value":
    const char *value_start = value_key + 8;

    // Skip whitespace
    while (*value_start == ' ')
        value_start++;

    if (*value_start == '"')
    {
        return 's'; // String
    }
    else if (*value_start == 't' || *value_start == 'f')
    {
        return 'b'; // Boolean (true/false)
    }
    else if (*value_start == '-' || (*value_start >= '0' && *value_start <= '9'))
    {
        return 'i'; // Integer/number
    }

    return '?';     // Unknown type
}

/**
 * Called when a configuration message is received from MQTT broker
 * This runs in the MQTT event handler context - keep it fast!
 *
 * Expected payload format: {"value": <value>, "timestamp": "..."}
 *
 * Uses manual string parsing (no cJSON dependency) following the existing
 * pattern of building JSON with snprintf.
 */
static void on_mqtt_config_message(const char *topic, const char *payload)
{
    ESP_LOGI(TAG, "╔════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  Configuration Message Received   ║");
    ESP_LOGI(TAG, "╠════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Topic: %s", topic);
    ESP_LOGI(TAG, "║  Payload: %s", payload);
    ESP_LOGI(TAG, "╚════════════════════════════════════╝");

    // Extract config key from topic (everything after /config/)
    const char *config_key = extract_config_key(topic);
    if (config_key == NULL)
    {
        ESP_LOGW(TAG, "Could not extract config key from topic");
        return;
    }

    // Check if payload contains "value" key
    if (strstr(payload, "\"value\":") == NULL)
    {
        ESP_LOGW(TAG, "Config payload missing 'value' field");
        return;
    }

    // Detect value type and parse accordingly
    char value_type = detect_config_value_type(payload);

    ESP_LOGI(TAG, "╔════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  Parsed Configuration              ║");
    ESP_LOGI(TAG, "╠════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Key: %s", config_key);

    switch (value_type)
    {
    case 'i': {
        int int_value;
        if (parse_config_int_value(payload, &int_value) == 0)
        {
            ESP_LOGI(TAG, "║  Value (int): %d", int_value);
        }
        else
        {
            ESP_LOGW(TAG, "║  Value: (failed to parse integer)");
        }
        break;
    }
    case 's': {
        char string_value[128];
        if (parse_config_string_value(payload, string_value, sizeof(string_value)) == 0)
        {
            ESP_LOGI(TAG, "║  Value (string): %s", string_value);
        }
        else
        {
            ESP_LOGW(TAG, "║  Value: (failed to parse string)");
        }
        break;
    }
    case 'b': {
        bool bool_value;
        if (parse_config_bool_value(payload, &bool_value) == 0)
        {
            ESP_LOGI(TAG, "║  Value (bool): %s", bool_value ? "true" : "false");
        }
        else
        {
            ESP_LOGW(TAG, "║  Value: (failed to parse boolean)");
        }
        break;
    }
    default:
        ESP_LOGW(TAG, "║  Value: (unknown or unsupported type)");
        break;
    }

    ESP_LOGI(TAG, "╚════════════════════════════════════╝");

    // TODO: Apply configuration settings based on config_key
    // This is a stub implementation - actual setting application is a future task
}

// ============================================================================
// RFID TAG CALLBACK
// ============================================================================

/**
 * Called whenever RFID reader detects a tag
 * This runs in the UART task context - keep it fast!
 */
static void on_tag_detected(const rfid_tag_event_t *event)
{
    // Flash activity LED
    gpio_set_level(ACTIVITY_LED, 1);

    // Convert RSSI to dBm (per R300 protocol: value 31-98 = -99 to -31 dBm)
    int rssi_dbm = event->rssi - 129;

    // Log tag detection with improved formatting
    ESP_LOGI(TAG, "══════════════════════════════════");
    ESP_LOGI(TAG, "  TAG DETECTED!");
    ESP_LOGI(TAG, "  EPC (%d bytes):", event->epc_len);
    printf("    ");
    for (int i = 0; i < event->epc_len; i++)
    {
        printf("%02X ", event->epc[i]);
        if ((i + 1) % 16 == 0 && i + 1 < event->epc_len)
        {
            printf("\n    "); // Line break for long EPCs
        }
    }
    printf("\n");
    ESP_LOGI(TAG, "  PC: %02X %02X", event->pc[0], event->pc[1]);
    ESP_LOGI(TAG, "  RSSI: %d dBm (raw: %d)", rssi_dbm, event->rssi);
    ESP_LOGI(TAG, "  Antenna: %d", event->antenna_id);
    ESP_LOGI(TAG, "  Frequency: %d", event->frequency);
    ESP_LOGI(TAG, "  Time: %lu ms", event->timestamp_ms);
    ESP_LOGI(TAG, "══════════════════════════════════\n");

    // Publish tag event to MQTT broker (if connected)
    if (mqtt_initialized && mqtt_client_is_connected())
    {
        esp_err_t ret = mqtt_client_publish_tag_event(event, false);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event published to MQTT broker");
        }
        else
        {
            ESP_LOGW(TAG, "  ✗ Failed to publish tag event to MQTT");
        }
    }
    else
    {
        ESP_LOGW(TAG, "  ⚠ MQTT not connected - storing event offline");
        // Store in offline logger for later transmission
        esp_err_t ret = offline_logger_store_event(event);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event stored offline (%lu pending)", offline_logger_get_pending_count());
        }
        else
        {
            ESP_LOGE(TAG, "  ✗ Failed to store event offline");
        }
    }

    // Turn off LED after brief flash
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(ACTIVITY_LED, 0);
}

// ============================================================================
// GPIO SETUP
// ============================================================================

static void IRAM_ATTR ir_sensor_isr_handler(void *arg)
{
    ir_trigger_pending = true;
    // No task notification needed — main loop polls ir_trigger_pending every 10ms
}

static void gpio_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO...");

    // Configure LEDs (output)
    gpio_config_t led_config = {
        .pin_bit_mask =
            (1ULL << WIFI_STATUS_LED) | (1ULL << MQTT_STATUS_LED) | (1ULL << ACTIVITY_LED) | (1ULL << SCANNING_LED),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&led_config);

    // Configure buttons (input-only pins)
    gpio_config_t button_config = {
        .pin_bit_mask = (1ULL << BUTTON1_PIN) | (1ULL << BUTTON2_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&button_config);

    // Configure IR sensor (GPIO26 input with pull-down, rising-edge interrupt)
    gpio_config_t ir_config = {
        .pin_bit_mask = (1ULL << IR_SENSOR_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,
        .intr_type    = GPIO_INTR_POSEDGE,
    };
    gpio_config(&ir_config);

    gpio_install_isr_service(0);
    gpio_isr_handler_add(IR_SENSOR_PIN, ir_sensor_isr_handler, NULL);

    // Initialize LED states (all OFF at startup)
    gpio_set_level(WIFI_STATUS_LED, 0);
    gpio_set_level(MQTT_STATUS_LED, 0);
    gpio_set_level(ACTIVITY_LED, 0);
    gpio_set_level(SCANNING_LED, 0);

    ESP_LOGI(TAG, "GPIO initialized");
    ESP_LOGI(TAG, "  WiFi Status LED: GPIO %d", WIFI_STATUS_LED);
    ESP_LOGI(TAG, "  MQTT Status LED: GPIO %d", MQTT_STATUS_LED);
    ESP_LOGI(TAG, "  Activity LED: GPIO %d", ACTIVITY_LED);
    ESP_LOGI(TAG, "  Scanning LED: GPIO %d", SCANNING_LED);
    ESP_LOGI(TAG, "  IR Sensor: GPIO %d (burst duration: %d ms)", IR_SENSOR_PIN, IR_SCAN_DURATION_MS);
}

static void rfid_reader_start_inventory_wrapper(void)
{
    ESP_LOGI(TAG, "Attempting to start RFID scan...");

    // Check battery level before allowing scan
    if (battery_monitor_is_critical())
    {
        ESP_LOGW(TAG, "Cannot start RFID scan - battery critical (<%dmV)", BATTERY_VOLTAGE_CRITICAL);
        // Flash scanning LED three times as error indicator
        for (int i = 0; i < 3; i++)
        {
            gpio_set_level(SCANNING_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(100));
            gpio_set_level(SCANNING_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        return;
    }

    // Step 1: Power ON the reader (if not already powered)
    if (!rfid_reader_is_powered())
    {
        ESP_LOGI(TAG, "Powering ON RFID reader...");
        esp_err_t power_ret = rfid_reader_power_on();
        if (power_ret != ESP_OK)
        {
            ESP_LOGE(TAG, "✗ Failed to power on reader: %s", esp_err_to_name(power_ret));
            return;
        }
        // Additional stabilization delay after power-on
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    // Step 2: Perform handshake to verify reader communication
    ESP_LOGI(TAG, "Performing reader handshake...");
    esp_err_t handshake_result = rfid_reader_handshake(NULL, NULL);

    if (handshake_result != ESP_OK)
    {
        ESP_LOGE(TAG, "✗ Cannot start scanning");
        ESP_LOGE(TAG, "  Handshake error: %s (0x%X)", esp_err_to_name(handshake_result), handshake_result);
        // Power off reader on handshake failure to save power
        rfid_reader_power_off();
        return;
    }

    ESP_LOGI(TAG, "✓ Reader handshake successful");

    // Step 3: Start inventory (reader is verified responsive)
    esp_err_t ret = rfid_reader_start_inventory(on_tag_detected, 0);

    if (ret == ESP_OK)
    {
        // Step 4: Only now activate scanning indicators
        gpio_set_level(SCANNING_LED, 1);
        rfid_scanning = true;
        ESP_LOGI(TAG, "✓ RFID scanning active");
    }
    else
    {
        ESP_LOGE(TAG, "✗ Failed to start inventory: %s", esp_err_to_name(ret));
        // Power off reader on inventory start failure
        rfid_reader_power_off();
    }
}

// ============================================================================
// BUTTON PROCESSING
// ============================================================================

static void process_buttons(void)
{
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

    // BUTTON1: Start/Stop RFID scanning
    {
        uint32_t        level = gpio_get_level(BUTTON1_PIN);
        button_state_t *state = &button_states[0];

        if (level == 0 && state->last_stable_state == 1)
        {
            if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS)
            {
                state->press_count++;
                state->last_press_time = current_time;

                // Toggle RFID scanning
                if (!rfid_scanning)
                {
                    rfid_reader_start_inventory_wrapper();
                }
                else
                {
                    ESP_LOGI(TAG, "Stopping RFID scan");
                    rfid_reader_stop_inventory();
                    gpio_set_level(SCANNING_LED, 0); // Turn off scanning indicator
                    rfid_scanning       = false;
                    ir_scan_active      = false;
                    ir_scan_end_time_ms = 0;

                    // Power off reader to conserve power when not scanning
                    // Per YR300 datasheet: sleep mode <100µA
                    rfid_reader_power_off();
                }
            }
        }

        state->last_stable_state = level;
    }

    // BUTTON2: Show statistics or enter setup mode (5s hold)
    {
        uint32_t        level = gpio_get_level(BUTTON2_PIN);
        button_state_t *state = &button_states[1];

        // Detect button press start (transition from released to pressed)
        if (level == 0 && state->last_stable_state == 1)
        {
            if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS)
            {
                // Record press start time
                state->last_press_time = current_time;
                // Clear setup triggered flag (high bit of press_count)
                state->press_count &= 0x7F;
            }
        }

        // Track press duration while button held (level == 0 continuously)
        if (level == 0 && state->last_stable_state == 0)
        {
            uint32_t press_duration = current_time - state->last_press_time;

            // Check for 5-second hold (only trigger once using high bit flag)
            if (press_duration >= 5000 && !(state->press_count & 0x80))
            {
                // 5s threshold crossed - enter setup mode
                ESP_LOGI(TAG, "BUTTON2 held for 5+ seconds - entering WiFi setup mode");
                state->press_count |= 0x80; // Mark that we've triggered setup

                // This function reboots the device - code below won't execute
                wifi_provisioning_setup_button_pressed();
            }
        }

        // Handle button release (transition from pressed to released)
        if (level == 1 && state->last_stable_state == 0)
        {
            uint32_t press_duration = current_time - state->last_press_time;

            // Only handle short press if we didn't trigger setup and debounce passed
            if (press_duration < 5000 && !(state->press_count & 0x80) && press_duration >= DEBOUNCE_TIME_MS)
            {
                state->press_count++;

                // Get and display statistics
                rfid_stats_t stats;
                if (rfid_reader_get_stats(&stats) == ESP_OK)
                {
                    ESP_LOGI(TAG, "═══════ RFID Statistics ═══════");
                    ESP_LOGI(TAG, "  Tags detected: %lu", stats.tags_detected);
                    ESP_LOGI(TAG, "  Total reads: %lu", stats.total_reads);
                    ESP_LOGI(TAG, "  Errors: %lu", stats.errors);
                    ESP_LOGI(TAG, "  Scanning: %s", stats.inventory_active ? "YES" : "NO");
                    ESP_LOGI(TAG, "════════════════════════════════\n");
                }

                // Publish health metrics via MQTT
                if (mqtt_client_is_connected())
                {
                    ESP_LOGI(TAG, "Publishing health metrics to MQTT...");
                    mqtt_client_publish_health_metrics();
                }
                else
                {
                    ESP_LOGW(TAG, "MQTT not connected - skipping health metrics publish");
                }
            }

            // Reset press count for next press cycle (keep low bits for potential debug)
            state->press_count = 0;
        }

        state->last_stable_state = level;
    }
}

// ============================================================================
// IR SENSOR PROCESSING
// ============================================================================

static void process_ir_sensor(void)
{
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

    // --- Trigger check ---
    if (ir_trigger_pending)
    {
        ir_trigger_pending = false;

        if (!rfid_scanning)
        {
            // No active scan — start one
            rfid_reader_start_inventory_wrapper();
            ir_scan_active      = true;
            ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS;
            ESP_LOGI(TAG, "IR trigger: scan started");
        }
        else if (ir_scan_active)
        {
            // IR-owned scan in progress — restart the timer only
            ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS;
            // ESP_LOGI(TAG, "IR trigger: burst timer restarted");
        }
        else
        {
            // Button-owned scan in progress — discard
            ESP_LOGI(TAG, "IR trigger: ignored (button scan active)");
        }
    }

    // --- Burst expiry check ---
    if (ir_scan_active && ir_scan_end_time_ms != 0 && current_time >= ir_scan_end_time_ms)
    {
        rfid_reader_stop_inventory();
        rfid_reader_power_off();
        rfid_scanning       = false;
        ir_scan_active      = false;
        ir_scan_end_time_ms = 0;
        gpio_set_level(SCANNING_LED, 0);
        ESP_LOGI(TAG, "IR burst expired: scan stopped");
    }
}

// ============================================================================
// BATTERY STATUS LED TASK (Phase 3)
// ============================================================================

/**
 * Battery status LED task
 *
 * Uses ACTIVITY_LED (GPIO19) to indicate battery level when not flashing
 * for tag detection. Patterns depend on battery percentage:
 *   - USB powered:     LED stays off (no pattern)
 *   - Battery >= 10%:  Brief 100ms flash every 5 seconds
 *   - Battery 5-10%:   Pulsing 500ms on / 500ms off
 *   - Battery < 5%:    Rapid pulsing 200ms on / 200ms off
 */
static void battery_status_led_task(void *pvParameters)
{
    const uint32_t FLASH_INTERVAL_MS = 5000;
    const uint32_t FLASH_DURATION_MS = 100;
    uint32_t       last_flash        = 0;

    while (1)
    {
        const battery_status_t *battery      = battery_monitor_get_status();
        uint32_t                current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

        if (battery->is_usb_present)
        {
            // USB powered - do not drive LED pattern
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }

        // Battery powered - show level via LED pattern
        if (battery->percentage >= 10)
        {
            // Brief flash every 5 seconds
            if ((current_time - last_flash) >= FLASH_INTERVAL_MS)
            {
                gpio_set_level(ACTIVITY_LED, 1);
                vTaskDelay(pdMS_TO_TICKS(FLASH_DURATION_MS));
                gpio_set_level(ACTIVITY_LED, 0);
                last_flash = current_time;
            }
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        else if (battery->percentage >= 5)
        {
            // Slow pulse at 500ms on / 500ms off
            gpio_set_level(ACTIVITY_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(500));
            gpio_set_level(ACTIVITY_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(500));
        }
        else
        {
            // Rapid pulse at 200ms on / 200ms off (critical warning)
            gpio_set_level(ACTIVITY_LED, 1);
            vTaskDelay(pdMS_TO_TICKS(200));
            gpio_set_level(ACTIVITY_LED, 0);
            vTaskDelay(pdMS_TO_TICKS(200));
        }
    }
}

// ============================================================================
// CRITICAL BATTERY SHUTDOWN (Phase 4)
// ============================================================================

/**
 * Execute graceful shutdown at empty battery level (<=3.2V)
 *
 * Steps:
 *   1. Flash all LEDs as visual warning
 *   2. Stop RFID scanning if active
 *   3. Publish offline status and disconnect MQTT
 *   4. Flush offline event cache via logger deinit
 *   5. Turn off all LEDs
 *   6. Enter deep sleep to preserve remaining battery
 *
 * Reference: ESP32 TRM Chapter 9 Section 9.3.5 (Brownout detector)
 * Device will restart on next power cycle (USB reconnect or battery swap).
 */
static void battery_critical_shutdown(void)
{
    ESP_LOGW(TAG, "====================================");
    ESP_LOGW(TAG, "CRITICAL BATTERY - INITIATING SHUTDOWN");
    ESP_LOGW(TAG, "====================================");

    // Flash all LEDs as warning before shutdown
    gpio_set_level(WIFI_STATUS_LED, 1);
    gpio_set_level(MQTT_STATUS_LED, 1);
    gpio_set_level(SCANNING_LED, 1);
    gpio_set_level(ACTIVITY_LED, 1);
    vTaskDelay(pdMS_TO_TICKS(500));

    // Stop RFID if active
    if (rfid_scanning)
    {
        rfid_reader_stop_inventory();
        rfid_reader_power_off();
        rfid_scanning = false;
    }

    // Publish offline status and disconnect MQTT (best effort)
    mqtt_client_disconnect();
    vTaskDelay(pdMS_TO_TICKS(1000)); // Allow disconnect to complete

    // Flush pending offline events to storage via graceful deinit
    offline_logger_deinit();

    // All LEDs off before sleep
    gpio_set_level(WIFI_STATUS_LED, 0);
    gpio_set_level(MQTT_STATUS_LED, 0);
    gpio_set_level(SCANNING_LED, 0);
    gpio_set_level(ACTIVITY_LED, 0);

    ESP_LOGW(TAG, "Entering deep sleep to preserve battery");
    ESP_LOGW(TAG, "Device will restart when USB power is reconnected");

    vTaskDelay(pdMS_TO_TICKS(100)); // Allow log buffer to flush

    // Enter deep sleep - device wakes only on power cycle
    esp_deep_sleep_start();
}

// ============================================================================
// MAIN TASK
// ============================================================================

static void main_task(void *arg)
{
    ESP_LOGI(TAG, "Main task started");

    uint32_t       health_publish_counter  = 0;
    const uint32_t HEALTH_PUBLISH_INTERVAL = 5000 / 10; // 60 seconds / 10ms delay = 6000 iterations

    while (1)
    {
        // Process WiFi provisioning state machine
        // Handles LED blinking, state transitions, connection monitoring
        wifi_provisioning_process();

        process_buttons();
        process_ir_sensor();

        // Update WiFi status LED (check every iteration)
        bool wifi_connected = wifi_manager_is_connected();
        gpio_set_level(WIFI_STATUS_LED, wifi_connected ? 1 : 0);

        // Update MQTT status LED (check every iteration)
        bool mqtt_connected = mqtt_initialized && mqtt_client_is_connected();
        gpio_set_level(MQTT_STATUS_LED, mqtt_connected ? 1 : 0);

        // Publish health metrics every 60 seconds (if MQTT connected)
        health_publish_counter++;
        if (health_publish_counter >= HEALTH_PUBLISH_INTERVAL)
        {
            health_publish_counter = 0;

            // Update battery status before publishing (captures under-load if scanning)
            battery_monitor_update(rfid_scanning);

            if (mqtt_connected)
            {
                mqtt_client_publish_health_metrics();
            }
        }

        // Stop active RFID scan if battery has dropped to critical level
        if (rfid_scanning && battery_monitor_is_critical())
        {
            ESP_LOGW(TAG, "Battery critical during scan - stopping RFID");
            rfid_reader_stop_inventory();
            rfid_reader_power_off();
            gpio_set_level(SCANNING_LED, 0);
            rfid_scanning = false;
        }

        // Check for empty battery level - initiate graceful shutdown
        const battery_status_t *battery = battery_monitor_get_status();
        if (battery->voltage_mv > 0 && battery->voltage_mv <= BATTERY_VOLTAGE_EMPTY)
        {
            battery_critical_shutdown();
            // Function never returns (enters deep sleep)
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

esp_err_t init_wifi_provisioning()
{
    ESP_LOGI(TAG, "Initializing WiFi provisioning system...");
    esp_err_t ret = wifi_provisioning_init(WIFI_STATUS_LED, 10000); // 10s connection timeout
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "WiFi provisioning initialization failed: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without provisioning support...\n");
        return ESP_ERR_NOT_SUPPORTED;
    }
    // Wait for WiFi to be ready before proceeding
    // If not configured, user must press BUTTON2 for 5 seconds to enter setup mode
    if (wifi_provisioning_is_ready())
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  WiFi Not Configured");
    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  Press BUTTON2 for 5 seconds to enter setup mode");
    ESP_LOGI(TAG, "  Current state: %s", wifi_provisioning_state_to_string(wifi_provisioning_get_state()));
    ESP_LOGI(TAG, "════════════════════════════════════\n");

    // Block here until configured or ready (AP mode, etc.)
    while (true)
    {
        wifi_provisioning_process();

        // Also process buttons so user can trigger setup mode
        process_buttons();

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

esp_err_t init_mqtt()
{

    ESP_LOGI(TAG, "Initializing MQTT client...");
    esp_err_t ret = mqtt_client_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize MQTT: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without MQTT...\n");
        return ESP_ERR_NOT_SUPPORTED;
    }
    // Mark MQTT as initialized (automatic reconnection is now active)
    mqtt_initialized = true;

    // Wait for MQTT connection (10 second timeout)
    ret = mqtt_client_wait_for_connection(10000);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "MQTT connection timeout");
        ESP_LOGW(TAG, "Broker will auto-reconnect when available");
        ESP_LOGW(TAG, "Continuing without MQTT...\n");
        return ESP_OK;
    }

    // Turn on MQTT status LED
    gpio_set_level(MQTT_STATUS_LED, 1);

    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  MQTT Connected Successfully!");
    ESP_LOGI(TAG, "════════════════════════════════════\n");

    // Subscribe to configuration topics
    ret = mqtt_client_subscribe_config(on_mqtt_config_message);
    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "Subscribed to configuration topics");
    }

    // Publish initial health metrics
    mqtt_client_publish_health_metrics();

    return ESP_OK;
}

esp_err_t init_wifi()
{

    ESP_LOGI(TAG, "Initializing WiFi...");
    esp_err_t ret = wifi_manager_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize WiFi: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without WiFi...");
        return ret;
    }

    // Wait for connection (30 second timeout)
    ret = wifi_manager_wait_for_connection(30000);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to connect to WiFi");
        ESP_LOGW(TAG, "Either it is currently unreachable or the provided credentials are incorrect. Check "
                      "SSID/password in wifi_manager.h");
        ESP_LOGW(TAG, "If the network appears later, the device will reconnect automatically");
        ESP_LOGW(TAG, "Continuing without WiFi...\n");
        return ESP_OK; // OK to continue, wifi isn't currently reachable but lighthouse can still operate until it is
                       // able to reconnect
    }

    // Turn on WiFi status LED
    gpio_set_level(WIFI_STATUS_LED, 1);

    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  WiFi Connected Successfully!");

    // Display connection information
    esp_netif_ip_info_t ip_info;
    if (wifi_manager_get_ip_info(&ip_info) == ESP_OK)
    {
        ESP_LOGI(TAG, "  IP Address: " IPSTR, IP2STR(&ip_info.ip));
        ESP_LOGI(TAG, "  Gateway: " IPSTR, IP2STR(&ip_info.gw));
        ESP_LOGI(TAG, "  Netmask: " IPSTR, IP2STR(&ip_info.netmask));
    }

    // Display signal strength
    int8_t rssi;
    if (wifi_manager_get_rssi(&rssi) == ESP_OK)
    {
        ESP_LOGI(TAG, "  Signal Strength: %d dBm", rssi);
        if (rssi >= -50)
        {
            ESP_LOGI(TAG, "  Signal Quality: Excellent");
        }
        else if (rssi >= -60)
        {
            ESP_LOGI(TAG, "  Signal Quality: Good");
        }
        else if (rssi >= -70)
        {
            ESP_LOGI(TAG, "  Signal Quality: Fair");
        }
        else
        {
            ESP_LOGI(TAG, "  Signal Quality: Poor");
        }
    }

    ESP_LOGI(TAG, "════════════════════════════════════\n");

    return ESP_OK;
}

esp_err_t init_offline_event_logger()
{
    ESP_LOGI(TAG, "Initializing offline event logger...");
    esp_err_t ret = offline_logger_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize offline logger: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without offline logging...\n");
        return ret;
    }

    return ESP_OK;
}

esp_err_t init_rfid_reader()
{
    esp_err_t ret = rfid_reader_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize RFID reader: %s", esp_err_to_name(ret));
        return ret;
    }

    // Power ON the reader before configuration
    ESP_LOGI(TAG, "Powering ON RFID reader for initial configuration...");
    ret = rfid_reader_power_on();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to power on RFID reader: %s", esp_err_to_name(ret));
        return ret;
    }

    // Additional stabilization delay after power-on
    vTaskDelay(pdMS_TO_TICKS(500));

    ESP_LOGI(TAG, "Resetting RFID reader...");
    rfid_reader_reset();
    vTaskDelay(pdMS_TO_TICKS(2000)); // Wait for restart

    ESP_LOGI(TAG, "Configuring reader for maximum range...");

    // Set maximum RF output power (33 dBm)
    // Per R300 protocol section 2.1.7, page 12
    // Valid range: 20-33 dBm
    uint8_t power_level = 33;

    ret = rfid_reader_set_power(power_level);
    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "  ✓ Power set to %d dBm", power_level);
    }
    else
    {
        ESP_LOGW(TAG, "  ✗ Failed to set power");
        return ret;
    }
    vTaskDelay(pdMS_TO_TICKS(200));

    // Set frequency region to FCC (902-928 MHz)
    // Per R300 protocol section 2.1.9, page 13
    // FCC region provides best range in USA
    // Frequency table on page 41:
    //   0x07 = 902.0 MHz
    //   0x3B = 928.0 MHz
    ret = rfid_reader_set_frequency_region(RFID_REGION_FCC, RFID_FREQ_902MHZ, RFID_FREQ_928MHZ);
    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "  ✓ Frequency set to FCC (902-928 MHz)");
    }
    else
    {
        ESP_LOGW(TAG, "  ✗ Failed to set frequency");
        return ret;
    }
    vTaskDelay(pdMS_TO_TICKS(200));

    // Power OFF reader after configuration to conserve power
    // Reader will be powered ON when user starts scanning via BUTTON1
    ESP_LOGI(TAG, "Powering OFF RFID reader until scanning requested...");
    rfid_reader_power_off();

    return ESP_OK;
}

// ============================================================================
// APPLICATION ENTRY POINT
// ============================================================================

void app_main(void)
{
    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  ESP32 Attendance System");
    ESP_LOGI(TAG, "  with UHF RFID Reader + WiFi");
    ESP_LOGI(TAG, "════════════════════════════════════\n");

    gpio_init();

    // Initialize battery monitor after GPIO (uses ADC1 and GPIO32)
    esp_err_t batt_ret = battery_monitor_init();
    if (batt_ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize battery monitor: %s", esp_err_to_name(batt_ret));
        // Non-critical - continue without battery monitoring
    }

    esp_err_t ret = init_wifi_provisioning();
    if (ret != ESP_OK)
        return;
    if (init_wifi() != ESP_OK)
        return;
    if (init_mqtt() != ESP_OK)
        return;

    if (init_offline_event_logger() != ESP_OK)
        return;
    if (init_rfid_reader() != ESP_OK)
        return;

    ESP_LOGI(TAG, "Configuration complete!\n");

    ESP_LOGI(TAG, "System ready!");
    ESP_LOGI(TAG, "  Press BUTTON1 to start/stop scanning");
    ESP_LOGI(TAG, "  Press BUTTON2 to show statistics");
    ESP_LOGI(TAG, "  RFID power control on GPIO5, sense on GPIO22\n");

    // Start battery status LED task (Phase 3)
    xTaskCreate(battery_status_led_task, "battery_led", 2048, NULL, 4, NULL);

    xTaskCreate(main_task, "main_task", 4096, NULL, 5, NULL);
}
