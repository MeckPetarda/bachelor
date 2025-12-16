/**
 * ESP32 Attendance System - Main Application
 * 
 * Integrates:
 *   - GPIO: Buttons, LEDs, PIR sensor
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

#include "uart_reader.h"

// ============================================================================
// GPIO CONFIGURATION
// ============================================================================

#define LED1_PIN           GPIO_NUM_5      // Status LED
#define LED2_PIN           GPIO_NUM_18     // Activity LED
#define BUTTON1_PIN        GPIO_NUM_34     // Start/Stop RFID scanning
#define BUTTON2_PIN        GPIO_NUM_35     // Show statistics
#define PIR_SENSOR_PIN     GPIO_NUM_2      // Motion detection

#define DEBOUNCE_TIME_MS   50
#define PIR_DEBOUNCE_MS    100

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
    gpio_set_level(LED2_PIN, 1);
    
    // Log tag detection
    ESP_LOGI(TAG, "══════════════════════════════════");
    ESP_LOGI(TAG, "  TAG DETECTED!");
    ESP_LOGI(TAG, "  EPC: ");
    printf("    ");
    for (int i = 0; i < event->epc_len; i++) {
        printf("%02X ", event->epc[i]);
    }
    printf("\n");
    ESP_LOGI(TAG, "  RSSI: %d dBm", event->rssi - 129);  // Convert to dBm
    ESP_LOGI(TAG, "  Antenna: %d", event->antenna_id);
    ESP_LOGI(TAG, "  Time: %d ms", event->timestamp_ms);
    ESP_LOGI(TAG, "══════════════════════════════════\n");
    
    // Turn off LED after brief flash
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(LED2_PIN, 0);
    
    // TODO: Send to Navigo3 via REST API
    // TODO: Store in local database if offline
}

// ============================================================================
// GPIO SETUP
// ============================================================================

static void gpio_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO...");
    
    // Configure LEDs (output)
    gpio_config_t led_config = {
        .pin_bit_mask = (1ULL << LED1_PIN) | (1ULL << LED2_PIN),
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
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&button_config);
    
    // Configure PIR sensor (input)
    gpio_config_t pir_config = {
        .pin_bit_mask = (1ULL << PIR_SENSOR_PIN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&pir_config);
    
    // Initialize LED states
    gpio_set_level(LED1_PIN, 0);
    gpio_set_level(LED2_PIN, 0);
    
    ESP_LOGI(TAG, "GPIO initialized");
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
                    ESP_LOGI(TAG, "Starting RFID scan...");
                    gpio_set_level(LED1_PIN, 1);
                    rfid_reader_start_inventory(on_tag_detected);
                    rfid_scanning = true;
                } else {
                    ESP_LOGI(TAG, "Stopping RFID scan");
                    rfid_reader_stop_inventory();
                    gpio_set_level(LED1_PIN, 0);
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
                    ESP_LOGI(TAG, "  Tags detected: %d", stats.tags_detected);
                    ESP_LOGI(TAG, "  Total reads: %d", stats.total_reads);
                    ESP_LOGI(TAG, "  Errors: %d", stats.errors);
                    ESP_LOGI(TAG, "  Scanning: %s", stats.inventory_active ? "YES" : "NO");
                    ESP_LOGI(TAG, "════════════════════════════════\n");
                }
            }
        }
        
        state->last_stable_state = level;
    }
}

// ============================================================================
// PIR SENSOR PROCESSING
// ============================================================================

static void process_pir(void)
{
    static uint8_t last_state = 0;
    static uint32_t last_change = 0;
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
    
    uint32_t pir_level = gpio_get_level(PIR_SENSOR_PIN);
    
    if (pir_level != last_state && 
        (current_time - last_change) >= PIR_DEBOUNCE_MS) {
        
        last_state = pir_level;
        last_change = current_time;
        
        if (pir_level == 1) {
            ESP_LOGI(TAG, "Motion detected!");
            
            // Auto-start RFID scanning on motion
            if (!rfid_scanning) {
                ESP_LOGI(TAG, "Auto-starting RFID scan due to motion");
                gpio_set_level(LED1_PIN, 1);
                rfid_reader_start_inventory(on_tag_detected);
                rfid_scanning = true;
            }
        } else {
            ESP_LOGI(TAG, "Motion stopped");
        }
    }
}

// ============================================================================
// MAIN TASK
// ============================================================================

static void main_task(void* arg)
{
    ESP_LOGI(TAG, "Main task started");
    
    while (1) {
        process_buttons();
        process_pir();
        
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
    ESP_LOGI(TAG, "  with UHF RFID Reader");
    ESP_LOGI(TAG, "════════════════════════════════════\n");
    
    // Initialize GPIO
    gpio_init();
    
    // Initialize RFID reader
    esp_err_t ret = rfid_reader_init();
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
    
    ESP_LOGI(TAG, "System ready!");
    ESP_LOGI(TAG, "  Press BUTTON1 to start/stop scanning");
    ESP_LOGI(TAG, "  Press BUTTON2 to show statistics");
    ESP_LOGI(TAG, "  PIR sensor enables auto-scanning\n");
    
    // Start main task
    xTaskCreate(main_task, "main_task", 4096, NULL, 5, NULL);
}
