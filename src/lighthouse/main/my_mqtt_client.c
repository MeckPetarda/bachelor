/**
 * MQTT Client - Implementation
 *
 * Implements MQTT connectivity for the ESP32 attendance system
 * with QoS 2 guaranteed delivery and automatic reconnection.
 *
 * ARCHITECTURE:
 * - Event-driven design using ESP-IDF event loop
 * - Non-blocking operations in event handlers
 * - Automatic reconnection handled by esp-mqtt library
 * - FreeRTOS event groups for synchronization
 */

#include "my_mqtt_client.h"
#include "battery_monitor.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"
#include "offline_event_logger.h"
#include "rfid_reader.h"
#include "sdkconfig.h"
#include "settings_storage.h"
#include "time_sync.h"
#include <stdio.h>
#include <string.h>
#include <sys/time.h>

// ============================================================================
// CONSTANTS & STATE
// ============================================================================

static const char *TAG = "MQTT_CLIENT";

/**
 * MQTT client handle
 */
static esp_mqtt_client_handle_t s_mqtt_client = NULL;

/**
 * FreeRTOS event group for connection status signaling
 */
static EventGroupHandle_t s_mqtt_event_group = NULL;

/**
 * Event bit indicating successful MQTT connection
 */
#define MQTT_CONNECTED_BIT BIT0

/**
 * Current connection state
 */
static mqtt_connection_state_t s_connection_state = MQTT_STATE_DISCONNECTED;

/**
 * Statistics tracking
 */
static mqtt_stats_t s_stats = {0};

/**
 * Configuration message callback
 */
static mqtt_config_callback_t s_config_callback = NULL;

/**
 * Device MAC address string (formatted as "AA:BB:CC:DD:EE:FF")
 */
static char s_device_mac[MQTT_MAC_STR_LEN] = {0};

/**
 * Topic buffer for building dynamic topics
 * Size: base (22) + MAC (17) + "/" (1) + suffix (max ~20) + null = ~64 bytes, using 128 for safety
 */
static char s_topic_buffer[128] = {0};

/**
 * Offline sync session tracking — set when a replay pass starts, cleared when
 * the server has been notified of completion (sync/complete sent).
 */
static bool s_sync_in_progress = false;

/**
 * Scan batch accumulator state
 */
static rfid_tag_event_t   s_batch_entries[MQTT_SCAN_BATCH_MAX_ENTRIES];
static uint32_t           s_batch_count       = 0;
static SemaphoreHandle_t  s_batch_mutex       = NULL;
static esp_timer_handle_t s_batch_timer       = NULL;
static uint32_t           s_batch_interval_ms = MQTT_SCAN_BATCH_INTERVAL_MS_DEFAULT;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Convert EPC bytes to hex string
 *
 * @param epc EPC byte array
 * @param len EPC length
 * @param output Output buffer (must be at least len*2 + 1 bytes)
 */
static void epc_to_hex_string(const uint8_t *epc, uint8_t len, char *output)
{
    for (int i = 0; i < len; i++)
    {
        sprintf(output + (i * 2), "%02X", epc[i]);
    }
    output[len * 2] = '\0';
}

/**
 * Convert RSSI value to dBm
 *
 * Per R300 protocol: RSSI value 31-98 = -99 to -31 dBm
 *
 * @param rssi Raw RSSI value from reader
 * @return RSSI in dBm
 */
static int rssi_to_dbm(uint8_t rssi)
{
    return rssi - 129;
}

/**
 * Initialize device MAC address string
 *
 * Retrieves the factory-programmed MAC address from eFuse and formats it
 * as a colon-separated uppercase hex string (e.g., "AA:BB:CC:DD:EE:FF").
 *
 * Reference: ESP32 Technical Reference Manual Section 4.4
 */
static void init_device_mac(void)
{
    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    snprintf(s_device_mac, sizeof(s_device_mac), "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3],
             mac[4], mac[5]);
    ESP_LOGI(TAG, "Device MAC: %s", s_device_mac);
}

/**
 * Offline event replay callback
 *
 * Called by the offline logger for each event during replay.
 * Uses the stored rtc_timestamp_s and time_quality to reconstruct
 * the correct timeBasis and timestampMs for the MQTT payload.
 *
 * @param event            RFID tag event to replay
 * @param offline_timestamp Boot-relative ms at original detection
 * @param replay_timestamp  Current boot-relative ms
 * @param rtc_timestamp_s   Unix seconds at detection time (0 if unknown)
 * @param time_quality      Time quality at recording time
 * @return ESP_OK if published successfully
 */
/**
 * Called by replay_task right before the first event publish.
 * Publishes sync/start so the server holds offline scans from the sweeper.
 */
