/**
 * wifi_provisioning.c - WiFi Provisioning State Machine Implementation
 *
 * Implements the provisioning state machine with:
 * - Boot state detection and initialization
 * - Setup mode entry via 5-second button press
 * - WiFi AP mode for web-based configuration
 * - HTTP server integration for credential submission
 * - WiFi STA connection testing
 * - LED blinking control during AP mode
 *
 * Reference:
 * - WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2
 * - ESP-IDF WiFi and HTTP Server documentation
 */

#include "wifi_provisioning.h"
#include "dns_server.h"
#include "settings_storage.h"
#include "wifi_http_server.h"
#include "wifi_provisioning_config.h"

#include "driver/gpio.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"
#include <string.h>

static const char *TAG = "WIFI_PROV";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define LED_BLINK_INTERVAL_MS 500         // LED toggle interval during AP mode (500ms on/off = 1s cycle)
#define SETUP_FLAG_NVS_KEY    "setup_req" // NVS key for setup request flag
#define NVS_NAMESPACE         "wifi_prov" // NVS namespace for provisioning flags

// WiFi event bits for connection testing
#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT      BIT1

// ============================================================================
// STATE MACHINE DATA
// ============================================================================

typedef struct
{
    // Core state
    wifi_state_t      current_state;
    wifi_prov_event_t pending_event;

    // Timing
    uint32_t state_enter_time_ms;
    uint32_t connection_timeout_ms;

    // LED control
    gpio_num_t led_pin;
    uint32_t   led_blink_interval_ms;
    uint32_t   last_led_toggle_ms;
    uint8_t    led_state;

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
    bool ap_started;
    bool http_server_started;
    bool wifi_initialized;
    bool connection_test_in_progress;
} wifi_provisioning_state_t;

static wifi_provisioning_state_t prov_state = {0};

// Event group for WiFi connection status
static EventGroupHandle_t s_wifi_event_group = NULL;

// Network interface handles
static esp_netif_t *s_ap_netif  = NULL;
static esp_netif_t *s_sta_netif = NULL;

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
    if (prov_state.current_state == new_state)
    {
        return; // No transition needed
    }

    ESP_LOGI(TAG, "State transition: %s -> %s", wifi_provisioning_state_to_string(prov_state.current_state),
             wifi_provisioning_state_to_string(new_state));

    prov_state.current_state       = new_state;
    prov_state.state_enter_time_ms = get_time_ms();

    // Reset LED state on transition
    prov_state.last_led_toggle_ms = get_time_ms();
    prov_state.led_state          = 0;
    gpio_set_level(prov_state.led_pin, 0);
}

/**
 * Check if setup mode was requested on previous boot
 * Uses NVS to persist the flag across reboots
 */
