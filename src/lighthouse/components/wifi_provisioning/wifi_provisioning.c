/**
 * wifi_provisioning.c - WiFi Provisioning State Machine Implementation
 *
 * Implements the provisioning state machine with:
 * - Boot state detection and initialization
 * - Setup mode entry via 5-second button press
 * - LED blinking control during AP mode
 * - State transitions and event handling
 *
 * Reference:
 * - WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2
 * - ESP-IDF GPIO and Timer documentation
 */

#include <string.h>
#include "wifi_provisioning.h"
#include "wifi_settings_storage.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "nvs_flash.h"
#include "nvs.h"

static const char* TAG = "WIFI_PROV";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define LED_BLINK_INTERVAL_MS   1000    // LED toggle interval during AP mode
#define SETUP_FLAG_NVS_KEY      "setup_req"  // NVS key for setup request flag
#define NVS_NAMESPACE           "wifi_prov"  // NVS namespace for provisioning flags

// ============================================================================
// STATE MACHINE DATA
// ============================================================================

typedef struct {
    // Core state
    wifi_state_t current_state;
    wifi_event_t pending_event;

    // Timing
    uint32_t state_enter_time_ms;
    uint32_t connection_timeout_ms;

    // LED control
    gpio_num_t led_pin;
    uint32_t led_blink_interval_ms;
    uint32_t last_led_toggle_ms;
    uint8_t led_state;

    // Pending credentials during setup (from HTTP form)
    char pending_ssid[32];
    char pending_password[64];
    bool credentials_pending;

    // Connection result
    bool connection_result_ready;
    bool connection_success;
    char error_message[128];

    // Flags
    bool initialized;
    bool setup_requested;
} wifi_provisioning_state_t;

static wifi_provisioning_state_t prov_state = {0};

// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

/**
 * Get current time in milliseconds
 */
static uint32_t get_time_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

/**
 * Transition to new state with logging
 */
static void transition_to(wifi_state_t new_state)
{
    if (prov_state.current_state == new_state) {
        return;  // No transition needed
    }

    ESP_LOGI(TAG, "State transition: %s -> %s",
             wifi_provisioning_state_to_string(prov_state.current_state),
             wifi_provisioning_state_to_string(new_state));

    prov_state.current_state = new_state;
    prov_state.state_enter_time_ms = get_time_ms();

    // Reset LED state on transition
    prov_state.last_led_toggle_ms = get_time_ms();
    prov_state.led_state = 0;
    gpio_set_level(prov_state.led_pin, 0);
}

/**
 * Check if setup mode was requested on previous boot
 * Uses NVS to persist the flag across reboots
 */
static bool check_setup_requested(void)
{
    nvs_handle_t nvs_handle;
    esp_err_t ret = nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs_handle);

    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        // Namespace doesn't exist yet - no setup requested
        return false;
    } else if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to open NVS for setup flag: %s", esp_err_to_name(ret));
        return false;
    }

    uint8_t setup_flag = 0;
    ret = nvs_get_u8(nvs_handle, SETUP_FLAG_NVS_KEY, &setup_flag);
    nvs_close(nvs_handle);

    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        return false;
    } else if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to read setup flag: %s", esp_err_to_name(ret));
        return false;
    }

    return (setup_flag == 1);
}

/**
 * Set setup requested flag in NVS (persists across reboot)
 */
static esp_err_t set_setup_requested(bool requested)
{
    nvs_handle_t nvs_handle;
    esp_err_t ret = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for setup flag: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = nvs_set_u8(nvs_handle, SETUP_FLAG_NVS_KEY, requested ? 1 : 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write setup flag: %s", esp_err_to_name(ret));
        nvs_close(nvs_handle);
        return ret;
    }

    ret = nvs_commit(nvs_handle);
    nvs_close(nvs_handle);

    return ret;
}

/**
 * Clear setup requested flag (after entering AP mode)
 */
static void clear_setup_requested(void)
{
    set_setup_requested(false);
}

/**
 * Process LED blinking for current state
 * Only blinks during AP_ACTIVE state
 */
static void process_led(void)
{
    if (prov_state.current_state != WIFI_STATE_AP_ACTIVE) {
        // LED off in non-AP states (or controlled by other logic)
        return;
    }

    uint32_t now = get_time_ms();
    uint32_t elapsed = now - prov_state.last_led_toggle_ms;

    if (elapsed >= prov_state.led_blink_interval_ms) {
        // Toggle LED
        prov_state.led_state = !prov_state.led_state;
        gpio_set_level(prov_state.led_pin, prov_state.led_state);
        prov_state.last_led_toggle_ms = now;
    }
}

/**
 * Process UNCONFIGURED state
 * Waiting for user to press setup button
 */
static void process_unconfigured(void)
{
    // Nothing to do - just waiting for button press
    // Button handler will trigger setup mode entry
}

/**
 * Process AP_ACTIVE state
 * Serving provisioning page, waiting for credentials
 */