static void on_sync_start(uint32_t count)
{
    if (s_mqtt_client == NULL || !mqtt_client_is_connected())
        return;

    // on_sync_start runs from replay_task — use local buffers, not s_topic_buffer,
    // to avoid racing with health timer and MQTT event handler calls to mqtt_client_get_topic().
    char topic_buf[128];

    if (count == 0)
    {
        if (s_sync_in_progress)
        {
            s_sync_in_progress = false;
            snprintf(topic_buf, sizeof(topic_buf), "%s%s/sync/complete", MQTT_TOPIC_BASE, s_device_mac);
            esp_mqtt_client_publish(s_mqtt_client, topic_buf, "{}", 0, 1, 0);
            ESP_LOGI(TAG, "Published sync/complete (replay-task safety path)");
        }
        return;
    }

    s_sync_in_progress = true;

    char payload[64];
    snprintf(payload, sizeof(payload), "{\"count\":%lu}", (unsigned long)count);

    snprintf(topic_buf, sizeof(topic_buf), "%s%s/sync/start", MQTT_TOPIC_BASE, s_device_mac);
    esp_mqtt_client_publish(s_mqtt_client, topic_buf, payload, 0, 1, 0);
    ESP_LOGI(TAG, "Published sync/start: %lu events", (unsigned long)count);
}

// JSON buffer large enough for OFFLINE_REPLAY_BATCH_SIZE entries (~350 bytes each).
#define OFFLINE_REPLAY_JSON_BUF_SIZE (OFFLINE_REPLAY_BATCH_SIZE * 350 + 32)

static esp_err_t replay_offline_event_batch(const offline_replay_entry_t *entries, uint32_t count,
                                            uint64_t replay_timestamp_ms)
{
    if (s_mqtt_client == NULL || !mqtt_client_is_connected())
        return ESP_FAIL;

    // replay_offline_event_batch runs from replay_task — use a local topic buffer to
    // avoid racing with health timer and MQTT event handler on s_topic_buffer.
    char scans_topic[128];
    snprintf(scans_topic, sizeof(scans_topic), "%s%s/scans", MQTT_TOPIC_BASE, s_device_mac);

    static char json_buf[OFFLINE_REPLAY_JSON_BUF_SIZE];
    int         pos = 0;

    json_buf[pos++] = '[';

    for (uint32_t i = 0; i < count; i++)
    {
        const offline_replay_entry_t *e = &entries[i];

        char epc_hex[65];
        epc_to_hex_string(e->event.epc, e->event.epc_len, epc_hex);
        int rssi_dbm = rssi_to_dbm(e->event.rssi);

        const char *time_basis;
        int64_t     timestamp_ms;

        if (e->time_quality == TIME_QUALITY_SYNCED && e->rtc_timestamp_s > 0)
        {
            timestamp_ms = (int64_t)e->rtc_timestamp_s * 1000;
            time_basis   = "synced";
        }
        else
        {
            timestamp_ms = (int64_t)e->offline_timestamp_ms;
            time_basis   = (e->time_quality == TIME_QUALITY_ESTIMATED) ? "estimated" : "relative";
        }

        int written = snprintf(json_buf + pos, sizeof(json_buf) - pos,
                               "%s{"
                               "\"epc\":\"%s\","
                               "\"timestampMs\":%lld,"
                               "\"rssiDbm\":%d,"
                               "\"antennaId\":%u,"
                               "\"frequency\":%u,"
                               "\"deviceId\":\"%s\","
                               "\"offline\":true,"
                               "\"replayTime\":%llu,"
                               "\"timeBasis\":\"%s\","
                               "\"seqNo\":%lu"
                               "}",
                               i > 0 ? "," : "",
                               epc_hex, timestamp_ms, rssi_dbm, e->event.antenna_id, e->event.frequency,
                               s_device_mac, replay_timestamp_ms, time_basis, (unsigned long)e->seq_no);

        if (written < 0 || pos + written >= (int)sizeof(json_buf) - 2)
        {
            ESP_LOGW(TAG, "Offline replay batch JSON buffer full at entry %lu — dropping batch", i);
            s_stats.publish_errors++;
            return ESP_FAIL;
        }
        pos += written;
    }

    json_buf[pos++] = ']';
    json_buf[pos]   = '\0';

    // enqueue (non-blocking): all batch entries go out in a single MQTT message,
    // reducing NVS saves from N to ⌈N/BATCH_SIZE⌉ (NVS writes are the dominant
    // replay latency on ESP32, typically 100–2000 ms each).
    int msg_id = esp_mqtt_client_enqueue(s_mqtt_client, scans_topic, json_buf, pos,
                                         MQTT_QOS_TAG_EVENTS_LIVE, 0, true);
    if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to enqueue offline replay batch (outbox full or disconnected)");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Enqueued offline replay batch: %lu events, msg_id=%d", (unsigned long)count, msg_id);
    return ESP_OK;
}

// ============================================================================
// BATCH ACCUMULATOR
// ============================================================================

#define SCAN_BATCH_JSON_BUF_SIZE (MQTT_SCAN_BATCH_MAX_ENTRIES * 200 + 32)

