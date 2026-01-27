/**
 * mqtt_settings_storage.c - MQTT Broker Configuration Storage Implementation
 *
 * Implements MQTT broker configuration storage using NVS.
 * Uses the same partition as WiFi credentials for simplicity.
 *
 * Reference: tasks/mqtt_setup.md
 */

#include "mqtt_settings_storage.h"
#include "esp_log.h"
#include "lwip/inet.h"
#include "nvs_flash.h"
#include <string.h>

static const char *TAG = "MQTT_STORAGE";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define NVS_PARTITION_NAME "nvs_settings"
#define NVS_NAMESPACE      "mqtt_settings"
#define NVS_BROKER_IP_KEY  "mqtt_broker_ip"
#define NVS_BROKER_PORT_KEY "mqtt_broker_port"
#define NVS_CONFIGURED_KEY "mqtt_configured"

// NVS handle (opened during init)
static nvs_handle_t mqtt_nvs_handle = 0;
static bool         nvs_initialized = false;

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

mqtt_storage_error_t mqtt_settings_init(void)
{
    if (nvs_initialized)
    {
        return MQTT_STORAGE_OK; // Already initialized
    }

    ESP_LOGI(TAG, "Initializing MQTT settings storage");

    // Initialize the nvs_settings partition (may already be initialized by wifi_settings)
    esp_err_t ret = nvs_flash_init_partition(NVS_PARTITION_NAME);
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        // This case should be rare since wifi_settings usually inits first
        ESP_LOGW(TAG, "NVS partition needs erase, reinitializing");
        ret = nvs_flash_erase_partition(NVS_PARTITION_NAME);
        if (ret != ESP_OK)
        {
            ESP_LOGE(TAG, "Failed to erase NVS partition: %s", esp_err_to_name(ret));
            return MQTT_STORAGE_WRITE_ERROR;
        }
        ret = nvs_flash_init_partition(NVS_PARTITION_NAME);
    }

    if (ret != ESP_OK && ret != ESP_ERR_NVS_NO_FREE_PAGES)
    {
        // ESP_ERR_NVS_NO_FREE_PAGES can happen if already initialized
        if (ret != ESP_OK)
        {
            ESP_LOGE(TAG, "NVS flash init failed: %s", esp_err_to_name(ret));
            return MQTT_STORAGE_WRITE_ERROR;
        }
    }

    // Open namespace for read/write access
    ret = nvs_open_from_partition(NVS_PARTITION_NAME, NVS_NAMESPACE, NVS_READWRITE, &mqtt_nvs_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to open NVS namespace: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    nvs_initialized = true;

    // Check if defaults need to be written
    if (!mqtt_settings_is_configured())
    {
        ESP_LOGI(TAG, "No MQTT config found, writing defaults");
        mqtt_storage_error_t err = mqtt_settings_save(MQTT_DEFAULT_BROKER_IP, MQTT_DEFAULT_BROKER_PORT);
        if (err != MQTT_STORAGE_OK)
        {
            ESP_LOGW(TAG, "Failed to write default MQTT settings");
        }
    }

    ESP_LOGI(TAG, "MQTT settings storage initialized successfully");

    return MQTT_STORAGE_OK;
}

bool mqtt_settings_is_configured(void)
{
    if (!nvs_initialized)
    {
        return false;
    }

    uint8_t   configured = 0;
    esp_err_t ret        = nvs_get_u8(mqtt_nvs_handle, NVS_CONFIGURED_KEY, &configured);

    if (ret == ESP_ERR_NVS_NOT_FOUND)
    {
        return false;
    }
    else if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to read configured flag: %s", esp_err_to_name(ret));
        return false;
    }

    return (configured == 1);
}

