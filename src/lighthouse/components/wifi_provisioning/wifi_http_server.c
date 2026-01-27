/**
 * wifi_http_server.c - WiFi Provisioning HTTP Server Implementation
 *
 * Implements a minimal HTTP server for WiFi provisioning:
 * - Serves HTML form for credential entry
 * - Handles form submission via POST
 * - Reports connection test results
 * - Provides device restart endpoint
 *
 * Reference:
 * - WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.3
 * - ESP-IDF HTTP Server documentation
 */

#include "wifi_http_server.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_spiffs.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "mqtt_client.h"
#include "mqtt_settings_storage.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *TAG = "WIFI_HTTP";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define MAX_ERROR_MSG_LEN       128
#define RESULT_WAIT_TIMEOUT_MS  15000 // Max time to wait for connection result
#define RESULT_POLL_INTERVAL_MS 200   // How often to check for result
#define MQTT_TEST_TIMEOUT_MS    5000  // Timeout for MQTT connection test
#define MQTT_CONNECTED_BIT      BIT0  // Event bit for MQTT connection

// ============================================================================
// MODULE STATE
// ============================================================================

static httpd_handle_t              server_handle        = NULL;
static wifi_credentials_callback_t credentials_callback = NULL;
static bool                        server_running       = false;

// Connection result state
static bool result_ready                    = false;
static bool result_success                  = false;
static char result_error[MAX_ERROR_MSG_LEN] = {0};

// Semaphore for synchronization between HTTP handler and state machine
static SemaphoreHandle_t result_semaphore = NULL;

// AP info for display
static char ap_ssid_display[33] = {0};

// SPIFFS state
static bool spiffs_initialized = false;

// MQTT test state
static EventGroupHandle_t       mqtt_test_event_group = NULL;
static esp_mqtt_client_handle_t mqtt_test_client      = NULL;

// Acknowledgment state for browser confirmation
typedef struct
{
    bool              ack_received;
    SemaphoreHandle_t ack_semaphore;
    uint32_t          expected_ack_id; // ID browser must send back
    uint32_t          next_msg_id;     // Counter for generating unique IDs
} ack_state_t;

static ack_state_t ack_state = {
    .ack_received    = false,
    .ack_semaphore   = NULL,
    .expected_ack_id = 0,
    .next_msg_id     = 1,
};

// ============================================================================
// SPIFFS INITIALIZATION
// ============================================================================

/**
 * Initialize SPIFFS filesystem
 * Must be called once before serving files
 */
static esp_err_t init_spiffs(void)
{
    if (spiffs_initialized)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing SPIFFS");

    esp_vfs_spiffs_conf_t conf = {
        .base_path              = "/spiffs",
        .partition_label        = "spiffs",
        .max_files              = 5,
        .format_if_mount_failed = false,
    };

    esp_err_t ret = esp_vfs_spiffs_register(&conf);

    if (ret != ESP_OK)
    {
        if (ret == ESP_ERR_NOT_FOUND)
        {
            ESP_LOGE(TAG, "SPIFFS partition not found. Check partitions.csv");
        }
        else
        {
            ESP_LOGE(TAG, "SPIFFS init failed: %s", esp_err_to_name(ret));
        }
        return ret;
    }

    // Verify files exist
    FILE *f = fopen("/spiffs/setup.html", "r");
    if (f == NULL)
    {
        ESP_LOGE(TAG, "setup.html not found in SPIFFS");
        return ESP_ERR_NOT_FOUND;
    }
    fclose(f);

    spiffs_initialized = true;
    ESP_LOGI(TAG, "SPIFFS initialized successfully");

    return ESP_OK;
}

// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

/**
 * URL decode a string in place
 * Handles %XX encoding and + for spaces
 */