static void flush_scan_batch(void)
{
    static rfid_tag_event_t local_entries[MQTT_SCAN_BATCH_MAX_ENTRIES];
    static char             json_buf[SCAN_BATCH_JSON_BUF_SIZE];

    xSemaphoreTake(s_batch_mutex, portMAX_DELAY);

    if (s_batch_count == 0)
    {
        xSemaphoreGive(s_batch_mutex);
        return;
    }

    uint32_t count = s_batch_count;
    memcpy(local_entries, s_batch_entries, count * sizeof(rfid_tag_event_t));
    s_batch_count = 0;

    xSemaphoreGive(s_batch_mutex);

    // Compute timestamp and time basis once for the batch window
    time_quality_t quality    = time_sync_get_quality();
    const char    *time_basis = "relative";
    int64_t        timestamp_ms;

    if (quality == TIME_QUALITY_SYNCED)
    {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        timestamp_ms = (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
        time_basis   = "synced";
    }
    else
    {
        timestamp_ms = (int64_t)(esp_timer_get_time() / 1000);
        time_basis   = (quality == TIME_QUALITY_ESTIMATED) ? "estimated" : "relative";
    }

    // Build JSON array
    int pos = 0;
    pos += snprintf(json_buf + pos, sizeof(json_buf) - pos, "[");

    uint32_t entries_written = 0;
    for (uint32_t i = 0; i < count; i++)
    {
        char epc_hex[65];
        epc_to_hex_string(local_entries[i].epc, local_entries[i].epc_len, epc_hex);
        int rssi_dbm = rssi_to_dbm(local_entries[i].rssi);

        char entry[200];
        int  entry_len = snprintf(entry, sizeof(entry),
                                  "%s{"
                                   "\"epc\":\"%s\","
                                   "\"timestampMs\":%lld,"
                                   "\"rssiDbm\":%d,"
                                   "\"antennaId\":%u,"
                                   "\"frequency\":%u,"
                                   "\"deviceId\":\"%s\","
                                   "\"offline\":false,"
                                   "\"timeBasis\":\"%s\""
                                   "}",
                                 i > 0 ? "," : "", epc_hex, timestamp_ms, rssi_dbm, local_entries[i].antenna_id,
                                  local_entries[i].frequency, s_device_mac, time_basis);

        // +2: closing "]" and null terminator
        if (pos + entry_len + 2 > (int)sizeof(json_buf))
        {
            ESP_LOGW(TAG, "Scan batch JSON truncated at entry %lu/%lu", i, count);
            break;
        }

        memcpy(json_buf + pos, entry, entry_len);
        pos += entry_len;
        entries_written++;
    }

    pos += snprintf(json_buf + pos, sizeof(json_buf) - pos, "]");

    char scans_topic[128];
    snprintf(scans_topic, sizeof(scans_topic), "%s%s/scans", MQTT_TOPIC_BASE, s_device_mac);

    int msg_id = esp_mqtt_client_enqueue(s_mqtt_client, scans_topic, json_buf, pos, MQTT_QOS_TAG_EVENTS_LIVE, 0, true);

    if (msg_id == -2)
    {
        ESP_LOGW(TAG, "MQTT outbox full - scan batch dropped (%lu entries)", entries_written);
        s_stats.publish_errors++;
    }
    else if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to enqueue scan batch (%lu entries)", entries_written);
        s_stats.publish_errors++;
    }
    else
    {
        ESP_LOGI(TAG, "Published tag event batch: %lu entries (msg_id=%d)", entries_written, msg_id);
    }
}

static void batch_timer_callback(void *arg)
{
    flush_scan_batch();
}

// ============================================================================
// MQTT EVENT HANDLER
// ============================================================================

/**
 * MQTT event handler
 *
 * Handles all MQTT lifecycle events per ESP-IDF documentation.
 * This handler runs in the MQTT task context and must be non-blocking.
 *
 * Key events:
 * - MQTT_EVENT_CONNECTED: Subscribe to control topics
 * - MQTT_EVENT_DISCONNECTED: Log disconnection reason
 * - MQTT_EVENT_DATA: Process incoming configuration messages
 * - MQTT_EVENT_PUBLISHED: Confirm message delivery (QoS > 0)
 * - MQTT_EVENT_ERROR: Handle connection/protocol errors
 */
