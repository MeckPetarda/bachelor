/**
 * ESP32 Attendance System - Main Application
 *
 * Integrates:
 *   - GPIO: Buttons, LEDs, RFID power control
 *   - RFID: Y300 UHF RFID reader for contactless tag detection
 *
 * GPIO Pin Assignments:
 *   - GPIO4:  LED1 — WiFi+MQTT combined indicator (green)
 *   - GPIO21: LED2 — IR mode / AP provisioning indicator (green)
 *   - GPIO26: LED3 — Active scan indicator (red)
 *   - GPIO25: LED4 — Tag activity / battery (yellow)
 *   - GPIO5:  RFID reader power control (S9013 transistor base)
 *   - GPIO22: RFID power rail sense
 *   - GPIO34: Button 1 — Scan mode control (input-only, external pull-up)
 *   - GPIO35: Button 2 — Status msg / WiFi setup (input-only, external pull-up)
 *
 * Scan Modes:
 *   IR Mode (default): IR sensor drives RFID on/off. LED2 solid on.
 *   Manual Mode: Button 1 short-press toggles RFID. LED2 off.
 *   Hold Button 1 for 3 s to toggle between modes.
 *
 * DATASHEET REFERENCES:
 * - ESP32 Datasheet: Section 4.8.1 (GPIO Interface)
 * - ESP32 TRM: Section 7.8 (UART Controller)
 * - R300 Protocol: R300_UHF_RFID_reader_module_protocol_.pdf
 */

// Uncomment to build RF debug firmware (replaces normal operation)
// #define RF_DEBUG_MODE

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
#include "esp_system.h"
#include "io_controller.h"
#include "my_mqtt_client.h"
#include "nvs_flash.h"
#include "offline_event_logger.h"
#include "rfid_reader.h"
#include "settings_storage.h"
#include "time_sync.h"
#include "wifi_manager.h"
#include "wifi_provisioning.h"

static const char *TAG = "MAIN";

// ============================================================================
// STATE TRACKING
// ============================================================================

static bool     mqtt_initialized        = false;
static uint32_t s_activity_led_off_time = 0; // Timestamp (ms) to turn off activity LED

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

    return -1; // Not a valid boolean
}

/**
 * Detect config value type from JSON payload
 *
 * @param payload JSON payload string
 * @return 's' for string, 'i' for integer, 'b' for boolean, '?' for unknown
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
        return 'b'; // Boolean
    }
    else if ((*value_start >= '0' && *value_start <= '9') || *value_start == '-')
    {
        return 'i'; // Integer
    }

    return '?';     // Unknown
}

/**
 * Handle incoming MQTT configuration messages
 *
 * Processes configuration updates received via MQTT and applies them
 * to the appropriate subsystem.
 *
 * Topic format: attendance/lighthouse/{MAC}/config/{key}
 *
 * Supported config keys:
 * - rfid/power:      Set RFID transmit power (20-33 dBm)
 * - rfid/beeper:     Set beeper mode (0=off, 1=on, 2=inventory)
 * - rfid/frequency:  Set frequency region ("FCC", "EU", "CN")
 *
 * @param topic Full MQTT topic string
 * @param payload JSON payload with value and timestamp
 */