static bool check_setup_requested(void)
{
    nvs_handle_t nvs_handle;
    esp_err_t    ret = nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs_handle);

    if (ret == ESP_ERR_NVS_NOT_FOUND)
    {
        // Namespace doesn't exist yet - no setup requested
        return false;
    }
    else if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to open NVS for setup flag: %s", esp_err_to_name(ret));
        return false;
    }

    uint8_t setup_flag = 0;
    ret                = nvs_get_u8(nvs_handle, SETUP_FLAG_NVS_KEY, &setup_flag);
    nvs_close(nvs_handle);

    if (ret == ESP_ERR_NVS_NOT_FOUND)
    {
        return false;
    }
    else if (ret != ESP_OK)
    {
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
    esp_err_t    ret = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);

    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to open NVS for setup flag: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = nvs_set_u8(nvs_handle, SETUP_FLAG_NVS_KEY, requested ? 1 : 0);
    if (ret != ESP_OK)
    {
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
 * Only blinks during AP_ACTIVE and CONNECTING states
 */
static void process_led(void)
{
    // Only blink during AP_ACTIVE and CONNECTING states
    if (prov_state.current_state != WIFI_STATE_AP_ACTIVE && prov_state.current_state != WIFI_STATE_CONNECTING)
    {
        return;
    }

    uint32_t now     = get_time_ms();
    uint32_t elapsed = now - prov_state.last_led_toggle_ms;

    if (elapsed >= prov_state.led_blink_interval_ms)
    {
        // Toggle LED
        prov_state.led_state = !prov_state.led_state;
        gpio_set_level(prov_state.led_pin, prov_state.led_state);
        prov_state.last_led_toggle_ms = now;
    }
}

// ============================================================================
// WIFI EVENT HANDLER
// ============================================================================

/**
 * WiFi event handler for connection testing
 */
static void wifi_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT)
    {
        switch (event_id)
        {
        case WIFI_EVENT_STA_START:
            ESP_LOGI(TAG, "WiFi STA started, connecting...");
            esp_wifi_connect();
            break;

        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *event = (wifi_event_sta_disconnected_t *)event_data;
            ESP_LOGW(TAG, "WiFi disconnected (reason: %d)", event->reason);

            if (prov_state.connection_test_in_progress)
            {
                // Connection test failed
                if (s_wifi_event_group)
                {
                    xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
                }
            }
        }
        break;

        case WIFI_EVENT_STA_CONNECTED:
            ESP_LOGI(TAG, "WiFi STA connected to AP");
            break;

        case WIFI_EVENT_AP_START:
            ESP_LOGI(TAG, "WiFi AP started");
            break;

        case WIFI_EVENT_AP_STOP:
            ESP_LOGI(TAG, "WiFi AP stopped");
            break;

        case WIFI_EVENT_AP_STACONNECTED: {
            wifi_event_ap_staconnected_t *event = (wifi_event_ap_staconnected_t *)event_data;
            ESP_LOGI(TAG, "Station connected to AP, MAC: " MACSTR ", AID: %d", MAC2STR(event->mac), event->aid);
        }
        break;

        case WIFI_EVENT_AP_STADISCONNECTED: {
            wifi_event_ap_stadisconnected_t *event = (wifi_event_ap_stadisconnected_t *)event_data;
            ESP_LOGI(TAG, "Station disconnected from AP, MAC: " MACSTR ", AID: %d", MAC2STR(event->mac), event->aid);
        }
        break;

        default:
            break;
        }
    }
    else if (event_base == IP_EVENT)
    {
        switch (event_id)
        {
        case IP_EVENT_STA_GOT_IP: {
            ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
            ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));

            if (prov_state.connection_test_in_progress && s_wifi_event_group)
            {
                xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
            }
        }
        break;

        default:
            break;
        }
    }
}

// ============================================================================
// WIFI AP MODE
// ============================================================================

/**
 * Initialize WiFi subsystem (needed before AP or STA mode)
 */
static esp_err_t wifi_init_common(void)
{
    if (prov_state.wifi_initialized)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing WiFi subsystem...");

    // Initialize TCP/IP stack
    esp_err_t ret = esp_netif_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to init netif: %s", esp_err_to_name(ret));
        return ret;
    }

    // Create default event loop
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
        return ret;
    }

    // Create event group for WiFi status
    if (s_wifi_event_group == NULL)
    {
        s_wifi_event_group = xEventGroupCreate();
        if (s_wifi_event_group == NULL)
        {
            ESP_LOGE(TAG, "Failed to create event group");
            return ESP_FAIL;
        }
    }

    // Register event handlers
    ret = esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to register WIFI event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = esp_event_handler_instance_register(IP_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to register IP event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    // Initialize WiFi with default config
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ret                    = esp_wifi_init(&cfg);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to init WiFi: %s", esp_err_to_name(ret));
        return ret;
    }

    prov_state.wifi_initialized = true;
    ESP_LOGI(TAG, "WiFi subsystem initialized");

    return ESP_OK;
}

/**
 * Start WiFi Access Point for provisioning
 */