static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    esp_mqtt_event_handle_t event = (esp_mqtt_event_handle_t)event_data;

    switch ((esp_mqtt_event_id_t)event_id)
    {
    case MQTT_EVENT_BEFORE_CONNECT:
        ESP_LOGI(TAG, "Connecting to MQTT broker...");
        s_connection_state = MQTT_STATE_CONNECTING;
        break;

    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "✓ Connected to MQTT broker");
        s_connection_state = MQTT_STATE_CONNECTED;
        s_stats.connection_count++;
        xEventGroupSetBits(s_mqtt_event_group, MQTT_CONNECTED_BIT);

        // Publish online status to dynamic topic
        {
            const char *status_topic = mqtt_client_get_topic("status");
            esp_mqtt_client_publish(event->client, status_topic, "online",
                                    0,  // Use default length (null-terminated)
                                    1,  // QoS 1
                                    1); // Retain flag

            ESP_LOGI(TAG, "Published online status to %s", status_topic);
        }

        // Re-subscribe to configuration topics if callback is registered
        // This ensures subscriptions are restored after broker restart or
        // reconnection
        if (s_config_callback != NULL)
        {
            char topic[128];
            snprintf(topic, sizeof(topic), "%s%s/config/+", MQTT_TOPIC_BASE, s_device_mac);

            int msg_id = esp_mqtt_client_subscribe(event->client, topic, MQTT_QOS_CONFIG_COMMANDS);
            if (msg_id >= 0)
            {
                ESP_LOGI(TAG, "Re-subscribed to config topics: %s", topic);
            }
            else
            {
                ESP_LOGW(TAG, "Failed to re-subscribe to config topics");
            }
        }

        // Subscribe to server ACK topic for offline replay acknowledgement
        {
            char ack_topic[128];
            snprintf(ack_topic, sizeof(ack_topic), "%s%s/ack", MQTT_TOPIC_BASE, s_device_mac);
            int ack_msg_id = esp_mqtt_client_subscribe(event->client, ack_topic, 1);
            if (ack_msg_id >= 0)
            {
                ESP_LOGI(TAG, "Subscribed to ACK topic: %s", ack_topic);
            }
            else
            {
                ESP_LOGW(TAG, "Failed to subscribe to ACK topic");
            }
        }

        // Register sync-start and replay callbacks (safe to call repeatedly — idempotent)
        offline_logger_set_sync_start_callback(on_sync_start);
        offline_logger_schedule_replay(replay_offline_event_batch, OFFLINE_REPLAY_GRACE_PERIOD);

        // Also try to start immediately for the normal reconnect case where the
        // logger is already initialized with pending events.
        uint32_t pending_events = offline_logger_get_pending_count();
        if (pending_events > 0)
        {
            ESP_LOGI(TAG, "════════════════════════════════════");
            ESP_LOGI(TAG, "  Network Restored!");
            ESP_LOGI(TAG, "  Found %lu offline events to replay", pending_events);
            ESP_LOGI(TAG, "════════════════════════════════════");

            esp_err_t replay_ret = offline_logger_start_replay(replay_offline_event_batch, OFFLINE_REPLAY_GRACE_PERIOD);

            if (replay_ret == ESP_OK)
            {
                ESP_LOGI(TAG, "Offline event replay initiated");
            }
            else
            {
                ESP_LOGW(TAG, "Failed to start offline event replay: %s", esp_err_to_name(replay_ret));
            }
        }
        break;

    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "Disconnected from MQTT broker");
        s_connection_state = MQTT_STATE_DISCONNECTED;
        s_stats.disconnection_count++;
        xEventGroupClearBits(s_mqtt_event_group, MQTT_CONNECTED_BIT);
        // Sync session aborted — will restart with sync/start on next reconnect
        s_sync_in_progress = false;
        // Stop any in-progress replay so that the next MQTT_EVENT_CONNECTED can start a fresh one
        offline_logger_stop_replay();
        break;

    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "Subscription acknowledged (msg_id=%d)", event->msg_id);
        break;

    case MQTT_EVENT_UNSUBSCRIBED:
        ESP_LOGI(TAG, "Unsubscribed (msg_id=%d)", event->msg_id);
        break;

    case MQTT_EVENT_PUBLISHED:
        ESP_LOGD(TAG, "Message published (msg_id=%d)", event->msg_id);
        s_stats.messages_published++;
        break;

    case MQTT_EVENT_DATA:
        // Incoming message on subscribed topic
        ESP_LOGI(TAG, "Received message on topic: %.*s", event->topic_len, event->topic);
        ESP_LOGI(TAG, "Payload: %.*s", event->data_len, event->data);

        s_stats.messages_received++;

        {
            // Check if this is a server ACK for offline replay
            char ack_topic[128];
            snprintf(ack_topic, sizeof(ack_topic), "%s%s/ack", MQTT_TOPIC_BASE, s_device_mac);
            bool is_ack = (event->topic_len == (int)strlen(ack_topic) &&
                           strncmp(event->topic, ack_topic, event->topic_len) == 0);

            if (is_ack)
            {
                // Parse ackedSeqNo from JSON payload (minimal: find key and read value)
                char data_buf[128];
                int  data_len = event->data_len < (int)(sizeof(data_buf) - 1) ? event->data_len : (int)(sizeof(data_buf) - 1);
                memcpy(data_buf, event->data, data_len);
                data_buf[data_len] = '\0';

                uint32_t acked_seq_no = 0;
                char    *ptr          = strstr(data_buf, "\"ackedSeqNo\":");
                if (ptr)
                {
                    ptr += strlen("\"ackedSeqNo\":");
                    sscanf(ptr, "%lu", (unsigned long *)&acked_seq_no);
                }

                ESP_LOGI(TAG, "Received ACK for seqNo %lu", (unsigned long)acked_seq_no);
                offline_logger_ack_received(acked_seq_no);

                // sync/complete is triggered from process_ack() in logging_task,
                // which is the only place rtc_read_index is actually updated.
                // Checking replay_batch_complete() here would always see stale state
                // because ack_received() is non-blocking (posts to queue, no update yet).
            }
            else if (s_config_callback != NULL)
            {
                // Forward to config callback
                char topic[256];
                char payload[512];

                int topic_len = event->topic_len < 255 ? event->topic_len : 255;
                int data_len  = event->data_len < 511 ? event->data_len : 511;

                memcpy(topic, event->topic, topic_len);
                topic[topic_len] = '\0';

                memcpy(payload, event->data, data_len);
                payload[data_len] = '\0';

                s_config_callback(topic, payload);
            }
        }
        break;

    case MQTT_EVENT_ERROR:
        ESP_LOGE(TAG, "MQTT Error occurred");
        s_connection_state = MQTT_STATE_ERROR;

        if (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT)
        {
            ESP_LOGE(TAG, "TCP transport error");
        }
        else if (event->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED)
        {
            ESP_LOGE(TAG, "Connection refused by broker");
        }
        break;

    default:
        ESP_LOGD(TAG, "Unhandled MQTT event: %d", event_id);
        break;
    }
}

