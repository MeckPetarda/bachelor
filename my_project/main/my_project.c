/**
 * ESP32 GPIO Button and LED Control with Debounced Interrupts
 * 
 * DATASHEET REFERENCES:
 * - ESP32 Series Datasheet v5.2, Section 4.8.1: General Purpose Input/Output Interface (GPIO)
 *   - 34 GPIO pins available (GPIO0-GPIO39, excluding certain restricted pins)
 *   - Pins have configurable pull-up/pull-down (~45 kΩ resistance per Table 5-3)
 *   - Level and edge trigger interrupt generation supported
 * - Section 2.3 IO Pins: Restrictions on GPIO usage (input-only pins: GPIO34-39)
 * - Section 4.4: General Purpose Timers for debounce timing
 * 
 * PIN MAPPING (Hornaxys Devboard):
 * - LED1: GPIO5  (VDD3P3_CPU domain per Table IO_MUX)
 * - LED2: GPIO18 (VDD3P3_CPU domain)
 * - BUTTON1: GPIO34 (input-only, RTC_GPIO4 - VDET_1 per Table 2-1)
 * - BUTTON2: GPIO35 (input-only, RTC_GPIO5 - VDET_2 per Table 2-1)
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_log.h"

// ============================================================================
// CONFIGURATION
// ============================================================================

#define LED1_PIN           GPIO_NUM_5      // GPIO5 - Output LED
#define LED2_PIN           GPIO_NUM_18     // GPIO18 - Output LED
#define BUTTON1_PIN        GPIO_NUM_34     // GPIO34 - Input-only button
#define BUTTON2_PIN        GPIO_NUM_35     // GPIO35 - Input-only button

#define DEBOUNCE_TIME_MS   20              // 20ms debounce window
#define LONG_PRESS_TIME_MS 1000            // 1 second = long press

// Bitmask for LED pins (GPIO5 and GPIO18)
#define LED_PIN_MASK       ((1ULL << LED1_PIN) | (1ULL << LED2_PIN))

// Bitmask for button input pins (GPIO34, GPIO35)
// Note: GPIO34-39 are input-only, have no internal pull-up/pull-down
#define BUTTON_PIN_MASK    ((1ULL << BUTTON1_PIN) | (1ULL << BUTTON2_PIN))

static const char* TAG = "GPIO_APP";

// ============================================================================
// STATE TRACKING
// ============================================================================

typedef struct {
    uint32_t last_interrupt_time;  // Timestamp of last interrupt (milliseconds)
    uint8_t last_stable_state;     // Last debounced state (0 = released, 1 = pressed)
    uint8_t press_count;           // Number of presses
} button_state_t;

static button_state_t button_states[2] = {0};  // Track state for each button

// ============================================================================
// ISR CONTEXT - Fast interrupt handler
// ============================================================================

/**
 * GPIO Interrupt Handler
 * Called when GPIO34 or GPIO35 transitions (falling edge = button press)
 * 
 * DATASHEET REFERENCE:
 * - Section 4.8.1: "Edge-trigger or level-trigger to generate CPU interrupts"
 * - ISR should complete quickly; debouncing logic deferred to timer
 */
static void IRAM_ATTR gpio_isr_handler(void* arg)
{
    uint32_t gpio_num = (uint32_t) arg;
    uint32_t current_time = xTaskGetTickCountFromISR() * portTICK_PERIOD_MS;
    
    button_state_t* state = (gpio_num == BUTTON1_PIN) ? 
        &button_states[0] : &button_states[1];
    
    // Ignore if still within debounce window
    if ((current_time - state->last_interrupt_time) < DEBOUNCE_TIME_MS) {
        return;
    }
    
    // Store interrupt time for next debounce check
    state->last_interrupt_time = current_time;
}

// ============================================================================
// DEBOUNCE AND LOGIC PROCESSING
// ============================================================================

/**
 * Process button states with debouncing
 * Called periodically from main task to sample and filter button inputs
 * 
 * This uses a simple state machine approach:
 * 1. Read current GPIO level
 * 2. If stable for debounce window, register as new state
 * 3. Detect state transitions for press/release events
 */