static esp_err_t wifi_start_ap(void)
{
    if (prov_state.ap_started)
    {
        ESP_LOGW(TAG, "AP already started");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting WiFi Access Point...");

    esp_err_t ret = wifi_init_common();
    if (ret != ESP_OK)
    {
        return ret;
    }

    // Create AP network interface if not exists
    if (s_ap_netif == NULL)
    {
        s_ap_netif = esp_netif_create_default_wifi_ap();
        if (s_ap_netif == NULL)
        {
            ESP_LOGE(TAG, "Failed to create AP netif");
            return ESP_FAIL;
        }
    }

    // Also create STA network interface now so we can switch to APSTA mode
    // later without stopping WiFi (preserves client connections)
    if (s_sta_netif == NULL)
    {
        s_sta_netif = esp_netif_create_default_wifi_sta();
        if (s_sta_netif == NULL)
        {
            ESP_LOGW(TAG, "Failed to create STA netif (will retry during connection test)");
            // Not fatal - we can try again later
        }
    }

    // Set WiFi mode to AP
    ret = esp_wifi_set_mode(WIFI_MODE_AP);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set AP mode: %s", esp_err_to_name(ret));
        return ret;
    }

    // Configure AP
    wifi_config_t wifi_config = {
        .ap =
            {
                .ssid_len       = strlen(WIFI_SETUP_AP_SSID),
                .channel        = WIFI_SETUP_AP_CHANNEL,
                .max_connection = WIFI_SETUP_AP_MAX_CONN,
                .authmode       = WIFI_AUTH_WPA2_PSK,
                .pmf_cfg        = {.required = false},
            },
    };

    // Copy SSID and password
    strncpy((char *)wifi_config.ap.ssid, WIFI_SETUP_AP_SSID, sizeof(wifi_config.ap.ssid) - 1);
    strncpy((char *)wifi_config.ap.password, WIFI_SETUP_AP_PASSWORD, sizeof(wifi_config.ap.password) - 1);

    // If password is less than 8 characters, use open auth
    if (strlen(WIFI_SETUP_AP_PASSWORD) < 8)
    {
        wifi_config.ap.authmode = WIFI_AUTH_OPEN;
        ESP_LOGW(TAG, "AP password too short, using open authentication");
    }

    ret = esp_wifi_set_config(WIFI_IF_AP, &wifi_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set AP config: %s", esp_err_to_name(ret));
        return ret;
    }

    // Start WiFi
    ret = esp_wifi_start();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start WiFi: %s", esp_err_to_name(ret));
        return ret;
    }

    prov_state.ap_started = true;

    ESP_LOGI(TAG, "WiFi AP started successfully");
    ESP_LOGI(TAG, "  SSID: %s", WIFI_SETUP_AP_SSID);
    ESP_LOGI(TAG, "  Password: %s", WIFI_SETUP_AP_PASSWORD);
    ESP_LOGI(TAG, "  IP: %s", WIFI_AP_IP_ADDR);

    return ESP_OK;
}

/**
 * Stop WiFi Access Point
 */
static esp_err_t wifi_stop_ap(void)
{
    if (!prov_state.ap_started)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping WiFi AP...");

    // Stop DNS server if running (captive portal)
    if (dns_server_is_running())
    {
        dns_server_stop();
        ESP_LOGI(TAG, "Captive portal disabled");
    }

    esp_err_t ret = esp_wifi_stop();
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to stop WiFi: %s", esp_err_to_name(ret));
    }

    prov_state.ap_started = false;

    return ESP_OK;
}

// ============================================================================
// HTTP SERVER INTEGRATION
// ============================================================================

/**
 * Callback when credentials are submitted from HTTP form
 */
static void on_credentials_received(const char *ssid, const char *password)
{
    ESP_LOGI(TAG, "Credentials received from HTTP form for SSID: %s", ssid);

    // Store credentials for testing
    esp_err_t ret = wifi_provisioning_submit_credentials(ssid, password);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to submit credentials: %s", esp_err_to_name(ret));
        wifi_http_server_set_connection_result(false, "Invalid credentials format");
    }
}

/**
 * Start HTTP server for provisioning
 */
static esp_err_t start_http_server(void)
{
    if (prov_state.http_server_started)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting HTTP server...");

    // Set credentials callback before starting
    wifi_http_server_set_credentials_callback(on_credentials_received);

    esp_err_t ret = wifi_http_server_start(WIFI_SETUP_AP_SSID, WIFI_SETUP_AP_PASSWORD);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start HTTP server: %s", esp_err_to_name(ret));
        return ret;
    }

    prov_state.http_server_started = true;
    ESP_LOGI(TAG, "HTTP server started on http://%s/", WIFI_AP_IP_ADDR);

    return ESP_OK;
}

