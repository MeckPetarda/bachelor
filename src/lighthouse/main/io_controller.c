/**
 * IO Controller — GPIO, button, LED, IR sensor, and scan-mode logic.
 *
 * Extracted from lighthouse.c to separate hardware IO from application
 * orchestration. This module owns all hardware IO state and processing.
 */

#include "io_controller.h"
#include "battery_monitor.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "offline_event_logger.h"
#include "rfid_reader.h"
#include "wifi_provisioning.h"

static const char *TAG = "IO_CTRL";

// ============================================================================
// GPIO CONFIGURATION
// ============================================================================

#define LED1_PIN     GPIO_NUM_4         // WiFi+MQTT combined indicator (green)
#define LED2_PIN     GPIO_NUM_21        // IR mode / AP provisioning indicator (green)
#define SCANNING_LED GPIO_NUM_26        // LED3 — Active scan indicator (red)
#define ACTIVITY_LED GPIO_NUM_25        // LED4 — Tag detection / battery (yellow)

#define BUTTON1_PIN GPIO_NUM_22         // Scan mode control
#define BUTTON2_PIN GPIO_NUM_23         // Status msg / WiFi setup

#define IR_SENSOR_PIN       GPIO_NUM_19 // IR presence sensor
#define IR_SCAN_DURATION_MS 5000        // Duration of IR-triggered scan burst (ms)

#define DEBOUNCE_TIME_MS 50
#define HOLD_3S_MS       3000           // 3-second hold threshold for Button 1

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

typedef struct
{
    uint32_t last_press_time;
    uint8_t  last_stable_state;
    uint8_t  press_count;
} button_state_t;

typedef enum
{
    SCAN_MODE_IR,     // default; IR sensor drives RFID on/off, LED2 solid on
    SCAN_MODE_MANUAL, // button short-press drives RFID on/off, LED2 off
} scan_mode_t;

// ============================================================================
// STATE TRACKING
// ============================================================================

static button_state_t button_states[2] = {0};
static bool           rfid_scanning    = false;

// Dual-button cache purge gesture state
static struct
{
    bool     active;           // Both buttons currently held
    uint32_t combo_start_time; // Tick time (ms) when combo was first detected
    uint8_t  leds_lit;         // Countdown LEDs currently on (0–3)
} combo_state = {0};

static bool combo_gesture_active = false;

static volatile bool ir_trigger_pending  = false; // Set in ISR, cleared in main loop
static bool          ir_scan_active      = false; // true = current scan was IR-initiated
static uint32_t      ir_scan_end_time_ms = 0;     // Tick timestamp when burst should stop

static scan_mode_t scan_mode = SCAN_MODE_IR;      // default on boot

// LED1 blink state for WiFi-no-MQTT condition
static uint32_t led1_last_toggle_ms = 0;
static uint8_t  led1_blink_state    = 0;

// Registered callbacks
static io_tag_callback_t    tag_callback    = NULL;
static io_health_callback_t health_callback = NULL;

// ============================================================================
// ISR
// ============================================================================

static void IRAM_ATTR ir_sensor_isr_handler(void *arg)
{
    ir_trigger_pending = true;
    // No task notification needed — main loop polls ir_trigger_pending every 10ms
}

// ============================================================================
// GPIO INITIALIZATION
// ============================================================================

void io_init(void)
{
    ESP_LOGI(TAG, "Initializing GPIO...");

    // Configure LEDs (output)
    gpio_config_t led_config = {
        .pin_bit_mask = (1ULL << LED1_PIN) | (1ULL << LED2_PIN) | (1ULL << ACTIVITY_LED) | (1ULL << SCANNING_LED),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&led_config);

    // Configure buttons — GPIO34/35 are input-only, no internal pull resistors
    // External pull-ups required (ESP32 DS v5.2 Section 4.8.1)
    gpio_config_t button_config = {
        .pin_bit_mask = (1ULL << BUTTON1_PIN) | (1ULL << BUTTON2_PIN),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&button_config);

    // Configure IR sensor (input-only pin, pull-down, rising-edge interrupt)
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

    // Initialize LED states — LED2 on (default IR mode), rest off
    gpio_set_level(LED1_PIN, 0);
    gpio_set_level(LED2_PIN, 1); // IR mode active by default
    gpio_set_level(ACTIVITY_LED, 0);
    gpio_set_level(SCANNING_LED, 0);

    ESP_LOGI(TAG, "GPIO initialized");
    ESP_LOGI(TAG, "  LED1 (WiFi+MQTT): GPIO %d", LED1_PIN);
    ESP_LOGI(TAG, "  LED2 (IR mode):   GPIO %d", LED2_PIN);
    ESP_LOGI(TAG, "  LED3 (Scanning):  GPIO %d", SCANNING_LED);
    ESP_LOGI(TAG, "  LED4 (Activity):  GPIO %d", ACTIVITY_LED);
    ESP_LOGI(TAG, "  IR Sensor: GPIO %d (burst duration: %d ms)", IR_SENSOR_PIN, IR_SCAN_DURATION_MS);
}