mqtt_storage_error_t mqtt_settings_load(mqtt_broker_config_t *config)
{
    if (!config)
    {
        return MQTT_STORAGE_INVALID_PARAM;
    }

    if (!nvs_initialized)
    {
        ESP_LOGE(TAG, "MQTT storage not initialized");
        // Return defaults
        strncpy(config->broker_ip, MQTT_DEFAULT_BROKER_IP, sizeof(config->broker_ip) - 1);
        config->broker_ip[sizeof(config->broker_ip) - 1] = '\0';
        config->broker_port = MQTT_DEFAULT_BROKER_PORT;
        return MQTT_STORAGE_OK;
    }

    // Read broker IP
    size_t    ip_len = sizeof(config->broker_ip);
    esp_err_t ret    = nvs_get_str(mqtt_nvs_handle, NVS_BROKER_IP_KEY, config->broker_ip, &ip_len);
    if (ret == ESP_ERR_NVS_NOT_FOUND)
    {
        ESP_LOGD(TAG, "Broker IP not found, using default");
        strncpy(config->broker_ip, MQTT_DEFAULT_BROKER_IP, sizeof(config->broker_ip) - 1);
        config->broker_ip[sizeof(config->broker_ip) - 1] = '\0';
    }
    else if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to read broker IP: %s", esp_err_to_name(ret));
        strncpy(config->broker_ip, MQTT_DEFAULT_BROKER_IP, sizeof(config->broker_ip) - 1);
        config->broker_ip[sizeof(config->broker_ip) - 1] = '\0';
    }

    // Read broker port
    ret = nvs_get_u16(mqtt_nvs_handle, NVS_BROKER_PORT_KEY, &config->broker_port);
    if (ret == ESP_ERR_NVS_NOT_FOUND)
    {
        ESP_LOGD(TAG, "Broker port not found, using default");
        config->broker_port = MQTT_DEFAULT_BROKER_PORT;
    }
    else if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to read broker port: %s", esp_err_to_name(ret));
        config->broker_port = MQTT_DEFAULT_BROKER_PORT;
    }

    ESP_LOGI(TAG, "Loaded MQTT config: %s:%u", config->broker_ip, config->broker_port);

    return MQTT_STORAGE_OK;
}

mqtt_storage_error_t mqtt_settings_save(const char *broker_ip, uint16_t broker_port)
{
    if (!broker_ip)
    {
        return MQTT_STORAGE_INVALID_PARAM;
    }

    // Validate IP format
    if (!mqtt_settings_validate_ip(broker_ip))
    {
        ESP_LOGE(TAG, "Invalid IP address format: %s", broker_ip);
        return MQTT_STORAGE_INVALID_PARAM;
    }

    // Validate port
    if (!mqtt_settings_validate_port(broker_port))
    {
        ESP_LOGE(TAG, "Invalid port number: %u", broker_port);
        return MQTT_STORAGE_INVALID_PARAM;
    }

    if (!nvs_initialized)
    {
        ESP_LOGE(TAG, "MQTT storage not initialized");
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Write broker IP
    esp_err_t ret = nvs_set_str(mqtt_nvs_handle, NVS_BROKER_IP_KEY, broker_ip);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to write broker IP: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Write broker port
    ret = nvs_set_u16(mqtt_nvs_handle, NVS_BROKER_PORT_KEY, broker_port);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to write broker port: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Write configured flag
    ret = nvs_set_u8(mqtt_nvs_handle, NVS_CONFIGURED_KEY, 1);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to write configured flag: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Commit changes to flash
    ret = nvs_commit(mqtt_nvs_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to commit NVS changes: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    ESP_LOGI(TAG, "MQTT config saved: %s:%u", broker_ip, broker_port);

    return MQTT_STORAGE_OK;
}

mqtt_storage_error_t mqtt_settings_reset_to_defaults(void)
{
    if (!nvs_initialized)
    {
        ESP_LOGE(TAG, "MQTT storage not initialized");
        return MQTT_STORAGE_WRITE_ERROR;
    }

    ESP_LOGI(TAG, "Resetting MQTT settings to defaults");

    // Erase all keys in namespace
    esp_err_t ret = nvs_erase_all(mqtt_nvs_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to erase MQTT namespace: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Commit the erase
    ret = nvs_commit(mqtt_nvs_handle);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to commit erase: %s", esp_err_to_name(ret));
        return MQTT_STORAGE_WRITE_ERROR;
    }

    // Write defaults
    mqtt_storage_error_t err = mqtt_settings_save(MQTT_DEFAULT_BROKER_IP, MQTT_DEFAULT_BROKER_PORT);
    if (err != MQTT_STORAGE_OK)
    {
        return err;
    }

    ESP_LOGI(TAG, "MQTT settings reset to defaults");

    return MQTT_STORAGE_OK;
}

bool mqtt_settings_validate_ip(const char *ip)
{
    if (!ip || strlen(ip) == 0 || strlen(ip) > MQTT_BROKER_IP_MAX_LEN)
    {
        return false;
    }

    // Use lwIP inet_aton for validation
    struct in_addr addr;
    return (inet_aton(ip, &addr) != 0);
}

bool mqtt_settings_validate_port(uint16_t port)
{
    return (port >= 1); //  && port <= 65535 is implicit by datatype
}

const char *mqtt_settings_error_to_string(mqtt_storage_error_t err)
{
    switch (err)
    {
    case MQTT_STORAGE_OK:
        return "OK";
    case MQTT_STORAGE_NOT_FOUND:
        return "Not found";
    case MQTT_STORAGE_WRITE_ERROR:
        return "Write error";
    case MQTT_STORAGE_INVALID_PARAM:
        return "Invalid parameter";
    default:
        return "Unknown error";
    }
}