// ============================================================================
// PUBLIC API IMPLEMENTATION
// ============================================================================

esp_err_t mqtt_client_init(void)
{
    ESP_LOGI(TAG, "Initializing MQTT client...");

    // ========================================================================
    // STEP 1: Initialize Device MAC Address
    // ========================================================================

    init_device_mac();
    ESP_LOGI(TAG, "  ✓ Device MAC initialized: %s", s_device_mac);

    // ========================================================================
    // STEP 2: Create Event Group
    // ========================================================================

    s_mqtt_event_group = xEventGroupCreate();
    if (s_mqtt_event_group == NULL)
    {
        ESP_LOGE(TAG, "Failed to create event group");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "  ✓ Event group created");

    // ========================================================================
    // STEP 3: Load MQTT Configuration from NVS
    // ========================================================================

    // Initialize MQTT settings storage
    settings_storage_error_t storage_err = settings_storage_init();
    if (storage_err != SETTINGS_STORAGE_OK)
    {
        ESP_LOGW(TAG, "Failed to init MQTT settings storage: %s", settings_storage_error_to_string(storage_err));
        ESP_LOGW(TAG, "Using default broker configuration");
    }

    // Load broker configuration
    mqtt_broker_config_t broker_config;
    storage_err = mqtt_settings_load(&broker_config);
    if (storage_err != SETTINGS_STORAGE_OK)
    {
        ESP_LOGW(TAG, "Failed to load MQTT settings: %s", settings_storage_error_to_string(storage_err));
        // Defaults are already populated by mqtt_settings_load
    }

    // Build broker URI
    static char broker_uri[MQTT_BROKER_URI_MAX_LEN];
    snprintf(broker_uri, sizeof(broker_uri), "mqtt://%s:%u", broker_config.broker_ip, broker_config.broker_port);

    ESP_LOGI(TAG, "  ✓ Loaded broker config: %s", broker_uri);

    // ========================================================================
    // STEP 4: Configure MQTT Client
    // ========================================================================

    // Build status topic for LWT (must persist - use separate buffer)
    static char lwt_topic[128];
    snprintf(lwt_topic, sizeof(lwt_topic), "%s%s/status", MQTT_TOPIC_BASE, s_device_mac);

    esp_mqtt_client_config_t mqtt_cfg = {

        // Broker configuration (from NVS)
        .broker.address.uri = broker_uri,

        // Client credentials - use MAC address as client ID
        .credentials.client_id               = s_device_mac,
        .credentials.username                = NULL, // No authentication for testing
        .credentials.authentication.password = NULL,

        // Session configuration
        .session.protocol_ver = MQTT_PROTOCOL_V_3_1_1,
        .session.keepalive    = 15, // Keep-alive interval (seconds)

        // Last Will & Testament - published when device disconnects unexpectedly
        .session.last_will =
            {
                .topic   = lwt_topic,
                .msg     = "offline",
                .msg_len = 0, // Use default (null-terminated)
                .qos     = 1, // QoS 1 for status
                .retain  = 1, // Retain offline status
            },

        // Network configuration
        .network.reconnect_timeout_ms        = 4000, // Wait 4s before retry
        .network.refresh_connection_after_ms = 0,    // 0 = disabled
        .network.timeout_ms                  = 500   // MQTT task poll timeout; lower = outbox drained faster

    };

    ESP_LOGI(TAG, "  ✓ MQTT configuration created");
    ESP_LOGI(TAG, "    Broker: %s", broker_uri);
    ESP_LOGI(TAG, "    Client ID: %s", s_device_mac);
    ESP_LOGI(TAG, "    LWT Topic: %s", lwt_topic);

    // ========================================================================
    // STEP 5: Initialize Client
    // ========================================================================

    s_mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    if (s_mqtt_client == NULL)
    {
        ESP_LOGE(TAG, "Failed to initialize MQTT client");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "  ✓ MQTT client initialized");

    // ========================================================================
    // STEP 6: Register Event Handler
    // ========================================================================

    esp_err_t ret = esp_mqtt_client_register_event(s_mqtt_client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to register event handler: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ Event handler registered");

    // ========================================================================
    // STEP 7: Start MQTT Client
    // ========================================================================

    ret = esp_mqtt_client_start(s_mqtt_client);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start MQTT client: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ MQTT client started");

    // Initialize statistics
    memset(&s_stats, 0, sizeof(s_stats));
    s_stats.state = MQTT_STATE_CONNECTING;

    // ========================================================================
    // STEP 8: Initialize Scan Batch Timer
    // ========================================================================

    settings_storage_error_t batch_err = scan_batch_settings_load(&s_batch_interval_ms);
    if (batch_err != SETTINGS_STORAGE_OK)
    {
        ESP_LOGW(TAG, "Failed to load scan batch interval, using default %d ms", MQTT_SCAN_BATCH_INTERVAL_MS_DEFAULT);
        s_batch_interval_ms = MQTT_SCAN_BATCH_INTERVAL_MS_DEFAULT;
    }
    ESP_LOGI(TAG, "Scan batch interval: %lu ms", s_batch_interval_ms);

    s_batch_mutex = xSemaphoreCreateMutex();
    if (s_batch_mutex == NULL)
    {
        ESP_LOGE(TAG, "Failed to create batch mutex");
        return ESP_FAIL;
    }

    esp_timer_create_args_t timer_args = {
        .callback = batch_timer_callback,
        .arg      = NULL,
        .name     = "scan_batch",
    };
    ret = esp_timer_create(&timer_args, &s_batch_timer);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to create scan batch timer: %s", esp_err_to_name(ret));
        return ESP_FAIL;
    }

    ret = esp_timer_start_periodic(s_batch_timer, (uint64_t)s_batch_interval_ms * 1000);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start scan batch timer: %s", esp_err_to_name(ret));
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "MQTT client initialized successfully");
    ESP_LOGI(TAG, "Waiting for connection to broker...");

    return ESP_OK;
}

