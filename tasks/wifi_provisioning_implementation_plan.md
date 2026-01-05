# WiFi Provisioning System - Sequential Implementation Steps

## Overview

This document breaks down the WiFi provisioning implementation into discrete, testable steps. Each step is designed to:
- Build on previous steps
- Be independently testable
- Not break existing functionality
- Minimize risk of regression

**Estimated effort per step:** 1-4 hours depending on complexity.

Follow steps in order. Do not skip ahead.

---

## PHASE 1: FOUNDATION - STORAGE LAYER

### Step 1.1: Create NVS Settings Partition Definition

**Objective:** Define and configure the settings partition in ESP32 partitions table.

**Files to Create/Modify:**
- Create: `partitions.csv` (in project root, if not exists)
- Reference: ESP32 TRM Section 3 (System and Memory)

**Action:**

Add to `partitions.csv`:

```csv
# Lighthouse Attendance System Partition Table
# Name,   Type, SubType, Offset,  Size,    Flags
nvs,      data, nvs,     0x9000,  0x5000,
otadata,  data, ota,     0xe000,  0x2000,
app0,     app,  ota_0,   0x10000, 0x140000,
app1,     app,  ota_1,   0x150000, 0x140000,
nvs_settings, data, nvs, 0x290000, 0x4000, encrypted
```

**Notes:**
- Offset 0x290000 assumes default partition layout; adjust if necessary
- Size 0x4000 (16KB) is sufficient for future MQTT settings expansion
- `encrypted` flag enables Flash Encryption layer (optional but recommended)
- Verify offsets don't overlap with existing app partitions

**Verification:**
- Run `idf.py partition-table` to validate syntax
- Confirm no overlapping addresses in output
- No functional test yet (just structure validation)

**Reference Documentation:**
- ESP-IDF Partition Tables: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/misc_system_apis.html#partition-table

---

### Step 1.2: Create WiFi Settings Storage Header

**Objective:** Define the interface and data structures for credential storage.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_settings_storage.h`

**Action:**

Create file with contents:

```c
/**
 * wifi_settings_storage.h - WiFi Credential Storage Interface
 * 
 * Manages encrypted storage of WiFi credentials in NVS partition.
 * Credentials are decrypted only in RAM during use.
 * 
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.1
 */

#ifndef WIFI_SETTINGS_STORAGE_H
#define WIFI_SETTINGS_STORAGE_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

// ============================================================================
// ERROR CODES
// ============================================================================

typedef enum {
    WIFI_STORAGE_OK = 0,
    WIFI_STORAGE_NOT_FOUND = 1,
    WIFI_STORAGE_CORRUPT = 2,
    WIFI_STORAGE_ENCRYPTION_ERROR = 3,
    WIFI_STORAGE_WRITE_ERROR = 4,
    WIFI_STORAGE_INVALID_PARAM = 5,
} wifi_storage_error_t;

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * WiFi Credentials (RAM only, never persisted in plaintext)
 */
typedef struct {
    char ssid[32];              // Network name (null-terminated)
    char password[64];          // Network password (null-terminated)
    uint8_t configured;         // Flag from partition (0=no, 1=yes)
} wifi_credentials_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize WiFi settings storage system
 * 
 * Opens nvs_settings partition, validates structure.
 * Safe to call multiple times.
 * 
 * @return WIFI_STORAGE_OK on success
 *         WIFI_STORAGE_NOT_FOUND if partition missing
 */
wifi_storage_error_t wifi_settings_init(void);

/**
 * Check if device has been configured for WiFi
 * 
 * Reads "configured" flag from NVS without decryption.
 * Fast, zero-copy operation.
 * 
 * @return true if credentials have been saved, false otherwise
 */
bool wifi_settings_is_configured(void);

/**
 * Load WiFi credentials from partition
 * 
 * Decrypts stored SSID and password from NVS partition.
 * Only call if wifi_settings_is_configured() returns true.
 * 
 * Credentials stored in provided structure (RAM only).
 * Structure is NOT modified if function fails.
 * 
 * @param creds Output: decrypted credentials (must not be NULL)
 * @return WIFI_STORAGE_OK on success
 *         WIFI_STORAGE_NOT_FOUND if not yet configured
 *         WIFI_STORAGE_ENCRYPTION_ERROR if decryption fails
 */
wifi_storage_error_t wifi_settings_load(wifi_credentials_t* creds);

/**
 * Save WiFi credentials to partition
 * 
 * Encrypts and stores SSID and password to NVS.
 * Sets "configured" flag to 1.
 * 
 * IMPORTANT: After calling this function successfully,
 * caller MUST trigger esp_restart() to reload partition.
 * Code after this call will execute but partition won't be
 * used until reboot.
 * 
 * Validation:
 * - SSID: non-empty, max 31 chars (32 with null terminator)
 * - Password: 8-63 chars (WPA2 requirement)
 * 
 * @param ssid WiFi network name (null-terminated)
 * @param password WiFi password (null-terminated)
 * @return WIFI_STORAGE_OK on success
 *         WIFI_STORAGE_INVALID_PARAM if validation fails
 *         WIFI_STORAGE_WRITE_ERROR if write to NVS fails
 */