static void process_ap_active(void)
{
    // LED blinking is handled in process_led()

    // Check if credentials were submitted
    if (prov_state.credentials_pending) {
        ESP_LOGI(TAG, "Credentials received, transitioning to CONNECTING");
        prov_state.credentials_pending = false;
        transition_to(WIFI_STATE_CONNECTING);
    }
}

/**
 * Process CONNECTING state
 * Attempting WiFi connection with provided credentials
 */
static void process_connecting(void)
{
    // Check if connection result is ready
    if (prov_state.connection_result_ready) {
        prov_state.connection_result_ready = false;

        if (prov_state.connection_success) {
            ESP_LOGI(TAG, "Connection successful!");
            transition_to(WIFI_STATE_CONNECTED);
        } else {
            ESP_LOGW(TAG, "Connection failed: %s", prov_state.error_message);
            // Return to AP mode for retry
            transition_to(WIFI_STATE_AP_ACTIVE);
        }
    }

    // Check for timeout
    uint32_t elapsed = get_time_ms() - prov_state.state_enter_time_ms;
    if (elapsed >= prov_state.connection_timeout_ms) {
        ESP_LOGW(TAG, "Connection timeout after %lu ms", (unsigned long)elapsed);
        strncpy(prov_state.error_message, "Connection timeout", sizeof(prov_state.error_message) - 1);
        prov_state.error_message[sizeof(prov_state.error_message) - 1] = '\0';
        transition_to(WIFI_STATE_AP_ACTIVE);
    }
}

/**
 * Process CONNECTED state
 * Normal operation, monitoring connection
 */
static void process_connected(void)
{
    // LED solid on to indicate connected
    gpio_set_level(prov_state.led_pin, 1);

    // Connection monitoring will be added in Phase 3
}

/**
 * Process OFFLINE state
 * Running without WiFi connection
 */
static void process_offline(void)
{
    // LED off to indicate offline
    gpio_set_level(prov_state.led_pin, 0);

    // Offline operation continues normally
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms)
{
    if (prov_state.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing WiFi provisioning system");

    // Validate parameters
    if (led_pin < 0 || led_pin >= GPIO_NUM_MAX) {
        ESP_LOGE(TAG, "Invalid LED pin: %d", led_pin);
        return ESP_ERR_INVALID_ARG;
    }

    // Store configuration
    prov_state.led_pin = led_pin;
    prov_state.connection_timeout_ms = connection_timeout_ms;
    prov_state.led_blink_interval_ms = LED_BLINK_INTERVAL_MS;

    // Configure LED GPIO (if not already configured by main app)
    gpio_config_t led_config = {
        .pin_bit_mask = (1ULL << led_pin),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&led_config);
    gpio_set_level(led_pin, 0);

    // Initialize default NVS partition (for provisioning flags)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        // NVS partition needs erase
        ESP_LOGW(TAG, "NVS needs erase, reinitializing");
        nvs_flash_erase();
        ret = nvs_flash_init();
    }
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize default NVS: %s", esp_err_to_name(ret));
        return ret;
    }

    // Initialize WiFi settings storage
    wifi_storage_error_t storage_ret = wifi_settings_init();
    if (storage_ret != WIFI_STORAGE_OK) {
        ESP_LOGW(TAG, "WiFi settings storage init failed: %s",
                 wifi_settings_error_to_string(storage_ret));
        // Continue anyway - device can still work in setup mode
    }

    // Determine initial state
    bool setup_requested = check_setup_requested();
    bool is_configured = wifi_settings_is_configured();

    ESP_LOGI(TAG, "Boot state: setup_requested=%d, is_configured=%d",
             setup_requested, is_configured);

    if (setup_requested) {
        // User requested setup mode before reboot
        clear_setup_requested();
        prov_state.current_state = WIFI_STATE_AP_ACTIVE;
        ESP_LOGI(TAG, "Entering AP mode (setup requested)");
        // AP and HTTP server will be started in Phase 3
    } else if (is_configured) {
        // Device has stored credentials - try to connect
        prov_state.current_state = WIFI_STATE_CONNECTING;
        ESP_LOGI(TAG, "Credentials found, will attempt connection");
        // Actual connection attempt will be in Phase 3

        // For now, transition to CONNECTED to allow normal operation
        // This will be replaced with actual WiFi connection in Phase 3
        prov_state.current_state = WIFI_STATE_CONNECTED;
        ESP_LOGI(TAG, "NOTE: WiFi connection not implemented yet - assuming connected");
    } else {
        // Device not configured - wait for user
        prov_state.current_state = WIFI_STATE_UNCONFIGURED;
        ESP_LOGI(TAG, "Device not configured, waiting for setup");
        ESP_LOGI(TAG, "Press BUTTON2 for 5 seconds to enter setup mode");
    }

    prov_state.state_enter_time_ms = get_time_ms();
    prov_state.initialized = true;

    ESP_LOGI(TAG, "WiFi provisioning initialized, state: %s",
             wifi_provisioning_state_to_string(prov_state.current_state));

    return ESP_OK;
}

