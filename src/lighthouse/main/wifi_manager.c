/**
 * WiFi Manager - Implementation
 *
 * Implements WiFi Station Mode for ESP32 with proper event handling
 * and reconnection logic as per ESP-IDF documentation.
 *
 * ARCHITECTURE NOTES:
 * - WiFi task runs on Core 0 (CONFIG_ESP32_WIFI_TASK_PINNED_TO_CORE_0=y)
 * - RFID task can run on Core 1 to prevent blocking
 * - Event handlers must be non-blocking per ESP-IDF guidelines
 */

#include "wifi_manager.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "nvs_flash.h"
#include "wifi_settings_storage.h"
#include <string.h>

// ============================================================================
// CONSTANTS & STATE
// ============================================================================

static const char *TAG = "WIFI_MGR";

/**
 * FreeRTOS event group for WiFi status signaling
 * Used to communicate between event handler and application tasks
 */
static EventGroupHandle_t s_wifi_event_group;

/**
 * ESP-NETIF WiFi station interface handle
 */
static esp_netif_t *s_sta_netif = NULL;

/**
 * Retry counter for reconnection attempts
 */
static int s_retry_count = 0;

/**
 * Connection state flag
 */
static bool s_is_connected = false;

// ============================================================================
// EVENT HANDLER
// ============================================================================

/**
 * WiFi and IP event handler
 *
 * Handles all WiFi lifecycle events per ESP-IDF documentation.
 * Must be non-blocking to avoid degrading WiFi performance.
 *
 * CRITICAL "RAINY DAY" SCENARIOS (per ESP-IDF docs):
 * - Disconnections with reason codes
 * - Handshake timeouts (wrong password)
 * - IP assignment failures (DHCP issues)
 */
