/**
 * Offline Event Logger - Implementation
 *
 * Implements persistent event storage using LittleFS on ESP32 flash memory.
 * Events are stored in a ring buffer with CRC32 validation and replayed
 * when network connectivity is restored.
 */

#include "offline_event_logger.h"
#include "time_sync.h"
#include "esp_crc.h"
#include "esp_littlefs.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// ============================================================================
// CONSTANTS AND MACROS
// ============================================================================

static const char *TAG = "OFFLINE_LOGGER";

#define EVENT_QUEUE_SIZE      64   // Max events in write queue
#define LOGGING_TASK_STACK    4096 // Stack size for logging task
#define LOGGING_TASK_PRIORITY 5    // Task priority
#define REPLAY_TASK_STACK     4096 // Stack size for replay task
#define REPLAY_TASK_PRIORITY  4    // Lower priority than logging

// NVS namespace and keys for persistent pointer storage (survives power outages)
#define NVS_NAMESPACE_OFFLINE "offline_log"
#define NVS_KEY_WRITE_INDEX   "write_idx"
#define NVS_KEY_READ_INDEX    "read_idx"

// ============================================================================
// GLOBAL STATE
// ============================================================================

// RTC memory for persistent write/read pointers (survives deep sleep)
RTC_DATA_ATTR static uint32_t rtc_write_index = 0;
RTC_DATA_ATTR static uint32_t rtc_read_index  = 0;
RTC_DATA_ATTR static bool     rtc_initialized = false;

// Runtime state
static struct
{
    bool initialized;
    bool mounted;
    int  fd; // File descriptor for events.bin

    // Write queue and synchronization
    QueueHandle_t     event_queue;   // Queue for async writes
    TaskHandle_t      logging_task;  // Background logging task
    SemaphoreHandle_t storage_mutex; // Protects file operations

    // Replay state
    TaskHandle_t              replay_task; // Background replay task
    offline_replay_callback_t replay_callback;
    bool                      replay_active;

    // Statistics
    offline_logger_stats_t stats;
} logger_state = {0};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Calculate CRC32 checksum for event validation
 */
static uint32_t calculate_event_crc(const offline_event_t *event)
{
    // CRC everything except the crc32 field itself
    size_t data_size = sizeof(offline_event_t) - sizeof(uint32_t) - sizeof(event->reserved);
    return esp_crc32_le(0, (uint8_t *)event, data_size);
}

/**
 * Convert RFID tag event to offline event format
 */
static void rfid_event_to_offline_event(const rfid_tag_event_t *rfid_event, offline_event_t *offline_event)
{
    memset(offline_event, 0, sizeof(offline_event_t));

    // Timestamp (milliseconds since boot)
    offline_event->timestamp_ms = esp_timer_get_time() / 1000;

    // RTC timestamp and time quality — depends on current sync state
    time_quality_t quality = time_sync_get_quality();
    if (quality == TIME_QUALITY_SYNCED)
    {
        // Wall-clock time is available: store Unix seconds
        int64_t ts_ms = time_sync_get_timestamp_ms();
        offline_event->rtc_timestamp_s = (uint32_t)(ts_ms / 1000);
    }
    else
    {
        // No authoritative time — leave rtc_timestamp_s as 0
        offline_event->rtc_timestamp_s = 0;
    }

    // Store time quality in reserved[0] for replay-time timeBasis selection
    offline_event->reserved[0] = (uint8_t)quality;

    // EPC data
    offline_event->epc_length = rfid_event->epc_len;
    memcpy(offline_event->epc, rfid_event->epc, rfid_event->epc_len < 24 ? rfid_event->epc_len : 24);

    // Reader ID (default to 1 for now)
    offline_event->reader_id = 1;

    // RSSI
    offline_event->rssi = rfid_event->rssi;

    // Calculate CRC32
    offline_event->crc32 = calculate_event_crc(offline_event);
}

/**
 * Convert offline event back to RFID tag event format
 */
