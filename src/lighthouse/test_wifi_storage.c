/**
 * test_wifi_storage.c - Test harness for WiFi settings storage
 *
 * Compile and run this to verify storage module works correctly.
 * To be run once, then deleted or moved to test directory.
 *
 * Usage:
 * 1. Temporarily modify main/CMakeLists.txt to use this file:
 *    - Move this file to main/ directory
 *    - Replace "lighthouse.c" with "test_wifi_storage.c" in SRCS
 * 2. Build and flash: idf.py build && idf.py -p /dev/ttyUSB0 flash
 * 3. Monitor output: idf.py -p /dev/ttyUSB0 monitor
 * 4. Restore original CMakeLists.txt after testing
 *
 * Reference: WIFI_PROVISIONING_IMPLEMENTATION_PLAN.md Step 1.5
 */

#include <stdio.h>
#include <string.h>
#include "wifi_settings_storage.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char* TAG = "TEST_STORAGE";

// Test result tracking
static int tests_passed = 0;
static int tests_failed = 0;

/**
 * Log test result and update counters
 */
static void log_test_result(const char* test_name, bool passed, const char* message)
{
    if (passed) {
        ESP_LOGI(TAG, "[PASS] %s", test_name);
        tests_passed++;
    } else {
        ESP_LOGE(TAG, "[FAIL] %s: %s", test_name, message ? message : "");
        tests_failed++;
    }
}

/**
 * Test 1: Initialize NVS storage
 */
static bool test_init(void)
{
    ESP_LOGI(TAG, "\n--- Test 1: Initialize NVS Storage ---");

    wifi_storage_error_t err = wifi_settings_init();
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Init failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Initialize NVS", false, msg);
        return false;
    }

    log_test_result("Initialize NVS", true, NULL);
    return true;
}

/**
 * Test 2: Check initial unconfigured state (or reset if already configured)
 */
static bool test_initial_state(void)
{
    ESP_LOGI(TAG, "\n--- Test 2: Check Initial State ---");

    bool configured = wifi_settings_is_configured();

    if (configured) {
        ESP_LOGW(TAG, "Device already configured - performing factory reset first");
        wifi_storage_error_t err = wifi_settings_factory_reset();
        if (err != WIFI_STORAGE_OK) {
            char msg[64];
            snprintf(msg, sizeof(msg), "Factory reset failed: %s", wifi_settings_error_to_string(err));
            log_test_result("Initial State (reset)", false, msg);
            return false;
        }

        // Verify reset worked
        configured = wifi_settings_is_configured();
        if (configured) {
            log_test_result("Initial State (reset)", false, "Still configured after reset");
            return false;
        }

        log_test_result("Initial State (after reset)", true, NULL);
    } else {
        log_test_result("Initial State (unconfigured)", true, NULL);
    }

    return true;
}

/**
 * Test 3: Save credentials
 */
static bool test_save_credentials(void)
{
    ESP_LOGI(TAG, "\n--- Test 3: Save Credentials ---");

    const char* test_ssid = "TestNetwork_123";
    const char* test_password = "SecurePassword456";

    wifi_storage_error_t err = wifi_settings_save(test_ssid, test_password);
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Save failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Save Credentials", false, msg);
        return false;
    }

    log_test_result("Save Credentials", true, NULL);
    return true;
}

/**
 * Test 4: Verify configured state after save
 */
static bool test_configured_state(void)
{
    ESP_LOGI(TAG, "\n--- Test 4: Check Configured State ---");

    bool configured = wifi_settings_is_configured();
    if (!configured) {
        log_test_result("Configured State", false, "Device should be configured after save");
        return false;
    }

    log_test_result("Configured State", true, NULL);
    return true;
}

/**
 * Test 5: Load and verify credentials
 */
static bool test_load_credentials(void)
{
    ESP_LOGI(TAG, "\n--- Test 5: Load and Verify Credentials ---");

    const char* expected_ssid = "TestNetwork_123";
    const char* expected_password = "SecurePassword456";

    wifi_credentials_t creds = {0};
    wifi_storage_error_t err = wifi_settings_load(&creds);
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Load failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Load Credentials", false, msg);
        return false;
    }

    // Verify SSID
    if (strcmp(creds.ssid, expected_ssid) != 0) {
        char msg[128];
        snprintf(msg, sizeof(msg), "SSID mismatch: expected '%s', got '%s'",
                 expected_ssid, creds.ssid);
        log_test_result("Load Credentials (SSID)", false, msg);
        return false;
    }

    // Verify password
    if (strcmp(creds.password, expected_password) != 0) {
        log_test_result("Load Credentials (Password)", false, "Password mismatch");
        return false;
    }

    // Verify configured flag
    if (creds.configured != 1) {
        log_test_result("Load Credentials (Flag)", false, "Configured flag not set");
        return false;
    }

    ESP_LOGI(TAG, "Loaded SSID: %s", creds.ssid);
    ESP_LOGI(TAG, "Loaded Password: %s", creds.password);
    ESP_LOGI(TAG, "Configured: %d", creds.configured);

    log_test_result("Load Credentials", true, NULL);
    return true;
}