// ============================================================================
// RFID SCAN START
// ============================================================================

void io_start_rfid_scan(void)
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
    esp_err_t ret = rfid_reader_start_inventory(tag_callback, 0);

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
// SCAN MODE ENTRY HELPERS
// ============================================================================

/**
 * Stop RFID scanning if currently active and power off reader.
 * Shared by mode-transition helpers.
 */
static void stop_rfid_if_active(void)
{
    if (rfid_scanning)
    {
        rfid_reader_stop_inventory();
        rfid_reader_power_off();
        gpio_set_level(SCANNING_LED, 0);
        rfid_scanning       = false;
        ir_scan_active      = false;
        ir_scan_end_time_ms = 0;
        ESP_LOGI(TAG, "RFID stopped for mode transition");
    }
}

/**
 * Enter IR auto-scan mode.
 * 1. Stop RFID if active.
 * 2. Set scan_mode = SCAN_MODE_IR.
 * 3. Turn LED2 solid on.
 * 4. Resume handling IR trigger events (ir_trigger_pending flag cleared).
 */
static void enter_ir_mode(void)
{
    stop_rfid_if_active();
    scan_mode = SCAN_MODE_IR;
    if (!wifi_provisioning_is_led2_controlled())
    {
        gpio_set_level(LED2_PIN, 1);
    }
    ir_trigger_pending = false; // discard stale events from manual-mode window
    ESP_LOGI(TAG, "Scan mode: IR (auto)");
}

/**
 * Enter manual scan mode.
 * 1. Stop RFID if active.
 * 2. Set scan_mode = SCAN_MODE_MANUAL.
 * 3. Turn LED2 off.
 * 4. IR trigger events will be ignored while in manual mode.
 */
static void enter_manual_mode(void)
{
    stop_rfid_if_active();
    scan_mode = SCAN_MODE_MANUAL;
    if (!wifi_provisioning_is_led2_controlled())
    {
        gpio_set_level(LED2_PIN, 0);
    }
    ESP_LOGI(TAG, "Scan mode: Manual");
}

// ============================================================================
// BUTTON PROCESSING
// ============================================================================

