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

#include "mqtt_client.h"
#include "mqtt_client.h"  // ESP-IDF MQTT client library
#include "esp_log.h"
#include "esp_event.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include <stdio.h>
#include <string.h>

// ============================================================================
// CONSTANTS & STATE
// ============================================================================

static const char* TAG = "MQTT_CLIENT";

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
static void epc_to_hex_string(const uint8_t* epc, uint8_t len, char* output)
{
    for (int i = 0; i < len; i++) {
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
static void mqtt_event_handler(void* handler_args, esp_event_base_t base,
                                int32_t event_id, void* event_data)
{
    esp_mqtt_event_handle_t event = (esp_mqtt_event_handle_t)event_data;

    switch ((esp_mqtt_event_id_t)event_id) {
        case MQTT_EVENT_BEFORE_CONNECT:
            ESP_LOGI(TAG, "Connecting to MQTT broker...");
            s_connection_state = MQTT_STATE_CONNECTING;
            break;

        case MQTT_EVENT_CONNECTED:
            ESP_LOGI(TAG, "✓ Connected to MQTT broker");
            s_connection_state = MQTT_STATE_CONNECTED;
            s_stats.connection_count++;
            xEventGroupSetBits(s_mqtt_event_group, MQTT_CONNECTED_BIT);

            // Publish online status
            esp_mqtt_client_publish(event->client,
                                   MQTT_TOPIC_DEVICE_STATUS,
                                   "online",
                                   0,  // Use default length (null-terminated)
                                   1,  // QoS 1
                                   1); // Retain flag

            ESP_LOGI(TAG, "Published online status");
            break;

        case MQTT_EVENT_DISCONNECTED:
            ESP_LOGW(TAG, "Disconnected from MQTT broker");
            s_connection_state = MQTT_STATE_DISCONNECTED;
            s_stats.disconnection_count++;
            xEventGroupClearBits(s_mqtt_event_group, MQTT_CONNECTED_BIT);
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
            ESP_LOGI(TAG, "Received message on topic: %.*s",
                     event->topic_len, event->topic);
            ESP_LOGI(TAG, "Payload: %.*s", event->data_len, event->data);

            s_stats.messages_received++;

            // Null-terminate topic and data for callback
            if (s_config_callback != NULL) {
                char topic[256];
                char payload[512];

                // Copy and null-terminate
                int topic_len = event->topic_len < 255 ? event->topic_len : 255;
                int data_len = event->data_len < 511 ? event->data_len : 511;

                memcpy(topic, event->topic, topic_len);
                topic[topic_len] = '\0';

                memcpy(payload, event->data, data_len);
                payload[data_len] = '\0';

                // Invoke callback
                s_config_callback(topic, payload);
            }
            break;

        case MQTT_EVENT_ERROR:
            ESP_LOGE(TAG, "MQTT Error occurred");
            s_connection_state = MQTT_STATE_ERROR;

            if (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) {
                ESP_LOGE(TAG, "TCP transport error");
            } else if (event->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) {
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
    // STEP 1: Create Event Group
    // ========================================================================

    s_mqtt_event_group = xEventGroupCreate();
    if (s_mqtt_event_group == NULL) {
        ESP_LOGE(TAG, "Failed to create event group");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "  ✓ Event group created");

    // ========================================================================
    // STEP 2: Configure MQTT Client
    // ========================================================================

    esp_mqtt_client_config_t mqtt_cfg = {
        // Broker configuration
        .broker.address.uri = MQTT_BROKER_URI,

        // Client credentials
        .credentials.client_id = MQTT_CLIENT_ID,
        .credentials.username = NULL,  // No authentication for testing
        .credentials.password = NULL,

        // Session configuration
        .session.protocol_ver = MQTT_PROTOCOL_V_3_1_1,
        .session.keepalive = 60,  // Keep-alive interval (seconds)

        // Last Will & Testament - published when device disconnects unexpectedly
        .session.last_will = {
            .topic = MQTT_TOPIC_DEVICE_STATUS,
            .msg = "offline",
            .msg_len = 0,  // Use default (null-terminated)
            .qos = 2,      // QoS 2 for critical status
            .retain = 1,   // Retain offline status
        },

        // Network configuration
        .network.reconnect_timeout_ms = 4000,  // Wait 4s before retry
        .network.refresh_connection_after_ms = 0,  // 0 = disabled
    };

    ESP_LOGI(TAG, "  ✓ MQTT configuration created");
    ESP_LOGI(TAG, "    Broker: %s", MQTT_BROKER_URI);
    ESP_LOGI(TAG, "    Client ID: %s", MQTT_CLIENT_ID);

    // ========================================================================
    // STEP 3: Initialize Client
    // ========================================================================

    s_mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    if (s_mqtt_client == NULL) {
        ESP_LOGE(TAG, "Failed to initialize MQTT client");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "  ✓ MQTT client initialized");

    // ========================================================================
    // STEP 4: Register Event Handler
    // ========================================================================

    esp_err_t ret = esp_mqtt_client_register_event(s_mqtt_client,
                                                   ESP_EVENT_ANY_ID,
                                                   mqtt_event_handler,
                                                   NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register event handler: %s",
                 esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ Event handler registered");

    // ========================================================================
    // STEP 5: Start MQTT Client
    // ========================================================================

    ret = esp_mqtt_client_start(s_mqtt_client);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start MQTT client: %s",
                 esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "  ✓ MQTT client started");

    // Initialize statistics
    memset(&s_stats, 0, sizeof(s_stats));
    s_stats.state = MQTT_STATE_CONNECTING;

    ESP_LOGI(TAG, "MQTT client initialized successfully");
    ESP_LOGI(TAG, "Waiting for connection to broker...");

    return ESP_OK;
}

esp_err_t mqtt_client_wait_for_connection(uint32_t timeout_ms)
{
    if (s_mqtt_event_group == NULL) {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    TickType_t timeout_ticks = (timeout_ms == 0) ? portMAX_DELAY :
                               pdMS_TO_TICKS(timeout_ms);

    EventBits_t bits = xEventGroupWaitBits(s_mqtt_event_group,
                                          MQTT_CONNECTED_BIT,
                                          pdFALSE,  // Don't clear on exit
                                          pdFALSE,  // Wait for bit
                                          timeout_ticks);

    if (bits & MQTT_CONNECTED_BIT) {
        ESP_LOGI(TAG, "✓ MQTT connection established");
        return ESP_OK;
    } else {
        ESP_LOGW(TAG, "✗ MQTT connection timeout");
        return ESP_ERR_TIMEOUT;
    }
}

bool mqtt_client_is_connected(void)
{
    return s_connection_state == MQTT_STATE_CONNECTED;
}

esp_err_t mqtt_client_publish_tag_event(const rfid_tag_event_t* event)
{
    if (s_mqtt_client == NULL) {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (event == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    // ========================================================================
    // Format Tag Data as JSON
    // ========================================================================

    // Convert EPC to hex string
    char epc_hex[65];  // Max 32 bytes * 2 + null terminator
    epc_to_hex_string(event->epc, event->epc_len, epc_hex);

    // Convert RSSI to dBm
    int rssi_dbm = rssi_to_dbm(event->rssi);

    // Build JSON payload
    char payload[512];
    int len = snprintf(payload, sizeof(payload),
        "{"
        "\"tag_id\":\"%s\","
        "\"timestamp\":%lu,"
        "\"rssi_dbm\":%d,"
        "\"antenna_id\":%u,"
        "\"frequency\":%u,"
        "\"device_id\":\"%s\""
        "}",
        epc_hex,
        event->timestamp_ms,
        rssi_dbm,
        event->antenna_id,
        event->frequency,
        MQTT_CLIENT_ID
    );

    if (len >= sizeof(payload)) {
        ESP_LOGW(TAG, "Payload truncated");
    }

    // ========================================================================
    // Publish to MQTT Broker with QoS 2
    // ========================================================================

    int msg_id = esp_mqtt_client_publish(s_mqtt_client,
                                        MQTT_TOPIC_TAG_DETECTED,
                                        payload,
                                        0,  // Use default length
                                        MQTT_QOS_TAG_EVENTS,  // QoS 2
                                        0); // Don't retain

    if (msg_id < 0) {
        ESP_LOGE(TAG, "Failed to publish tag event");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Published tag event: %s (msg_id=%d)", epc_hex, msg_id);

    return ESP_OK;
}

esp_err_t mqtt_client_publish_health_metrics(void)
{
    if (s_mqtt_client == NULL) {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (!mqtt_client_is_connected()) {
        ESP_LOGW(TAG, "Cannot publish health metrics - not connected");
        return ESP_FAIL;
    }

    // ========================================================================
    // Publish Memory Information
    // ========================================================================

    uint32_t free_heap = esp_get_free_heap_size();
    char memory_payload[64];
    snprintf(memory_payload, sizeof(memory_payload), "{\"free_heap\":%lu}", free_heap);

    esp_mqtt_client_publish(s_mqtt_client,
                           MQTT_TOPIC_HEALTH_BASE "memory",
                           memory_payload,
                           0,
                           MQTT_QOS_HEALTH_METRICS,
                           0);

    // ========================================================================
    // Publish Uptime
    // ========================================================================

    uint32_t uptime_sec = xTaskGetTickCount() * portTICK_PERIOD_MS / 1000;
    char uptime_payload[64];
    snprintf(uptime_payload, sizeof(uptime_payload), "{\"uptime_sec\":%lu}", uptime_sec);

    esp_mqtt_client_publish(s_mqtt_client,
                           MQTT_TOPIC_HEALTH_BASE "uptime",
                           uptime_payload,
                           0,
                           MQTT_QOS_HEALTH_METRICS,
                           0);

    ESP_LOGD(TAG, "Published health metrics");

    return ESP_OK;
}

esp_err_t mqtt_client_subscribe_config(mqtt_config_callback_t callback)
{
    if (s_mqtt_client == NULL) {
        ESP_LOGE(TAG, "MQTT client not initialized");
        return ESP_FAIL;
    }

    if (callback == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    // Store callback for event handler
    s_config_callback = callback;

    // Subscribe to configuration topics with wildcard
    char topic[128];
    snprintf(topic, sizeof(topic), "%s+", MQTT_TOPIC_CONFIG_BASE);

    int msg_id = esp_mqtt_client_subscribe(s_mqtt_client,
                                          topic,
                                          MQTT_QOS_CONFIG_COMMANDS);

    if (msg_id < 0) {
        ESP_LOGE(TAG, "Failed to subscribe to config topics");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Subscribed to config topics: %s", topic);

    return ESP_OK;
}

esp_err_t mqtt_client_disconnect(void)
{
    if (s_mqtt_client == NULL) {
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Disconnecting from MQTT broker...");

    // Publish offline status before disconnecting
    esp_mqtt_client_publish(s_mqtt_client,
                           MQTT_TOPIC_DEVICE_STATUS,
                           "offline",
                           0,
                           2,  // QoS 2
                           1); // Retain

    return esp_mqtt_client_disconnect(s_mqtt_client);
}

esp_err_t mqtt_client_destroy(void)
{
    if (s_mqtt_client == NULL) {
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Destroying MQTT client...");

    esp_err_t ret = esp_mqtt_client_stop(s_mqtt_client);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to stop MQTT client: %s", esp_err_to_name(ret));
    }

    ret = esp_mqtt_client_destroy(s_mqtt_client);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to destroy MQTT client: %s", esp_err_to_name(ret));
        return ret;
    }

    s_mqtt_client = NULL;
    s_connection_state = MQTT_STATE_DISCONNECTED;

    if (s_mqtt_event_group != NULL) {
        vEventGroupDelete(s_mqtt_event_group);
        s_mqtt_event_group = NULL;
    }

    ESP_LOGI(TAG, "MQTT client destroyed");

    return ESP_OK;
}

esp_err_t mqtt_client_get_stats(mqtt_stats_t* stats)
{
    if (stats == NULL) {
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
