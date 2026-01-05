/**
 * wifi_settings_storage.c - WiFi Credential Storage Implementation
 *
 * Implements encrypted credential storage using AES-128 and NVS.
 *
 * Reference:
 * - ESP32 TRM Section 14 (AES Accelerator)
 * - ESP-IDF NVS documentation
 * - WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.1
 */

#include <string.h>
#include <stdlib.h>
#include "wifi_settings_storage.h"
#include "nvs_flash.h"
#include "mbedtls/aes.h"
#include "esp_log.h"

static const char* TAG = "WIFI_STORAGE";

// ============================================================================
// CONFIGURATION
// ============================================================================

#define NVS_PARTITION_NAME      "nvs_settings"
#define NVS_NAMESPACE           "wifi_settings"
#define NVS_CONFIGURED_KEY      "configured"
#define NVS_SSID_KEY            "ssid_enc"
#define NVS_PASSWORD_KEY        "pass_enc"

#define SSID_MAX_LEN            31      // 32 with null terminator
#define PASSWORD_MIN_LEN        8       // WPA2 requirement
#define PASSWORD_MAX_LEN        63

// Device-specific AES key (must match compile-time constant)
// SECURITY NOTE: In production, generate unique per device during firmware build
// For now, using a placeholder - replace with device-specific key
static const uint8_t ENCRYPTION_KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
};

// NVS partition handle (opened during init)
static nvs_handle_t wifi_nvs_handle = 0;
static bool nvs_initialized = false;

// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

/**
 * Encrypt plaintext buffer using AES-128-ECB
 *
 * Input buffer must be padded to multiple of 16 bytes.
 * Output buffer must be same size as input.
 *
 * Reference: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/cryptography/mbedtls.html
 */
static wifi_storage_error_t aes_encrypt(
    const uint8_t* plaintext,
    size_t len,
    uint8_t* ciphertext)
{
    if (!plaintext || !ciphertext || len == 0 || len % 16 != 0) {
        return WIFI_STORAGE_INVALID_PARAM;
    }

    mbedtls_aes_context aes_ctx;
    mbedtls_aes_init(&aes_ctx);

    int ret = mbedtls_aes_setkey_enc(&aes_ctx, ENCRYPTION_KEY, 128);
    if (ret != 0) {
        ESP_LOGE(TAG, "AES key setup failed: %d", ret);
        mbedtls_aes_free(&aes_ctx);
        return WIFI_STORAGE_ENCRYPTION_ERROR;
    }

    // Encrypt in 16-byte blocks (ECB mode)
    for (size_t i = 0; i < len; i += 16) {
        ret = mbedtls_aes_crypt_ecb(&aes_ctx, MBEDTLS_AES_ENCRYPT,
                                     plaintext + i, ciphertext + i);
        if (ret != 0) {
            ESP_LOGE(TAG, "AES encryption failed: %d", ret);
            mbedtls_aes_free(&aes_ctx);
            return WIFI_STORAGE_ENCRYPTION_ERROR;
        }
    }

    mbedtls_aes_free(&aes_ctx);
    return WIFI_STORAGE_OK;
}

/**
 * Decrypt ciphertext buffer using AES-128-ECB
 *
 * Input buffer must be multiple of 16 bytes.
 * Output buffer must be same size as input.
 */