void io_process_buttons(void)
{
    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

    // ---- Dual-button combo detection (cache purge gesture) ----
    {
        uint32_t b1 = gpio_get_level(BUTTON1_PIN);
        uint32_t b2 = gpio_get_level(BUTTON2_PIN);

        if (b1 == 0 && b2 == 0)
        {
            if (!combo_state.active)
            {
                ESP_LOGI(TAG, "Initializing combo gesture");

                // Rising edge of combo — initialise
                if (rfid_scanning)
                {
                    rfid_reader_stop_inventory();
                    rfid_reader_power_off();
                    rfid_scanning = false;
                }
                combo_gesture_active         = true;
                combo_state.active           = true;
                combo_state.combo_start_time = current_time;
                combo_state.leds_lit         = 0;
                gpio_set_level(LED1_PIN, 0);
                gpio_set_level(LED2_PIN, 0);
                gpio_set_level(ACTIVITY_LED, 0);
                gpio_set_level(SCANNING_LED, 0);
            }

            // Update countdown LEDs
            uint32_t elapsed = current_time - combo_state.combo_start_time;

            if (elapsed >= 2500 && combo_state.leds_lit < 1)
            {
                ESP_LOGI(TAG, "Combo gesture 1/4");
                gpio_set_level(LED1_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(200));
                combo_state.leds_lit = 1;
            }
            else if (elapsed >= 5000 && combo_state.leds_lit < 2)
            {
                ESP_LOGI(TAG, "Combo gesture 2/4");
                gpio_set_level(LED2_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(200));
                combo_state.leds_lit = 2;
            }
            else if (elapsed >= 7500 && combo_state.leds_lit < 3)
            {
                ESP_LOGI(TAG, "Combo gesture 3/4");
                gpio_set_level(SCANNING_LED, 1);
                vTaskDelay(pdMS_TO_TICKS(200));
                combo_state.leds_lit = 3;
            }
            else if (elapsed >= 10000 && combo_state.leds_lit < 4)
            {
                ESP_LOGI(TAG, "Combo gesture 4/4");
                gpio_set_level(ACTIVITY_LED, 1);
                vTaskDelay(pdMS_TO_TICKS(200));
                combo_state.leds_lit = 4;
            }
            else if (elapsed >= 11000)
            {
                esp_err_t ret = offline_logger_clear_all();
                if (ret == ESP_OK)
                {
                    // Confirmation flash sequence then restart
                    gpio_set_level(LED1_PIN, 0);
                    gpio_set_level(LED2_PIN, 0);
                    gpio_set_level(ACTIVITY_LED, 0);
                    gpio_set_level(SCANNING_LED, 0);

                    gpio_set_level(LED1_PIN, 1);
                    vTaskDelay(pdMS_TO_TICKS(200));
                    gpio_set_level(LED1_PIN, 0);
                    vTaskDelay(pdMS_TO_TICKS(200));

                    gpio_set_level(LED2_PIN, 1);
                    vTaskDelay(pdMS_TO_TICKS(200));
                    gpio_set_level(LED2_PIN, 0);
                    vTaskDelay(pdMS_TO_TICKS(200));

                    gpio_set_level(ACTIVITY_LED, 1);
                    vTaskDelay(pdMS_TO_TICKS(200));
                    gpio_set_level(ACTIVITY_LED, 0);
                    vTaskDelay(pdMS_TO_TICKS(200));

                    gpio_set_level(SCANNING_LED, 1);
                    vTaskDelay(pdMS_TO_TICKS(200));
                    gpio_set_level(SCANNING_LED, 0);
                    vTaskDelay(pdMS_TO_TICKS(200));

                    esp_restart();
                }
                else
                {
                    // Error flash — all four LEDs together three times
                    for (int i = 0; i < 3; i++)
                    {
                        gpio_set_level(LED1_PIN, 1);
                        gpio_set_level(LED2_PIN, 1);
                        gpio_set_level(ACTIVITY_LED, 1);
                        gpio_set_level(SCANNING_LED, 1);
                        vTaskDelay(pdMS_TO_TICKS(200));
                        gpio_set_level(LED1_PIN, 0);
                        gpio_set_level(LED2_PIN, 0);
                        gpio_set_level(ACTIVITY_LED, 0);
                        gpio_set_level(SCANNING_LED, 0);
                        vTaskDelay(pdMS_TO_TICKS(200));
                    }
                    combo_state.active   = false;
                    combo_gesture_active = false;
                    combo_state.leds_lit = 0;
                    gpio_set_level(LED1_PIN, 0);
                    gpio_set_level(LED2_PIN, 0);
                    gpio_set_level(ACTIVITY_LED, 0);
                    gpio_set_level(SCANNING_LED, 0);
                }
            }

            return;
        }
        else
        {
            if (combo_state.active)
            {
                // Gesture cancelled — restore clean state
                combo_state.active   = false;
                combo_gesture_active = false;
                combo_state.leds_lit = 0;
                gpio_set_level(LED1_PIN, 0);
                gpio_set_level(LED2_PIN, 0);
                gpio_set_level(ACTIVITY_LED, 0);
                gpio_set_level(SCANNING_LED, 0);

                return;
            }
        }
    }

    // BUTTON1: Scan mode control
    // IR mode:     short press = no-op; 3 s hold = enter manual mode
    // Manual mode: short press = toggle RFID; 3 s hold = enter IR mode
    {
        uint32_t        level = gpio_get_level(BUTTON1_PIN);
        button_state_t *state = &button_states[0];

        if (combo_state.active)
        {
            state->last_stable_state = level;
        }
        else
        {
            // Detect press start (falling edge)
            if (level == 0 && state->last_stable_state == 1)
            {
                if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS)
                {
                    state->last_press_time = current_time;
                    state->press_count &= 0x7F; // clear hold-triggered flag
                }
            }

            // Detect 3 s hold (while held)
            if (level == 0 && state->last_stable_state == 0)
            {
                uint32_t press_duration = current_time - state->last_press_time;
                if (press_duration >= HOLD_3S_MS && !(state->press_count & 0x80))
                {
                    state->press_count |= 0x80; // mark hold triggered (fire once)
                    if (scan_mode == SCAN_MODE_IR)
                    {
                        enter_manual_mode();
                    }
                    else
                    {
                        enter_ir_mode();
                    }
                }
            }

            // Detect release (rising edge) — handle short press
            if (level == 1 && state->last_stable_state == 0)
            {
                uint32_t press_duration = current_time - state->last_press_time;
                if (press_duration < HOLD_3S_MS && !(state->press_count & 0x80) && press_duration >= DEBOUNCE_TIME_MS)
                {
                    // Short press
                    if (scan_mode == SCAN_MODE_MANUAL)
                    {
                        // Toggle RFID on/off
                        if (!rfid_scanning)
                        {
                            io_start_rfid_scan();
                        }
                        else
                        {
                            ESP_LOGI(TAG, "Stopping RFID scan (manual mode)");
                            rfid_reader_stop_inventory();
                            gpio_set_level(SCANNING_LED, 0);
                            rfid_scanning       = false;
                            ir_scan_active      = false;
                            ir_scan_end_time_ms = 0;
                            rfid_reader_power_off();
                        }
                    }
                    // In IR mode: short press is a no-op (ignored)
                }
                state->press_count = 0;
            }

            state->last_stable_state = level;
        }
    }

    // BUTTON2: Show statistics or enter setup mode (5s hold)
    {
        uint32_t        level = gpio_get_level(BUTTON2_PIN);
        button_state_t *state = &button_states[1];

        if (combo_state.active)
        {
            state->last_stable_state = level;
        }
        else
        {
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

                    // Publish health metrics via callback (if registered)
                    if (health_callback)
                    {
                        health_callback();
                    }
                }

                // Reset press count for next press cycle (keep low bits for potential debug)
                state->press_count = 0;
            }

            state->last_stable_state = level;
        }
    }
}

