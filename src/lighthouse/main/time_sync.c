/**
 * Time Synchronization Module - Implementation
 *
 * Manages SNTP-based wall-clock synchronization for the ESP32 lighthouse.
 * Tracks time quality state, persists last-known-good time to NVS,
 * and provides a clean API for timestamp-quality-aware publishing.
 *
 * Boot sequence behavior:
 *   1. On init: check NVS for last_unix_s / last_uptime_ms
 *      - If found: set TIME_QUALITY_ESTIMATED
 *      - If not found: remain TIME_QUALITY_NONE
 *   2. Start SNTP client (non-blocking)
 *   3. On sync callback: upgrade to TIME_QUALITY_SYNCED, persist to NVS
 *
 * DATASHEET REFERENCES:
 *   - ESP32 Datasheet Section 3.3.4 (RTC timer drift ~5% at 150 kHz)
 *   - ESP-IDF LwIP SNTP documentation (esp_sntp.h)
 */

#include "time_sync.h"
#include "esp_log.h"
#include "esp_sntp.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "nvs.h"
#include "nvs_flash.h"
#include <string.h>
#include <sys/time.h>
#include <time.h>

// ============================================================================
// CONSTANTS
// ============================================================================

static const char *TAG = "TIME_SYNC";

#define NVS_NAMESPACE_TIME_SYNC "time_sync"
#define NVS_KEY_LAST_UNIX_S     "last_unix_s"
#define NVS_KEY_LAST_UPTIME_MS  "last_uptime_ms"

#define SYNC_DONE_BIT BIT0

// ============================================================================
// MODULE STATE
// ============================================================================

static time_quality_t    s_quality        = TIME_QUALITY_NONE;
static EventGroupHandle_t s_sync_event_group = NULL;

// ============================================================================
// NVS HELPERS
// ============================================================================

/**
 * Persist last-known-good Unix time and uptime snapshot to NVS
 */
static void nvs_save_time(int64_t unix_s, int64_t uptime_ms)
{
    nvs_handle_t handle;
    esp_err_t    ret = nvs_open(NVS_NAMESPACE_TIME_SYNC, NVS_READWRITE, &handle);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to open NVS namespace for write: %s", esp_err_to_name(ret));
        return;
    }

    nvs_set_i64(handle, NVS_KEY_LAST_UNIX_S, unix_s);
    nvs_set_i64(handle, NVS_KEY_LAST_UPTIME_MS, uptime_ms);
    nvs_commit(handle);
    nvs_close(handle);

    ESP_LOGI(TAG, "Persisted time to NVS: unix_s=%lld, uptime_ms=%lld", unix_s, uptime_ms);
}

/**
 * Load last-known-good time from NVS
 *
 * @param out_unix_s    Output: last known Unix time in seconds
 * @param out_uptime_ms Output: uptime snapshot at that moment
 * @return true if both keys were found and loaded
 */
static bool nvs_load_time(int64_t *out_unix_s, int64_t *out_uptime_ms)
{
    nvs_handle_t handle;
    esp_err_t    ret = nvs_open(NVS_NAMESPACE_TIME_SYNC, NVS_READONLY, &handle);
    if (ret != ESP_OK)
    {
        return false; // Namespace doesn't exist yet (first boot)
    }

    int64_t unix_s     = 0;
    int64_t uptime_ms  = 0;
    bool    found_both = false;

    if (nvs_get_i64(handle, NVS_KEY_LAST_UNIX_S, &unix_s) == ESP_OK &&
        nvs_get_i64(handle, NVS_KEY_LAST_UPTIME_MS, &uptime_ms) == ESP_OK)
    {
        *out_unix_s     = unix_s;
        *out_uptime_ms  = uptime_ms;
        found_both      = true;
    }

    nvs_close(handle);
    return found_both;
}

// ============================================================================
// SNTP SYNC CALLBACK
// ============================================================================

/**
 * Called by ESP-IDF SNTP stack when a successful time adjustment occurs.
 *
 * Transitions quality to TIME_QUALITY_SYNCED and persists the new
 * authoritative time to NVS so future boots have an estimated lower bound.
 */
static void sntp_sync_notification_cb(struct timeval *tv)
{
    struct timeval now;
    gettimeofday(&now, NULL);

    int64_t unix_s    = (int64_t)now.tv_sec;
    int64_t uptime_ms = (int64_t)(esp_timer_get_time() / 1000);

    // Upgrade quality state
    s_quality = TIME_QUALITY_SYNCED;

    // Persist to NVS for next boot
    nvs_save_time(unix_s, uptime_ms);

    // Signal waiting tasks
    if (s_sync_event_group != NULL)
    {
        xEventGroupSetBits(s_sync_event_group, SYNC_DONE_BIT);
    }

    // Log the synced time in human-readable form
    time_t    t   = (time_t)unix_s;
    struct tm *tm = localtime(&t);
    char       buf[32];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S %Z", tm);
    ESP_LOGI(TAG, "SNTP sync successful: %s (unix=%lld)", buf, unix_s);
}

