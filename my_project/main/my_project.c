/**
 * ESP32 Attendance System with RFID Reader Integration
 * 
 * Combines GPIO button/LED control with UART-based Y300 UHF RFID reader
 * for hands-free tag detection.
 * 
 * DATASHEET REFERENCES:
 * - ESP32 Series Datasheet v5.2, Section 4.8.1: GPIO Interface
 * - ESP32 Technical Reference Manual, Section 7.8: UART Controller
 * - Y300/R300 Communication Interface Specification
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_log.h"

#include "uart_reader.h"

// ============================================================================
// CONFIGURATION
// ============================================================================

#define LED1_PIN           GPIO_NUM_5      // GPIO5 - Output LED
#define LED2_PIN           GPIO_NUM_18     // GPIO18 - Output LED
#define BUTTON1_PIN        GPIO_NUM_34     // GPIO34 - Input-only button
#define BUTTON2_PIN        GPIO_NUM_35     // GPIO35 - Input-only button
#define PIR_SENSOR_PIN     GPIO_NUM_2      // GPIO2 - PIR motion sensor

#define DEBOUNCE_TIME_MS   20              // 20ms debounce window
#define PIR_DEBOUNCE_MS    100             // 100ms debounce for PIR

#define LED_PIN_MASK       ((1ULL << LED1_PIN) | (1ULL << LED2_PIN))
#define BUTTON_PIN_MASK    ((1ULL << BUTTON1_PIN) | (1ULL << BUTTON2_PIN))

static const char* TAG = "MAIN_APP";

// ============================================================================
// STATE TRACKING
// ============================================================================

typedef struct {
    uint32_t last_interrupt_time;
    uint8_t last_stable_state;
    uint8_t press_count;
} button_state_t;

typedef struct {
    uint32_t last_change_time;
    uint8_t last_stable_state;
} pir_state_t;

static button_state_t button_states[2] = {0};
static pir_state_t pir_state = {0};

// ============================================================================
// GPIO INTERRUPT HANDLERS
// ============================================================================

static void IRAM_ATTR gpio_isr_handler(void* arg)
{
    uint32_t gpio_num = (uint32_t) arg;
    uint32_t current_time = xTaskGetTickCountFromISR() * portTICK_PERIOD_MS;
    
    button_state_t* state = (gpio_num == BUTTON1_PIN) ? 
        &button_states[0] : &button_states[1];
    
    if ((current_time - state->last_interrupt_time) < DEBOUNCE_TIME_MS) {
        return;
    }
    
    state->last_interrupt_time = current_time;
}

// ============================================================================
// BUTTON AND SENSOR PROCESSING
// ============================================================================

static void process_buttons(void)
{
    static uint32_t last_sample_time = 0;
    uint32_t current_time = xTaskGetTickCountFromISR() * portTICK_PERIOD_MS;
    
    if ((current_time - last_sample_time) < 5) {
        return;
    }
    last_sample_time = current_time;
    
    // Process BUTTON1 (GPIO34)
    {
        uint32_t button_level = gpio_get_level(BUTTON1_PIN);
        button_state_t* state = &button_states[0];
        
        if ((current_time - state->last_interrupt_time) >= DEBOUNCE_TIME_MS) {
            
            if (button_level == 0 && state->last_stable_state == 1) {
                state->press_count++;
                ESP_LOGI(TAG, "BUTTON1 PRESSED (count: %d)", state->press_count);
                gpio_set_level(LED1_PIN, 1);
            }
            else if (button_level == 1 && state->last_stable_state == 0) {
                ESP_LOGI(TAG, "BUTTON1 RELEASED");
                gpio_set_level(LED1_PIN, 0);
            }
            
            state->last_stable_state = button_level;
        }
    }
    
    // Process BUTTON2 (GPIO35)
    {
        uint32_t button_level = gpio_get_level(BUTTON2_PIN);
        button_state_t* state = &button_states[1];
        
        if ((current_time - state->last_interrupt_time) >= DEBOUNCE_TIME_MS) {
            
            if (button_level == 0 && state->last_stable_state == 1) {
                state->press_count++;
                ESP_LOGI(TAG, "BUTTON2 PRESSED (count: %d)", state->press_count);
                gpio_set_level(LED2_PIN, 1);
            }
            else if (button_level == 1 && state->last_stable_state == 0) {
                ESP_LOGI(TAG, "BUTTON2 RELEASED");
                gpio_set_level(LED2_PIN, 0);
            }
            
            state->last_stable_state = button_level;
        }
    }
}

static void process_pir(void)
{
    static uint32_t last_sample_time = 0;
    uint32_t current_time = xTaskGetTickCountFromISR() * portTICK_PERIOD_MS;
    
    if ((current_time - last_sample_time) < 10) {
        return;
    }
    last_sample_time = current_time;
    
    uint32_t pir_level = gpio_get_level(PIR_SENSOR_PIN);
    
    if ((current_time - pir_state.last_change_time) >= PIR_DEBOUNCE_MS) {
        
        if (pir_level == 1 && pir_state.last_stable_state == 0) {
            ESP_LOGI(TAG, "PIR: Motion detected");
            pir_state.last_change_time = current_time;
        }
        else if (pir_level == 0 && pir_state.last_stable_state == 1) {
            ESP_LOGI(TAG, "PIR: Motion ended");
            pir_state.last_change_time = current_time;
        }
        
        pir_state.last_stable_state = pir_level;
    }
}

// ============================================================================
// GPIO INITIALIZATION
// ============================================================================

static void gpio_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO pins...");
    
    // LED output configuration
    gpio_config_t led_config = {
        .pin_bit_mask = LED_PIN_MASK,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    
    gpio_config(&led_config);
    gpio_set_level(LED1_PIN, 0);
    gpio_set_level(LED2_PIN, 0);
    
    ESP_LOGI(TAG, "LED pins configured: GPIO%d (LED1), GPIO%d (LED2)",
             LED1_PIN, LED2_PIN);
    
    // Button input configuration
    gpio_config_t button_config = {
        .pin_bit_mask = BUTTON_PIN_MASK,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_ANYEDGE,
    };
    
    gpio_config(&button_config);
    gpio_install_isr_service(0);
    gpio_isr_handler_add(BUTTON1_PIN, gpio_isr_handler, (void*) BUTTON1_PIN);
    gpio_isr_handler_add(BUTTON2_PIN, gpio_isr_handler, (void*) BUTTON2_PIN);
    
    ESP_LOGI(TAG, "Button pins configured: GPIO%d (BUTTON1), GPIO%d (BUTTON2)",
             BUTTON1_PIN, BUTTON2_PIN);
    
    // PIR sensor configuration
    gpio_config_t pir_config = {
        .pin_bit_mask = (1ULL << PIR_SENSOR_PIN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    
    gpio_config(&pir_config);
    ESP_LOGI(TAG, "PIR sensor configured: GPIO%d", PIR_SENSOR_PIN);
}

// ============================================================================
// RFID EVENT PROCESSING
// ============================================================================

/**
 * Task to monitor RFID reader event queue
 * 
 * Processes tag detection events and handles integration with attendance
 * system. Could trigger REST API calls to backend or local data logging.
 */