// ============================================================================
// IR SENSOR PROCESSING
// ============================================================================

/**
 * Poll-to-ready power-on sequence for the IR trigger path.
 *
 * Calls rfid_reader_power_on() (which now returns immediately after asserting
 * GPIO5) then spins on the GPIO22 power-rail sense pin until it goes HIGH or a
 * 2000 ms timeout elapses.  On confirmation, starts inventory immediately
 * without a handshake — the actual reader boot time is logged at INFO level so
 * it can be used later to replace the loop with a single fixed delay.
 *
 * Per ESP32 TRM Section 17.3: esp_timer_get_time() returns a 64-bit
 * microsecond counter suitable for elapsed-time measurement in polling loops.
 *
 * @return true  if inventory was started successfully
 * @return false if the rail timed out or inventory start failed (reader
 *               powered off before returning)
 */
static bool ir_trigger_start_scan(void)
{
    const int64_t POLL_TIMEOUT_US = 2000LL * 1000; // 2000 ms

    // Step 1: Assert GPIO5 — returns immediately, no blocking delay.
    rfid_reader_power_on();

    // Step 2: Bounded poll on GPIO22 power-rail sense (ESP32 DS Section 4.8.1).
    int64_t start_us = esp_timer_get_time();
    while (true)
    {
        if (gpio_get_level(RFID_POWER_SENSE_PIN))
        {
            int64_t elapsed_ms = (esp_timer_get_time() - start_us) / 1000;
            ESP_LOGI(TAG, "IR trigger: power rail HIGH after %lld ms", elapsed_ms);
            break;
        }

        int64_t elapsed_us = esp_timer_get_time() - start_us;
        if (elapsed_us > POLL_TIMEOUT_US)
        {
            ESP_LOGE(TAG, "IR trigger: power rail timeout after %lld ms — aborting scan", elapsed_us / 1000);
            rfid_reader_power_off();
            return false;
        }

        vTaskDelay(pdMS_TO_TICKS(1)); // Yield to avoid starving other tasks
    }

    // Step 3: Rail confirmed — start inventory immediately, no handshake.
    esp_err_t ret = rfid_reader_start_inventory(tag_callback, 0);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "IR trigger: failed to start inventory: %s", esp_err_to_name(ret));
        rfid_reader_power_off();
        return false;
    }

    return true;
}