static void url_decode(char *str)
{
    char *src    = str;
    char *dst    = str;
    char  hex[3] = {0};

    while (*src)
    {
        if (*src == '%' && src[1] && src[2])
        {
            hex[0] = src[1];
            hex[1] = src[2];
            *dst++ = (char)strtol(hex, NULL, 16);
            src += 3;
        }
        else if (*src == '+')
        {
            *dst++ = ' ';
            src++;
        }
        else
        {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

/**
 * Extract value for a key from URL-encoded form data
 * Returns pointer to value (must be freed by caller) or NULL if not found
 */
static char *extract_form_value(const char *content, const char *key)
{
    char search_key[64];
    snprintf(search_key, sizeof(search_key), "%s=", key);

    const char *start = strstr(content, search_key);
    if (!start)
    {
        return NULL;
    }

    start += strlen(search_key);
    const char *end = strchr(start, '&');
    size_t      len = end ? (size_t)(end - start) : strlen(start);

    char *value = malloc(len + 1);
    if (!value)
    {
        return NULL;
    }

    strncpy(value, start, len);
    value[len] = '\0';
    url_decode(value);

    return value;
}

// ============================================================================
// HTTP HANDLERS
// ============================================================================

/**
 * GET "/" - Serve provisioning webpage from SPIFFS
 */
static esp_err_t get_provisioning_page_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "GET / - Serving setup page from SPIFFS");

    // Open setup.html from SPIFFS
    FILE *f = fopen("/spiffs/setup.html", "r");
    if (f == NULL)
    {
        ESP_LOGE(TAG, "Failed to open setup.html");
        httpd_resp_send_404(req);
        return ESP_OK;
    }

    // Determine file size
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    // Set HTTP headers
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    httpd_resp_set_hdr(req, "Cache-Control", "no-cache");

    // Send file in chunks (avoid large buffer)
    char   buffer[512];
    size_t read_bytes;
    while ((read_bytes = fread(buffer, 1, sizeof(buffer), f)) > 0)
    {
        if (httpd_resp_send_chunk(req, buffer, read_bytes) != ESP_OK)
        {
            ESP_LOGE(TAG, "Error sending setup page chunk");
            fclose(f);
            return ESP_FAIL;
        }
    }

    // End response
    httpd_resp_send_chunk(req, NULL, 0);
    fclose(f);

    ESP_LOGI(TAG, "Setup page served successfully (%ld bytes)", file_size);

    return ESP_OK;
}

/**
 * Captive portal redirect handler (wildcard route)
 *
 * This handler catches all GET requests that don't match specific routes
 * (/, /configure, /restart) and redirects them to the provisioning page.
 * This enables captive portal detection on mobile devices and computers.
 *
 * When a device connects to the AP, it performs connectivity checks by
 * requesting URLs like captive.apple.com or connectivitycheck.gstatic.com.
 * By redirecting these requests to our setup page, the OS detects a
 * "captive portal" and automatically opens a browser.
 */
static esp_err_t captive_portal_handler(httpd_req_t *req)
{
    ESP_LOGD(TAG, "Captive portal redirect for: %s", req->uri);

    /* Set HTTP 302 Found status for redirect */
    httpd_resp_set_status(req, "302 Found");

    /* Set Location header to redirect to setup page */
    httpd_resp_set_hdr(req, "Location", "http://192.168.4.1/");

    /* Send empty response body (standard for redirects) */
    httpd_resp_send(req, NULL, 0);

    return ESP_OK;
}

/**
 * GET "/restart" - Restart device
 */
static esp_err_t get_restart_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "Restart requested via HTTP");

    // Send response before restarting
    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr(req, "<!DOCTYPE html><html><head>"
                            "<meta charset=\"UTF-8\">"
                            "<title>Restarting...</title>"
                            "<style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;}</style>"
                            "</head><body>"
                            "<h1>Restarting device...</h1>"
                            "<p>Please wait. The device will reconnect to the configured network.</p>"
                            "</body></html>");

    // Brief delay to ensure response is sent
    vTaskDelay(pdMS_TO_TICKS(500));

    // Restart the device
    ESP_LOGI(TAG, "Restarting device...");
    esp_restart();

    // Never reached
    return ESP_OK;
}

/**
 * POST "/ack" - Browser acknowledgment
 *
 * Called by browser after displaying result.
 * Verifies the ack_id matches expected, then signals that user has seen the message.
 */