static void process_buttons(void)
{
    static uint32_t last_sample_time = 0;
    uint32_t current_time = xTaskGetTickCountFromISR() * portTICK_PERIOD_MS;
    
    // Sample buttons at regular intervals (every 5ms between edge detection)
    if ((current_time - last_sample_time) < 5) {
        return;
    }
    last_sample_time = current_time;
    
    // Process BUTTON1 (GPIO34)
    {
        uint32_t button_level = gpio_get_level(BUTTON1_PIN);
        button_state_t* state = &button_states[0];
        
        // Debounce: if state has been stable for debounce window
        if ((current_time - state->last_interrupt_time) >= DEBOUNCE_TIME_MS) {
            
            // Detect press (transition from 1 to 0, since input-only pins read directly)
            if (button_level == 0 && state->last_stable_state == 1) {
                state->press_count++;
                ESP_LOGI(TAG, "BUTTON1 PRESSED (count: %d)", state->press_count);
                gpio_set_level(LED1_PIN, 1);  // Turn on LED1
            }
            // Detect release (transition from 0 to 1)
            else if (button_level == 1 && state->last_stable_state == 0) {
                ESP_LOGI(TAG, "BUTTON1 RELEASED");
                gpio_set_level(LED1_PIN, 0);  // Turn off LED1
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
                gpio_set_level(LED2_PIN, 1);  // Turn on LED2
            }
            else if (button_level == 1 && state->last_stable_state == 0) {
                ESP_LOGI(TAG, "BUTTON2 RELEASED");
                gpio_set_level(LED2_PIN, 0);  // Turn off LED2
            }
            
            state->last_stable_state = button_level;
        }
    }
}

// ============================================================================
// GPIO CONFIGURATION
// ============================================================================

/**
 * Initialize GPIO pins for LEDs and buttons
 * 
 * DATASHEET REFERENCES:
 * - Table 4-6 Peripheral Pin Configurations: GPIO5 and GPIO18 support I/O/T
 * - Table 2-1 Pin Overview: GPIO34/35 are input-only (no output driver)
 * - Section 2.3.1 Restrictions: "GPIO 34-39 are input-only pins"
 */
static void gpio_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO pins...");
    
    // ========== LED OUTPUT CONFIGURATION ==========
    // LED1 (GPIO5) and LED2 (GPIO18) as outputs
    
    gpio_config_t led_config = {
        .pin_bit_mask = LED_PIN_MASK,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,    // No pull-up needed for outputs
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,       // No interrupts for outputs
    };
    
    gpio_config(&led_config);
    
    // Initialize LED pins to OFF (low level)
    gpio_set_level(LED1_PIN, 0);
    gpio_set_level(LED2_PIN, 0);
    
    ESP_LOGI(TAG, "LED pins configured: GPIO%d (LED1), GPIO%d (LED2)",
             LED1_PIN, LED2_PIN);
    
    // ========== BUTTON INPUT CONFIGURATION ==========
    // BUTTON1 (GPIO34) and BUTTON2 (GPIO35) as inputs with interrupts
    
    // NOTE: GPIO34 and GPIO35 are input-only and do NOT have internal pull-up/pull-down
    // See Datasheet Section 2.3.1 and Table 2-1
    // External pull-up resistors (10k) should be connected to 3.3V
    // When button pressed, pin goes LOW (GND)
    
    gpio_config_t button_config = {
        .pin_bit_mask = BUTTON_PIN_MASK,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,     // GPIO34/35 have no pull-up capability
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_ANYEDGE,        // Trigger on both rising and falling edges
    };
    
    gpio_config(&button_config);
    
    // Install ISR service for GPIO interrupts
    gpio_install_isr_service(0);  // Flags: 0 = no special flags
    
    // Register ISR handlers
    // When GPIO34 or GPIO35 transition, call gpio_isr_handler
    gpio_isr_handler_add(BUTTON1_PIN, gpio_isr_handler, (void*) BUTTON1_PIN);
    gpio_isr_handler_add(BUTTON2_PIN, gpio_isr_handler, (void*) BUTTON2_PIN);
    
    ESP_LOGI(TAG, "Button pins configured: GPIO%d (BUTTON1), GPIO%d (BUTTON2)",
             BUTTON1_PIN, BUTTON2_PIN);
    ESP_LOGI(TAG, "NOTE: Requires external 10kΩ pull-up resistors to 3.3V on input pins");
}

// ============================================================================
// MAIN APPLICATION TASK
// ============================================================================

static void app_main_task(void* pvParameters)
{
    ESP_LOGI(TAG, "Starting GPIO Button/LED application");
    ESP_LOGI(TAG, "Press buttons to toggle LEDs");
    
    while (1) {
        // Process button states (debounce and logic)
        process_buttons();
        
        // Small delay to prevent CPU saturation
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

void app_main(void)
{
    ESP_LOGI(TAG, "\n\n====== ESP32 GPIO Button/LED Demo ======");
    ESP_LOGI(TAG, "Compiled: %s %s", __DATE__, __TIME__);
    
    // Initialize GPIO pins
    gpio_init();
    
    // Create main task
    xTaskCreate(app_main_task, "gpio_task", 4096, NULL, 5, NULL);
    
    ESP_LOGI(TAG, "Application started successfully");
}
