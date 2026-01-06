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
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

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

// AP info for display
static char ap_ssid_display[33] = {0};

// ============================================================================
// HTML PAGE CONTENT
// ============================================================================

static const char *PROVISIONING_PAGE_HTML =
    "<!DOCTYPE html>"
    "<html>"
    "<head>"
    "<title>Lighthouse WiFi Setup</title>"
    "<meta charset=\"UTF-8\">"
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    "<style>"
    "body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}"
    ".container{max-width:400px;margin:0 auto;background:#fff;padding:20px;"
    "border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}"
    "h1{font-size:22px;color:#333;margin-bottom:20px;}"
    "form{margin:20px 0;}"
    "label{display:block;margin-top:15px;font-weight:bold;color:#555;}"
    "input[type=text],input[type=password]{width:100%;padding:10px;"
    "margin:5px 0 10px 0;box-sizing:border-box;border:1px solid #ddd;"
    "border-radius:4px;font-size:16px;}"
    "button{padding:12px 20px;background:#007bff;color:white;border:none;"
    "cursor:pointer;font-size:16px;width:100%;border-radius:4px;margin-top:10px;}"
    "button:hover{background:#0056b3;}"
    "button:disabled{background:#ccc;cursor:not-allowed;}"
    ".status{margin-top:20px;padding:15px;border-radius:4px;display:none;}"
    ".status.show{display:block;}"
    ".status.info{background:#e7f3ff;border:1px solid #b3d7ff;color:#004085;}"
    ".status.success{background:#d4edda;border:1px solid #c3e6cb;color:#155724;}"
    ".status.error{background:#f8d7da;border:1px solid #f5c6cb;color:#721c24;}"
    ".restart-btn{background:#28a745;margin-top:15px;}"
    ".restart-btn:hover{background:#1e7e34;}"
    "</style>"
    "</head>"
    "<body>"
    "<div class=\"container\">"
    "<h1>Lighthouse WiFi Setup</h1>"
    "<form id=\"setupForm\">"
    "<label for=\"ssid\">WiFi Network (SSID):</label>"
    "<input type=\"text\" id=\"ssid\" name=\"ssid\" required maxlength=\"31\" "
    "placeholder=\"Enter network name\">"
    "<label for=\"password\">Password:</label>"
    "<input type=\"password\" id=\"password\" name=\"password\" required "
    "minlength=\"8\" maxlength=\"63\" placeholder=\"Enter password (min 8 chars)\">"
    "<button type=\"submit\" id=\"submitBtn\">Test Connection</button>"
    "</form>"
    "<div class=\"status\" id=\"status\"></div>"
    "</div>"
    "<script>"
    "const form=document.getElementById('setupForm');"
    "const status=document.getElementById('status');"
    "const submitBtn=document.getElementById('submitBtn');"
    "form.onsubmit=async(e)=>{"
    "e.preventDefault();"
    "const fd=new FormData(form);"
    "submitBtn.disabled=true;"
    "submitBtn.textContent='Testing...';"
    "status.className='status show info';"
    "status.textContent='Testing WiFi connection...';"
    "try{"
    "const res=await fetch('/configure',{method:'POST',body:fd});"
    "const json=await res.json();"
    "if(json.status==='success'){"
    "status.className='status show success';"
    "status.innerHTML=json.message+"
    "'<br><button class=\"restart-btn\" onclick=\"location.href=\\'/restart\\'\">Restart Device</button>';"
    "}else{"
    "status.className='status show error';"
    "status.textContent=json.message;"
    "submitBtn.disabled=false;"
    "submitBtn.textContent='Test Connection';"
    "}"
    "}catch(err){"
    "status.className='status show error';"
    "status.textContent='Connection error: '+err.message;"
    "submitBtn.disabled=false;"
    "submitBtn.textContent='Test Connection';"
    "}"
    "};"
    "</script>"
    "</body>"
    "</html>";

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
 * GET "/" - Serve provisioning webpage
 */
static esp_err_t get_provisioning_page_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "Serving provisioning page");

    httpd_resp_set_type(req, "text/html");
    httpd_resp_set_hdr(req, "Cache-Control", "no-cache");
    httpd_resp_send(req, PROVISIONING_PAGE_HTML, strlen(PROVISIONING_PAGE_HTML));

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

    // Wait for connection result with timeout
    uint32_t wait_start = xTaskGetTickCount() * portTICK_PERIOD_MS;
    while (!result_ready)
    {
        uint32_t elapsed = (xTaskGetTickCount() * portTICK_PERIOD_MS) - wait_start;
        if (elapsed >= RESULT_WAIT_TIMEOUT_MS)
        {
            ESP_LOGW(TAG, "Timeout waiting for connection result");
            httpd_resp_set_type(req, "application/json");
            httpd_resp_sendstr(req, "{\"status\":\"error\",\"message\":\"Connection test timeout\"}");
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(RESULT_POLL_INTERVAL_MS));
    }

    // Send result to client
    httpd_resp_set_type(req, "application/json");

    if (result_success)
    {
        ESP_LOGI(TAG, "Connection successful, sending success response");
        httpd_resp_sendstr(req, "{\"status\":\"success\",\"message\":\"Connected successfully! Click the button below "
                                "to restart the device.\"}");
    }
    else
    {
        char response[256];
        snprintf(response, sizeof(response), "{\"status\":\"error\",\"message\":\"%s\"}",
                 result_error[0] ? result_error : "Connection failed");
        ESP_LOGI(TAG, "Connection failed, sending error response");
        httpd_resp_sendstr(req, response);
    }

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

    // Store AP SSID for display
    if (ap_ssid)
    {
        strncpy(ap_ssid_display, ap_ssid, sizeof(ap_ssid_display) - 1);
        ap_ssid_display[sizeof(ap_ssid_display) - 1] = '\0';
    }

    // Configure HTTP server
    httpd_config_t config   = HTTPD_DEFAULT_CONFIG();
    config.stack_size       = 8192;
    config.max_uri_handlers = 4;
    config.lru_purge_enable = true;

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

    server_running = true;
    ESP_LOGI(TAG, "HTTP server started on port 80");

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
}

bool wifi_http_server_is_running(void)
{
    return server_running;
}