wifi_storage_error_t wifi_settings_save(const char* ssid, const char* password);

/**
 * Factory reset - clear all WiFi configuration
 * 
 * Erases encrypted credentials and sets "configured" flag to 0.
 * Device will return to unconfigured state on next boot.
 * 
 * IMPORTANT: After calling this function successfully,
 * caller MUST trigger esp_restart() for changes to take effect.
 * 
 * @return WIFI_STORAGE_OK on success
 *         WIFI_STORAGE_WRITE_ERROR if erase fails
 */
wifi_storage_error_t wifi_settings_factory_reset(void);

/**
 * Get human-readable error description
 * 
 * @param err Error code from previous operation
 * @return String description (never NULL, always valid C string)
 */
const char* wifi_settings_error_to_string(wifi_storage_error_t err);

#endif // WIFI_SETTINGS_STORAGE_H
```

**Verification:**
- File compiles with no errors
- Header guards present
- All public functions documented with param/return info
- Data structures match partition layout from Step 1.1

**Notes:**
- No implementation yet (just interface definition)
- Error codes match design in implementation plan
- Documentation references datasheet sections

---

### Step 1.3: Create WiFi Settings Storage Implementation

**Objective:** Implement NVS I/O and AES encryption for credential storage.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_settings_storage.c`

**Action:**

Create file with contents:

```c
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
static nvs_handle_t nvs_handle = 0;
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

/**
 * Pad buffer to multiple of 16 bytes with zero padding
 * 
 * @param buf Buffer to pad (must have space for padding)
 * @param current_len Current length of data
 * @param padded_len Output: length after padding (multiple of 16)
 */
static void zero_pad_to_block_size(uint8_t* buf, size_t current_len, size_t* padded_len)
{
    size_t remainder = current_len % 16;
    if (remainder == 0) {
        *padded_len = current_len;
    } else {
        size_t padding_needed = 16 - remainder;
        memset(buf + current_len, 0, padding_needed);
        *padded_len = current_len + padding_needed;
    }
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

wifi_storage_error_t wifi_settings_init(void)
{
    if (nvs_initialized) {
        return WIFI_STORAGE_OK;  // Already initialized
    }
    
    ESP_LOGI(TAG, "Initializing NVS flash");
    
    esp_err_t ret = nvs_flash_init_partition("nvs_settings");
    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGE(TAG, "nvs_settings partition not found");
        return WIFI_STORAGE_NOT_FOUND;
    } else if (ret != ESP_OK) {
        ESP_LOGE(TAG, "NVS flash init failed: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    ret = nvs_open_from_partition("nvs_settings", NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS namespace: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    nvs_initialized = true;
    ESP_LOGI(TAG, "NVS initialization successful");
    
    return WIFI_STORAGE_OK;
}

bool wifi_settings_is_configured(void)
{
    if (!nvs_initialized) {
        ESP_LOGW(TAG, "NVS not initialized");
        return false;
    }
    
    uint8_t configured = 0;
    esp_err_t ret = nvs_get_u8(nvs_handle, NVS_CONFIGURED_KEY, &configured);
    
    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        // Key doesn't exist yet (first boot)
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
    
    // Read configured flag
    uint8_t configured = 0;
    esp_err_t ret = nvs_get_u8(nvs_handle, NVS_CONFIGURED_KEY, &configured);
    if (ret != ESP_OK || configured != 1) {
        return WIFI_STORAGE_NOT_FOUND;
    }
    
    // Read encrypted SSID (32 bytes)
    uint8_t encrypted_ssid[32] = {0};
    size_t encrypted_ssid_len = sizeof(encrypted_ssid);
    ret = nvs_get_blob(nvs_handle, NVS_SSID_KEY, encrypted_ssid, &encrypted_ssid_len);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read encrypted SSID: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_CORRUPT;
    }
    
    // Read encrypted password (64 bytes)
    uint8_t encrypted_password[64] = {0};
    size_t encrypted_password_len = sizeof(encrypted_password);
    ret = nvs_get_blob(nvs_handle, NVS_PASSWORD_KEY, encrypted_password, &encrypted_password_len);
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
        ESP_LOGE(TAG, "Invalid SSID length: %u (max %u)", ssid_len, SSID_MAX_LEN);
        return WIFI_STORAGE_INVALID_PARAM;
    }
    
    // Validate password
    size_t password_len = strlen(password);
    if (password_len < PASSWORD_MIN_LEN || password_len > PASSWORD_MAX_LEN) {
        ESP_LOGE(TAG, "Invalid password length: %u (must be %u-%u)",
                 password_len, PASSWORD_MIN_LEN, PASSWORD_MAX_LEN);
        return WIFI_STORAGE_INVALID_PARAM;
    }
    
    if (!nvs_initialized) {
        ESP_LOGE(TAG, "NVS not initialized");
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Prepare SSID for encryption (pad to 32 bytes)
    uint8_t ssid_buf[32] = {0};
    memcpy(ssid_buf, ssid, ssid_len);
    
    // Encrypt SSID
    uint8_t encrypted_ssid[32] = {0};
    wifi_storage_error_t err = aes_encrypt(ssid_buf, 32, encrypted_ssid);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Failed to encrypt SSID");
        return err;
    }
    
    // Prepare password for encryption (pad to 64 bytes)
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
    esp_err_t ret = nvs_set_blob(nvs_handle, NVS_SSID_KEY, encrypted_ssid, 32);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write SSID: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Write encrypted password
    ret = nvs_set_blob(nvs_handle, NVS_PASSWORD_KEY, encrypted_password, 64);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write password: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Write configured flag
    ret = nvs_set_u8(nvs_handle, NVS_CONFIGURED_KEY, 1);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write configured flag: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Commit changes
    ret = nvs_commit(nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    ESP_LOGI(TAG, "Credentials saved successfully");
    
    return WIFI_STORAGE_OK;
}

wifi_storage_error_t wifi_settings_factory_reset(void)
{
    if (!nvs_initialized) {
        ESP_LOGE(TAG, "NVS not initialized");
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Erase all keys in namespace
    esp_err_t ret = nvs_erase_all(nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to erase NVS: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    // Commit changes
    ret = nvs_commit(nvs_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit factory reset: %s", esp_err_to_name(ret));
        return WIFI_STORAGE_WRITE_ERROR;
    }
    
    ESP_LOGI(TAG, "Factory reset complete");
    
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
```

