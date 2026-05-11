/**
 * Offline Event Logger - ESP32 Attendance System
 *
 * Provides local event storage during network outages with automatic
 * synchronization when connectivity is restored.
 *
 * Features:
 * - LittleFS-based persistent storage (survives power cycles)
 * - Ring buffer with 48-byte event records
 * - CRC32 validation for data integrity
 * - Non-blocking writes (asynchronous operation)
 * - Automatic event replay with throttling
 * - Graceful overflow handling (oldest events overwritten)
 *
 * Storage Architecture:
 * - Partition: offline_events (2 MB at 0x110000)
 * - Capacity: ~43,690 events (2-3 hours @ 5 events/sec)
 * - Format: Binary fixed-size records (48 bytes each)
 * - Write pointer stored in RTC_SLOW_MEM (survives deep sleep)
 *
 * DATASHEET REFERENCES:
 * - ESP-IDF LittleFS Component Documentation
 * - Technical Report: Network Resilience and Offline Event Logging Architecture
 */

#ifndef OFFLINE_EVENT_LOGGER_H
#define OFFLINE_EVENT_LOGGER_H

#include "esp_err.h"
#include "rfid_reader.h"
#include "time_sync.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// CONFIGURATION
// ============================================================================

#define OFFLINE_EVENTS_PARTITION_LABEL "offline_events"
#define OFFLINE_EVENTS_BASE_PATH       "/offline_events"
#define OFFLINE_EVENTS_FILE_PATH       "/offline_events/events.bin"

/**
 * Event Record Size (48 bytes aligned)
 * Per technical report Appendix A, section 5.1
 */
#define OFFLINE_EVENT_RECORD_SIZE 48

/**
 * Maximum events in 2 MB partition
 * 2,097,152 bytes / 48 bytes = 43,690 events
 */
#define OFFLINE_MAX_EVENTS 43690

/**
 * Event replay throttle rate (events per second)
 * Per technical report section 6.1
 */
#define OFFLINE_REPLAY_RATE_LIMIT 10

/**
 * Grace period before starting replay (seconds)
 * Allows server to prepare for offline event ingestion
 */
#define OFFLINE_REPLAY_GRACE_PERIOD 5

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * Offline Event Record (48 bytes aligned)
 *
 * Per technical report section 5.1:
 * - timestamp_ms: milliseconds since boot (for ordering)
 * - rtc_timestamp_s: Unix time (synchronized when online)
 * - epc: Electronic Product Code (RFID tag ID)
 * - epc_length: Actual EPC length (1-24 bytes)
 * - reader_id: Which reader detected (1=A, 2=B, etc.)
 * - rssi: Signal strength (raw value)
 * - crc32: CRC32 checksum for integrity verification
 * - seq_no: monotonically increasing sequence number per device (assigned at write
 *   time, excluded from CRC). Legacy entries written before this field was added
 *   have seq_no == 0; the server acknowledges them with ackedSeqNo == 0.
 *   Time quality at recording time is inferred from rtc_timestamp_s: > 0 means
 *   TIME_QUALITY_SYNCED, == 0 means TIME_QUALITY_NONE.
 */
typedef struct __attribute__((packed))
{
    uint64_t timestamp_ms;    // 8 bytes - milliseconds since boot
    uint32_t rtc_timestamp_s; // 4 bytes - Unix time (0 if unavailable)
    uint8_t  epc[24];         // 24 bytes - EPC buffer (96-bit max)
    uint8_t  epc_length;      // 1 byte - actual EPC length
    uint8_t  reader_id;       // 1 byte - reader ID (1=A, 2=B)
    uint16_t rssi;            // 2 bytes - signal strength
    uint32_t crc32;           // 4 bytes - CRC32 checksum (does not cover seq_no)
    uint32_t seq_no;          // 4 bytes - monotonic sequence number (not CRC'd)
} offline_event_t;

_Static_assert(sizeof(offline_event_t) == 48, "offline_event_t must be exactly 48 bytes");

/**
 * Offline Logger Statistics
 */