/**
 * Stop HTTP server
 */
static esp_err_t stop_http_server(void)
{
    if (!prov_state.http_server_started)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping HTTP server...");

    esp_err_t ret                  = wifi_http_server_stop();
    prov_state.http_server_started = false;

    return ret;
}

// ============================================================================
// WIFI STA CONNECTION TESTING
// ============================================================================

/**
 * Test WiFi connection with provided credentials
 * Returns true if connection successful
 *
 * IMPORTANT: Uses APSTA mode to keep AP active during test.
 * This allows the HTTP handler to receive the result and send
 * the response back to the browser.
 */
static bool test_wifi_connection(const char *ssid, const char *password)
{
    ESP_LOGI(TAG, "Testing WiFi connection to: %s", ssid);

    prov_state.connection_test_in_progress = true;

    // Clear event bits
    if (s_wifi_event_group)
    {
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT);
    }

    // Check if STA netif exists (should be created in wifi_start_ap)
    if (s_sta_netif == NULL)
    {
        // Try to create it now
        s_sta_netif = esp_netif_create_default_wifi_sta();
        if (s_sta_netif == NULL)
        {
            ESP_LOGE(TAG, "Failed to create STA netif");
            prov_state.connection_test_in_progress = false;
            return false;
        }
    }

    // Switch to APSTA mode WITHOUT stopping WiFi
    // This preserves client connections to the AP
    ESP_LOGI(TAG, "Switching to APSTA mode (preserving AP connections)...");
    esp_err_t ret = esp_wifi_set_mode(WIFI_MODE_APSTA);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set APSTA mode: %s", esp_err_to_name(ret));
        prov_state.connection_test_in_progress = false;
        return false;
    }

    // Disconnect any existing STA connection before configuring new one
    // This is needed because switching to APSTA mode may trigger auto-connect
    // if there's an existing STA config, and we can't set config while connecting
    esp_wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(100)); // Brief delay to ensure disconnect completes

    // Configure STA with provided credentials
    wifi_config_t sta_config = {
        .sta =
            {
                .threshold.authmode = WIFI_AUTH_WPA2_PSK,
                .pmf_cfg            = {.capable = true, .required = false},
            },
    };

    strncpy((char *)sta_config.sta.ssid, ssid, sizeof(sta_config.sta.ssid) - 1);
    strncpy((char *)sta_config.sta.password, password, sizeof(sta_config.sta.password) - 1);

    ret = esp_wifi_set_config(WIFI_IF_STA, &sta_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set STA config: %s", esp_err_to_name(ret));
        prov_state.connection_test_in_progress = false;
        // Switch back to AP-only mode
        esp_wifi_set_mode(WIFI_MODE_AP);
        return false;
    }

    // Connect to the target network (AP stays running)
    ret = esp_wifi_connect();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initiate WiFi connection: %s", esp_err_to_name(ret));
        prov_state.connection_test_in_progress = false;
        esp_wifi_set_mode(WIFI_MODE_AP);
        return false;
    }

    ESP_LOGI(TAG, "AP still active during connection test (APSTA mode)");

    // Wait for connection result
    ESP_LOGI(TAG, "Waiting for connection (timeout: %lu ms)...", (unsigned long)prov_state.connection_timeout_ms);

    EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT, pdFALSE, pdFALSE,
                                           pdMS_TO_TICKS(prov_state.connection_timeout_ms));

    prov_state.connection_test_in_progress = false;

    if (bits & WIFI_CONNECTED_BIT)
    {
        ESP_LOGI(TAG, "WiFi connection test SUCCESSFUL!");
        // Keep APSTA mode - AP stays active for browser to get response
        // AP will be disabled when device restarts
        return true;
    }
    else
    {
        ESP_LOGW(TAG, "WiFi connection test FAILED (timeout or auth error)");

        // Disconnect STA but keep AP running
        esp_wifi_disconnect();

        // Switch back to AP-only mode for retry (no stop needed, preserves client connections)
        esp_wifi_set_mode(WIFI_MODE_AP);
        return false;
    }
}