static void offline_event_to_rfid_event(const offline_event_t *offline_event, rfid_tag_event_t *rfid_event)
{
    memset(rfid_event, 0, sizeof(rfid_tag_event_t));

    // Copy EPC data
    rfid_event->epc_len = offline_event->epc_length;
    memcpy(rfid_event->epc, offline_event->epc, offline_event->epc_length);

    // RSSI
    rfid_event->rssi = offline_event->rssi;

    // Timestamp
    rfid_event->timestamp_ms = (uint32_t)offline_event->timestamp_ms;

    // Other fields can be set to defaults
    rfid_event->antenna_id = offline_event->reader_id;
    rfid_event->frequency  = 0;
}

/**
 * Write event at specific index in ring buffer
 */
static esp_err_t write_event_at_index(uint32_t index, const offline_event_t *event)
{
    if (!logger_state.mounted)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Calculate file offset
    off_t offset = index * OFFLINE_EVENT_RECORD_SIZE;

    // Seek to position
    if (lseek(logger_state.fd, offset, SEEK_SET) != offset)
    {
        ESP_LOGE(TAG, "Failed to seek to offset %ld", offset);
        return ESP_FAIL;
    }

    // Write event
    ssize_t written = write(logger_state.fd, event, OFFLINE_EVENT_RECORD_SIZE);
    if (written != OFFLINE_EVENT_RECORD_SIZE)
    {
        ESP_LOGE(TAG, "Failed to write event (wrote %d bytes)", written);
        return ESP_FAIL;
    }

    // Flush to ensure data is written
    fsync(logger_state.fd);

    return ESP_OK;
}

/**
 * Read event at specific index from ring buffer
 */
static esp_err_t read_event_at_index(uint32_t index, offline_event_t *event)
{
    if (!logger_state.mounted)
    {
        return ESP_ERR_INVALID_STATE;
    }

    // Calculate file offset
    off_t offset = index * OFFLINE_EVENT_RECORD_SIZE;

    // Seek to position
    if (lseek(logger_state.fd, offset, SEEK_SET) != offset)
    {
        ESP_LOGE(TAG, "Failed to seek to offset %ld", offset);
        return ESP_FAIL;
    }

    // Read event
    ssize_t bytes_read = read(logger_state.fd, event, OFFLINE_EVENT_RECORD_SIZE);
    if (bytes_read != OFFLINE_EVENT_RECORD_SIZE)
    {
        ESP_LOGE(TAG, "Failed to read event (read %d bytes)", bytes_read);
        return ESP_FAIL;
    }

    return ESP_OK;
}

/**
 * Validate event CRC32
 */
static bool validate_event_crc(const offline_event_t *event)
{
    uint32_t calculated_crc = calculate_event_crc(event);
    return calculated_crc == event->crc32;
}

/**
 * Get number of pending events in ring buffer
 */
static uint32_t get_pending_count_internal(void)
{
    if (rtc_write_index >= rtc_read_index)
    {
        return rtc_write_index - rtc_read_index;
    }
    else
    {
        // Buffer wrapped around
        return (OFFLINE_MAX_EVENTS - rtc_read_index) + rtc_write_index;
    }
}

// ============================================================================
// NVS HELPERS — persistent pointer storage that survives full power outages
// ============================================================================

static nvs_handle_t s_nvs_handle = 0;
static bool         s_nvs_open   = false;

static void nvs_open_logger(void)
{
    esp_err_t ret = nvs_open(NVS_NAMESPACE_OFFLINE, NVS_READWRITE, &s_nvs_handle);
    if (ret == ESP_OK)
    {
        s_nvs_open = true;
    }
    else
    {
        ESP_LOGW(TAG, "Failed to open NVS namespace '%s': %s", NVS_NAMESPACE_OFFLINE, esp_err_to_name(ret));
    }
}

static void nvs_save_pointers(void)
{
    if (!s_nvs_open)
        return;
    nvs_set_u32(s_nvs_handle, NVS_KEY_WRITE_INDEX, rtc_write_index);
    nvs_set_u32(s_nvs_handle, NVS_KEY_READ_INDEX, rtc_read_index);
    nvs_commit(s_nvs_handle);
}