static esp_err_t post_ack_handler(httpd_req_t *req)
{
    // Read request body to get ack_id
    char content[64] = {0};
    int  content_len = req->content_len;

    if (content_len > 0 && content_len < (int)sizeof(content))
    {
        int received = httpd_req_recv(req, content, content_len);
        if (received == content_len)
        {
            content[content_len] = '\0';
        }
    }

    // Parse ack_id from content (format: "ack_id=123")
    uint32_t received_id = 0;
    char    *id_str      = strstr(content, "ack_id=");
    if (id_str)
    {
        received_id = (uint32_t)strtoul(id_str + 7, NULL, 10);
    }

    ESP_LOGI(TAG, "Browser ack received: id=%lu, expected=%lu", (unsigned long)received_id,
             (unsigned long)ack_state.expected_ack_id);

    // Verify ID matches
    if (received_id != ack_state.expected_ack_id)
    {
        ESP_LOGW(TAG, "Ack ID mismatch - ignoring stale acknowledgment");
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"ignored\",\"reason\":\"id_mismatch\"}");
        return ESP_OK;
    }

    // Mark acknowledgment received
    ack_state.ack_received = true;

    // Signal waiting handler
    if (ack_state.ack_semaphore)
    {
        xSemaphoreGive(ack_state.ack_semaphore);
    }

    // Return success response
    httpd_resp_set_type(req, "application/json");
    httpd_resp_sendstr(req, "{\"status\":\"ack_received\"}");

    return ESP_OK;
}

/**
 * POST "/test/wifi" - Test WiFi connectivity
 *
 * Tests WiFi connection without saving credentials.
 * Returns JSON: {"status": "ok|fail", "message": "..."}
 */
static esp_err_t post_test_wifi_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "Received WiFi test request");

    // Read request body
    char content[256] = {0};
    int  content_len  = req->content_len;

    if (content_len <= 0 || content_len >= (int)sizeof(content))
    {
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Invalid request\"}");
        return ESP_OK;
    }

    int received = httpd_req_recv(req, content, content_len);
    if (received != content_len)
    {
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Failed to read request\"}");
        return ESP_OK;
    }
    content[content_len] = '\0';

    // Extract SSID and password from URL-encoded form
    char *ssid     = extract_form_value(content, "ssid");
    char *password = extract_form_value(content, "password");

    if (!ssid || !password)
    {
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"SSID and password required\"}");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Testing WiFi connection to: %s", ssid);

    // Clear previous result
    wifi_http_server_clear_result();

    // Call callback to initiate connection test
    if (credentials_callback)
    {
        credentials_callback(ssid, password);
    }
    else
    {
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Server not ready\"}");
        return ESP_OK;
    }

    free(ssid);
    free(password);

    // Wait for connection result
    bool        success   = false;
    const char *error_msg = NULL;
    esp_err_t   wait_ret  = wifi_http_server_wait_connection_result(RESULT_WAIT_TIMEOUT_MS, &success, &error_msg);

    httpd_resp_set_type(req, "application/json");
    char response[256];

    if (wait_ret == ESP_ERR_TIMEOUT)
    {
        snprintf(response, sizeof(response), "{\"status\":\"fail\",\"message\":\"Connection test timeout\"}");
    }
    else if (success)
    {
        snprintf(response, sizeof(response), "{\"status\":\"ok\",\"message\":\"WiFi connection successful\"}");
    }
    else
    {
        snprintf(response, sizeof(response), "{\"status\":\"fail\",\"message\":\"%s\"}",
                 error_msg ? error_msg : "Connection failed");
    }

    httpd_resp_sendstr(req, response);
    return ESP_OK;
}

/**
 * MQTT test event handler
 *
 * Used for testing MQTT broker connectivity.
 */