// ============================================================================
// STATE PROCESSING FUNCTIONS
// ============================================================================

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
 * Enter AP_ACTIVE state - start AP and HTTP server
 */
static void enter_ap_active_state(void)
{
    ESP_LOGI(TAG, "Entering AP_ACTIVE state...");

    // Start WiFi AP
    esp_err_t ret = wifi_start_ap();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start WiFi AP");
        return;
    }

    // Start HTTP server
    ret = start_http_server();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start HTTP server");
        wifi_stop_ap();
        return;
    }

    // Start DNS server for captive portal
    ret = dns_server_start();
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to start DNS server: %s (captive portal may not work)", esp_err_to_name(ret));
        // Continue anyway - manual browser access still works
    }
    else
    {
        ESP_LOGI(TAG, "Captive portal enabled - setup page will open automatically on connected devices");
    }

    ESP_LOGI(TAG, "AP mode active - waiting for credentials");
    ESP_LOGI(TAG, "Connect to WiFi: %s (password: %s)", WIFI_SETUP_AP_SSID, WIFI_SETUP_AP_PASSWORD);
    ESP_LOGI(TAG, "Then open http://%s/ in browser", WIFI_AP_IP_ADDR);
}

/**
 * Process AP_ACTIVE state
 * Serving provisioning page, waiting for credentials
 */
static void process_ap_active(void)
{
    // LED blinking is handled in process_led()

    // Check if credentials were submitted
    if (prov_state.credentials_pending)
    {
        ESP_LOGI(TAG, "Credentials received, transitioning to CONNECTING");
        prov_state.credentials_pending = false;
        transition_to(WIFI_STATE_CONNECTING);
    }
}

/**
 * Process CONNECTING state
 * Attempting WiFi connection with provided credentials
 *
 * NOTE: AP and HTTP server remain active during the connection test
 * (using APSTA mode) so the browser can receive the response.
 */
static void process_connecting(void)
{
    // Only run connection test once per state entry
    static bool test_started = false;

    if (!test_started)
    {
        test_started = true;

        ESP_LOGI(TAG, "Testing WiFi connection...");

        // Test the connection (AP stays active via APSTA mode)
        bool success = test_wifi_connection(prov_state.pending_ssid, prov_state.pending_password);

        if (success)
        {
            // Connection successful - save credentials
            ESP_LOGI(TAG, "Connection successful! Saving credentials...");

            settings_storage_error_t storage_ret =
                wifi_settings_save(prov_state.pending_ssid, prov_state.pending_password);
            if (storage_ret != SETTINGS_STORAGE_OK)
            {
                ESP_LOGE(TAG, "Failed to save credentials: %s", settings_storage_error_to_string(storage_ret));
                strncpy(prov_state.error_message, "Failed to save credentials", sizeof(prov_state.error_message) - 1);
                prov_state.connection_success = false;
            }
            else
            {
                ESP_LOGI(TAG, "Credentials saved successfully");
                prov_state.connection_success = true;
            }

            // Notify HTTP server of result (browser will receive this response)
            wifi_http_server_set_connection_result(prov_state.connection_success, prov_state.error_message);

            if (prov_state.connection_success)
            {
                // Transition to CONNECTED - AP stays active for browser to show restart button
                // Device will restart when user clicks restart button
                transition_to(WIFI_STATE_AP_ACTIVE_CONNECTED);
            }
            else
            {
                // Failed to save - return to AP_ACTIVE for retry
                // AP is already running in APSTA mode, just transition state
                test_started = false;
                transition_to(WIFI_STATE_AP_ACTIVE);
            }
        }
        else
        {
            // Connection failed
            ESP_LOGW(TAG, "Connection failed");
            strncpy(prov_state.error_message, "Connection failed - check SSID and password",
                    sizeof(prov_state.error_message) - 1);
            prov_state.error_message[sizeof(prov_state.error_message) - 1] = '\0';
            prov_state.connection_success                                  = false;

            // Notify HTTP server of failure
            wifi_http_server_set_connection_result(false, prov_state.error_message);

            // Return to AP mode for retry (test_wifi_connection already restarted AP)
            test_started = false;
            transition_to(WIFI_STATE_AP_ACTIVE);
        }
    }
}