typedef struct
{
    uint32_t events_written;     // Total events written to storage
    uint32_t events_replayed;    // Total events replayed to server
    uint32_t write_errors;       // Failed write operations
    uint32_t crc_errors;         // Corrupted events detected
    uint32_t buffer_overflows;   // Times buffer wrapped around
    uint32_t pending_events;     // Events waiting to be replayed
    bool     replay_in_progress; // Currently replaying events
} offline_logger_stats_t;

/**
 * Number of offline events bundled into one MQTT message during replay.
 * Batching cuts per-event NVS saves and MQTT round-trips, which are the
 * dominant latency during offline replay (~100-2000 ms per NVS write).
 */
#define OFFLINE_REPLAY_BATCH_SIZE 8

/**
 * Single entry within a batch replay callback.
 */
typedef struct
{
    rfid_tag_event_t event;
    uint64_t         offline_timestamp_ms;
    uint32_t         rtc_timestamp_s;
    time_quality_t   time_quality;
    uint32_t         seq_no;
} offline_replay_entry_t;

/**
 * Batch Event Replay Callback
 *
 * Called once per batch of up to OFFLINE_REPLAY_BATCH_SIZE events during
 * replay. Publishing as a single MQTT array message reduces MQTT round-trips
 * and, crucially, the number of NVS saves triggered by incoming ACKs.
 *
 * @param entries             Array of up to OFFLINE_REPLAY_BATCH_SIZE entries
 * @param count               Actual number of entries in this batch
 * @param replay_timestamp_ms Current boot-relative time in ms
 * @return ESP_OK if batch published successfully; ESP_FAIL stops replay
 */
typedef esp_err_t (*offline_batch_replay_callback_t)(const offline_replay_entry_t *entries,
                                                     uint32_t                      count,
                                                     uint64_t                      replay_timestamp_ms);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize offline event logger
 *
 * Performs the following initialization:
 * 1. Mount LittleFS partition (format if missing)
 * 2. Verify storage integrity
 * 3. Restore write/read pointers from RTC memory
 * 4. Create event logging task
 *
 * IMPORTANT: Call this during app_main() before starting RFID scanning.
 *
 * @return ESP_OK on success, error code otherwise
 *
 * Example:
 * ```c
 * void app_main(void) {
 *     // Initialize logger first
 *     offline_logger_init();
 *
 *     // Then start RFID and MQTT
 *     rfid_reader_init();
 *     mqtt_client_init();
 * }
 * ```
 */
esp_err_t offline_logger_init(void);

/**
 * Deinitialize offline event logger
 *
 * Gracefully shuts down logger:
 * - Stops logging task
 * - Flushes pending writes
 * - Unmounts filesystem
 * - Frees resources
 *
 * @return ESP_OK on success
 */
esp_err_t offline_logger_deinit(void);

/**
 * Log RFID tag event for offline storage
 *
 * Stores event to LittleFS with timestamp and CRC32 validation.
 * This function is non-blocking - events are queued and written
 * asynchronously by the logging task.
 *
 * Call this when MQTT is unavailable to ensure events are not lost.
 *
 * @param event RFID tag detection event from reader
 * @return ESP_OK if event queued successfully
 *         ESP_ERR_NO_MEM if queue is full (very rare)
 *         ESP_FAIL if logger not initialized
 *
 * Example:
 * ```c
 * void on_tag_detected(const rfid_tag_event_t* event) {
 *     if (mqtt_client_is_connected()) {
 *         mqtt_client_publish_tag_event(event);
 *     } else {
 *         offline_logger_store_event(event);
 *     }
 * }
 * ```
 */
esp_err_t offline_logger_store_event(const rfid_tag_event_t *event);