static void rfid_event_task(void* pvParameters)
{
    QueueHandle_t event_queue = uart_reader_get_event_queue();
    
    if (!event_queue) {
        ESP_LOGE(TAG, "Failed to get RFID event queue");
        vTaskDelete(NULL);
        return;
    }
    
    rfid_event_t event;
    
    ESP_LOGI(TAG, "RFID event task started");
    
    while (1) {
        if (xQueueReceive(event_queue, &event, pdMS_TO_TICKS(1000))) {
            switch (event.type) {
                case RFID_EVENT_TAG_READ:
                    ESP_LOGI(TAG, "Tag detected: EPC=%02X%02X%02X%02X... "
                                  "(len=%d, antenna=%d, RSSI=%d)",
                             event.tag_epc[0], event.tag_epc[1], 
                             event.tag_epc[2], event.tag_epc[3],
                             event.epc_length, event.antenna_port, event.rssi);
                    
                    // Flash LED to indicate tag detection
                    gpio_set_level(LED1_PIN, 1);
                    vTaskDelay(pdMS_TO_TICKS(100));
                    gpio_set_level(LED1_PIN, 0);
                    
                    // Here: POST tag data to backend, update database, etc.
                    // Example: http_post_attendance_event(event.tag_epc, event.epc_length);
                    break;
                    
                case RFID_EVENT_INVENTORY_COMPLETE:
                    ESP_LOGI(TAG, "Inventory scan complete");
                    break;
                    
                case RFID_EVENT_ERROR_FRAME:
                    ESP_LOGW(TAG, "RFID: Frame format error");
                    break;
                    
                case RFID_EVENT_ERROR_TIMEOUT:
                    ESP_LOGW(TAG, "RFID: Response timeout");
                    break;
                    
                case RFID_EVENT_COMM_ERROR:
                    ESP_LOGE(TAG, "RFID: Communication error");
                    break;
                    
                default:
                    ESP_LOGW(TAG, "Unknown RFID event: %d", event.type);
                    break;
            }
        }
    }
}

// ============================================================================
// MAIN APPLICATION TASK
// ============================================================================

static void app_main_task(void* pvParameters)
{
    ESP_LOGI(TAG, "Starting main application task");
    
    while (1) {
        // Process GPIO inputs
        process_buttons();
        process_pir();
        
        // Small delay to prevent CPU saturation
        // FreeRTOS ref: vTaskDelay allows other tasks to run
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

void app_main(void)
{
    ESP_LOGI(TAG, "\n\n====== ESP32 Attendance System with RFID ======");
    ESP_LOGI(TAG, "Compiled: %s %s", __DATE__, __TIME__);
    
    // Initialize GPIO (buttons, LEDs, PIR)
    gpio_init();
    
    // Initialize UART-based RFID reader
    // This creates background tasks for UART handling and event processing
    esp_err_t ret = uart_reader_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize UART reader: %s", esp_err_to_name(ret));
        return;
    }
    
    // Start RFID reader in real-time inventory mode (continuous tag detection)
    // This sends 0x89 command to reader for streaming tag data
    ret = uart_reader_start_inventory(true);  // true = real-time mode
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start inventory: %s", esp_err_to_name(ret));
    }
    
    // Create main GPIO processing task
    xTaskCreate(app_main_task, "gpio_task", 4096, NULL, 5, NULL);
    
    // Create RFID event handler task
    xTaskCreate(rfid_event_task, "rfid_event_task", 4096, NULL, 5, NULL);
    
    ESP_LOGI(TAG, "Application started successfully");
    // FreeRTOS scheduler takes over here - no return from app_main
}
