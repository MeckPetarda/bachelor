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
#include "esp_system.h"
#include "esp_spiffs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include <string.h>
#include <stdio.h>

static const char *TAG = "WIFI_HTTP";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define MAX_ERROR_MSG_LEN       128
#define RESULT_WAIT_TIMEOUT_MS  15000 // Max time to wait for connection result
#define RESULT_POLL_INTERVAL_MS 200   // How often to check for result

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

static char *extract_multipart_value(const char *content, const char *key)
{
    // Build the pattern we're looking for: name="<key>"
    char name_pattern[128];
    snprintf(name_pattern, sizeof(name_pattern), "name=\"%s\"", key);

    // Find the field in the multipart data
    const char *field_start = strstr(content, name_pattern);
    if (!field_start)
    {
        return NULL;
    }

    // Move past the name="key" line to find the value
    // The value starts after the next \r\n\r\n (empty line separating headers from content)
    const char *value_start = strstr(field_start, "\r\n\r\n");
    if (!value_start)
    {
        return NULL;
    }

    value_start += 4; // Skip the \r\n\r\n

    // Find the end of the value (next boundary marker which starts with \r\n---)
    const char *value_end = strstr(value_start, "\r\n");
    if (!value_end)
    {
        return NULL;
    }

    size_t len = (size_t)(value_end - value_start);

    char *value = malloc(len + 1);
    if (!value)
    {
        return NULL;
    }

    strncpy(value, value_start, len);
    value[len] = '\0';

    return value;
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
    char buffer[512];
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
 * POST "/configure" - Handle credential submission
 */
static esp_err_t post_configure_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "Received configuration request");

    // Read request body
    char content[512] = {0};
    int  content_len  = req->content_len;

    if (content_len <= 0 || content_len >= (int)sizeof(content))
    {
        ESP_LOGE(TAG, "Invalid content length: %d", content_len);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Invalid request\"}");
        return ESP_OK;
    }

    int received = httpd_req_recv(req, content, content_len);
    if (received != content_len)
    {
        ESP_LOGE(TAG, "Failed to receive content: expected %d, got %d", content_len, received);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Failed to read request\"}");
        return ESP_OK;
    }
    content[content_len] = '\0';

    ESP_LOGI(TAG, "Form data: %s", content);

    // Extract SSID and password
    char *ssid     = extract_multipart_value(content, "ssid");
    char *password = extract_multipart_value(content, "password");

    if (!ssid || !password)
    {
        ESP_LOGE(TAG, "Missing SSID or password in form data");
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"SSID and password are required\"}");
        return ESP_OK;
    }

    // Validate SSID
    size_t ssid_len = strlen(ssid);
    if (ssid_len == 0 || ssid_len > 31)
    {
        ESP_LOGE(TAG, "Invalid SSID length: %zu", ssid_len);
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"SSID must be 1-31 characters\"}");
        return ESP_OK;
    }

    // Validate password
    size_t password_len = strlen(password);
    if (password_len < 8 || password_len > 63)
    {
        ESP_LOGE(TAG, "Invalid password length: %zu", password_len);
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Password must be 8-63 characters\"}");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Testing connection to SSID: %s", ssid);

    // Clear previous result
    wifi_http_server_clear_result();

    // Call callback to initiate connection test
    if (credentials_callback)
    {
        credentials_callback(ssid, password);
    }
    else
    {
        ESP_LOGW(TAG, "No credentials callback registered");
        free(ssid);
        free(password);
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Server not ready\"}");
        return ESP_OK;
    }

    free(ssid);
    free(password);

    // Wait for connection result using semaphore (with timeout)
    bool        success   = false;
    const char *error_msg = NULL;
    esp_err_t   wait_ret  = wifi_http_server_wait_connection_result(RESULT_WAIT_TIMEOUT_MS, &success, &error_msg);

    // Send result to client
    httpd_resp_set_type(req, "application/json");

    if (wait_ret == ESP_ERR_TIMEOUT)
    {
        ESP_LOGW(TAG, "Timeout waiting for connection result");
        httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Connection test timeout\"}");
    }
    else if (wait_ret == ESP_OK && success)
    {
        ESP_LOGI(TAG, "Connection successful, sending success response");
        httpd_resp_sendstr(req, "{\"status\":\"success\",\"message\":\"Connected successfully! Click the button below "
                                "to restart the device.\"}");
    }
    else
    {
        char response[256];
        snprintf(response, sizeof(response), "{\"status\":\"error\",\"message\":\"%s\"}",
                 error_msg ? error_msg : "Connection failed");
        ESP_LOGI(TAG, "Connection failed, sending error response");
        httpd_resp_sendstr(req, response);
    }

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
    config.max_uri_handlers = 8;  // Increased to accommodate wildcard handler
    config.lru_purge_enable = true;
    config.uri_match_fn     = httpd_uri_match_wildcard;  // Enable wildcard matching

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

    httpd_uri_t uri_post_configure = {
        .uri      = "/configure",
        .method   = HTTP_POST,
        .handler  = post_configure_handler,
        .user_ctx = NULL,
    };

    httpd_uri_t uri_get_restart = {
        .uri      = "/restart",
        .method   = HTTP_GET,
        .handler  = get_restart_handler,
        .user_ctx = NULL,
    };

    httpd_register_uri_handler(server_handle, &uri_get_root);
    httpd_register_uri_handler(server_handle, &uri_post_configure);
    httpd_register_uri_handler(server_handle, &uri_get_restart);

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