void io_process_ir_sensor(void)
{
    if (combo_gesture_active)
    {
        return;
    }

    uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

    // --- Trigger check ---
    if (ir_trigger_pending)
    {
        ir_trigger_pending = false;

        // Ignore IR events while in manual mode
        if (scan_mode == SCAN_MODE_MANUAL)
        {
            ESP_LOGD(TAG, "IR trigger: ignored (manual mode active)");
            goto ir_burst_check;
        }

        if (!rfid_scanning)
        {
            // No active scan — start one via poll-to-ready (no handshake on hot path)
            if (ir_trigger_start_scan())
            {
                gpio_set_level(SCANNING_LED, 1);
                rfid_scanning       = true;
                ir_scan_active      = true;
                ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS;
                ESP_LOGI(TAG, "IR trigger: scan started");
            }
        }
        else if (ir_scan_active)
        {
            // IR-owned scan in progress — restart the timer only
            ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS;
            ESP_LOGD(TAG, "IR trigger: burst timer restarted");
        }
        else
        {
            // Button-owned scan in progress — discard
            ESP_LOGI(TAG, "IR trigger: ignored (button scan active)");
        }
    }

ir_burst_check:
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
// STATUS LED UPDATE
// ============================================================================

void io_update_status_leds(bool wifi_connected, bool mqtt_connected)
{
    // Update LED1: WiFi+MQTT combined indicator
    // Off = no WiFi; blink 500ms = WiFi but no MQTT; solid = WiFi+MQTT
    {
        if (!wifi_connected)
        {
            gpio_set_level(LED1_PIN, 0);
            led1_blink_state = 0;
        }
        else if (mqtt_connected)
        {
            gpio_set_level(LED1_PIN, 1);
            led1_blink_state = 1;
        }
        else
        {
            // WiFi connected, MQTT not yet connected — blink at 500 ms
            uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
            if ((now - led1_last_toggle_ms) >= 500)
            {
                led1_blink_state    = !led1_blink_state;
                led1_last_toggle_ms = now;
                gpio_set_level(LED1_PIN, led1_blink_state);
            }
        }
    }

    // Update LED2: IR mode indicator (only when wifi_provisioning is not controlling it)
    if (!wifi_provisioning_is_led2_controlled())
    {
        gpio_set_level(LED2_PIN, scan_mode == SCAN_MODE_IR ? 1 : 0);
    }
}

// ============================================================================
// BATTERY STATUS LED TASK
// ============================================================================

/**
 * Battery status LED task
 *
 * Uses ACTIVITY_LED to indicate battery level when not flashing
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

void io_start_battery_led_task(void)
{
    xTaskCreate(battery_status_led_task, "battery_led", 2048, NULL, 4, NULL);
}

// ============================================================================
// ACTIVITY LED FLASH
// ============================================================================

void io_flash_activity_led(void)
{
    gpio_set_level(ACTIVITY_LED, 1);
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(ACTIVITY_LED, 0);
}

void io_activity_led_on(void)
{
    gpio_set_level(ACTIVITY_LED, 1);
}

void io_activity_led_off(void)
{
    gpio_set_level(ACTIVITY_LED, 0);
}

// ============================================================================
// STATE GETTERS / SETTERS
// ============================================================================

bool io_is_scanning(void)
{
    return rfid_scanning;
}

void io_set_scanning(bool active)
{
    rfid_scanning = active;
    gpio_set_level(SCANNING_LED, active ? 1 : 0);
    if (!active)
    {
        ir_scan_active      = false;
        ir_scan_end_time_ms = 0;
    }
}

bool io_is_combo_active(void)
{
    return combo_state.active;
}

void io_set_tag_callback(io_tag_callback_t cb)
{
    tag_callback = cb;
}

void io_set_health_callback(io_health_callback_t cb)
{
    health_callback = cb;
}

// ============================================================================
// LED HELPERS
// ============================================================================

void io_set_all_leds(bool state)
{
    uint32_t level = state ? 1 : 0;
    gpio_set_level(LED1_PIN, level);
    gpio_set_level(LED2_PIN, level);
    gpio_set_level(SCANNING_LED, level);
    gpio_set_level(ACTIVITY_LED, level);
}

gpio_num_t io_get_led1_pin(void)
{
    return LED1_PIN;
}

gpio_num_t io_get_led2_pin(void)
{
    return LED2_PIN;
}