static void wifi_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START)
    {
        // WiFi driver started successfully
        ESP_LOGI(TAG, "WiFi driver started, connecting to AP...");
        esp_wifi_connect();
    }
    else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED)
    {
        // Lost connection to AP
        wifi_event_sta_disconnected_t *event = (wifi_event_sta_disconnected_t *)event_data;

        ESP_LOGW(TAG, "Disconnected from AP (reason: %d)", event->reason);

        // Check for common failure reasons
        if (event->reason == WIFI_REASON_HANDSHAKE_TIMEOUT)
        {
            ESP_LOGE(TAG, "Handshake timeout - check password and AP security mode");
        }

        s_is_connected = false;

        // Implement retry logic with maximum attempt limit
        if (s_retry_count < WIFI_MAX_RETRY_ATTEMPTS)
        {
            ESP_LOGI(TAG, "Retrying connection (%d/%d)...", s_retry_count + 1, WIFI_MAX_RETRY_ATTEMPTS);
            esp_wifi_connect();
            s_retry_count++;
        }
        else
        {
            ESP_LOGE(TAG, "Maximum retry attempts reached, giving up");
            xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
        }
    }
    else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_CONNECTED)
    {
        // Successfully connected to AP
        wifi_event_sta_connected_t *event = (wifi_event_sta_connected_t *)event_data;
        ESP_LOGI(TAG, "Connected to AP: %s (channel %d)", event->ssid, event->channel);

        // Note: Don't set connected flag yet - wait for IP assignment
    }
    else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP)
    {
        // DHCP assigned IP address
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI(TAG, "Got IP address: " IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "Gateway: " IPSTR, IP2STR(&event->ip_info.gw));
        ESP_LOGI(TAG, "Netmask: " IPSTR, IP2STR(&event->ip_info.netmask));

        s_retry_count  = 0;
        s_is_connected = true;
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
    else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_LOST_IP)
    {
        // Lost IP address
        ESP_LOGW(TAG, "Lost IP address");
        s_is_connected = false;
    }
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t wifi_manager_init(void)
{
    esp_err_t ret;

    ESP_LOGI(TAG, "Initializing WiFi manager...");

    // ========================================================================
    // STEP 1: Initialize NVS Flash
    // ========================================================================
    // CRITICAL: Must be called before any WiFi operations
    // Stores WiFi credentials and configuration persistently

    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        // NVS partition was truncated and needs to be erased
        ESP_LOGW(TAG, "NVS partition needs erasing, erasing...");
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to initialize NVS flash: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ NVS flash initialized");

    // ========================================================================
    // STEP 2: Initialize Network Interface & Event Loop
    // ========================================================================
    // Creates the TCP/IP stack (lwIP) and event handling infrastructure

    ret = esp_netif_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to initialize network interface: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ Network interface (lwIP) %s", ret == ESP_ERR_INVALID_STATE ? "already initialized" : "initialized");

    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ Event loop %s", ret == ESP_ERR_INVALID_STATE ? "already exists" : "created");

    // Check if STA netif already exists (created by provisioning system)
    s_sta_netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    if (s_sta_netif == NULL)
    {
        s_sta_netif = esp_netif_create_default_wifi_sta();
        if (s_sta_netif == NULL)
        {
            ESP_LOGE(TAG, "Failed to create default WiFi STA interface");
            return ESP_FAIL;
        }
        ESP_LOGI(TAG, "  ✓ WiFi STA interface created");
    }
    else
    {
        ESP_LOGI(TAG, "  ✓ WiFi STA interface already exists");
    }

    // ========================================================================
    // STEP 3: Initialize WiFi Driver
    // ========================================================================
    // Use WIFI_INIT_CONFIG_DEFAULT() macro for safe defaults
    // Per ESP-IDF docs: always use default macro to ensure forward compatibility

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ret                    = esp_wifi_init(&cfg);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "Failed to initialize WiFi driver: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ WiFi driver %s", ret == ESP_ERR_INVALID_STATE ? "already initialized" : "initialized");

    // ========================================================================
    // STEP 4: Create Event Group
    // ========================================================================
    // For signaling connection status between event handler and app

    s_wifi_event_group = xEventGroupCreate();
    if (s_wifi_event_group == NULL)
    {
        ESP_LOGE(TAG, "Failed to create event group");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "  ✓ Event group created");

    // ========================================================================
    // STEP 5: Register Event Handlers
    // ========================================================================
    // Handle WiFi events (connect, disconnect) and IP events (got IP)

    ret = esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to register WiFi event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to register IP event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_LOST_IP, &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to register IP lost event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "  ✓ Event handlers registered");

    // ========================================================================
    // STEP 6: Set WiFi Mode
    // ========================================================================
    // WIFI_MODE_STA = Station mode (connect to AP)
    // Other modes: AP (access point), APSTA (both), NAN (WiFi Aware)

    ret = esp_wifi_set_mode(WIFI_MODE_STA);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set WiFi mode: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ WiFi mode set to STA (Station)");

    // ========================================================================
    // STEP 7: Configure WiFi Credentials
    // ========================================================================
    // Priority order:
    // 1. First choice: Credentials from NVS (user-provisioned)
    // 2. Second choice: Hardcoded SDK config (factory defaults)

    wifi_config_t wifi_config = {
        .sta =
            {
                .threshold.authmode = WIFI_AUTH_WPA2_PSK, // Minimum security
                .pmf_cfg            = {.capable = true, .required = false},
            },
    };

    // Try to load saved credentials from NVS
    wifi_credentials_t   creds    = {0};
    wifi_storage_error_t load_err = wifi_settings_load(&creds);

    if (load_err == WIFI_STORAGE_OK && creds.ssid[0] != '\0')
    {
        // Use saved credentials from NVS (user-provisioned)
        strncpy((char *)wifi_config.sta.ssid, creds.ssid, sizeof(wifi_config.sta.ssid) - 1);
        wifi_config.sta.ssid[sizeof(wifi_config.sta.ssid) - 1] = '\0';

        strncpy((char *)wifi_config.sta.password, creds.password, sizeof(wifi_config.sta.password) - 1);
        wifi_config.sta.password[sizeof(wifi_config.sta.password) - 1] = '\0';

        // Clear credentials from RAM after copying for security
        memset(&creds, 0, sizeof(creds));

        ESP_LOGI(TAG, "  ✓ Using saved WiFi credentials: %s", wifi_config.sta.ssid);
    }
    else
    {
        // Fall back to SDK config (factory defaults)
        if (load_err != WIFI_STORAGE_OK)
        {
            ESP_LOGW(TAG, "Failed to load saved credentials: %s", wifi_settings_error_to_string(load_err));
        }
        else
        {
            ESP_LOGW(TAG, "Saved credentials are empty");
        }

        strncpy((char *)wifi_config.sta.ssid, WIFI_SSID, sizeof(wifi_config.sta.ssid) - 1);
        wifi_config.sta.ssid[sizeof(wifi_config.sta.ssid) - 1] = '\0';

        strncpy((char *)wifi_config.sta.password, WIFI_PASSWORD, sizeof(wifi_config.sta.password) - 1);
        wifi_config.sta.password[sizeof(wifi_config.sta.password) - 1] = '\0';

        ESP_LOGI(TAG, "  ✓ Using SDK config credentials (factory defaults): %s", wifi_config.sta.ssid);
    }

    ret = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set WiFi config: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ WiFi credentials configured");

    // ========================================================================
    // STEP 8: Start WiFi Driver and Connect
    // ========================================================================
    // This activates the WiFi driver
    // WIFI_EVENT_STA_START will be triggered, which initiates connection
    //
    // Note: We always call esp_wifi_start() because:
    // - esp_wifi_get_mode() returns the MODE we SET, not whether WiFi is STARTED
    // - If WiFi was started by provisioning but mode changed to STA, we need to
    //   ensure connection is re-initiated

    ret = esp_wifi_start();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start WiFi: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ WiFi driver started");

    // Explicitly initiate connection
    // This is needed because if WiFi was already started by provisioning,
    // esp_wifi_start() won't trigger WIFI_EVENT_STA_START again, so the
    // event handler's esp_wifi_connect() call won't happen
    s_retry_count = 0;
    xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT);
    ret = esp_wifi_connect();
    if (ret != ESP_OK && ret != ESP_ERR_WIFI_CONN)
    {
        // ESP_ERR_WIFI_CONN means already connecting, which is fine
        ESP_LOGW(TAG, "esp_wifi_connect returned: %s", esp_err_to_name(ret));
    }

    // Enable debug logging for troubleshooting
    esp_log_level_set("wifi", ESP_LOG_INFO);

    ESP_LOGI(TAG, "WiFi manager initialized successfully");
    ESP_LOGI(TAG, "Waiting for connection...");

    return ESP_OK;
}