**Verification:**
- File compiles without errors
- All functions from header implemented
- Error handling consistent
- Comments reference ESP32 TRM and ESP-IDF docs

**Notes:**
- Uses NVS (Non-Volatile Storage) from ESP-IDF
- AES encryption via mbedTLS (already in ESP-IDF)
- Credentials never logged (security best practice)
- Partition name "nvs_settings" matches partitions.csv

**Testing after this step:**
- Cannot test yet (needs CMakeLists.txt setup)

---

### Step 1.4: Create CMakeLists.txt for Component

**Objective:** Set up build configuration for new WiFi provisioning component.

**Files to Create:**
- Create: `components/wifi_provisioning/CMakeLists.txt`

**Action:**

Create file with contents:

```cmake
idf_component_register(
    SRCS
        "wifi_settings_storage.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        "nvs_flash"
        "mbedtls"
        "esp_common"
        "freertos"
)
```

**Verification:**
- No build errors when running `idf.py build`
- File placed in correct location: `components/wifi_provisioning/CMakeLists.txt`

**Notes:**
- Only includes storage module in this step
- Will add more modules in later steps
- REQUIRES lists dependencies (already in ESP-IDF)

---

### Step 1.5: Create Test Harness for Storage Module

**Objective:** Verify storage module works correctly with real NVS partition.

**Files to Create:**
- Create: `test_wifi_storage.c` (in project root, temporary test file)

**Action:**

Create simple test program:

```c
/**
 * test_wifi_storage.c - Test harness for WiFi settings storage
 * 
 * Compile and run this to verify storage module works correctly.
 * To be run once, then deleted or moved to test directory.
 */

#include <stdio.h>
#include <string.h>
#include "wifi_provisioning/wifi_settings_storage.h"
#include "esp_log.h"
#include "nvs_flash.h"

static const char* TAG = "TEST_STORAGE";

void test_storage_module(void)
{
    ESP_LOGI(TAG, "=== WiFi Settings Storage Test ===\n");
    
    // Test 1: Initialize
    ESP_LOGI(TAG, "Test 1: Initialize NVS");
    wifi_storage_error_t err = wifi_settings_init();
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: %s", wifi_settings_error_to_string(err));
        return;
    }
    ESP_LOGI(TAG, "PASSED\n");
    
    // Test 2: Check unconfigured (on first run)
    ESP_LOGI(TAG, "Test 2: Check initial unconfigured state");
    bool configured = wifi_settings_is_configured();
    ESP_LOGI(TAG, "Device configured: %s", configured ? "true" : "false");
    if (configured) {
        ESP_LOGI(TAG, "WARNING: Device already configured. Running factory reset...");
        err = wifi_settings_factory_reset();
        if (err != WIFI_STORAGE_OK) {
            ESP_LOGE(TAG, "Failed to factory reset");
            return;
        }
        ESP_LOGI(TAG, "PASSED (after reset)\n");
    } else {
        ESP_LOGI(TAG, "PASSED\n");
    }
    
    // Test 3: Save credentials
    ESP_LOGI(TAG, "Test 3: Save credentials");
    const char* test_ssid = "TEST_NETWORK";
    const char* test_password = "testpassword123";
    err = wifi_settings_save(test_ssid, test_password);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: %s", wifi_settings_error_to_string(err));
        return;
    }
    ESP_LOGI(TAG, "PASSED\n");
    
    // Test 4: Check configured
    ESP_LOGI(TAG, "Test 4: Check configured state after save");
    configured = wifi_settings_is_configured();
    if (!configured) {
        ESP_LOGE(TAG, "FAILED: Device should be configured");
        return;
    }
    ESP_LOGI(TAG, "PASSED\n");
    
    // Test 5: Load credentials
    ESP_LOGI(TAG, "Test 5: Load and verify credentials");
    wifi_credentials_t creds = {0};
    err = wifi_settings_load(&creds);
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: %s", wifi_settings_error_to_string(err));
        return;
    }
    
    if (strcmp(creds.ssid, test_ssid) != 0) {
        ESP_LOGE(TAG, "FAILED: SSID mismatch. Expected '%s', got '%s'", test_ssid, creds.ssid);
        return;
    }
    
    if (strcmp(creds.password, test_password) != 0) {
        ESP_LOGE(TAG, "FAILED: Password mismatch");
        return;
    }
    
    ESP_LOGI(TAG, "Loaded SSID: %s", creds.ssid);
    ESP_LOGI(TAG, "Loaded Password: %s", creds.password);
    ESP_LOGI(TAG, "PASSED\n");
    
    // Test 6: Invalid credentials
    ESP_LOGI(TAG, "Test 6: Test invalid inputs");
    err = wifi_settings_save("", "password");  // Empty SSID
    if (err == WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: Should reject empty SSID");
        return;
    }
    
    err = wifi_settings_save("SSID", "short");  // Password too short
    if (err == WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: Should reject short password");
        return;
    }
    
    ESP_LOGI(TAG, "PASSED\n");
    
    // Test 7: Factory reset
    ESP_LOGI(TAG, "Test 7: Factory reset");
    err = wifi_settings_factory_reset();
    if (err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "FAILED: %s", wifi_settings_error_to_string(err));
        return;
    }
    
    configured = wifi_settings_is_configured();
    if (configured) {
        ESP_LOGE(TAG, "FAILED: Device should be unconfigured after reset");
        return;
    }
    
    ESP_LOGI(TAG, "PASSED\n");
    
    ESP_LOGI(TAG, "=== ALL TESTS PASSED ===\n");
}

void app_main(void)
{
    // Initialize NVS (required before any storage operations)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        ret = nvs_flash_init();
    }
    
    if (ret != ESP_OK) {
        printf("NVS init failed\n");
        return;
    }
    
    test_storage_module();
}
```

**Verification:**
- Compile: `idf.py build`
- Flash: `idf.py -p /dev/ttyUSB0 flash`
- Monitor: `idf.py -p /dev/ttyUSB0 monitor`
- All tests should print PASSED

**Expected Output:**
```
I (XXX) TEST_STORAGE: === WiFi Settings Storage Test ===
I (XXX) TEST_STORAGE: Test 1: Initialize NVS
I (XXX) WIFI_STORAGE: Initializing NVS flash
I (XXX) WIFI_STORAGE: NVS initialization successful
I (XXX) TEST_STORAGE: PASSED
...
I (XXX) TEST_STORAGE: === ALL TESTS PASSED ===
```

**Notes:**
- This is a temporary test file for validation
- Can be deleted after verification
- Tests cover normal cases and error handling

---

## PHASE 2: STATE MACHINE & BUTTON INTEGRATION

### Step 2.1: Create WiFi Provisioning Header

**Objective:** Define state machine interface and public API for provisioning system.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_provisioning.h`

**Action:**

Create file with contents (see WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2 for reference):

```c
/**
 * wifi_provisioning.h - WiFi Provisioning State Machine
 * 
 * Manages device provisioning flow:
 * - Detects first boot (unconfigured)
 * - Handles user-triggered setup mode
 * - Manages WiFi connection attempts
 * - Controls LED status indicators
 * 
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2
 */

#ifndef WIFI_PROVISIONING_H
#define WIFI_PROVISIONING_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "driver/gpio.h"

// ============================================================================
// STATE AND EVENT DEFINITIONS
// ============================================================================

typedef enum {
    WIFI_STATE_UNCONFIGURED = 0,      // No config saved; waiting for user
    WIFI_STATE_SETUP_REQUESTED = 1,   // User triggered setup (reboot flag set)
    WIFI_STATE_AP_ACTIVE = 2,         // AP broadcasting, serving provisioning page
    WIFI_STATE_CONNECTING = 3,        // Attempting STA connection with test credentials
    WIFI_STATE_CONNECTED = 4,         // Successfully connected to WiFi
    WIFI_STATE_OFFLINE = 5,           // Connection failed or unavailable
} wifi_state_t;