static wifi_storage_error_t aes_decrypt(
    const uint8_t* ciphertext,
    size_t len,
    uint8_t* plaintext)
{
    if (!plaintext || !ciphertext || len == 0 || len % 16 != 0) {
        return WIFI_STORAGE_INVALID_PARAM;
    }

    mbedtls_aes_context aes_ctx;
    mbedtls_aes_init(&aes_ctx);

    int ret = mbedtls_aes_setkey_dec(&aes_ctx, ENCRYPTION_KEY, 128);
    if (ret != 0) {
        ESP_LOGE(TAG, "AES key setup failed: %d", ret);
        mbedtls_aes_free(&aes_ctx);
        return WIFI_STORAGE_ENCRYPTION_ERROR;
    }

    // Decrypt in 16-byte blocks (ECB mode)
    for (size_t i = 0; i < len; i += 16) {
        ret = mbedtls_aes_crypt_ecb(&aes_ctx, MBEDTLS_AES_DECRYPT,
                                     ciphertext + i, plaintext + i);
        if (ret != 0) {
            ESP_LOGE(TAG, "AES decryption failed: %d", ret);
            mbedtls_aes_free(&aes_ctx);
            return WIFI_STORAGE_ENCRYPTION_ERROR;
        }
    }

    mbedtls_aes_free(&aes_ctx);
    return WIFI_STORAGE_OK;
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

wifi_storage_error_t wifi_settings_init(void)
{
    if (nvs_initialized) {
        return WIFI_STORAGE_OK;  // Already initialized
    }

    ESP_LOGI(TAG, "Initializing WiFi settings storage");

    // Initialize the nvs_settings partition
    esp_err_t ret = nvs_flash_init_partition(NVS_PARTITION_NAME);
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        // Partition was truncated or is new version - erase and reinit
        ESP_LOGW(TAG, "NVS partition needs erase, reinitializing");
        ret = nvs_flash_erase_partition(NVS_PARTITION_NAME);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to erase NVS partition: %s", esp_err_to_name(ret));
            return WIFI_STORAGE_WRITE_ERROR;
        }
        ret = nvs_flash_init_partition(NVS_PARTITION_NAME);
    }

    if (ret == ESP_ERR_NOT_FOUND) {
        ESP_LOGE(TAG, "NVS partition '%s' not found", NVS_PARTITION_NAME);
        return WIFI_STORAGE_NOT_FOUND;
    } else if (ret != ESP_OK) {
        ESP_LOGE(TAG, "NVS flash init failed: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Open namespace for read/write access
    ret = nvs_open_from_partition(NVS_PARTITION_NAME, NVS_NAMESPACE, NVS_READWRITE, &wifi_nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS namespace: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    nvs_initialized = true;
    ESP_LOGI(TAG, "WiFi settings storage initialized successfully");

    return WIFI_STORAGE_OK;
}

bool wifi_settings_is_configured(void)
{
    if (!nvs_initialized) {
        ESP_LOGW(TAG, "NVS not initialized, cannot check configuration");
        return false;
    }

    uint8_t configured = 0;
    esp_err_t ret = nvs_get_u8(wifi_nvs_handle, NVS_CONFIGURED_KEY, &configured);

    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        // Key doesn't exist yet (first boot or after factory reset)
        return false;
    } else if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to read configured flag: %s", esp_err_to_name(ret));
        return false;
    }

    return (configured == 1);
}

wifi_storage_error_t wifi_settings_load(wifi_credentials_t* creds)
{
    if (!creds) {
        return WIFI_STORAGE_INVALID_PARAM;
    }

    if (!nvs_initialized) {
        ESP_LOGE(TAG, "NVS not initialized");
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Read configured flag first
    uint8_t configured = 0;
    esp_err_t ret = nvs_get_u8(wifi_nvs_handle, NVS_CONFIGURED_KEY, &configured);
    if (ret != ESP_OK || configured != 1) {
        ESP_LOGW(TAG, "Device not configured");
        return WIFI_STORAGE_NOT_FOUND;
    }

    // Read encrypted SSID (32 bytes, padded)
    uint8_t encrypted_ssid[32] = {0};
    size_t encrypted_ssid_len = sizeof(encrypted_ssid);
    ret = nvs_get_blob(wifi_nvs_handle, NVS_SSID_KEY, encrypted_ssid, &encrypted_ssid_len);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read encrypted SSID: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_CORRUPT;
    }

    // Read encrypted password (64 bytes, padded)
    uint8_t encrypted_password[64] = {0};
    size_t encrypted_password_len = sizeof(encrypted_password);
    ret = nvs_get_blob(wifi_nvs_handle, NVS_PASSWORD_KEY, encrypted_password, &encrypted_password_len);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read encrypted password: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_CORRUPT;
    }

    // Decrypt SSID
    uint8_t decrypted_ssid[32] = {0};
    wifi_storage_error_t err = aes_decrypt(encrypted_ssid, 32, decrypted_ssid);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Failed to decrypt SSID");
        return err;
    }

    // Decrypt password
    uint8_t decrypted_password[64] = {0};
    err = aes_decrypt(encrypted_password, 64, decrypted_password);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Failed to decrypt password");
        return err;
    }

    // Copy to output structure (as null-terminated strings)
    strncpy(creds->ssid, (const char*)decrypted_ssid, sizeof(creds->ssid) - 1);
    creds->ssid[sizeof(creds->ssid) - 1] = '\0';

    strncpy(creds->password, (const char*)decrypted_password, sizeof(creds->password) - 1);
    creds->password[sizeof(creds->password) - 1] = '\0';

    creds->configured = 1;

    ESP_LOGI(TAG, "Credentials loaded successfully (SSID: %s)", creds->ssid);

    return WIFI_STORAGE_OK;
}

