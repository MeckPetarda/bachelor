/**
 * Time Synchronization Module - ESP32 Attendance System
 *
 * Manages SNTP-based wall-clock synchronization with quality tracking
 * and NVS persistence for last-known-good time across boots.
 *
 * Time Quality States:
 *   TIME_QUALITY_NONE      - No time reference (boot-relative only)
 *   TIME_QUALITY_ESTIMATED - Lower-bound from NVS (previous boot's time)
 *   TIME_QUALITY_SYNCED    - SNTP synchronized, wall-clock is authoritative
 *
 * NVS Persistence:
 *   Namespace: "time_sync"
 *   Keys: "last_unix_s" (int64), "last_uptime_ms" (int64)
 *
 * SNTP Configuration:
 *   - Server: MQTT broker IP (same machine hosts NTP daemon)
 *   - Mode: SNTP_OPMODE_POLL with 1-hour default interval
 *   - Timezone: CET/CEST (configurable via setenv("TZ", ...))
 *
 * DATASHEET REFERENCES:
 *   - ESP32 Datasheet Section 3.3.4 (RTC timer, ~5% drift at 150kHz)
 *   - ESP-IDF esp_sntp.h component documentation
 */

#ifndef TIME_SYNC_H
#define TIME_SYNC_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

// ============================================================================
// TIME QUALITY ENUM
// ============================================================================

/**
 * Time quality states indicating reliability of current wall-clock time.
 *
 * The integer values are stored in offline event records (reserved[0]),
 * so the encoding is fixed: 0=NONE, 1=ESTIMATED, 2=SYNCED.
 */
typedef enum
{
    TIME_QUALITY_NONE      = 0, // No time reference — timestamps are boot-relative ms
    TIME_QUALITY_ESTIMATED = 1, // NVS lower-bound from last boot — timestamps are boot-relative ms
    TIME_QUALITY_SYNCED    = 2, // SNTP synced — timestamps are real Unix ms
} time_quality_t;

// ============================================================================
// TIMEZONE CONFIGURATION
// ============================================================================

/**
 * POSIX TZ string for Central European Time with automatic DST transitions.
 * CET-1 = UTC+1, CEST = summer time (UTC+2)
 * Transitions: last Sunday in March at 02:00, last Sunday in October at 03:00
 */
#define TIME_SYNC_TZ_STRING "CET-1CEST,M3.5.0,M10.5.0/3"

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize SNTP time synchronization
 *
 * Configures the SNTP client with the given NTP server address,
 * sets the timezone, registers the sync notification callback,
 * and attempts to restore last-known-good time from NVS.
 *
 * Does NOT block — call time_sync_wait_for_sync() to wait for first sync.
 *
 * Must be called after WiFi is connected.
 *
 * @param ntp_server_ip NTP server IPv4 address string (same host as MQTT broker)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t time_sync_init(const char *ntp_server_ip);

/**
 * Get current time quality state
 *
 * @return Current time quality (NONE, ESTIMATED, or SYNCED)
 */
time_quality_t time_sync_get_quality(void);

/**
 * Check if time is SNTP synchronized
 *
 * Convenience wrapper for time_sync_get_quality() == TIME_QUALITY_SYNCED.
 *
 * @return true if wall-clock time is available and authoritative
 */
bool time_sync_is_synced(void);

/**
 * Block until SNTP sync completes or timeout expires
 *
 * Used during boot sequence to wait for the first successful SNTP
 * synchronization before beginning RFID scanning. If the timeout
 * expires before sync, the device continues with NONE or ESTIMATED
 * time quality depending on NVS state.
 *
 * @param timeout_ms Maximum milliseconds to wait (e.g., 5000)
 */
void time_sync_wait_for_sync(uint32_t timeout_ms);

/**
 * Get current wall-clock time as Unix milliseconds
 *
 * Returns the current time in Unix milliseconds when SNTP-synced,
 * or 0 if time quality is not TIME_QUALITY_SYNCED.
 *
 * @return Unix time in milliseconds, or 0 if not synced
 */
int64_t time_sync_get_timestamp_ms(void);

/**
 * Persist current time to NVS before controlled shutdown
 *
 * Saves the current Unix time and uptime snapshot to NVS so that
 * the next boot can establish a TIME_QUALITY_ESTIMATED lower bound.
 *
 * Call from the graceful disconnect / battery shutdown path before
 * esp_restart() or esp_deep_sleep_start().
 */
void time_sync_notify_shutdown(void);

#endif // TIME_SYNC_H