typedef enum {
    WIFI_EVENT_NONE = 0,
    WIFI_EVENT_CONFIG_LOADED = 1,      // Credentials loaded from storage
    WIFI_EVENT_SETUP_BUTTON_PRESSED = 2, // User pressed setup button
    WIFI_EVENT_CREDS_SUBMITTED = 3,    // HTTP form submitted
    WIFI_EVENT_CONNECTION_SUCCESS = 4, // STA connected successfully
    WIFI_EVENT_CONNECTION_FAILED = 5,  // STA connection timeout
    WIFI_EVENT_REBOOT_REQUESTED = 6,   // User clicked restart
} wifi_event_t;

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize WiFi provisioning system
 * 
 * Call early in app_main(), BEFORE initializing RFID reader.
 * 
 * Checks partition for configured status, initializes state machine.
 * LED pin is configured for status indication.
 * 
 * @param led_pin GPIO pin for WiFi status LED (typically LED1_PIN / GPIO5)
 * @param connection_timeout_ms Timeout for WiFi connection test (default 10000)
 * @return ESP_OK on success
 *         Other error codes on NVS/storage failure (device can continue offline)
 */
esp_err_t wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms);

/**
 * Called when BUTTON2 is held for 5 seconds
 * 
 * Signals that user wants to enter setup mode.
 * Internally sets reboot flag and calls esp_restart().
 * 
 * NOTE: This function does NOT return to caller.
 * Code after this call will not execute.
 * 
 * This function should be called from process_buttons() in main task.
 */
void wifi_provisioning_setup_button_pressed(void);

/**
 * Process WiFi provisioning state machine
 * 
 * Call from main task loop every ~10ms.
 * Handles:
 * - LED blinking control (setup mode)
 * - State transitions
 * - WiFi connection monitoring
 * - HTTP server startup/shutdown
 * 
 * Low CPU cost: mostly flag checks, minimal blocking operations.
 */
void wifi_provisioning_process(void);

/**
 * Get current provisioning state
 * 
 * @return Current state (see wifi_state_t enum)
 */
wifi_state_t wifi_provisioning_get_state(void);

/**
 * Check if system is ready for normal operation
 * 
 * Returns true when:
 * - WiFi connected (WIFI_STATE_CONNECTED), OR
 * - Running offline (WIFI_STATE_OFFLINE)
 * 
 * Returns false when:
 * - Still in setup (WIFI_STATE_AP_ACTIVE)
 * - Waiting for configuration (WIFI_STATE_UNCONFIGURED)
 * - Testing credentials (WIFI_STATE_CONNECTING)
 * 
 * @return true if RFID system can start normally
 */
bool wifi_provisioning_is_ready(void);

/**
 * Get human-readable state description
 * 
 * Useful for logging and debugging.
 * 
 * @param state State to describe
 * @return String like "CONNECTED", "OFFLINE", "AP_ACTIVE", etc.
 */
const char* wifi_provisioning_state_to_string(wifi_state_t state);

/**
 * Report connection test result
 * 
 * Called by HTTP server after testing WiFi credentials.
 * Updates state machine and sends response to user.
 * 
 * @param success true if connection succeeded
 * @param error_message Error description if success=false (can be NULL)
 */
void wifi_provisioning_set_connection_result(bool success, const char* error_message);

/**
 * Request device restart
 * 
 * Called by HTTP server when user clicks restart button.
 * Saves credentials to partition and reboots.
 * 
 * Credentials must have been validated before calling this.
 */
void wifi_provisioning_restart_device(void);

#endif // WIFI_PROVISIONING_H
```

**Verification:**
- File compiles with no errors
- All function declarations documented
- References to implementation plan section 2.2

**Notes:**
- Implementation will follow in next step
- Design matches state machine from architecture document

---

### Step 2.2: Create WiFi Provisioning Implementation (Part 1 - Basics)

**Objective:** Implement state machine initialization and basic state transitions.

**Files to Create:**
- Create: `components/wifi_provisioning/wifi_provisioning.c` (Part 1)

**Action:**

Create file with initial implementation (state machine framework):

```c
/**
 * wifi_provisioning.c - WiFi Provisioning State Machine
 * 
 * Manages provisioning flow and state transitions.
 * Part 1: Basic initialization and state management
 * 
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Section 2.2
 */

#include <string.h>
#include "wifi_provisioning.h"
#include "wifi_settings_storage.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"

static const char* TAG = "WIFI_PROV";

// ============================================================================
// STATE MACHINE STATE
// ============================================================================

typedef struct {
    wifi_state_t current_state;
    uint32_t state_enter_time_ms;
    
    // Configuration
    gpio_num_t led_pin;
    uint32_t connection_timeout_ms;
    
    // LED blinking for setup mode
    uint32_t led_blink_interval_ms;
    uint32_t last_led_toggle_ms;
    uint8_t led_state;
    
    // Pending credentials during setup
    char pending_ssid[32];
    char pending_password[64];
    bool connection_result;
    char connection_error[64];
    
    // Reboot flag (set when entering setup)
    bool reboot_requested;
} provisioning_state_t;