/**
 * Test 6: Test invalid inputs (negative testing)
 */
static bool test_invalid_inputs(void)
{
    ESP_LOGI(TAG, "\n--- Test 6: Test Invalid Inputs ---");

    wifi_storage_error_t err;

    // Test empty SSID
    err = wifi_settings_save("", "validpassword123");
    if (err == WIFI_STORAGE_OK) {
        log_test_result("Invalid Input (Empty SSID)", false, "Should reject empty SSID");
        return false;
    }
    ESP_LOGI(TAG, "Empty SSID correctly rejected");

    // Test too short password (less than 8 chars)
    err = wifi_settings_save("ValidSSID", "short");
    if (err == WIFI_STORAGE_OK) {
        log_test_result("Invalid Input (Short Password)", false, "Should reject password < 8 chars");
        return false;
    }
    ESP_LOGI(TAG, "Short password correctly rejected");

    // Test NULL pointers
    err = wifi_settings_save(NULL, "validpassword123");
    if (err == WIFI_STORAGE_OK) {
        log_test_result("Invalid Input (NULL SSID)", false, "Should reject NULL SSID");
        return false;
    }
    ESP_LOGI(TAG, "NULL SSID correctly rejected");

    err = wifi_settings_save("ValidSSID", NULL);
    if (err == WIFI_STORAGE_OK) {
        log_test_result("Invalid Input (NULL Password)", false, "Should reject NULL password");
        return false;
    }
    ESP_LOGI(TAG, "NULL password correctly rejected");

    // Test NULL credentials pointer on load
    err = wifi_settings_load(NULL);
    if (err == WIFI_STORAGE_OK) {
        log_test_result("Invalid Input (NULL Load)", false, "Should reject NULL creds pointer");
        return false;
    }
    ESP_LOGI(TAG, "NULL credentials pointer correctly rejected");

    log_test_result("Invalid Inputs", true, NULL);
    return true;
}

/**
 * Test 7: Test maximum length credentials
 */
static bool test_max_length_credentials(void)
{
    ESP_LOGI(TAG, "\n--- Test 7: Test Maximum Length Credentials ---");

    // Max SSID: 31 chars (32 with null terminator)
    const char* max_ssid = "1234567890123456789012345678901";  // 31 chars
    // Max password: 63 chars
    const char* max_password = "123456789012345678901234567890123456789012345678901234567890123";  // 63 chars

    wifi_storage_error_t err = wifi_settings_save(max_ssid, max_password);
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Save max length failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Max Length Save", false, msg);
        return false;
    }

    // Load and verify
    wifi_credentials_t creds = {0};
    err = wifi_settings_load(&creds);
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Load max length failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Max Length Load", false, msg);
        return false;
    }

    if (strcmp(creds.ssid, max_ssid) != 0) {
        log_test_result("Max Length SSID", false, "Max length SSID mismatch");
        return false;
    }

    if (strcmp(creds.password, max_password) != 0) {
        log_test_result("Max Length Password", false, "Max length password mismatch");
        return false;
    }

    log_test_result("Max Length Credentials", true, NULL);
    return true;
}

/**
 * Test 8: Factory reset
 */
static bool test_factory_reset(void)
{
    ESP_LOGI(TAG, "\n--- Test 8: Factory Reset ---");

    // Ensure we have credentials saved first
    if (!wifi_settings_is_configured()) {
        wifi_settings_save("TempNetwork", "TempPassword123");
    }

    wifi_storage_error_t err = wifi_settings_factory_reset();
    if (err != WIFI_STORAGE_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Factory reset failed: %s", wifi_settings_error_to_string(err));
        log_test_result("Factory Reset", false, msg);
        return false;
    }

    // Verify device is unconfigured
    if (wifi_settings_is_configured()) {
        log_test_result("Factory Reset", false, "Device still configured after reset");
        return false;
    }

    // Verify load fails after reset
    wifi_credentials_t creds = {0};
    err = wifi_settings_load(&creds);
    if (err != WIFI_STORAGE_NOT_FOUND) {
        log_test_result("Factory Reset", false, "Load should return NOT_FOUND after reset");
        return false;
    }

    log_test_result("Factory Reset", true, NULL);
    return true;
}