wifi_storage_error_t wifi_settings_save(const char* ssid, const char* password)
{
    if (!ssid || !password) {
        return WIFI_STORAGE_INVALID_PARAM;
    }

    // Validate SSID
    size_t ssid_len = strlen(ssid);
    if (ssid_len == 0 || ssid_len > SSID_MAX_LEN) {
        ESP_LOGE(TAG, "Invalid SSID length: %zu (max %d)", ssid_len, SSID_MAX_LEN);
        return WIFI_STORAGE_INVALID_PARAM;
    }

    // Validate password
    size_t password_len = strlen(password);
    if (password_len < PASSWORD_MIN_LEN || password_len > PASSWORD_MAX_LEN) {
        ESP_LOGE(TAG, "Invalid password length: %zu (must be %d-%d)",
                 password_len, PASSWORD_MIN_LEN, PASSWORD_MAX_LEN);
        return WIFI_STORAGE_INVALID_PARAM;
    }

    if (!nvs_initialized) {
        ESP_LOGE(TAG, "NVS not initialized");
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Prepare SSID for encryption (pad to 32 bytes with zeros)
    uint8_t ssid_buf[32] = {0};
    memcpy(ssid_buf, ssid, ssid_len);

    // Encrypt SSID
    uint8_t encrypted_ssid[32] = {0};
    wifi_storage_error_t err = aes_encrypt(ssid_buf, 32, encrypted_ssid);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Failed to encrypt SSID");
        return err;
    }

    // Prepare password for encryption (pad to 64 bytes with zeros)
    uint8_t password_buf[64] = {0};
    memcpy(password_buf, password, password_len);

    // Encrypt password
    uint8_t encrypted_password[64] = {0};
    err = aes_encrypt(password_buf, 64, encrypted_password);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Failed to encrypt password");
        return err;
    }

    // Write encrypted SSID
    esp_err_t ret = nvs_set_blob(wifi_nvs_handle, NVS_SSID_KEY, encrypted_ssid, 32);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write encrypted SSID: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Write encrypted password
    ret = nvs_set_blob(wifi_nvs_handle, NVS_PASSWORD_KEY, encrypted_password, 64);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write encrypted password: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Write configured flag
    ret = nvs_set_u8(wifi_nvs_handle, NVS_CONFIGURED_KEY, 1);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write configured flag: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Commit changes to flash
    ret = nvs_commit(wifi_nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS changes: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    ESP_LOGI(TAG, "Credentials saved successfully (SSID: %s)", ssid);

    return WIFI_STORAGE_OK;
}

wifi_storage_error_t wifi_settings_factory_reset(void)
{
    if (!nvs_initialized) {
        ESP_LOGE(TAG, "NVS not initialized");
        return WIFI_STORAGE_WRITE_ERROR;
    }

    ESP_LOGI(TAG, "Performing factory reset of WiFi settings");

    // Erase all keys in the namespace
    esp_err_t ret = nvs_erase_all(wifi_nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to erase NVS namespace: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    // Commit the erase operation
    ret = nvs_commit(wifi_nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit factory reset: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }

    ESP_LOGI(TAG, "Factory reset complete - device is now unconfigured");

    return WIFI_STORAGE_OK;
}

const char* wifi_settings_error_to_string(wifi_storage_error_t err)
{
    switch (err) {
        case WIFI_STORAGE_OK:
            return "OK";
        case WIFI_STORAGE_NOT_FOUND:
            return "Not found";
        case WIFI_STORAGE_CORRUPT:
            return "Data corrupt";
        case WIFI_STORAGE_ENCRYPTION_ERROR:
            return "Encryption error";
        case WIFI_STORAGE_WRITE_ERROR:
            return "Write error";
        case WIFI_STORAGE_INVALID_PARAM:
            return "Invalid parameter";
        default:
            return "Unknown error";
    }
}