static provisioning_state_t prov_state = {
    .current_state = WIFI_STATE_UNCONFIGURED,
    .state_enter_time_ms = 0,
    .led_pin = GPIO_NUM_MAX,
    .connection_timeout_ms = 10000,
    .led_blink_interval_ms = 1000,
    .last_led_toggle_ms = 0,
    .led_state = 0,
    .reboot_requested = false,
};

static bool initialized = false;

// ============================================================================
// INTERNAL HELPERS
// ============================================================================

/**
 * Get milliseconds since boot
 */
static uint32_t get_time_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

/**
 * Set LED state (0 or 1)
 */
static void set_led(uint8_t state)
{
    if (prov_state.led_pin < GPIO_NUM_MAX) {
        gpio_set_level(prov_state.led_pin, state);
    }
}

/**
 * Handle LED blinking for setup mode
 */
static void process_led(void)
{
    if (prov_state.current_state != WIFI_STATE_AP_ACTIVE) {
        return;  // Only blink in AP mode
    }
    
    uint32_t current_time = get_time_ms();
    uint32_t elapsed = current_time - prov_state.last_led_toggle_ms;
    
    if (elapsed >= prov_state.led_blink_interval_ms) {
        prov_state.led_state = prov_state.led_state ? 0 : 1;
        set_led(prov_state.led_state);
        prov_state.last_led_toggle_ms = current_time;
    }
}

/**
 * Transition to new state, log the change
 */
