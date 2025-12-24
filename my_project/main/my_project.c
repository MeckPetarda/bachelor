/**
 * ESP32 Attendance System - Main Application
 *
 * Integrates:
 *   - GPIO: Buttons, LEDs (PIR sensor disabled - GPIO 2 used for RFID power monitoring)
 *   - RFID: Y300 UHF RFID reader for contactless tag detection
 *
 * Press BUTTON1 to start/stop RFID scanning
 * Press BUTTON2 to show statistics
 *
 * DATASHEET REFERENCES:
 * - ESP32 Datasheet: Section 4.8.1 (GPIO Interface)
 * - ESP32 TRM: Section 7.8 (UART Controller)
 * - R300 Protocol: R300_UHF_RFID_reader_module_protocol_.pdf
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_log.h"

#include "hal/gpio_types.h"
#include "uart_reader.h"
#include "wifi_manager.h"
#include "my_mqtt_client.h"
#include "offline_event_logger.h"

// ============================================================================
// GPIO CONFIGURATION
// ============================================================================

#define WIFI_STATUS_LED    GPIO_NUM_5      // WiFi connection status (ON = connected)
#define MQTT_STATUS_LED    GPIO_NUM_23     // MQTT broker status (ON = connected)
#define ACTIVITY_LED       GPIO_NUM_19     // Tag detection activity (flashes on detection)
#define SCANNING_LED       GPIO_NUM_18     // RFID scanning active (ON = scanning)
#define BUTTON1_PIN        GPIO_NUM_34     // Start/Stop RFID scanning
#define BUTTON2_PIN        GPIO_NUM_35     // Show statistics
// PIR sensor disabled - GPIO 2 now used for RFID power status monitoring
// #define PIR_SENSOR_PIN     GPIO_NUM_2      // Motion detection

#define DEBOUNCE_TIME_MS   50
// #define PIR_DEBOUNCE_MS    100

static const char* TAG = "MAIN";

// ============================================================================
// STATE TRACKING
// ============================================================================

typedef struct {
    uint32_t last_press_time;
    uint8_t last_stable_state;
    uint8_t press_count;
} button_state_t;

static button_state_t button_states[2] = {0};
static bool rfid_scanning = false;
static bool mqtt_initialized = false;

// ============================================================================
// MQTT CONFIGURATION CALLBACK
// ============================================================================

/**
 * Called when a configuration message is received from MQTT broker
 * This runs in the MQTT event handler context - keep it fast!
 */
static void on_mqtt_config_message(const char* topic, const char* payload)
{
    ESP_LOGI(TAG, "╔════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  Configuration Message Received   ║");
    ESP_LOGI(TAG, "╠════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Topic: %s", topic);
    ESP_LOGI(TAG, "║  Payload: %s", payload);
    ESP_LOGI(TAG, "╚════════════════════════════════════╝");

    // TODO: Parse and apply configuration
    // Examples:
    // - attendance/config/ESP32_ATTENDANCE_01/led -> control LED
    // - attendance/config/ESP32_ATTENDANCE_01/scan -> start/stop scanning
    // - attendance/config/ESP32_ATTENDANCE_01/power -> set RFID power level
}

// ============================================================================
// RFID TAG CALLBACK
// ============================================================================

/**
 * Called whenever RFID reader detects a tag
 * This runs in the UART task context - keep it fast!
 */