/**
 * Process CONNECTED state
 * Successfully connected, waiting for restart
 */
static void process_connected(void)
{
    // LED solid on to indicate connected
    gpio_set_level(prov_state.led_pin, 1);

    // Device is ready - waiting for user to click restart
    // HTTP server will call wifi_provisioning_restart_device() when user clicks restart
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
    if (prov_state.initialized)
    {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing WiFi provisioning system");

    // Validate parameters
    if (led_pin < 0 || led_pin >= GPIO_NUM_MAX)
    {
        ESP_LOGE(TAG, "Invalid LED pin: %d", led_pin);
        return ESP_ERR_INVALID_ARG;
    }

    // Store configuration
    prov_state.led_pin               = led_pin;
    prov_state.connection_timeout_ms = connection_timeout_ms;
    prov_state.led_blink_interval_ms = LED_BLINK_INTERVAL_MS;

    // Configure LED GPIO (if not already configured by main app)
    gpio_config_t led_config = {
        .pin_bit_mask = (1ULL << led_pin),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&led_config);
    gpio_set_level(led_pin, 0);

    // Initialize default NVS partition (for provisioning flags)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        // NVS partition needs erase
        ESP_LOGW(TAG, "NVS needs erase, reinitializing");
        nvs_flash_erase();
        ret = nvs_flash_init();
    }
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize default NVS: %s", esp_err_to_name(ret));
        return ret;
    }

    // Initialize WiFi settings storage
    settings_storage_error_t storage_ret = settings_storage_init();
    if (storage_ret != SETTINGS_STORAGE_OK)
    {
        ESP_LOGW(TAG, "WiFi settings storage init failed: %s", settings_storage_error_to_string(storage_ret));
        // Continue anyway - device can still work in setup mode
    }

    // Determine initial state
    bool setup_requested = check_setup_requested();
    bool is_configured   = wifi_settings_is_configured();

    ESP_LOGI(TAG, "Boot state: setup_requested=%d, is_configured=%d", setup_requested, is_configured);

    if (setup_requested)
    {
        // User requested setup mode before reboot
        clear_setup_requested();
        prov_state.current_state = WIFI_STATE_AP_ACTIVE;
        ESP_LOGI(TAG, "Entering AP mode (setup requested)");

        // Start AP and HTTP server
        enter_ap_active_state();

        prov_state.state_enter_time_ms = get_time_ms();
        prov_state.initialized         = true;

        return ESP_OK;
    }
    else if (is_configured)
    {
        // Device has stored credentials - load them and auto-connect
        wifi_credentials_t       creds    = {0};
        settings_storage_error_t load_err = wifi_settings_load(&creds);

        if (load_err == SETTINGS_STORAGE_OK)
        {
            // Store credentials in state machine for auto-connection
            strncpy(prov_state.pending_ssid, creds.ssid, sizeof(prov_state.pending_ssid) - 1);
            prov_state.pending_ssid[sizeof(prov_state.pending_ssid) - 1] = '\0';

            strncpy(prov_state.pending_password, creds.password, sizeof(prov_state.pending_password) - 1);
            prov_state.pending_password[sizeof(prov_state.pending_password) - 1] = '\0';

            // Clear credentials from RAM after copying
            memset(&creds, 0, sizeof(creds));

            ESP_LOGI(TAG, "Loaded saved credentials for SSID: %s", prov_state.pending_ssid);

            // Mark as ready - wifi_manager will use these credentials
            prov_state.current_state = WIFI_STATE_CONNECTED;
            ESP_LOGI(TAG, "Device configured - ready to connect");
        }
        else
        {
            // Load failed despite being configured - fall back to unconfigured
            ESP_LOGW(TAG, "Failed to load credentials: %s", settings_storage_error_to_string(load_err));
            prov_state.current_state = WIFI_STATE_UNCONFIGURED;
            ESP_LOGI(TAG, "Falling back to unconfigured state");
            ESP_LOGI(TAG, "Press BUTTON2 for 5 seconds to enter setup mode");
        }
    }
    else
    {
        // Device not configured - wait for user
        prov_state.current_state = WIFI_STATE_UNCONFIGURED;
        ESP_LOGI(TAG, "Device not configured, waiting for setup");
        ESP_LOGI(TAG, "Press BUTTON2 for 5 seconds to enter setup mode");
    }

    prov_state.state_enter_time_ms = get_time_ms();
    prov_state.initialized         = true;

    ESP_LOGI(TAG, "WiFi provisioning initialized, state: %s",
             wifi_provisioning_state_to_string(prov_state.current_state));

    return ESP_OK;
}