/**
 * Test 9: Error string conversion
 */
static bool test_error_strings(void)
{
    ESP_LOGI(TAG, "\n--- Test 9: Error String Conversion ---");

    // Verify all error codes have valid strings
    const char* str;

    str = wifi_settings_error_to_string(WIFI_STORAGE_OK);
    if (str == NULL || strlen(str) == 0) {
        log_test_result("Error String (OK)", false, "NULL or empty string");
        return false;
    }
    ESP_LOGI(TAG, "WIFI_STORAGE_OK: '%s'", str);

    str = wifi_settings_error_to_string(WIFI_STORAGE_NOT_FOUND);
    if (str == NULL || strlen(str) == 0) {
        log_test_result("Error String (NOT_FOUND)", false, "NULL or empty string");
        return false;
    }
    ESP_LOGI(TAG, "WIFI_STORAGE_NOT_FOUND: '%s'", str);

    str = wifi_settings_error_to_string(WIFI_STORAGE_CORRUPT);
    ESP_LOGI(TAG, "WIFI_STORAGE_CORRUPT: '%s'", str);

    str = wifi_settings_error_to_string(WIFI_STORAGE_ENCRYPTION_ERROR);
    ESP_LOGI(TAG, "WIFI_STORAGE_ENCRYPTION_ERROR: '%s'", str);

    str = wifi_settings_error_to_string(WIFI_STORAGE_WRITE_ERROR);
    ESP_LOGI(TAG, "WIFI_STORAGE_WRITE_ERROR: '%s'", str);

    str = wifi_settings_error_to_string(WIFI_STORAGE_INVALID_PARAM);
    ESP_LOGI(TAG, "WIFI_STORAGE_INVALID_PARAM: '%s'", str);

    // Test unknown error code
    str = wifi_settings_error_to_string((wifi_storage_error_t)99);
    ESP_LOGI(TAG, "Unknown error (99): '%s'", str);

    log_test_result("Error Strings", true, NULL);
    return true;
}

/**
 * Run all tests
 */
static void run_all_tests(void)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "╔══════════════════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║         WiFi Settings Storage Module Test Suite          ║");
    ESP_LOGI(TAG, "╠══════════════════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Testing NVS partition I/O and AES encryption/decryption ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════════════════╝");
    ESP_LOGI(TAG, "");

    // Run tests in sequence - stop on critical failures
    if (!test_init()) {
        ESP_LOGE(TAG, "Critical failure: Cannot continue without NVS initialization");
        goto summary;
    }

    if (!test_initial_state()) {
        ESP_LOGW(TAG, "Initial state test failed, but continuing...");
    }

    if (!test_save_credentials()) {
        ESP_LOGE(TAG, "Critical failure: Cannot test load without successful save");
        goto summary;
    }

    test_configured_state();
    test_load_credentials();
    test_invalid_inputs();
    test_max_length_credentials();
    test_factory_reset();
    test_error_strings();

summary:
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "╔══════════════════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║                     TEST SUMMARY                         ║");
    ESP_LOGI(TAG, "╠══════════════════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Tests Passed: %2d                                        ║", tests_passed);
    ESP_LOGI(TAG, "║  Tests Failed: %2d                                        ║", tests_failed);
    ESP_LOGI(TAG, "╠══════════════════════════════════════════════════════════╣");

    if (tests_failed == 0) {
        ESP_LOGI(TAG, "║  ✓ ALL TESTS PASSED - Storage module is working!        ║");
    } else {
        ESP_LOGE(TAG, "║  ✗ SOME TESTS FAILED - Review errors above              ║");
    }

    ESP_LOGI(TAG, "╚══════════════════════════════════════════════════════════╝");
    ESP_LOGI(TAG, "");
}

/**
 * Main entry point for test
 */
void app_main(void)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "Starting WiFi Storage Module Tests...");
    ESP_LOGI(TAG, "");

    // Initialize default NVS partition first (required by ESP-IDF)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition needs erase, reinitializing...");
        nvs_flash_erase();
        ret = nvs_flash_init();
    }

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Default NVS initialization failed: %s", esp_err_to_name(ret));
        ESP_LOGE(TAG, "Cannot proceed with tests.");
        return;
    }

    ESP_LOGI(TAG, "Default NVS initialized successfully");

    // Run all storage tests
    run_all_tests();

    // Keep running to allow serial monitor review
    ESP_LOGI(TAG, "Tests complete. Device will idle.");
    ESP_LOGI(TAG, "Press reset button to run tests again.");

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