static void on_tag_detected(const rfid_tag_event_t* event)
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
    for (int i = 0; i < event->epc_len; i++) {
        printf("%02X ", event->epc[i]);
        if ((i + 1) % 16 == 0 && i + 1 < event->epc_len) {
            printf("\n    ");  // Line break for long EPCs
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
    if (mqtt_initialized && mqtt_client_is_connected()) {
        esp_err_t ret = mqtt_client_publish_tag_event(event, false);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "  ✓ Tag event published to MQTT broker");
        } else {
            ESP_LOGW(TAG, "  ✗ Failed to publish tag event to MQTT");
        }
    } else {
        ESP_LOGW(TAG, "  ⚠ MQTT not connected - storing event offline");
        // Store in offline logger for later transmission
        esp_err_t ret = offline_logger_store_event(event);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "  ✓ Tag event stored offline (%lu pending)",
                    offline_logger_get_pending_count());
        } else {
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

static void gpio_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO...");

    // Configure LEDs (output)
    gpio_config_t led_config = {
        .pin_bit_mask = (1ULL << WIFI_STATUS_LED) | (1ULL << MQTT_STATUS_LED) |
                        (1ULL << ACTIVITY_LED) | (1ULL << SCANNING_LED),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&led_config);

    // Configure buttons (input-only pins)
    gpio_config_t button_config = {
        .pin_bit_mask = (1ULL << BUTTON1_PIN) | (1ULL << BUTTON2_PIN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&button_config);

    // PIR sensor disabled - GPIO 2 now used for RFID power status monitoring in uart_reader.c
    // gpio_config_t pir_config = {
    //     .pin_bit_mask = (1ULL << PIR_SENSOR_PIN),
    //     .mode = GPIO_MODE_INPUT,
    //     .pull_up_en = GPIO_PULLUP_DISABLE,
    //     .pull_down_en = GPIO_PULLDOWN_DISABLE,
    //     .intr_type = GPIO_INTR_DISABLE,
    // };
    // gpio_config(&pir_config);

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
}

static void rfid_reader_start_inventory_wrapper(void) {
  ESP_LOGI(TAG, "Starting RFID scan...");
  gpio_set_level(SCANNING_LED, 1);  // Turn on scanning indicator
  // Use default interval of 250ms (pass 0 for default)
  rfid_reader_start_inventory(on_tag_detected, 0);
  rfid_scanning = true;
}

// ============================================================================
// BUTTON PROCESSING
// ============================================================================

static void process_buttons(void)
{
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
    
    // BUTTON1: Start/Stop RFID scanning
    {
        uint32_t level = gpio_get_level(BUTTON1_PIN);
        button_state_t* state = &button_states[0];
        
        if (level == 0 && state->last_stable_state == 1) {
            if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS) {
                state->press_count++;
                state->last_press_time = current_time;
                
                // Toggle RFID scanning
                if (!rfid_scanning) {
                    rfid_reader_start_inventory_wrapper();
                } else {
                    ESP_LOGI(TAG, "Stopping RFID scan");
                    rfid_reader_stop_inventory();
                    gpio_set_level(SCANNING_LED, 0);  // Turn off scanning indicator
                    rfid_scanning = false;
                }
            }
        }
        
        state->last_stable_state = level;
    }
    
    // BUTTON2: Show statistics
    {
        uint32_t level = gpio_get_level(BUTTON2_PIN);
        button_state_t* state = &button_states[1];
        
        if (level == 0 && state->last_stable_state == 1) {
            if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS) {
                state->press_count++;
                state->last_press_time = current_time;
                
                // Get and display statistics
                rfid_stats_t stats;
                if (rfid_reader_get_stats(&stats) == ESP_OK) {
                    ESP_LOGI(TAG, "═══════ RFID Statistics ═══════");
                    ESP_LOGI(TAG, "  Tags detected: %lu", stats.tags_detected);
                    ESP_LOGI(TAG, "  Total reads: %lu", stats.total_reads);
                    ESP_LOGI(TAG, "  Errors: %lu", stats.errors);
                    ESP_LOGI(TAG, "  Scanning: %s", stats.inventory_active ? "YES" : "NO");
                    ESP_LOGI(TAG, "════════════════════════════════\n");
                }
            }
        }
        
        state->last_stable_state = level;
    }
}

// ============================================================================
// PIR SENSOR PROCESSING (DISABLED - GPIO 2 used for RFID power monitoring)
// ============================================================================

// static void process_pir(void)
// {
//     static uint8_t last_state = 0;
//     static uint32_t last_change = 0;
//     uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
//
//     uint32_t pir_level = gpio_get_level(PIR_SENSOR_PIN);
//
//     if (pir_level != last_state &&
//         (current_time - last_change) >= PIR_DEBOUNCE_MS) {
//
//         last_state = pir_level;
//         last_change = current_time;
//
//         if (pir_level == 1) {
//             ESP_LOGI(TAG, "Motion detected!");
//
//             // Auto-start RFID scanning on motion
//             // if (!rfid_scanning) {
//             //     ESP_LOGI(TAG, "Auto-starting RFID scan due to motion");
//             //     rfid_reader_start_inventory_wrapper();
//             // }
//         } else {
//             ESP_LOGI(TAG, "Motion stopped");
//         }
//     }
// }