static bool nvs_load_pointers(uint32_t *write_idx, uint32_t *read_idx)
{
    if (!s_nvs_open)
        return false;
    esp_err_t r1 = nvs_get_u32(s_nvs_handle, NVS_KEY_WRITE_INDEX, write_idx);
    esp_err_t r2 = nvs_get_u32(s_nvs_handle, NVS_KEY_READ_INDEX, read_idx);
    return (r1 == ESP_OK && r2 == ESP_OK);
}

// ============================================================================
// BACKGROUND TASKS
// ============================================================================

/**
 * Event logging task
 *
 * Runs continuously, dequeuing events and writing them to storage.
 * This ensures RFID detection is never blocked by storage operations.
 */
static void logging_task(void *arg)
{
    ESP_LOGI(TAG, "Logging task started");

    rfid_tag_event_t rfid_event;

    while (1)
    {
        // Wait for event from queue (blocks until available)
        if (xQueueReceive(logger_state.event_queue, &rfid_event, portMAX_DELAY))
        {
            // Convert to offline format
            offline_event_t offline_event;
            rfid_event_to_offline_event(&rfid_event, &offline_event);

            // Acquire storage mutex
            if (xSemaphoreTake(logger_state.storage_mutex, pdMS_TO_TICKS(1000)))
            {
                // Write event at current write index
                esp_err_t ret = write_event_at_index(rtc_write_index, &offline_event);

                if (ret == ESP_OK)
                {
                    // Advance write pointer
                    uint32_t old_write_index = rtc_write_index;
                    rtc_write_index          = (rtc_write_index + 1) % OFFLINE_MAX_EVENTS;

                    // Check if we wrapped around and overwrote unread events
                    if (get_pending_count_internal() >= OFFLINE_MAX_EVENTS - 1)
                    {
                        // Buffer overflow - advance read pointer
                        rtc_read_index = (rtc_read_index + 1) % OFFLINE_MAX_EVENTS;
                        logger_state.stats.buffer_overflows++;
                        ESP_LOGW(TAG, "Buffer overflow! Oldest event overwritten");
                    }

                    // Persist updated pointers to NVS so they survive a power outage
                    nvs_save_pointers();

                    logger_state.stats.events_written++;
                    ESP_LOGD(TAG, "Event stored at index %lu (pending: %lu)", old_write_index,
                             get_pending_count_internal());
                }
                else
                {
                    logger_state.stats.write_errors++;
                    ESP_LOGE(TAG, "Failed to write event");
                }

                xSemaphoreGive(logger_state.storage_mutex);
            }
            else
            {
                ESP_LOGE(TAG, "Failed to acquire storage mutex");
                logger_state.stats.write_errors++;
            }
        }
    }
}

/**
 * Event replay task
 *
 * Replays stored events to the server with throttling.
 */
