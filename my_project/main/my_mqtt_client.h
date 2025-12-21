/**
 * MQTT Client - ESP32 MQTT Manager for Attendance System
 *
 * Provides MQTT connectivity for publishing tag detection events
 * and subscribing to configuration/control topics.
 *
 * Features:
 * - QoS 2 (Exactly Once) delivery for critical attendance events
 * - Automatic reconnection with exponential backoff
 * - Hierarchical topic structure
 * - Event-driven architecture
 * - Last Will & Testament for device status
 *
 * DATASHEET REFERENCES:
 * - ESP-IDF v5.5.1 MQTT Documentation
 * - MQTT 3.1.1 Specification
 */

#ifndef MQTT_CLIENT_H
#define MQTT_CLIENT_H

#include "esp_err.h"
#include "uart_reader.h"
#include <stdbool.h>
#include <stdint.h>
#include <mqtt_client.h>

// ============================================================================
// CONFIGURATION
// ============================================================================

/**
 * MQTT Broker Configuration
 *
 * For testing, use local Mosquitto broker:
 *   mosquitto -p 1883
 *
 * For production, configure via menuconfig or change these defaults:
 */
#define MQTT_BROKER_URI         "mqtt://10.0.0.222:1883"
#define MQTT_BROKER_PORT        1883
#define MQTT_CLIENT_ID          "ESP32_ATTENDANCE_01"

/**
 * MQTT Topic Structure
 *
 * attendance/
 * ├── tags/detected              - Tag detection events (QoS 2)
 * ├── device/{device_id}/status  - Device online/offline (Last Will)
 * ├── config/{device_id}/+       - Configuration updates (subscribe)
 * └── health/{device_id}/+       - Health metrics (QoS 0)
 */
#define MQTT_TOPIC_TAG_DETECTED     "attendance/tags/detected"
#define MQTT_TOPIC_DEVICE_STATUS    "attendance/device/ESP32_ATTENDANCE_01/status"
#define MQTT_TOPIC_CONFIG_BASE      "attendance/config/ESP32_ATTENDANCE_01/"
#define MQTT_TOPIC_HEALTH_BASE      "attendance/health/ESP32_ATTENDANCE_01/"

/**
 * Quality of Service Levels
 *
 * Per thesis requirement: QoS 2 for attendance events (guaranteed delivery)
 */
#define MQTT_QOS_TAG_EVENTS         2    // QoS 2: Exactly Once
#define MQTT_QOS_HEALTH_METRICS     0    // QoS 0: At Most Once
#define MQTT_QOS_CONFIG_COMMANDS    1    // QoS 1: At Least Once

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/**
 * MQTT Connection State
 */
typedef enum {
    MQTT_STATE_DISCONNECTED = 0,
    MQTT_STATE_CONNECTING,
    MQTT_STATE_CONNECTED,
    MQTT_STATE_ERROR
} mqtt_connection_state_t;

/**
 * MQTT Statistics
 */
typedef struct {
    uint32_t messages_published;        // Total messages sent
    uint32_t messages_received;         // Total messages received
    uint32_t publish_errors;            // Failed publish attempts
    uint32_t connection_count;          // Times connected
    uint32_t disconnection_count;       // Times disconnected
    mqtt_connection_state_t state;      // Current connection state
} mqtt_stats_t;

/**
 * MQTT Configuration Message Callback
 *
 * Called when a configuration message is received from the broker.
 *
 * @param topic Topic name (null-terminated)
 * @param payload Message payload (null-terminated)
 */
typedef void (*mqtt_config_callback_t)(const char* topic, const char* payload);

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Initialize MQTT client
 *
 * Performs the following initialization:
 * 1. Create MQTT client configuration
 * 2. Initialize client handle
 * 3. Register event handlers
 * 4. Configure Last Will & Testament
 * 5. Start MQTT client
 *
 * IMPORTANT: Call wifi_manager_init() and ensure WiFi is connected
 * before calling this function. MQTT requires active network connection.
 *
 * @return ESP_OK on success, error code otherwise
 *
 * Example:
 * ```c
 * // Initialize WiFi first
 * wifi_manager_init();
 * wifi_manager_wait_for_connection(30000);
 *
 * // Then initialize MQTT
 * mqtt_client_init();
 * mqtt_client_wait_for_connection(10000);
 * ```
 */
esp_err_t mqtt_client_init(void);

/**
 * Wait for MQTT connection to complete
 *
 * Blocks until either:
 * - MQTT successfully connects to broker (returns ESP_OK)
 * - Timeout expires (returns ESP_ERR_TIMEOUT)
 *
 * @param timeout_ms Maximum time to wait in milliseconds (0 = wait forever)
 * @return ESP_OK if connected, ESP_ERR_TIMEOUT on timeout
 */
esp_err_t mqtt_client_wait_for_connection(uint32_t timeout_ms);

/**
 * Check if MQTT client is connected
 *
 * @return true if connected to broker, false otherwise
 */
bool mqtt_client_is_connected(void);

/**
 * Publish tag detection event
 *
 * Publishes an RFID tag detection event to the broker with QoS 2
 * (exactly once delivery) as required by the thesis specification.
 *
 * Message format (JSON):
 * ```json
 * {
 *   "tag_id": "E12345678901",
 *   "timestamp": 1702000000,
 *   "rssi_dbm": -65,
 *   "antenna_id": 1,
 *   "frequency": 915,
 *   "device_id": "ESP32_ATTENDANCE_01"
 * }
 * ```
 *
 * @param event Tag detection event from RFID reader
 * @return ESP_OK on success, error code otherwise
 *
 * Note: This function formats the event into JSON and publishes it.
 * The publish is asynchronous - MQTT_EVENT_PUBLISHED confirms delivery.
 */
esp_err_t mqtt_client_publish_tag_event(const rfid_tag_event_t* event);

/**
 * Publish health metrics
 *
 * Publishes system health information (memory, WiFi RSSI, uptime) to
 * health topics with QoS 0 (fire and forget).
 *
 * Topics:
 * - attendance/health/{device_id}/memory
 * - attendance/health/{device_id}/wifi_rssi
 * - attendance/health/{device_id}/uptime
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t mqtt_client_publish_health_metrics(void);

/**
 * Subscribe to configuration topics
 *
 * Subscribes to configuration command topics using wildcard:
 * - attendance/config/{device_id}/+
 *
 * When messages arrive, the registered callback will be invoked.
 *
 * @param callback Function to call when config message received
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t mqtt_client_subscribe_config(mqtt_config_callback_t callback);

/**
 * Disconnect from MQTT broker
 *
 * Gracefully disconnects from broker and publishes Last Will message.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t mqtt_client_disconnect(void);

/**
 * Destroy MQTT client and cleanup resources
 *
 * Stops client, unregisters handlers, and frees memory.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t mqtt_client_destroy(void);

/**
 * Get MQTT statistics
 *
 * @param stats Pointer to structure to receive statistics
 * @return ESP_OK on success, ESP_ERR_INVALID_ARG if stats is NULL
 */
esp_err_t mqtt_client_get_stats(mqtt_stats_t* stats);

/**
 * Clear statistics counters
 */
void mqtt_client_clear_stats(void);

/**
 * Get current connection state
 *
 * @return Current MQTT connection state
 */
mqtt_connection_state_t mqtt_client_get_state(void);

#endif // MQTT_CLIENT_H