esp_err_t mqtt_client_wait_for_connection(uint32_t timeout_ms)
{
    if (s_mqtt_event_group == NULL)
    {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    TickType_t timeout_ticks = (timeout_ms == 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms);

    EventBits_t bits = xEventGroupWaitBits(s_mqtt_event_group, MQTT_CONNECTED_BIT,
                                           pdFALSE, // Don't clear on exit
                                           pdFALSE, // Wait for bit
                                           timeout_ticks);

    if (bits & MQTT_CONNECTED_BIT)
    {
        ESP_LOGI(TAG, "✓ MQTT connection established");
        return ESP_OK;
    }
    else
    {
        ESP_LOGW(TAG, "✗ MQTT connection timeout");
        return ESP_ERR_TIMEOUT;
    }
}

bool mqtt_client_is_connected(void)
{
    return s_connection_state == MQTT_STATE_CONNECTED;
}

esp_err_t mqtt_client_publish_tag_event(const rfid_tag_event_t *event, bool offline)
{
    if (s_mqtt_client == NULL)
    {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (event == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    // Check if connected before attempting to publish
    if (!mqtt_client_is_connected())
    {
        ESP_LOGW(TAG, "Cannot publish tag event - not connected to broker");
        return ESP_FAIL;
    }

    if (!offline)
    {
        // ====================================================================
        // Live path: accumulate into batch buffer
        // ====================================================================
        xSemaphoreTake(s_batch_mutex, portMAX_DELAY);

        if (s_batch_count == MQTT_SCAN_BATCH_MAX_ENTRIES)
        {
            // Buffer full — flush immediately before adding the new event
            xSemaphoreGive(s_batch_mutex);
            flush_scan_batch();
            xSemaphoreTake(s_batch_mutex, portMAX_DELAY);
        }

        s_batch_entries[s_batch_count] = *event;
        s_batch_count++;

        xSemaphoreGive(s_batch_mutex);
        return ESP_OK;
    }

    // ========================================================================
    // Offline (replay) path: publish single-element array at QoS 2
    // ========================================================================

    char epc_hex[65];
    epc_to_hex_string(event->epc, event->epc_len, epc_hex);
    int rssi_dbm = rssi_to_dbm(event->rssi);

    time_quality_t quality    = time_sync_get_quality();
    const char    *time_basis = "relative";
    int64_t        timestamp_ms;

    if (quality == TIME_QUALITY_SYNCED)
    {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        timestamp_ms = (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
        time_basis   = "synced";
    }
    else
    {
        timestamp_ms = (int64_t)(esp_timer_get_time() / 1000);
        time_basis   = (quality == TIME_QUALITY_ESTIMATED) ? "estimated" : "relative";
    }

    uint64_t replay_time = (uint64_t)(esp_timer_get_time() / 1000);
    char     payload[512];
    int      len = snprintf(payload, sizeof(payload),
                            "[{"
                                 "\"epc\":\"%s\","
                                 "\"timestampMs\":%lld,"
                                 "\"rssiDbm\":%d,"
                                 "\"antennaId\":%u,"
                                 "\"frequency\":%u,"
                                 "\"deviceId\":\"%s\","
                                 "\"offline\":true,"
                                 "\"replayTime\":%llu,"
                                 "\"timeBasis\":\"%s\""
                                 "}]",
                            epc_hex, timestamp_ms, rssi_dbm, event->antenna_id, event->frequency, s_device_mac, replay_time,
                            time_basis);

    if (len >= (int)sizeof(payload))
    {
        ESP_LOGW(TAG, "Offline replay payload truncated");
    }

    char scans_topic[128];
    snprintf(scans_topic, sizeof(scans_topic), "%s%s/scans", MQTT_TOPIC_BASE, s_device_mac);

    int msg_id = esp_mqtt_client_publish(s_mqtt_client, scans_topic, payload, 0, MQTT_QOS_TAG_EVENTS, 0);
    if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to publish offline replay event");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Published offline replay event: %s timeBasis=%s ts=%lld (msg_id=%d)", epc_hex, time_basis,
             timestamp_ms, msg_id);
    return ESP_OK;
}

esp_err_t mqtt_client_publish_health_metrics(void)
{
    if (s_mqtt_client == NULL)
    {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (!mqtt_client_is_connected())
    {
        ESP_LOGW(TAG, "Cannot publish health metrics - not connected");
        return ESP_FAIL;
    }

    // ========================================================================
    // Gather System Health Metrics
    // ========================================================================

    uint32_t free_heap     = esp_get_free_heap_size();
    uint32_t min_free_heap = esp_get_minimum_free_heap_size();
    uint32_t uptime_sec    = xTaskGetTickCount() * portTICK_PERIOD_MS / 1000;

    // Get WiFi RSSI
    int8_t           wifi_rssi = 0;
    wifi_ap_record_t ap_info;
    if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK)
    {
        wifi_rssi = ap_info.rssi;
    }

    // ========================================================================
    // Gather RFID Health Metrics
    // ========================================================================

    rfid_health_t       rfid_health;
    rfid_reader_state_t rfid_state = rfid_reader_get_state();

    // Convert state enum to string for readability
    const char *state_str;
    switch (rfid_state)
    {
    case RFID_STATE_UNINITIALIZED:
        state_str = "UNINITIALIZED";
        break;
    case RFID_STATE_POWERED_OFF:
        state_str = "POWERED_OFF";
        break;
    case RFID_STATE_STARTUP_PENDING:
        state_str = "STARTUP_PENDING";
        break;
    case RFID_STATE_RESPONSIVE:
        state_str = "RESPONSIVE";
        break;
    case RFID_STATE_UNRESPONSIVE:
        state_str = "UNRESPONSIVE";
        break;
    default:
        state_str = "UNKNOWN";
        break;
    }

    // Get RFID health data (use defaults if unavailable)
    bool rfid_is_responsive      = false;
    bool rfid_power_rail_present = false;
    char rfid_fw_version[8]      = "0.0";
    int  rfid_last_error         = 0;

    if (rfid_reader_get_health(&rfid_health) == ESP_OK)
    {
        rfid_is_responsive      = rfid_health.is_responsive;
        rfid_power_rail_present = rfid_health.power_rail_present;
        snprintf(rfid_fw_version, sizeof(rfid_fw_version), "%u.%u", rfid_health.fw_major, rfid_health.fw_minor);
        rfid_last_error = rfid_health.last_error;
    }

    // ========================================================================
    // Build Consolidated Health JSON Payload
    // ========================================================================

    char payload[600];
    int  len;

#if CONFIG_BATTERY_SENSE_ENABLED
    const battery_status_t *battery      = battery_monitor_get_status();
    const char             *power_source = battery_monitor_get_power_source();
    const char             *health_str;
    switch (battery->health)
    {
    case BATTERY_HEALTH_GOOD:
        health_str = "good";
        break;
    case BATTERY_HEALTH_DEGRADED:
        health_str = "degraded";
        break;
    case BATTERY_HEALTH_CRITICAL:
        health_str = "critical";
        break;
    default:
        health_str = "unknown";
        break;
    }

    len = snprintf(payload, sizeof(payload),
                   "{"
                   "\"uptime_sec\":%lu,"
                   "\"free_heap_bytes\":%lu,"
                   "\"min_free_heap_bytes\":%lu,"
                   "\"wifi_rssi_dbm\":%d,"
                   "\"rfid\":{"
                   "\"state\":\"%s\","
                   "\"is_responsive\":%s,"
                   "\"power_rail_present\":%s,"
                   "\"fw_version\":\"%s\","
                   "\"last_error\":%d"
                   "},"
                   "\"battery\":{"
                   "\"sense_enabled\":true,"
                   "\"voltage_mv\":%u,"
                   "\"percentage\":%u,"
                   "\"is_charging\":false,"
                   "\"power_source\":\"%s\","
                   "\"health_status\":\"%s\","
                   "\"voltage_under_load_mv\":%u"
                   "}"
                   "}",
                   uptime_sec, free_heap, min_free_heap, wifi_rssi, state_str, rfid_is_responsive ? "true" : "false",
                   rfid_power_rail_present ? "true" : "false", rfid_fw_version, rfid_last_error, battery->voltage_mv,
                   battery->percentage, power_source, health_str, battery->voltage_under_load_mv);
#else
    len = snprintf(payload, sizeof(payload),
                   "{"
                   "\"uptime_sec\":%lu,"
                   "\"free_heap_bytes\":%lu,"
                   "\"min_free_heap_bytes\":%lu,"
                   "\"wifi_rssi_dbm\":%d,"
                   "\"rfid\":{"
                   "\"state\":\"%s\","
                   "\"is_responsive\":%s,"
                   "\"power_rail_present\":%s,"
                   "\"fw_version\":\"%s\","
                   "\"last_error\":%d"
                   "},"
                   "\"battery\":{\"sense_enabled\":false}"
                   "}",
                   uptime_sec, free_heap, min_free_heap, wifi_rssi, state_str, rfid_is_responsive ? "true" : "false",
                   rfid_power_rail_present ? "true" : "false", rfid_fw_version, rfid_last_error);
#endif

    if (len >= sizeof(payload))
    {
        ESP_LOGW(TAG, "Health payload truncated");
    }

    // ========================================================================
    // Publish to Consolidated Health Topic
    // ========================================================================

    // Use a local buffer — mqtt_client_publish_health_metrics is called from a timer
    // task; sharing s_topic_buffer with replay_task causes silent topic corruption.
    char health_topic[128];
    snprintf(health_topic, sizeof(health_topic), "%s%s/health", MQTT_TOPIC_BASE, s_device_mac);
    int msg_id = esp_mqtt_client_publish(s_mqtt_client, health_topic, payload, 0, MQTT_QOS_HEALTH_METRICS, 0);

    if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to publish health metrics");
        return ESP_FAIL;
    }

    ESP_LOGD(TAG, "Published health metrics to %s", health_topic);

    return ESP_OK;
}

esp_err_t mqtt_client_subscribe_config(mqtt_config_callback_t callback)
{
    if (s_mqtt_client == NULL)
    {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (callback == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    // Store callback for event handler
    s_config_callback = callback;

    // Subscribe to configuration topics with wildcard: attendance/lighthouse/{MAC}/config/+
    char topic[128];
    snprintf(topic, sizeof(topic), "%s%s/config/+", MQTT_TOPIC_BASE, s_device_mac);

    int msg_id = esp_mqtt_client_subscribe(s_mqtt_client, topic, MQTT_QOS_CONFIG_COMMANDS);

    if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to subscribe to config topics");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Subscribed to config topics: %s", topic);

    return ESP_OK;
}

esp_err_t mqtt_client_disconnect(void)
{
    if (s_mqtt_client == NULL)
    {
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Disconnecting from MQTT broker...");

    // Publish offline status before disconnecting (graceful disconnect)
    const char *status_topic = mqtt_client_get_topic("status");
    esp_mqtt_client_publish(s_mqtt_client, status_topic, "offline", 0,
                            1,  // QoS 1
                            1); // Retain

    ESP_LOGI(TAG, "Published offline status to %s", status_topic);

    return esp_mqtt_client_disconnect(s_mqtt_client);
}

esp_err_t mqtt_client_destroy(void)
{
    if (s_mqtt_client == NULL)
    {
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Destroying MQTT client...");

    esp_err_t ret = esp_mqtt_client_stop(s_mqtt_client);
    if (ret != ESP_OK)
    {
        ESP_LOGW(TAG, "Failed to stop MQTT client: %s", esp_err_to_name(ret));
    }

    ret = esp_mqtt_client_destroy(s_mqtt_client);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to destroy MQTT client: %s", esp_err_to_name(ret));
        return ret;
    }

    s_mqtt_client      = NULL;
    s_connection_state = MQTT_STATE_DISCONNECTED;

    if (s_mqtt_event_group != NULL)
    {
        vEventGroupDelete(s_mqtt_event_group);
        s_mqtt_event_group = NULL;
    }

    ESP_LOGI(TAG, "MQTT client destroyed");

    return ESP_OK;
}

esp_err_t mqtt_client_get_stats(mqtt_stats_t *stats)
{
    if (stats == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(stats, &s_stats, sizeof(mqtt_stats_t));
    stats->state = s_connection_state;

    return ESP_OK;
}

void mqtt_client_clear_stats(void)
{
    memset(&s_stats, 0, sizeof(mqtt_stats_t));
}

mqtt_connection_state_t mqtt_client_get_state(void)
{
    return s_connection_state;
}

const char *mqtt_client_get_device_mac(void)
{
    return s_device_mac;
}

const char *mqtt_client_get_topic(const char *suffix)
{
    snprintf(s_topic_buffer, sizeof(s_topic_buffer), "%s%s/%s", MQTT_TOPIC_BASE, s_device_mac, suffix);
    return s_topic_buffer;
}