static void mqtt_test_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    switch ((esp_mqtt_event_id_t)event_id)
    {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "MQTT test: Connected to broker");
        if (mqtt_test_event_group)
        {
            xEventGroupSetBits(mqtt_test_event_group, MQTT_CONNECTED_BIT);
        }
        break;

    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGI(TAG, "MQTT test: Disconnected");
        break;

    case MQTT_EVENT_ERROR:
        ESP_LOGE(TAG, "MQTT test: Connection error");
        break;

    default:
        break;
    }
}

/**
 * POST "/test/mqtt" - Test MQTT broker connectivity
 *
 * Tests connection to MQTT broker without persisting.
 * Returns JSON: {"status": "ok|fail", "message": "..."}
 */
static esp_err_t post_test_mqtt_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "Received MQTT test request");

    // Read request body
    char content[128] = {0};
    int  content_len  = req->content_len;

    if (content_len <= 0 || content_len >= (int)sizeof(content))
    {
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Invalid request\"}");
        return ESP_OK;
    }

    int received = httpd_req_recv(req, content, content_len);
    if (received != content_len)
    {
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Failed to read request\"}");
        return ESP_OK;
    }
    content[content_len] = '\0';

    // Extract MQTT IP and port from URL-encoded form
    char *mqtt_ip       = extract_form_value(content, "mqtt_ip");
    char *mqtt_port_str = extract_form_value(content, "mqtt_port");

    if (!mqtt_ip || !mqtt_port_str)
    {
        free(mqtt_ip);
        free(mqtt_port_str);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"MQTT IP and port required\"}");
        return ESP_OK;
    }

    // Validate IP
    if (!mqtt_settings_validate_ip(mqtt_ip))
    {
        free(mqtt_ip);
        free(mqtt_port_str);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Invalid IP address format\"}");
        return ESP_OK;
    }

    // Parse and validate port
    uint16_t mqtt_port = (uint16_t)atoi(mqtt_port_str);
    if (!mqtt_settings_validate_port(mqtt_port))
    {
        free(mqtt_ip);
        free(mqtt_port_str);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Invalid port number\"}");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Testing MQTT connection to: %s:%u", mqtt_ip, mqtt_port);

    // Create event group for test
    if (mqtt_test_event_group == NULL)
    {
        mqtt_test_event_group = xEventGroupCreate();
    }
    else
    {
        xEventGroupClearBits(mqtt_test_event_group, MQTT_CONNECTED_BIT);
    }

    // Build broker URI
    char broker_uri[64];
    snprintf(broker_uri, sizeof(broker_uri), "mqtt://%s:%u", mqtt_ip, mqtt_port);

    free(mqtt_ip);
    free(mqtt_port_str);

    // Configure MQTT client for test
    esp_mqtt_client_config_t mqtt_cfg = {
        .broker.address.uri           = broker_uri,
        .session.protocol_ver         = MQTT_PROTOCOL_V_3_1_1,
        .session.keepalive            = 10,
        .network.reconnect_timeout_ms = 1000,
        .network.timeout_ms           = MQTT_TEST_TIMEOUT_MS,
    };

    // Create test client
    mqtt_test_client = esp_mqtt_client_init(&mqtt_cfg);
    if (mqtt_test_client == NULL)
    {
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Failed to create MQTT client\"}");
        return ESP_OK;
    }

    // Register event handler
    esp_mqtt_client_register_event(mqtt_test_client, ESP_EVENT_ANY_ID, mqtt_test_event_handler, NULL);

    // Start client
    esp_err_t start_ret = esp_mqtt_client_start(mqtt_test_client);
    if (start_ret != ESP_OK)
    {
        esp_mqtt_client_destroy(mqtt_test_client);
        mqtt_test_client = NULL;
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Failed to start MQTT client\"}");
        return ESP_OK;
    }

    // Wait for connection result
    EventBits_t bits = xEventGroupWaitBits(mqtt_test_event_group, MQTT_CONNECTED_BIT,
                                           pdTRUE,  // Clear on exit
                                           pdFALSE, // Wait for any bit
                                           pdMS_TO_TICKS(MQTT_TEST_TIMEOUT_MS));

    // Cleanup test client
    esp_mqtt_client_stop(mqtt_test_client);
    esp_mqtt_client_destroy(mqtt_test_client);
    mqtt_test_client = NULL;

    // Send response
    httpd_resp_set_type(req, "application/json");

    if (bits & MQTT_CONNECTED_BIT)
    {
        ESP_LOGI(TAG, "MQTT test successful");
        httpd_resp_sendstr(req, "{\"status\":\"ok\",\"message\":\"MQTT broker connection successful\"}");
    }
    else
    {
        ESP_LOGW(TAG, "MQTT test failed - connection timeout");
        httpd_resp_sendstr(req, "{\"status\":\"fail\",\"message\":\"Could not connect to MQTT broker\"}");
    }

    return ESP_OK;
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t wifi_http_server_start(const char *ap_ssid, const char *ap_password)
{
    if (server_running)
    {
        ESP_LOGW(TAG, "HTTP server already running");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting HTTP server");

    // Initialize SPIFFS (load HTML file)
    esp_err_t spiffs_ret = init_spiffs();
    if (spiffs_ret != ESP_OK)
    {
        ESP_LOGE(TAG, "SPIFFS init failed, cannot serve setup page");
        return spiffs_ret;
    }

    // Store AP SSID for display
    if (ap_ssid)
    {
        strncpy(ap_ssid_display, ap_ssid, sizeof(ap_ssid_display) - 1);
        ap_ssid_display[sizeof(ap_ssid_display) - 1] = '\0';
    }

    // Configure HTTP server
    httpd_config_t config   = HTTPD_DEFAULT_CONFIG();
    config.stack_size       = 8192;
    config.max_uri_handlers = 10;                       // Increased to accommodate test endpoints
    config.lru_purge_enable = true;
    config.uri_match_fn     = httpd_uri_match_wildcard; // Enable wildcard matching

    // Start HTTP server
    esp_err_t ret = httpd_start(&server_handle, &config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start HTTP server: %s", esp_err_to_name(ret));
        return ret;
    }

    // Register URI handlers
    httpd_uri_t uri_get_root = {
        .uri      = "/",
        .method   = HTTP_GET,
        .handler  = get_provisioning_page_handler,
        .user_ctx = NULL,
    };

    httpd_uri_t uri_get_restart = {
        .uri      = "/restart",
        .method   = HTTP_GET,
        .handler  = get_restart_handler,
        .user_ctx = NULL,
    };

    httpd_uri_t uri_post_ack = {
        .uri      = "/ack",
        .method   = HTTP_POST,
        .handler  = post_ack_handler,
        .user_ctx = NULL,
    };

    httpd_register_uri_handler(server_handle, &uri_get_root);
    httpd_register_uri_handler(server_handle, &uri_get_restart);
    httpd_register_uri_handler(server_handle, &uri_post_ack);

    // Register test endpoints
    httpd_uri_t uri_test_wifi = {
        .uri      = "/test/wifi",
        .method   = HTTP_POST,
        .handler  = post_test_wifi_handler,
        .user_ctx = NULL,
    };
    httpd_register_uri_handler(server_handle, &uri_test_wifi);

    httpd_uri_t uri_test_mqtt = {
        .uri      = "/test/mqtt",
        .method   = HTTP_POST,
        .handler  = post_test_mqtt_handler,
        .user_ctx = NULL,
    };
    httpd_register_uri_handler(server_handle, &uri_test_mqtt);

    // Register wildcard handler LAST - catches all other GET requests for captive portal
    // This must be registered after specific handlers so they take priority
    httpd_uri_t uri_captive_portal = {
        .uri      = "/*",
        .method   = HTTP_GET,
        .handler  = captive_portal_handler,
        .user_ctx = NULL,
    };
    httpd_register_uri_handler(server_handle, &uri_captive_portal);

    server_running = true;
    ESP_LOGI(TAG, "HTTP server started on port 80 with captive portal support");

    return ESP_OK;
}

esp_err_t wifi_http_server_stop(void)
{
    if (!server_running || !server_handle)
    {
        ESP_LOGD(TAG, "HTTP server not running");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping HTTP server");

    esp_err_t ret  = httpd_stop(server_handle);
    server_handle  = NULL;
    server_running = false;

    // Clear result state
    wifi_http_server_clear_result();

    return ret;
}

void wifi_http_server_set_credentials_callback(wifi_credentials_callback_t callback)
{
    credentials_callback = callback;
    ESP_LOGD(TAG, "Credentials callback %s", callback ? "registered" : "cleared");
}

void wifi_http_server_set_connection_result(bool success, const char *error_message)
{
    result_success = success;

    if (!success && error_message)
    {
        strncpy(result_error, error_message, sizeof(result_error) - 1);
        result_error[sizeof(result_error) - 1] = '\0';
    }
    else
    {
        result_error[0] = '\0';
    }

    result_ready = true;

    // Signal waiting HTTP handler via semaphore
    if (result_semaphore != NULL)
    {
        xSemaphoreGive(result_semaphore);
    }

    ESP_LOGI(TAG, "Connection result set: success=%d, error=%s", success, result_error[0] ? result_error : "(none)");
}

bool wifi_http_server_is_result_ready(void)
{
    return result_ready;
}

bool wifi_http_server_get_result_success(void)
{
    return result_success;
}

const char *wifi_http_server_get_result_error(void)
{
    if (result_error[0] == '\0')
    {
        return NULL;
    }
    return result_error;
}

void wifi_http_server_clear_result(void)
{
    result_ready    = false;
    result_success  = false;
    result_error[0] = '\0';

    // Ensure semaphore is in taken state (not signaled)
    if (result_semaphore != NULL)
    {
        // Try to take without blocking - this clears any pending signal
        xSemaphoreTake(result_semaphore, 0);
    }
}

esp_err_t wifi_http_server_wait_connection_result(uint32_t timeout_ms, bool *out_success, const char **out_error)
{
    if (out_success == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    // Create semaphore on first use
    if (result_semaphore == NULL)
    {
        result_semaphore = xSemaphoreCreateBinary();
        if (result_semaphore == NULL)
        {
            ESP_LOGE(TAG, "Failed to create result semaphore");
            return ESP_ERR_NO_MEM;
        }
    }

    // If result is already ready, return immediately
    if (result_ready)
    {
        *out_success = result_success;
        if (out_error != NULL)
        {
            *out_error = result_error[0] ? result_error : NULL;
        }
        return ESP_OK;
    }

    // Wait for semaphore signal (with timeout)
    BaseType_t ret = xSemaphoreTake(result_semaphore, pdMS_TO_TICKS(timeout_ms));

    if (ret == pdTRUE)
    {
        // Result is now ready
        *out_success = result_success;
        if (out_error != NULL)
        {
            *out_error = result_error[0] ? result_error : NULL;
        }
        return ESP_OK;
    }
    else
    {
        // Timeout
        ESP_LOGW(TAG, "Timeout waiting for connection result");
        return ESP_ERR_TIMEOUT;
    }
}

bool wifi_http_server_is_running(void)
{
    return server_running;
}

esp_err_t wifi_http_server_wait_for_ack(uint32_t timeout_ms)
{
    // Create semaphore on first use
    if (ack_state.ack_semaphore == NULL)
    {
        ack_state.ack_semaphore = xSemaphoreCreateBinary();
        if (ack_state.ack_semaphore == NULL)
        {
            ESP_LOGE(TAG, "Failed to create ack semaphore");
            return ESP_ERR_NO_MEM;
        }
    }

    // Reset acknowledgment flag
    ack_state.ack_received = false;

    // Wait for acknowledgment
    BaseType_t ret = xSemaphoreTake(ack_state.ack_semaphore, pdMS_TO_TICKS(timeout_ms));

    if (ret == pdTRUE)
    {
        ESP_LOGI(TAG, "Acknowledgment received from browser");
        return ESP_OK;
    }
    else
    {
        ESP_LOGW(TAG, "Acknowledgment timeout - browser may not have received result");
        return ESP_ERR_TIMEOUT;
    }
}