void wifi_provisioning_setup_button_pressed(void)
{
    ESP_LOGI(TAG, "Setup button pressed - entering setup mode");

    // Set flag so we enter AP mode after reboot
    esp_err_t ret = set_setup_requested(true);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set setup flag, aborting");
        return;
    }

    ESP_LOGI(TAG, "Restarting device to enter setup mode...");

    // Brief delay to ensure log message is printed
    vTaskDelay(pdMS_TO_TICKS(100));

    // Reboot device
    esp_restart();

    // Code below never executes
}

void wifi_provisioning_process(void)
{
    if (!prov_state.initialized) {
        return;
    }

    // Process LED blinking
    process_led();

    // Process state-specific logic
    switch (prov_state.current_state) {
        case WIFI_STATE_UNCONFIGURED:
            process_unconfigured();
            break;

        case WIFI_STATE_SETUP_REQUESTED:
            // This state is transient (handled by reboot)
            break;

        case WIFI_STATE_AP_ACTIVE:
            process_ap_active();
            break;

        case WIFI_STATE_CONNECTING:
            process_connecting();
            break;

        case WIFI_STATE_CONNECTED:
            process_connected();
            break;

        case WIFI_STATE_OFFLINE:
            process_offline();
            break;

        default:
            ESP_LOGE(TAG, "Unknown state: %d", prov_state.current_state);
            break;
    }
}

wifi_state_t wifi_provisioning_get_state(void)
{
    return prov_state.current_state;
}

bool wifi_provisioning_is_ready(void)
{
    return (prov_state.current_state == WIFI_STATE_CONNECTED ||
            prov_state.current_state == WIFI_STATE_OFFLINE);
}

const char* wifi_provisioning_state_to_string(wifi_state_t state)
{
    switch (state) {
        case WIFI_STATE_UNCONFIGURED:
            return "UNCONFIGURED";
        case WIFI_STATE_SETUP_REQUESTED:
            return "SETUP_REQUESTED";
        case WIFI_STATE_AP_ACTIVE:
            return "AP_ACTIVE";
        case WIFI_STATE_CONNECTING:
            return "CONNECTING";
        case WIFI_STATE_CONNECTED:
            return "CONNECTED";
        case WIFI_STATE_OFFLINE:
            return "OFFLINE";
        default:
            return "UNKNOWN";
    }
}

void wifi_provisioning_set_connection_result(bool success, const char* error_message)
{
    prov_state.connection_success = success;
    prov_state.connection_result_ready = true;

    if (!success && error_message) {
        strncpy(prov_state.error_message, error_message, sizeof(prov_state.error_message) - 1);
        prov_state.error_message[sizeof(prov_state.error_message) - 1] = '\0';
    } else {
        prov_state.error_message[0] = '\0';
    }
}

esp_err_t wifi_provisioning_submit_credentials(const char* ssid, const char* password)
{
    if (!ssid || !password) {
        return ESP_ERR_INVALID_ARG;
    }

    if (prov_state.current_state != WIFI_STATE_AP_ACTIVE) {
        ESP_LOGW(TAG, "Cannot submit credentials - not in AP_ACTIVE state");
        return ESP_ERR_INVALID_STATE;
    }

    // Validate SSID
    size_t ssid_len = strlen(ssid);
    if (ssid_len == 0 || ssid_len > 31) {
        ESP_LOGE(TAG, "Invalid SSID length: %zu", ssid_len);
        return ESP_ERR_INVALID_ARG;
    }

    // Validate password
    size_t password_len = strlen(password);
    if (password_len < 8 || password_len > 63) {
        ESP_LOGE(TAG, "Invalid password length: %zu (must be 8-63)", password_len);
        return ESP_ERR_INVALID_ARG;
    }

    // Store pending credentials
    strncpy(prov_state.pending_ssid, ssid, sizeof(prov_state.pending_ssid) - 1);
    prov_state.pending_ssid[sizeof(prov_state.pending_ssid) - 1] = '\0';

    strncpy(prov_state.pending_password, password, sizeof(prov_state.pending_password) - 1);
    prov_state.pending_password[sizeof(prov_state.pending_password) - 1] = '\0';

    prov_state.credentials_pending = true;

    ESP_LOGI(TAG, "Credentials submitted for SSID: %s", ssid);

    return ESP_OK;
}

const char* wifi_provisioning_get_error_message(void)
{
    if (prov_state.error_message[0] == '\0') {
        return NULL;
    }
    return prov_state.error_message;
}

void wifi_provisioning_restart_device(void)
{
    ESP_LOGI(TAG, "Restart requested - rebooting device...");

    // Brief delay to ensure log message is printed
    vTaskDelay(pdMS_TO_TICKS(100));

    // Reboot device
    esp_restart();

    // Code below never executes
}