static void transition_to(wifi_state_t new_state)
{
    if (new_state == prov_state.current_state) {
        return;
    }
    
    ESP_LOGI(TAG, "State transition: %s → %s",
             wifi_provisioning_state_to_string(prov_state.current_state),
             wifi_provisioning_state_to_string(new_state));
    
    prov_state.current_state = new_state;
    prov_state.state_enter_time_ms = get_time_ms();
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t wifi_provisioning_init(gpio_num_t led_pin, uint32_t connection_timeout_ms)
{
    if (initialized) {
        return ESP_OK;
    }
    
    ESP_LOGI(TAG, "Initializing WiFi provisioning");
    
    // Store configuration
    prov_state.led_pin = led_pin;
    prov_state.connection_timeout_ms = connection_timeout_ms;
    
    // Configure LED pin
    if (led_pin < GPIO_NUM_MAX) {
        gpio_config_t led_config = {
            .pin_bit_mask = (1ULL << led_pin),
            .mode = GPIO_MODE_OUTPUT,
            .pull_up_en = GPIO_PULLUP_DISABLE,
            .pull_down_en = GPIO_PULLDOWN_DISABLE,
            .intr_type = GPIO_INTR_DISABLE,
        };
        gpio_config(&led_config);
        set_led(0);  // Start with LED off
    }
    
    // Initialize storage
    wifi_storage_error_t storage_err = wifi_settings_init();
    if (storage_err != WIFI_STORAGE_OK) {
        ESP_LOGE(TAG, "Storage init failed: %s",
                 wifi_settings_error_to_string(storage_err));
        // Don't fail completely; device can still work offline
    }
    
    // Determine initial state
    if (wifi_settings_is_configured()) {
        ESP_LOGI(TAG, "Device configured; attempting to connect");
        transition_to(WIFI_STATE_CONNECTING);
    } else {
        ESP_LOGI(TAG, "Device not configured; waiting for user");
        transition_to(WIFI_STATE_UNCONFIGURED);
    }
    
    initialized = true;
    
    ESP_LOGI(TAG, "WiFi provisioning initialized");
    
    return ESP_OK;
}

void wifi_provisioning_setup_button_pressed(void)
{
    if (!initialized) {
        ESP_LOGW(TAG, "Provisioning not initialized");
        return;
    }
    
    ESP_LOGI(TAG, "Setup button pressed - entering setup mode");
    
    // Set flag and reboot
    prov_state.reboot_requested = true;
    
    // Device will reboot; on next boot, detect setup mode
    vTaskDelay(pdMS_TO_TICKS(100));  // Brief delay to ensure logging
    
    ESP_LOGI(TAG, "Restarting...");
    esp_restart();
    
    // Never reaches here
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void wifi_provisioning_process(void)
{
    if (!initialized) {
        return;
    }
    
    // Process LED blinking
    process_led();
    
    // State machine processing
    switch (prov_state.current_state) {
        case WIFI_STATE_UNCONFIGURED:
            // Waiting for user to press setup button
            // No state transitions here (button press triggers reboot)
            break;
        
        case WIFI_STATE_AP_ACTIVE:
            // AP is running, HTTP server handling provisioning
            // Transitions happen when credentials submitted
            break;
        
        case WIFI_STATE_CONNECTING:
            // Attempting WiFi connection
            // TODO: Implement WiFi connection logic (next steps)
            break;
        
        case WIFI_STATE_CONNECTED:
            // Connected - normal operation
            break;
        
        case WIFI_STATE_OFFLINE:
            // Not connected - running offline
            break;
        
        default:
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
    // TODO: Implement in next steps
    (void)success;
    (void)error_message;
}

void wifi_provisioning_restart_device(void)
{
    // TODO: Implement in next steps
}
```

**Verification:**
- File compiles with storage module
- Basic state transitions work (use debugger or logging)
- No functional WiFi operations yet (just structure)

**Notes:**
- WiFi operations will be added in subsequent steps
- HTTP server integration will follow
- This establishes the state machine framework

---

### Step 2.3: Integrate Button Detection for 5-Second Press

**Objective:** Extend existing button handling to detect 5-second BUTTON2 hold for setup mode entry.

**Files to Modify:**
- Modify: `my_project.c` (process_buttons function)

**Action:**

Locate the BUTTON2 handling section (lines 176-201) and replace with:

```c
// BUTTON2: Show statistics (short press) or enter setup mode (5s hold)
{
    uint32_t level = gpio_get_level(BUTTON2_PIN);
    button_state_t* state = &button_states[1];
    
    if (level == 0 && state->last_stable_state == 0) {
        // Button is being held down - check for 5 second threshold
        uint32_t hold_duration = current_time - state->last_press_time;
        
        // 5-second threshold: enter setup mode
        if (hold_duration >= 5000 && !(state->press_count & 0x80)) {
            // Mark that we've triggered setup (use high bit of counter)
            state->press_count |= 0x80;
            
            ESP_LOGI(TAG, "BUTTON2 held for 5+ seconds - entering WiFi setup mode");
            
            // This function handles reboot internally
            wifi_provisioning_setup_button_pressed();
            // Never returns
        }
    } else if (level == 1 && state->last_stable_state == 0) {
        // Button released
        if ((current_time - state->last_press_time) >= DEBOUNCE_TIME_MS) {
            uint32_t hold_duration = current_time - state->last_press_time;
            
            // Short press: show statistics (only if setup not triggered)
            if (hold_duration < 5000 && !(state->press_count & 0x80)) {
                state->press_count++;
                
                // Existing statistics display code
                rfid_stats_t stats;
                if (rfid_reader_get_stats(&stats) == ESP_OK) {
                    ESP_LOGI(TAG, "â•â•â•â•â•â•â• RFID Statistics â•â•â•â•â•â•â•");
                    ESP_LOGI(TAG, "  Tags detected: %d", stats.tags_detected);
                    ESP_LOGI(TAG, "  Total reads: %d", stats.total_reads);
                    ESP_LOGI(TAG, "  Errors: %d", stats.errors);
                    ESP_LOGI(TAG, "  Scanning: %s", stats.inventory_active ? "YES" : "NO");
                    ESP_LOGI(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n");
                }
            }
            
            // Reset counter for next press
            state->press_count = 0;
        }
    }
    
    state->last_stable_state = level;
}
```

**Add include at top of my_project.c:**

```c
#include "wifi_provisioning.h"
```

**Verification:**
- File compiles without errors
- Short BUTTON2 press still shows statistics
- 5-second BUTTON2 hold triggers setup (will see reboot log message)

**Notes:**
- Backward compatible: short press behavior unchanged
- Uses high bit of press_count to avoid double-triggering
- Button debounce unchanged (DEBOUNCE_TIME_MS still applies)

---

### Step 2.4: Integrate WiFi Provisioning into app_main()

**Objective:** Add WiFi provisioning initialization to main application startup sequence.

**Files to Modify:**
- Modify: `my_project.c` (app_main function)

**Action:**

In `app_main()`, after `gpio_init()` and before RFID initialization, add:

```c
// ========== WiFi Provisioning System ==========
ESP_LOGI(TAG, "Initializing WiFi provisioning");
esp_err_t wifi_ret = wifi_provisioning_init(LED1_PIN, 10000);
if (wifi_ret != ESP_OK) {
    ESP_LOGW(TAG, "WiFi provisioning init failed: %s", esp_err_to_name(wifi_ret));
    // Continue anyway - device can work offline
}

// Wait for device to be ready (configured or setup complete)
if (!wifi_provisioning_is_ready()) {
    ESP_LOGI(TAG, "Waiting for WiFi configuration...");
    ESP_LOGI(TAG, "Press BUTTON2 for 5 seconds to enter setup mode");
    
    // Process provisioning state machine until ready
    while (!wifi_provisioning_is_ready()) {
        wifi_provisioning_process();
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    
    ESP_LOGI(TAG, "WiFi provisioning ready - proceeding");
}
// =============================================
```

**Location:** After `gpio_init()` (line 263), before RFID initialization (line 266).

**Verification:**
- Device boots and reaches "Waiting for WiFi configuration" message (if unconfigured)
- Press BUTTON2 for 5 seconds → device reboots and enters LED blinking pattern
- Device is in AP mode broadcasting network

**Notes:**
- If already configured, skips to normal operation
- Blocks main task until ready (acceptable for initialization)
- LED will blink at 1 second interval in AP mode

---

### Step 2.5: Integrate WiFi Provisioning into Main Task Loop

**Objective:** Add state machine processing to existing main task for LED control and state monitoring.

**Files to Modify:**
- Modify: `my_project.c` (main_task function)

**Action:**

Update main_task to call provisioning processing:

```c
static void main_task(void* arg)
{
    ESP_LOGI(TAG, "Main task started");
    
    while (1) {
        // Process WiFi provisioning state machine
        // Handles LED blinking, state transitions, etc.
        wifi_provisioning_process();
        
        // Existing button and sensor processing
        process_buttons();
        process_pir();
        
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

**Location:** Lines 239-249, add call before existing button/PIR processing.

**Verification:**
- LED blinks at 1 second interval when in AP mode
- Blink stops when exiting AP mode
- No impact on button/PIR processing timing

**Notes:**
- Very low CPU cost (mostly flag checks)
- Integrates seamlessly with existing 10ms loop
- LED control can be observed during setup

---

### Step 2.6: Update CMakeLists.txt to Include Provisioning

**Objective:** Add WiFi provisioning module to build.

**Files to Modify:**
- Modify: `components/wifi_provisioning/CMakeLists.txt`

**Action:**

Update to:

```cmake
idf_component_register(
    SRCS
        "wifi_provisioning.c"
        "wifi_settings_storage.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        "nvs_flash"
        "mbedtls"
        "esp_common"
        "freertos"
        "esp_timer"
        "driver"
)
```

**Verification:**
- Project builds: `idf.py build`
- No linker errors

---

### Step 2.7: Test Phase 2 - Button and State Machine

**Objective:** Verify button detection and state machine work together.

**Test Procedure:**

1. **Unconfigured device:**
   - Flash firmware
   - Device should reach "Waiting for WiFi configuration" message
   - LED off initially

2. **Setup button press:**
   - Press BUTTON2 for 5 seconds
   - Device logs "entering setup mode"
   - Device reboots
   - On reboot, LED begins blinking at 1 second interval
   - Device is in AP mode

3. **Short button press:**
   - While in normal operation, press BUTTON2 for <1 second
   - Should show RFID statistics (existing functionality)
   - Should NOT trigger setup mode

4. **State transitions:**
   - Monitor serial output for state transition logs
   - Expected transitions: UNCONFIGURED → SETUP_REQUESTED (after reboot) → AP_ACTIVE

**Expected Output (during unconfigured boot):**
```
I (XXX) WIFI_PROV: Initializing WiFi provisioning
I (XXX) WIFI_STORAGE: Initializing NVS flash
I (XXX) WIFI_STORAGE: NVS initialization successful
I (XXX) WIFI_PROV: Device not configured; waiting for user
I (XXX) WIFI_PROV: WiFi provisioning initialized
I (XXX) MAIN: Waiting for WiFi configuration...
I (XXX) MAIN: Press BUTTON2 for 5 seconds to enter setup mode
```

**Expected Output (during 5s button press):**
```
I (XXX) MAIN: BUTTON2 held for 5+ seconds - entering WiFi setup mode
I (XXX) WIFI_PROV: Setup button pressed - entering setup mode
I (XXX) WIFI_PROV: Restarting...
```

**Expected Output (on reboot in setup mode):**
```
I (XXX) WIFI_PROV: State transition: UNCONFIGURED → AP_ACTIVE
I (XXX) MAIN: System ready!
```

**Notes:**
- No WiFi connectivity test yet (HTTP server not implemented)
- This phase validates button handling and state machine only
- Next phase adds HTTP server and actual WiFi testing

---

## PHASE 3: HTTP SERVER & WEB PROVISIONING

### Step 3.1: Create WiFi HTTP Server Header

[Continuing in next section...]

---

## Summary of Phase 1 & 2

At the end of Phase 2:
- ✅ NVS settings partition configured
- ✅ Credential storage implemented (encrypted)
- ✅ State machine framework operational
- ✅ Button integration complete (5s press detected)
- ✅ LED blinking in AP mode
- ✅ Device boots to "waiting for config" state if unconfigured
- ✅ Setup mode triggerable and state transitions working

**NOT YET IMPLEMENTED:**
- HTTP server
- WiFi connection testing
- Credential provisioning form
- Actual WiFi STA mode connection

These will be completed in Phase 3.

---

## How to Use This Document

1. **Follow steps in order** - each builds on previous ones
2. **Verify each step** before moving to next
3. **Commit after each step** - easier to track progress and debug issues
4. **Reference the implementation plan** - each step links to relevant sections
5. **Test incrementally** - don't wait until all phases complete to test

Expected total time:
- Phase 1: 4-6 hours (storage layer)
- Phase 2: 2-3 hours (state machine & integration)
- Phase 3: 4-6 hours (HTTP server)

**Total: 10-15 hours for complete implementation**