// ============================================================================
// MAIN TASK
// ============================================================================

static void main_task(void* arg)
{
    ESP_LOGI(TAG, "Main task started");

    uint32_t health_publish_counter = 0;
    const uint32_t HEALTH_PUBLISH_INTERVAL = 60000 / 10;  // 60 seconds / 10ms delay = 6000 iterations

    while (1) {
        process_buttons();
        // process_pir();  // Disabled - GPIO 2 used for RFID power monitoring

        // Update WiFi status LED (check every iteration)
        bool wifi_connected = wifi_manager_is_connected();
        gpio_set_level(WIFI_STATUS_LED, wifi_connected ? 1 : 0);

        // Update MQTT status LED (check every iteration)
        bool mqtt_connected = mqtt_initialized && mqtt_client_is_connected();
        gpio_set_level(MQTT_STATUS_LED, mqtt_connected ? 1 : 0);

        // Publish health metrics every 60 seconds (if MQTT connected)
        health_publish_counter++;
        if (health_publish_counter >= HEALTH_PUBLISH_INTERVAL) {
            health_publish_counter = 0;

            if (mqtt_connected) {
                mqtt_client_publish_health_metrics();
            }
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
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

    // ============================================================================
    // INITIALIZE OFFLINE EVENT LOGGER
    // ============================================================================

    ESP_LOGI(TAG, "Initializing offline event logger...");
    esp_err_t ret = offline_logger_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize offline logger: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without offline logging...\n");
    }

    // Initialize GPIO
    gpio_init();

    // ============================================================================
    // INITIALIZE WIFI (PoC)
    // ============================================================================

    ESP_LOGI(TAG, "Initializing WiFi...");
    ret = wifi_manager_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize WiFi: %s", esp_err_to_name(ret));
        ESP_LOGW(TAG, "Continuing without WiFi...");
    } else {
        // Wait for connection (30 second timeout)
        ret = wifi_manager_wait_for_connection(30000);
        if (ret == ESP_OK) {
            // Turn on WiFi status LED
            gpio_set_level(WIFI_STATUS_LED, 1);

            ESP_LOGI(TAG, "════════════════════════════════════");
            ESP_LOGI(TAG, "  WiFi Connected Successfully!");

            // Display connection information
            esp_netif_ip_info_t ip_info;
            if (wifi_manager_get_ip_info(&ip_info) == ESP_OK) {
                ESP_LOGI(TAG, "  IP Address: " IPSTR, IP2STR(&ip_info.ip));
                ESP_LOGI(TAG, "  Gateway: " IPSTR, IP2STR(&ip_info.gw));
                ESP_LOGI(TAG, "  Netmask: " IPSTR, IP2STR(&ip_info.netmask));
            }

            // Display signal strength
            int8_t rssi;
            if (wifi_manager_get_rssi(&rssi) == ESP_OK) {
                ESP_LOGI(TAG, "  Signal Strength: %d dBm", rssi);
                if (rssi >= -50) {
                    ESP_LOGI(TAG, "  Signal Quality: Excellent");
                } else if (rssi >= -60) {
                    ESP_LOGI(TAG, "  Signal Quality: Good");
                } else if (rssi >= -70) {
                    ESP_LOGI(TAG, "  Signal Quality: Fair");
                } else {
                    ESP_LOGI(TAG, "  Signal Quality: Poor");
                }
            }

            ESP_LOGI(TAG, "════════════════════════════════════\n");

            // ================================================================
            // INITIALIZE MQTT (PoC)
            // ================================================================

            ESP_LOGI(TAG, "Initializing MQTT client...");
            ret = mqtt_client_init();
            if (ret != ESP_OK) {
                ESP_LOGE(TAG, "Failed to initialize MQTT: %s", esp_err_to_name(ret));
                ESP_LOGW(TAG, "Continuing without MQTT...\n");
            } else {
                // Mark MQTT as initialized (automatic reconnection is now active)
                mqtt_initialized = true;

                // Wait for MQTT connection (10 second timeout)
                ret = mqtt_client_wait_for_connection(10000);
                if (ret == ESP_OK) {
                    // Turn on MQTT status LED
                    gpio_set_level(MQTT_STATUS_LED, 1);

                    ESP_LOGI(TAG, "════════════════════════════════════");
                    ESP_LOGI(TAG, "  MQTT Connected Successfully!");
                    ESP_LOGI(TAG, "════════════════════════════════════\n");

                    // Subscribe to configuration topics
                    ret = mqtt_client_subscribe_config(on_mqtt_config_message);
                    if (ret == ESP_OK) {
                        ESP_LOGI(TAG, "Subscribed to configuration topics");
                    }

                    // Publish initial health metrics
                    mqtt_client_publish_health_metrics();
                } else {
                    ESP_LOGW(TAG, "MQTT connection timeout");
                    ESP_LOGW(TAG, "Broker will auto-reconnect when available");
                    ESP_LOGW(TAG, "Continuing without MQTT...\n");
                }
            }
        } else {
            ESP_LOGW(TAG, "Failed to connect to WiFi");
            ESP_LOGW(TAG, "Check SSID/password in wifi_manager.h");
            ESP_LOGW(TAG, "Continuing without WiFi...\n");
        }
    }

    // ============================================================================

    // Initialize RFID reader
    ret = rfid_reader_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize RFID reader: %s",
                 esp_err_to_name(ret));
        return;
    }
    
    // Small delay for module to stabilize
    vTaskDelay(pdMS_TO_TICKS(500));
    
    // Optional: Reset reader on startup
    ESP_LOGI(TAG, "Resetting RFID reader...");
    rfid_reader_reset();
    vTaskDelay(pdMS_TO_TICKS(2000));  // Wait for restart
    
    // Optional: Get firmware version
    uint8_t major, minor;
    if (rfid_reader_get_firmware(&major, &minor) == ESP_OK) {
        ESP_LOGI(TAG, "RFID Reader Firmware: %d.%d\n", major, minor);
    }
    
    // ============================================================================
    // CONFIGURE READER FOR MAXIMUM RANGE
    // ============================================================================
    
    ESP_LOGI(TAG, "Configuring reader for maximum range...");
    
    // Set maximum RF output power (33 dBm)
    // Per R300 protocol section 2.1.7, page 12
    // Valid range: 20-33 dBm
    
    uint8_t power_level = 33;

    ret = rfid_reader_set_power(power_level);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "  ✓ Power set to %d dBm", power_level);
    } else {
        ESP_LOGW(TAG, "  ✗ Failed to set power");
    }
    vTaskDelay(pdMS_TO_TICKS(200));
    
    // Set frequency region to FCC (902-928 MHz)
    // Per R300 protocol section 2.1.9, page 13
    // FCC region provides best range in USA
    // Frequency table on page 41:
    //   0x07 = 902.0 MHz
    //   0x3B = 928.0 MHz
    ret = rfid_reader_set_frequency_region(RFID_REGION_FCC, 
                                          RFID_FREQ_902MHZ, 
                                          RFID_FREQ_928MHZ);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "  ✓ Frequency set to FCC (902-928 MHz)");
    } else {
        ESP_LOGW(TAG, "  ✗ Failed to set frequency");
    }
    vTaskDelay(pdMS_TO_TICKS(200));
    
    ESP_LOGI(TAG, "Configuration complete!\n");
    
    // ============================================================================
    
    ESP_LOGI(TAG, "System ready!");
    ESP_LOGI(TAG, "  Press BUTTON1 to start/stop scanning");
    ESP_LOGI(TAG, "  Press BUTTON2 to show statistics");
    ESP_LOGI(TAG, "  RFID power monitoring active on GPIO 2\n");
    
    // Start main task
    xTaskCreate(main_task, "main_task", 4096, NULL, 5, NULL);
}