void wifi_provisioning_setup_button_pressed(void)
{
    ESP_LOGI(TAG, "Setup button pressed - entering setup mode");

    // Set flag so we enter AP mode after reboot
    esp_err_t ret = set_setup_requested(true);
    if (ret != ESP_OK)
    {
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
    if (!prov_state.initialized)
    {
        ESP_LOGW(TAG, "Provisioning process running, but state is uninitialized");
        return;
    }

    // Process LED blinking
    process_led();

    // Process state-specific logic
    switch (prov_state.current_state)
    {
    case WIFI_STATE_UNCONFIGURED:
        process_unconfigured();
        break;

    case WIFI_STATE_SETUP_REQUESTED:
        // This state is transient (handled by reboot)
        break;

    case WIFI_STATE_AP_ACTIVE:
    case WIFI_STATE_AP_ACTIVE_CONNECTED:
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
    return (prov_state.current_state == WIFI_STATE_CONNECTED || prov_state.current_state == WIFI_STATE_OFFLINE);
}

const char *wifi_provisioning_state_to_string(wifi_state_t state)
{
    switch (state)
    {
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
    case WIFI_STATE_AP_ACTIVE_CONNECTED:
        return "CONNECTED";
    case WIFI_STATE_OFFLINE:
        return "OFFLINE";
    default:
        return "UNKNOWN";
    }
}

void wifi_provisioning_set_connection_result(bool success, const char *error_message)
{
    prov_state.connection_success      = success;
    prov_state.connection_result_ready = true;

    if (!success && error_message)
    {
        strncpy(prov_state.error_message, error_message, sizeof(prov_state.error_message) - 1);
        prov_state.error_message[sizeof(prov_state.error_message) - 1] = '\0';
    }
    else
    {
        prov_state.error_message[0] = '\0';
    }
}

esp_err_t wifi_provisioning_submit_credentials(const char *ssid, const char *password)
{
    if (!ssid || !password)
    {
        return ESP_ERR_INVALID_ARG;
    }

    if (prov_state.current_state != WIFI_STATE_AP_ACTIVE && prov_state.current_state != WIFI_STATE_AP_ACTIVE_CONNECTED)
    {
        ESP_LOGW(TAG, "Cannot submit credentials - not in AP_ACTIVE state");
        return ESP_ERR_INVALID_STATE;
    }

    // Validate SSID
    size_t ssid_len = strlen(ssid);
    if (ssid_len == 0 || ssid_len > 31)
    {
        ESP_LOGE(TAG, "Invalid SSID length: %zu", ssid_len);
        return ESP_ERR_INVALID_ARG;
    }

    // Validate password
    size_t password_len = strlen(password);
    if (password_len < 8 || password_len > 63)
    {
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
    ESP_LOGI(TAG, "Credentials submitted for SSID: %s", password);

    return ESP_OK;
}

const char *wifi_provisioning_get_error_message(void)
{
    if (prov_state.error_message[0] == '\0')
    {
        return NULL;
    }
    return prov_state.error_message;
}

void wifi_provisioning_restart_device(void)
{
    ESP_LOGI(TAG, "Restart requested - rebooting device...");

    // Stop DNS server if running (captive portal)
    if (dns_server_is_running())
    {
        dns_server_stop();
    }

    // Stop HTTP server if running
    stop_http_server();

    // Brief delay to ensure log message is printed
    vTaskDelay(pdMS_TO_TICKS(100));

    // Reboot device
    esp_restart();

    // Code below never executes
}