static void on_mqtt_config_message(const char *topic, const char *payload)
{
    ESP_LOGI(TAG, "Config message received:");
    ESP_LOGI(TAG, "  Topic: %s", topic);
    ESP_LOGI(TAG, "  Payload: %s", payload);

    const char *key = extract_config_key(topic);
    if (key == NULL)
    {
        ESP_LOGW(TAG, "Could not extract config key from topic");
        return;
    }

    ESP_LOGI(TAG, "  Config key: %s", key);
    char value_type = detect_config_value_type(payload);
    ESP_LOGI(TAG, "  Value type: %c", value_type);

    // Handle RFID power configuration
    if (strcmp(key, "rfid/power") == 0)
    {
        int power_value;
        if (parse_config_int_value(payload, &power_value) == 0)
        {
            if (power_value >= 20 && power_value <= 33)
            {
                esp_err_t ret = rfid_reader_set_power((uint8_t)power_value);
                if (ret == ESP_OK)
                {
                    ESP_LOGI(TAG, "  ✓ RFID power set to %d dBm", power_value);
                }
                else
                {
                    ESP_LOGE(TAG, "  ✗ Failed to set RFID power: %s", esp_err_to_name(ret));
                }
            }
            else
            {
                ESP_LOGW(TAG, "  ✗ RFID power value out of range (20-33): %d", power_value);
            }
        }
    }
    // Handle RFID beeper configuration
    else if (strcmp(key, "rfid/beeper") == 0)
    {
        int beeper_mode;
        if (parse_config_int_value(payload, &beeper_mode) == 0)
        {
            if (beeper_mode >= 0 && beeper_mode <= 2)
            {
                esp_err_t ret = rfid_reader_set_beeper_mode((uint8_t)beeper_mode);
                if (ret == ESP_OK)
                {
                    ESP_LOGI(TAG, "  ✓ Beeper mode set to %d", beeper_mode);
                }
                else
                {
                    ESP_LOGE(TAG, "  ✗ Failed to set beeper mode: %s", esp_err_to_name(ret));
                }
            }
        }
    }
    // Handle RFID frequency region configuration
    else if (strcmp(key, "rfid/frequency") == 0)
    {
        char region_str[16];
        if (parse_config_string_value(payload, region_str, sizeof(region_str)) == 0)
        {
            uint8_t region, start_freq, end_freq;
            if (strcmp(region_str, "FCC") == 0)
            {
                region     = RFID_REGION_FCC;
                start_freq = RFID_FREQ_902MHZ;
                end_freq   = RFID_FREQ_928MHZ;
            }
            else if (strcmp(region_str, "EU") == 0)
            {
                region     = RFID_REGION_ETSI;
                start_freq = RFID_FREQ_865MHZ;
                end_freq   = RFID_FREQ_868MHZ;
            }
            else if (strcmp(region_str, "CN") == 0)
            {
                region     = RFID_REGION_CHN;
                start_freq = RFID_FREQ_920MHZ;
                end_freq   = RFID_FREQ_925MHZ;
            }
            else
            {
                ESP_LOGW(TAG, "  ✗ Unknown frequency region: %s", region_str);
                return;
            }

            esp_err_t ret = rfid_reader_set_frequency_region(region, start_freq, end_freq);
            if (ret == ESP_OK)
            {
                ESP_LOGI(TAG, "  ✓ Frequency region set to %s", region_str);
            }
            else
            {
                ESP_LOGE(TAG, "  ✗ Failed to set frequency: %s", esp_err_to_name(ret));
            }
        }
    }
    else
    {
        ESP_LOGW(TAG, "  Unknown config key: %s", key);
    }
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
    // Turn on activity LED — LED-off is handled by the main loop
    // Do NOT call vTaskDelay here — this callback runs in the UART RX task
    io_activity_led_on();
    s_activity_led_off_time = xTaskGetTickCount() * portTICK_PERIOD_MS + 50;

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

    // Always store to offline cache first (non-blocking queue write)
    esp_err_t store_ret = offline_logger_store_event(event);
    if (store_ret != ESP_OK)
    {
        ESP_LOGE(TAG, "  ✗ Failed to store event offline");
    }

    // Additionally enqueue to MQTT if connected (non-blocking via enqueue)
    if (mqtt_initialized && mqtt_client_is_connected())
    {
        esp_err_t ret = mqtt_client_publish_tag_event(event, false);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event enqueued to MQTT (cached offline: %s)", store_ret == ESP_OK ? "yes" : "no");
        }
        else
        {
            ESP_LOGW(TAG, "  ✗ Failed to enqueue tag event to MQTT (cached offline: %s)",
                     store_ret == ESP_OK ? "yes" : "no");
        }
    }
    else
    {
        ESP_LOGW(TAG, "  ⚠ MQTT not connected - event cached offline (%lu pending)",
                 offline_logger_get_pending_count());
    }
}

// ============================================================================
// HEALTH PUBLISH CALLBACK (for io_controller button2 handler)
// ============================================================================