static void replay_task(void *arg)
{
    uint32_t grace_period_s = (uint32_t)(uintptr_t)arg;

    ESP_LOGI(TAG, "Replay task started (grace period: %lu seconds)", grace_period_s);

    // Wait for grace period
    if (grace_period_s > 0)
    {
        ESP_LOGI(TAG, "Waiting %lu seconds before starting replay...", grace_period_s);
        vTaskDelay(pdMS_TO_TICKS(grace_period_s * 1000));
    }

    ESP_LOGI(TAG, "Starting event replay...");
    logger_state.replay_active = true;

    uint32_t events_replayed   = 0;
    uint64_t replay_start_time = esp_timer_get_time() / 1000;

    while (logger_state.replay_active && get_pending_count_internal() > 0)
    {
        // Acquire storage mutex
        if (xSemaphoreTake(logger_state.storage_mutex, pdMS_TO_TICKS(1000)))
        {
            // Read event at current read index
            offline_event_t offline_event;
            esp_err_t       ret = read_event_at_index(rtc_read_index, &offline_event);

            if (ret == ESP_OK)
            {
                // Validate CRC
                if (validate_event_crc(&offline_event))
                {
                    // Convert to RFID format
                    rfid_tag_event_t rfid_event;
                    offline_event_to_rfid_event(&offline_event, &rfid_event);

                    // Release mutex before callback (avoid holding during network I/O)
                    xSemaphoreGive(logger_state.storage_mutex);

                    // Call replay callback with stored time metadata
                    if (logger_state.replay_callback)
                    {
                        uint64_t       replay_time   = esp_timer_get_time() / 1000;
                        time_quality_t stored_quality = (time_quality_t)offline_event.reserved[0];
                        ret = logger_state.replay_callback(&rfid_event, offline_event.timestamp_ms, replay_time,
                                                           offline_event.rtc_timestamp_s, stored_quality);

                        if (ret == ESP_OK)
                        {
                            events_replayed++;
                            logger_state.stats.events_replayed++;

                            // Advance read pointer (acquire mutex again)
                            if (xSemaphoreTake(logger_state.storage_mutex, pdMS_TO_TICKS(1000)))
                            {
                                rtc_read_index = (rtc_read_index + 1) % OFFLINE_MAX_EVENTS;
                                // Persist updated read pointer so replay progress survives power loss
                                nvs_save_pointers();
                                xSemaphoreGive(logger_state.storage_mutex);
                            }

                            ESP_LOGI(TAG, "Replayed event %lu/%lu", events_replayed,
                                     events_replayed + get_pending_count_internal());
                        }
                        else
                        {
                            ESP_LOGW(TAG, "Failed to replay event, will retry");
                            vTaskDelay(pdMS_TO_TICKS(1000)); // Wait before retry
                        }
                    }

                    // Throttle replay rate (max 10 events/second)
                    vTaskDelay(pdMS_TO_TICKS(100));
                }
                else
                {
                    // CRC validation failed
                    logger_state.stats.crc_errors++;
                    ESP_LOGE(TAG, "CRC validation failed for event at index %lu", rtc_read_index);

                    // Skip corrupted event
                    rtc_read_index = (rtc_read_index + 1) % OFFLINE_MAX_EVENTS;
                    xSemaphoreGive(logger_state.storage_mutex);
                }
            }
            else
            {
                xSemaphoreGive(logger_state.storage_mutex);
                ESP_LOGE(TAG, "Failed to read event");
                vTaskDelay(pdMS_TO_TICKS(1000));
            }
        }
        else
        {
            ESP_LOGE(TAG, "Failed to acquire storage mutex during replay");
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
    }

    logger_state.replay_active = false;
    logger_state.replay_task   = NULL;

    uint64_t replay_duration = (esp_timer_get_time() / 1000) - replay_start_time;
    ESP_LOGI(TAG, "Replay complete! Replayed %lu events in %llu ms", events_replayed, replay_duration);

    vTaskDelete(NULL);
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t offline_logger_init(void)
{
    if (logger_state.initialized)
    {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing offline event logger...");

    // Configure LittleFS
    esp_vfs_littlefs_conf_t conf = {
        .base_path              = OFFLINE_EVENTS_BASE_PATH,
        .partition_label        = OFFLINE_EVENTS_PARTITION_LABEL,
        .format_if_mount_failed = true,
        .dont_mount             = false,
    };

    // Mount partition
    esp_err_t ret = esp_vfs_littlefs_register(&conf);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to mount LittleFS partition: %s", esp_err_to_name(ret));
        return ret;
    }

    logger_state.mounted = true;
    ESP_LOGI(TAG, "LittleFS partition mounted at %s", OFFLINE_EVENTS_BASE_PATH);

    // Get partition info
    size_t total = 0, used = 0;
    ret = esp_littlefs_info(OFFLINE_EVENTS_PARTITION_LABEL, &total, &used);
    if (ret == ESP_OK)
    {
        ESP_LOGI(TAG, "Partition size: %u KB, used: %u KB (%u%% free)", total / 1024, used / 1024,
                 ((total - used) * 100) / total);
    }

    // Open or create events file
    logger_state.fd = open(OFFLINE_EVENTS_FILE_PATH, O_RDWR | O_CREAT, 0644);
    if (logger_state.fd < 0)
    {
        ESP_LOGE(TAG, "Failed to open events file");
        esp_vfs_littlefs_unregister(OFFLINE_EVENTS_PARTITION_LABEL);
        logger_state.mounted = false;
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Events file opened: %s", OFFLINE_EVENTS_FILE_PATH);

    // Open NVS for persistent pointer storage (survives power outages, unlike RTC memory)
    nvs_open_logger();

    if (!rtc_initialized)
    {
        // RTC memory was lost — this could be a genuine first boot OR recovery from a
        // full power outage. Check NVS (flash-backed) for previously saved pointers.
        uint32_t nvs_write = 0, nvs_read = 0;
        if (nvs_load_pointers(&nvs_write, &nvs_read))
        {
            rtc_write_index = nvs_write;
            rtc_read_index  = nvs_read;
            ESP_LOGI(TAG, "Pointers restored from NVS after power loss: write=%lu, read=%lu",
                     rtc_write_index, rtc_read_index);
        }
        else
        {
            // Genuine first boot — no saved state in NVS
            rtc_write_index = 0;
            rtc_read_index  = 0;
            ESP_LOGI(TAG, "RTC pointers initialized (first boot)");
        }
        rtc_initialized = true;
    }
    else
    {
        ESP_LOGI(TAG, "RTC pointers restored from deep sleep: write=%lu, read=%lu",
                 rtc_write_index, rtc_read_index);
    }

    // Create storage mutex
    logger_state.storage_mutex = xSemaphoreCreateMutex();
    if (!logger_state.storage_mutex)
    {
        ESP_LOGE(TAG, "Failed to create storage mutex");
        close(logger_state.fd);
        esp_vfs_littlefs_unregister(OFFLINE_EVENTS_PARTITION_LABEL);
        return ESP_ERR_NO_MEM;
    }

    // Create event queue
    logger_state.event_queue = xQueueCreate(EVENT_QUEUE_SIZE, sizeof(rfid_tag_event_t));
    if (!logger_state.event_queue)
    {
        ESP_LOGE(TAG, "Failed to create event queue");
        vSemaphoreDelete(logger_state.storage_mutex);
        close(logger_state.fd);
        esp_vfs_littlefs_unregister(OFFLINE_EVENTS_PARTITION_LABEL);
        return ESP_ERR_NO_MEM;
    }

    // Create logging task
    BaseType_t task_ret = xTaskCreate(logging_task, "offline_log", LOGGING_TASK_STACK, NULL, LOGGING_TASK_PRIORITY,
                                      &logger_state.logging_task);

    if (task_ret != pdPASS)
    {
        ESP_LOGE(TAG, "Failed to create logging task");
        vQueueDelete(logger_state.event_queue);
        vSemaphoreDelete(logger_state.storage_mutex);
        close(logger_state.fd);
        esp_vfs_littlefs_unregister(OFFLINE_EVENTS_PARTITION_LABEL);
        return ESP_ERR_NO_MEM;
    }

    // Initialize statistics
    memset(&logger_state.stats, 0, sizeof(offline_logger_stats_t));
    logger_state.stats.pending_events = get_pending_count_internal();

    logger_state.initialized = true;

    ESP_LOGI(TAG, "════════════════════════════════════");
    ESP_LOGI(TAG, "  Offline Event Logger Ready!");
    ESP_LOGI(TAG, "  Max capacity: %d events", OFFLINE_MAX_EVENTS);
    ESP_LOGI(TAG, "  Pending events: %lu", logger_state.stats.pending_events);
    ESP_LOGI(TAG, "════════════════════════════════════\n");

    return ESP_OK;
}

esp_err_t offline_logger_deinit(void)
{
    if (!logger_state.initialized)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Deinitializing offline event logger...");

    // Stop replay if active
    if (logger_state.replay_active)
    {
        offline_logger_stop_replay();
    }

    // Delete logging task
    if (logger_state.logging_task)
    {
        vTaskDelete(logger_state.logging_task);
        logger_state.logging_task = NULL;
    }

    // Delete queue
    if (logger_state.event_queue)
    {
        vQueueDelete(logger_state.event_queue);
        logger_state.event_queue = NULL;
    }

    // Delete mutex
    if (logger_state.storage_mutex)
    {
        vSemaphoreDelete(logger_state.storage_mutex);
        logger_state.storage_mutex = NULL;
    }

    // Close file
    if (logger_state.fd >= 0)
    {
        close(logger_state.fd);
        logger_state.fd = -1;
    }

    // Unmount partition
    if (logger_state.mounted)
    {
        esp_vfs_littlefs_unregister(OFFLINE_EVENTS_PARTITION_LABEL);
        logger_state.mounted = false;
    }

    logger_state.initialized = false;

    ESP_LOGI(TAG, "Offline event logger deinitialized");
    return ESP_OK;
}

esp_err_t offline_logger_store_event(const rfid_tag_event_t *event)
{
    if (!logger_state.initialized)
    {
        return ESP_FAIL;
    }

    // Queue event for async writing (non-blocking)
    if (xQueueSend(logger_state.event_queue, event, 0) != pdTRUE)
    {
        ESP_LOGW(TAG, "Event queue full! Dropping event");
        return ESP_ERR_NO_MEM;
    }

    return ESP_OK;
}

esp_err_t offline_logger_start_replay(offline_replay_callback_t callback, uint32_t grace_period_s)
{
    if (!logger_state.initialized)
    {
        return ESP_FAIL;
    }

    if (logger_state.replay_active)
    {
        ESP_LOGW(TAG, "Replay already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    if (!callback)
    {
        return ESP_ERR_INVALID_ARG;
    }

    // Check if there are events to replay
    uint32_t pending = get_pending_count_internal();
    if (pending == 0)
    {
        ESP_LOGI(TAG, "No events to replay");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting replay of %lu events...", pending);

    logger_state.replay_callback = callback;

    // Create replay task
    BaseType_t ret = xTaskCreate(replay_task, "offline_replay", REPLAY_TASK_STACK, (void *)(uintptr_t)grace_period_s,
                                 REPLAY_TASK_PRIORITY, &logger_state.replay_task);

    if (ret != pdPASS)
    {
        ESP_LOGE(TAG, "Failed to create replay task");
        return ESP_ERR_NO_MEM;
    }

    return ESP_OK;
}

esp_err_t offline_logger_stop_replay(void)
{
    if (!logger_state.replay_active)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping replay...");
    logger_state.replay_active = false;

    // Wait for task to finish
    while (logger_state.replay_task != NULL)
    {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    ESP_LOGI(TAG, "Replay stopped");
    return ESP_OK;
}

bool offline_logger_is_replaying(void)
{
    return logger_state.replay_active;
}

uint32_t offline_logger_get_pending_count(void)
{
    if (!logger_state.initialized)
    {
        return 0;
    }

    return get_pending_count_internal();
}

esp_err_t offline_logger_get_stats(offline_logger_stats_t *stats)
{
    if (!stats)
    {
        return ESP_ERR_INVALID_ARG;
    }

    if (!logger_state.initialized)
    {
        memset(stats, 0, sizeof(offline_logger_stats_t));
        return ESP_OK;
    }

    memcpy(stats, &logger_state.stats, sizeof(offline_logger_stats_t));
    stats->pending_events     = get_pending_count_internal();
    stats->replay_in_progress = logger_state.replay_active;

    return ESP_OK;
}

esp_err_t offline_logger_clear_all(void)
{
    if (!logger_state.initialized)
    {
        return ESP_FAIL;
    }

    ESP_LOGW(TAG, "Clearing all stored events!");

    if (xSemaphoreTake(logger_state.storage_mutex, pdMS_TO_TICKS(1000)))
    {
        rtc_write_index = 0;
        rtc_read_index  = 0;
        nvs_save_pointers();
        xSemaphoreGive(logger_state.storage_mutex);

        ESP_LOGI(TAG, "All events cleared");
        return ESP_OK;
    }

    return ESP_FAIL;
}

esp_err_t offline_logger_format_partition(void)
{
    ESP_LOGW(TAG, "Formatting partition (DESTRUCTIVE)!");

    bool was_initialized = logger_state.initialized;

    // Deinitialize first
    if (was_initialized)
    {
        offline_logger_deinit();
    }

    // Format partition
    esp_err_t ret = esp_littlefs_format(OFFLINE_EVENTS_PARTITION_LABEL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to format partition: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "Partition formatted successfully");

    // Re-initialize if it was initialized before
    if (was_initialized)
    {
        rtc_write_index = 0;
        rtc_read_index  = 0;
        rtc_initialized = true;
        return offline_logger_init();
    }

    return ESP_OK;
}