esp_err_t wifi_manager_connect(void)
{
    ESP_LOGI(TAG, "Initiating WiFi connection...");
    s_retry_count = 0;
    xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT);
    return esp_wifi_connect();
}

esp_err_t wifi_manager_wait_for_connection(uint32_t timeout_ms)
{
    TickType_t timeout_ticks = (timeout_ms == 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms);

    // Wait for either connected or failed bit
    EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
                                           pdFALSE, // Don't clear on exit
                                           pdFALSE, // Wait for either bit
                                           timeout_ticks);

    if (bits & WIFI_CONNECTED_BIT)
    {
        ESP_LOGI(TAG, "✓ Connected to WiFi successfully");
        return ESP_OK;
    }
    else if (bits & WIFI_FAIL_BIT)
    {
        ESP_LOGE(TAG, "✗ Failed to connect to WiFi");
        return ESP_FAIL;
    }
    else
    {
        ESP_LOGW(TAG, "✗ WiFi connection timeout");
        return ESP_ERR_TIMEOUT;
    }
}

bool wifi_manager_is_connected(void)
{
    return s_is_connected;
}

esp_err_t wifi_manager_disconnect(void)
{
    ESP_LOGI(TAG, "Disconnecting from WiFi...");
    s_is_connected = false;
    return esp_wifi_disconnect();
}

esp_err_t wifi_manager_get_ip_info(esp_netif_ip_info_t *ip_info)
{
    if (ip_info == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    if (!s_is_connected || s_sta_netif == NULL)
    {
        return ESP_FAIL;
    }

    return esp_netif_get_ip_info(s_sta_netif, ip_info);
}

esp_err_t wifi_manager_get_rssi(int8_t *rssi)
{
    if (rssi == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    if (!s_is_connected)
    {
        return ESP_FAIL;
    }

    wifi_ap_record_t ap_info;
    esp_err_t        ret = esp_wifi_sta_get_ap_info(&ap_info);
    if (ret == ESP_OK)
    {
        *rssi = ap_info.rssi;
    }

    return ret;
}