static void publish_health_if_connected(void)
{
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
    io_set_all_leds(true);
    vTaskDelay(pdMS_TO_TICKS(500));

    // Stop RFID if active
    if (io_is_scanning())
    {
        rfid_reader_stop_inventory();
        rfid_reader_power_off();
        io_set_scanning(false);
    }

    // Publish offline status and disconnect MQTT (best effort)
    mqtt_client_disconnect();
    vTaskDelay(pdMS_TO_TICKS(1000)); // Allow disconnect to complete

    // Persist current time to NVS so next boot has an estimated lower bound
    time_sync_notify_shutdown();

    // Flush pending offline events to storage via graceful deinit
    offline_logger_deinit();

    // All LEDs off before sleep
    io_set_all_leds(false);

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

        io_process_buttons();
        io_process_ir_sensor();

        // Turn off activity LED after tag flash duration
        if (s_activity_led_off_time != 0)
        {
            uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
            if (now >= s_activity_led_off_time)
            {
                io_activity_led_off();
                s_activity_led_off_time = 0;
            }
        }

        if (io_is_combo_active())
        {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        bool wifi_connected = wifi_manager_is_connected();
        bool mqtt_connected = mqtt_initialized && mqtt_client_is_connected();

        io_update_status_leds(wifi_connected, mqtt_connected);

        // Publish health metrics every 60 seconds (if MQTT connected)
        health_publish_counter++;
        if (health_publish_counter >= HEALTH_PUBLISH_INTERVAL)
        {
            health_publish_counter = 0;

            // Update battery status before publishing (captures under-load if scanning)
            battery_monitor_update(io_is_scanning());

            if (mqtt_connected)
            {
                mqtt_client_publish_health_metrics();
            }
        }

        // Stop active RFID scan if battery has dropped to critical level
        if (io_is_scanning() && battery_monitor_is_critical())
        {
            ESP_LOGW(TAG, "Battery critical during scan - stopping RFID");
            rfid_reader_stop_inventory();
            rfid_reader_power_off();
            io_set_scanning(false);
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
    esp_err_t ret = wifi_provisioning_init(io_get_led1_pin(), io_get_led2_pin(), 10000); // 10s connection timeout
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
        io_process_buttons();

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

esp_err_t init_time_sync(const char *broker_ip)
{
    ESP_LOGI(TAG, "Initializing SNTP time synchronization (server: %s)...", broker_ip);

    esp_err_t ret = time_sync_init(broker_ip);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to initialize time sync: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without SNTP — timestamps will be boot-relative");
        return ret;
    }

    // Wait up to 5 seconds for the first SNTP sync.
    // If it times out the device continues operating; SNTP retries in background.
    time_sync_wait_for_sync(5000);

    time_quality_t quality = time_sync_get_quality();
    ESP_LOGI(TAG, "Time sync complete. Quality: %s",
             quality == TIME_QUALITY_SYNCED      ? "SYNCED"
             : quality == TIME_QUALITY_ESTIMATED ? "ESTIMATED"
                                                 : "NONE");

    return ESP_OK;
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

    // Notify provisioning system that MQTT is confirmed
    // (clears LED2 provisioning-pending state if set)
    wifi_provisioning_notify_mqtt_connected();

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

    // LED1 will be set solid by main_task once MQTT also connects;
    // interim: set it on now (WiFi connected, MQTT pending = blink in main loop)
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

    // Set maximum RF output power (25 dBm — hardware cap for YPD-R300 variant)
    // Per R300 protocol section 2.1.7, page 12
    // Hardware valid range: 20-25 dBm (spec says 20-33 but >25 returns 0x48)
    uint8_t power_level = 25;

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
#ifdef RF_DEBUG_MODE
    // Initialize NVS (required by ESP-IDF)
    esp_err_t nvs_ret = nvs_flash_init();
    if (nvs_ret == ESP_ERR_NVS_NO_FREE_PAGES || nvs_ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        nvs_flash_erase();
        nvs_flash_init();
    }

    rfid_reader_init();
    rfid_reader_power_on();
    vTaskDelay(pdMS_TO_TICKS(500));

    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║         LIGHTHOUSE RF DEBUG MODE             ║");
    ESP_LOGI(TAG, "╠══════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  WiFi/MQTT/NTP/IR — DISABLED                ║");
    ESP_LOGI(TAG, "║  Running R300 RF diagnostics only            ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    rfid_debug_power_sweep();
    vTaskDelay(pdMS_TO_TICKS(100));

    rfid_reader_set_power(25);
    vTaskDelay(pdMS_TO_TICKS(200));
    rfid_debug_get_output_power(); // Should now read 33
    vTaskDelay(pdMS_TO_TICKS(100));

    rfid_debug_get_output_power();
    vTaskDelay(pdMS_TO_TICKS(100));
    rfid_debug_get_frequency_region();
    vTaskDelay(pdMS_TO_TICKS(100));
    rfid_debug_get_work_antenna();
    vTaskDelay(pdMS_TO_TICKS(100));
    rfid_debug_get_temperature();
    vTaskDelay(pdMS_TO_TICKS(100));
    rfid_debug_get_ant_detector_status();
    vTaskDelay(pdMS_TO_TICKS(100));
    rfid_debug_set_ant_detector(true); // Enable detector before inventory
    vTaskDelay(pdMS_TO_TICKS(100));

    ESP_LOGI(TAG, "────────────────────────────────────────────────");
    rfid_debug_continuous_rssi_inventory(0xFF); // All channels, fastest mode
    // Never returns
#else
    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  ESP32 Attendance System");
    ESP_LOGI(TAG, "  with UHF RFID Reader + WiFi");
    ESP_LOGI(TAG, "════════════════════════════════════\n");

    io_init();

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

    // Initialize time sync using the MQTT broker IP as the NTP server address.
    // The same Linux machine runs both the MQTT broker and the NTP daemon (chrony).
    mqtt_broker_config_t broker_config;
    settings_storage_init();
    mqtt_settings_load(&broker_config);
    init_time_sync(broker_config.broker_ip);

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

    // Register IO callbacks
    io_set_tag_callback(on_tag_detected);
    io_set_health_callback(publish_health_if_connected);

    // Start battery status LED task (Phase 3)
    io_start_battery_led_task();

    xTaskCreate(main_task, "main_task", 4096, NULL, 5, NULL);
#endif // RF_DEBUG_MODE
}