// ============================================================================
// PUBLIC API
// ============================================================================

esp_err_t time_sync_init(const char *ntp_server_ip)
{
    if (ntp_server_ip == NULL || ntp_server_ip[0] == '\0')
    {
        ESP_LOGE(TAG, "NTP server IP is required");
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "Initializing time sync with NTP server: %s", ntp_server_ip);

    // -------------------------------------------------------------------------
    // Step 1: Set timezone BEFORE SNTP init so localtime() is correct on sync
    // -------------------------------------------------------------------------
    setenv("TZ", TIME_SYNC_TZ_STRING, 1);
    tzset();
    ESP_LOGI(TAG, "Timezone set: %s", TIME_SYNC_TZ_STRING);

    // -------------------------------------------------------------------------
    // Step 2: Create sync event group for time_sync_wait_for_sync()
    // -------------------------------------------------------------------------
    s_sync_event_group = xEventGroupCreate();
    if (s_sync_event_group == NULL)
    {
        ESP_LOGE(TAG, "Failed to create sync event group");
        return ESP_ERR_NO_MEM;
    }

    // -------------------------------------------------------------------------
    // Step 3: Attempt to restore last-known-good time from NVS
    // -------------------------------------------------------------------------
    int64_t last_unix_s    = 0;
    int64_t last_uptime_ms = 0;
    if (nvs_load_time(&last_unix_s, &last_uptime_ms))
    {
        // Sanity check: time must be after 2024-01-01 to be meaningful
        if (last_unix_s > 1704067200LL)
        {
            s_quality = TIME_QUALITY_ESTIMATED;
            ESP_LOGI(TAG, "NVS time loaded: last_unix_s=%lld, last_uptime_ms=%lld -> TIME_QUALITY_ESTIMATED",
                     last_unix_s, last_uptime_ms);
        }
        else
        {
            ESP_LOGW(TAG, "NVS time value looks invalid (%lld), ignoring", last_unix_s);
        }
    }
    else
    {
        ESP_LOGI(TAG, "No NVS time found -> TIME_QUALITY_NONE");
    }

    // -------------------------------------------------------------------------
    // Step 4: Configure and start SNTP
    // -------------------------------------------------------------------------
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, ntp_server_ip);

    // Allow large time step on first sync (IMMED), then use smooth adjustments
    sntp_set_sync_mode(SNTP_SYNC_MODE_IMMED);

    // Register callback to be notified when sync occurs
    sntp_set_time_sync_notification_cb(sntp_sync_notification_cb);

    esp_sntp_init();

    ESP_LOGI(TAG, "SNTP client started (server=%s, mode=POLL)", ntp_server_ip);
    ESP_LOGI(TAG, "Initial time quality: %s",
             s_quality == TIME_QUALITY_SYNCED    ? "SYNCED"    :
             s_quality == TIME_QUALITY_ESTIMATED ? "ESTIMATED" : "NONE");

    return ESP_OK;
}

time_quality_t time_sync_get_quality(void)
{
    return s_quality;
}

bool time_sync_is_synced(void)
{
    return s_quality == TIME_QUALITY_SYNCED;
}

void time_sync_wait_for_sync(uint32_t timeout_ms)
{
    if (s_sync_event_group == NULL)
    {
        ESP_LOGW(TAG, "time_sync_wait_for_sync: not initialized");
        return;
    }

    if (s_quality == TIME_QUALITY_SYNCED)
    {
        return; // Already synced
    }

    ESP_LOGI(TAG, "Waiting up to %lu ms for SNTP sync...", timeout_ms);

    TickType_t timeout_ticks = (timeout_ms == 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms);
    EventBits_t bits = xEventGroupWaitBits(s_sync_event_group,
                                           SYNC_DONE_BIT,
                                           pdFALSE, // Don't clear on exit
                                           pdFALSE, // Wait for any bit
                                           timeout_ticks);

    if (bits & SYNC_DONE_BIT)
    {
        ESP_LOGI(TAG, "SNTP sync achieved within timeout");
    }
    else
    {
        ESP_LOGW(TAG, "SNTP sync timeout — continuing with quality=%s",
                 s_quality == TIME_QUALITY_ESTIMATED ? "ESTIMATED" : "NONE");
    }
}

int64_t time_sync_get_timestamp_ms(void)
{
    if (s_quality != TIME_QUALITY_SYNCED)
    {
        return 0;
    }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
}

void time_sync_notify_shutdown(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    int64_t unix_s    = (int64_t)tv.tv_sec;
    int64_t uptime_ms = (int64_t)(esp_timer_get_time() / 1000);

    // Only persist if we have a meaningful time (not boot-epoch)
    if (unix_s > 1704067200LL)
    {
        nvs_save_time(unix_s, uptime_ms);
        ESP_LOGI(TAG, "Shutdown time persisted to NVS");
    }
    else
    {
        ESP_LOGW(TAG, "Skipping NVS persist: clock not set (unix_s=%lld)", unix_s);
    }
}