/**
 * Start event replay process
 *
 * Begins replaying stored offline events to the server with throttling.
 * This should be called when network connectivity is restored.
 *
 * Per technical report section 6.1:
 * 1. Waits for grace period (30 seconds default)
 * 2. Replays events at max 10 events/second
 * 3. Marks events with offline flag
 * 4. Continues until all events replayed
 *
 * @param callback Function to call for each batch of events (MQTT publish)
 * @param grace_period_s Delay before starting replay (0 = immediate)
 * @return ESP_OK if replay started successfully
 *         ESP_ERR_INVALID_STATE if already replaying
 *         ESP_ERR_INVALID_ARG if callback is NULL
 *
 * Example:
 * ```c
 * void on_mqtt_connected(void) {
 *     offline_logger_start_replay(publish_offline_batch, 30);
 * }
 * ```
 */
esp_err_t offline_logger_start_replay(offline_batch_replay_callback_t callback, uint32_t grace_period_s);

/**
 * Stop event replay process
 *
 * Immediately stops ongoing replay. Remaining events will stay
 * in storage until next replay is initiated.
 *
 * @return ESP_OK on success
 */
esp_err_t offline_logger_stop_replay(void);

/**
 * Check if replay is currently in progress
 *
 * @return true if replaying events, false otherwise
 */
bool offline_logger_is_replaying(void);

/**
 * Get number of pending events waiting to be replayed
 *
 * @return Number of events in storage
 */
uint32_t offline_logger_get_pending_count(void);

/**
 * Get offline logger statistics
 *
 * @param stats Pointer to structure to receive statistics
 * @return ESP_OK on success, ESP_ERR_INVALID_ARG if stats is NULL
 */
esp_err_t offline_logger_get_stats(offline_logger_stats_t *stats);

/**
 * Clear all stored events (DESTRUCTIVE)
 *
 * Erases all offline events from storage. Use with caution!
 *
 * @return ESP_OK on success
 */
esp_err_t offline_logger_clear_all(void);

/**
 * Format offline events partition (DESTRUCTIVE)
 *
 * Completely reformats the LittleFS partition, erasing all data.
 * Only use this for recovery from filesystem corruption.
 *
 * @return ESP_OK on success
 */
esp_err_t offline_logger_format_partition(void);

/**
 * Sync-start notification callback
 *
 * Called from the replay task immediately before the first event is published
 * (after the grace period). Use it to publish sync/start to the server.
 *
 * @param count Number of events about to be replayed
 */
typedef void (*offline_sync_start_callback_t)(uint32_t count);

/**
 * Register a callback fired at the start of each replay pass.
 * Safe to call before offline_logger_init().
 */
void offline_logger_set_sync_start_callback(offline_sync_start_callback_t callback);

/**
 * Pre-register replay callback for deferred start
 *
 * Call this when MQTT connects so that offline_logger_init(), if it runs later,
 * can automatically start replay without needing an additional trigger.
 * If the logger is already initialized and has pending events, the registered
 * callback is picked up by the next offline_logger_start_replay() call.
 *
 * Safe to call before offline_logger_init().
 *
 * @param callback     Function to call for each batch of events during replay
 * @param grace_period_s Delay before starting replay (0 = immediate)
 */
void offline_logger_schedule_replay(offline_batch_replay_callback_t callback, uint32_t grace_period_s);

/**
 * Acknowledge receipt of replayed events up to acked_seq_no
 *
 * Called from the MQTT event handler when the server publishes an ACK on
 * attendance/lighthouse/{MAC}/ack. Advances rtc_read_index past all entries
 * whose seq_no <= acked_seq_no and persists the new position to NVS.
 *
 * For legacy entries (seq_no == 0): advanced when acked_seq_no == 0.
 * Safe to call from any task context.
 *
 * @param acked_seq_no Highest sequence number committed by the server
 */
void offline_logger_ack_received(uint32_t acked_seq_no);

/**
 * Check whether all events that existed at the START of the current replay
 * pass have been acknowledged.
 *
 * Returns true when rtc_read_index has caught up to the write-index snapshot
 * taken when offline_logger_start_replay() was called. New live events written
 * to flash after replay started are NOT counted — this lets sync/complete fire
 * even when the ring buffer continues to receive live scans.
 *
 * Returns false if no replay has ever been started.
 */
bool offline_logger_replay_batch_complete(void);

#endif // OFFLINE_EVENT_LOGGER_H
