# ESP32 MQTT Implementation Guide

## Overview

MQTT (Message Queuing Telemetry Transport) is a lightweight publish/subscribe protocol perfect for IoT devices. The ESP-IDF provides the **esp-mqtt** component which is a fully functional MQTT 3.1.1 and MQTT 5.0 client.

---

## What Needs to Be Done

### 1. **Component Setup**
- Add esp-mqtt component to your project
- Configure transport layer (TCP, SSL, WebSocket)
- Enable required features via menuconfig

### 2. **Configuration**
- Define broker URI/host/port
- Set client ID and authentication
- Configure QoS levels
- Set up keep-alive parameters

### 3. **Event Handling**
- Register event handler for MQTT lifecycle events
- Handle connection/disconnection
- Manage message subscriptions
- Handle publish acknowledgments

### 4. **Publishing & Subscribing**
- Publish tag detection events to topics
- Subscribe to control topics from server
- Handle incoming messages

### 5. **Testing**
- Test with local MQTT broker (Mosquitto)
- Verify message delivery
- Test reconnection scenarios

---

## MQTT Fundamentals

### What is MQTT?

**Publish/Subscribe Model**:
```
ESP32 (Publisher) → MQTT Broker ← Server (Subscriber)
                         ↓
                    (Stores & Forwards)
```

Your system:
- **Publisher**: ESP32 publishes RFID tag detections
- **Subscriber**: Your server/Navigo3 integration subscribes to receive events
- **Broker**: Intermediary that manages connections and message routing

### Three QoS Levels (Quality of Service)

From ESP-IDF documentation:

1. **QoS 0 - At Most Once** (Fire & Forget)
   - No acknowledgment from broker
   - Lowest overhead
   - Risk: Message lost if connection drops
   - Use: Non-critical sensor readings

2. **QoS 1 - At Least Once**
   - Broker acknowledges receipt
   - Message guaranteed to arrive at least once
   - May duplicate in rare cases
   - Use: Most IoT applications, moderate overhead

3. **QoS 2 - Exactly Once**
   - Four-way handshake with broker
   - Guaranteed unique delivery (no duplicates)
   - Highest overhead
   - Use: Critical events (your attendance system needs this!)

**Your System Requirement**: Your thesis document specifies **QoS 2 for guaranteed delivery** of attendance events.

---

## Component Installation & Configuration

### Step 1: Add esp-mqtt Component

Run in your project directory:
```bash
idf.py add-dependency espressif/mqtt
```

This adds the mqtt component to your `idf_component_requirements.txt`.

**Alternatively** (manual): Add to your `CMakeLists.txt`:
```cmake
idf_component_depends(mqtt)
```

Reference: ESP-IDF v5.5.1 documentation on ESP-MQTT component setup

### Step 2: Enable Features via menuconfig

```bash
idf.py menuconfig
```

Navigate to: **Component config → ESP-MQTT Configuration**

Key configurations:
- `CONFIG_MQTT_PROTOCOL_311` - MQTT 3.1.1 support (default, sufficient)
- `CONFIG_MQTT_PROTOCOL_5` - MQTT 5.0 support (optional)
- `CONFIG_MQTT_TRANSPORT_TCP` - Plain TCP (port 1883)
- `CONFIG_MQTT_TRANSPORT_SSL` - TLS encryption (port 8883) - optional for testing
- `CONFIG_MQTT_TRANSPORT_WEBSOCKET` - WebSocket support (optional)

For your initial testing, keep it simple:
- ✓ TCP transport enabled
- ✓ MQTT 3.1.1 protocol
- Disable SSL/TLS for now (add later if needed)

Reference: ESP-IDF v5.5.1 ESP-MQTT Configuration section

---

## MQTT Client Architecture

### Required Headers

```c
#include "mqtt_client.h"          // Main MQTT client API
#include "esp_event.h"            // Event handling (already have)
```

### Core Data Types

**Configuration Structure** (`esp_mqtt_client_config_t`):
```c
esp_mqtt_client_config_t mqtt_cfg = {
    .broker.address.uri = "mqtt://your-broker:1883",
    // OR:
    .broker.address.hostname = "your-broker",
    .broker.address.port = 1883,
    .credentials.username = "user",
    .credentials.password = "pass",
    .credentials.client_id = "ESP32_ATTENDANCE_01",
    .session.protocol_ver = MQTT_PROTOCOL_V_3_1_1,
    .session.last_will = {
        .topic = "attendance/device/status",
        .msg = "offline",
        .qos = 2,
        .retain = true,
    },
};
```

**Client Handle**: `esp_mqtt_client_handle_t` - represents an MQTT client instance

### Initialization Sequence

```
1. Create configuration struct
2. Initialize client: esp_mqtt_client_init(&config)
3. Register event handler: esp_mqtt_client_register_event()
4. Start client: esp_mqtt_client_start()
```

Reference: ESP-IDF v5.5.1 ESP-MQTT API Reference

---

## Event System

### MQTT Events (from ESP-IDF documentation)

**Connection Lifecycle**:

1. **MQTT_EVENT_BEFORE_CONNECT**
   - Client initialized
   - About to attempt connection
   - Use: Clear previous state

2. **MQTT_EVENT_CONNECTED**
   - Successfully connected to broker
   - Ready to publish/subscribe
   - Use: Subscribe to control topics here

3. **MQTT_EVENT_DISCONNECTED**
   - Connection lost (intentional or unexpected)
   - Contains disconnect reason
   - Use: Log error, handle reconnection

**Data Events**:

4. **MQTT_EVENT_SUBSCRIBED**
   - Broker confirmed subscription
   - Use: Log subscription success

5. **MQTT_EVENT_UNSUBSCRIBED**
   - Broker confirmed unsubscription

6. **MQTT_EVENT_PUBLISHED**
   - Broker acknowledged publish
   - Use: For QoS > 0, confirms delivery

7. **MQTT_EVENT_DATA**
   - New message arrived on subscribed topic
   - Contains: topic, payload, topic_len, data_len
   - Use: Process incoming commands

**Error Handling**:

8. **MQTT_EVENT_ERROR**
   - Client encountered error
   - Contains error details in `event->error_handle`
   - Reference: `esp_mqtt_error_type_t` enum

### Event Handler Pattern

```c
static void mqtt_event_handler(void *handler_args, 
                               esp_event_base_t base, 
                               int32_t event_id, 
                               void *event_data)
{
    esp_mqtt_event_handle_t event = event_data;
    
    switch(event->event_id) {
        case MQTT_EVENT_CONNECTED:
            // Subscribe to control topics
            esp_mqtt_client_subscribe(event->client, "attendance/config", 2);
            break;
            
        case MQTT_EVENT_DATA:
            // Handle incoming message
            process_mqtt_message(event->topic, event->data, event->data_len);
            break;
            
        case MQTT_EVENT_ERROR:
            // Log and handle error
            ESP_LOGE(TAG, "MQTT Error: %d", event->error_handle->error_type);
            break;
            
        default:
            break;
    }
}
```

Important from ESP-IDF docs: **Do NOT perform blocking operations in event handler** - it runs in the MQTT task context.

---

## Publishing Data

### Publishing Tag Detection

```c
esp_mqtt_client_publish(client, 
                        "attendance/tags/detected",    // topic
                        json_payload,                   // message
                        strlen(json_payload),           // length
                        2,                              // QoS 2
                        0);                             // retain flag (0 = don't retain)
```

**Message Format** (recommended):
```json
{
  "tag_id": "E12345678901",
  "timestamp": 1702000000,
  "direction": "entry",
  "signal_strength": -85,
  "device_id": "ESP32_GATE_01"
}
```

### Key Considerations

- **Topic Structure**: Use hierarchical topics: `attendance/location/event_type`
- **Payload Format**: JSON is standard for IoT (use cJSON library if needed)
- **QoS Level**: Your thesis requires QoS 2 for guaranteed delivery
- **Retain Flag**: Set to 0 (don't retain) for event streams; set to 1 for state (like "offline" in last will)

Reference: ESP-IDF publish API documentation

---

## Subscribing to Topics

### Subscribe to Control Commands

```c
esp_mqtt_client_subscribe(client, 
                         "attendance/config/+",      // Wildcard subscription
                         1);                         // QoS 1
```

MQTT uses wildcards:
- `+` = Single level (e.g., `attendance/config/led` matches)
- `#` = Multi-level (e.g., `attendance/#` matches all attendance topics)

### Handling Subscribed Messages

```c
case MQTT_EVENT_DATA:
    // event->topic points to topic string
    // event->data points to payload (NOT null-terminated!)
    // event->topic_len, event->data_len contain lengths
    
    char topic[256];
    char data[256];
    
    memcpy(topic, event->topic, event->topic_len);
    topic[event->topic_len] = '\0';
    
    memcpy(data, event->data, event->data_len);
    data[event->data_len] = '\0';
    
    ESP_LOGI(TAG, "Topic: %s, Data: %s", topic, data);
    break;
```

**Important**: Payload is NOT null-terminated! Use event->data_len to safely process it.

---

## Disconnection & Reconnection

### Automatic Reconnection

ESP-MQTT handles reconnection automatically. Configure:
```c
.session.reconnect_timeout_ms = 4000,    // Wait 4s before retry
.network.refresh_connection_after_ms = 0, // 0 = disabled (don't refresh)
```

### Handling Disconnection Reasons

```c
case MQTT_EVENT_DISCONNECTED:
    switch(event->error_handle->error_type) {
        case MQTT_ERROR_TYPE_TCP_TRANSPORT:
            ESP_LOGI(TAG, "TCP disconnect");
            break;
        case MQTT_ERROR_TYPE_CONNECTION_REFUSED:
            ESP_LOGI(TAG, "Broker refused connection");
            break;
        case MQTT_ERROR_TYPE_UNKNOWN:
            ESP_LOGI(TAG, "Unknown MQTT error");
            break;
        default:
            break;
    }
    break;
```

Reference: `esp_mqtt_error_type_t` enum in ESP-IDF

### Offline Buffering Strategy

For your offline requirement, you'll need:
1. **NVS-based queue** to store messages when offline
2. **Retry logic** that publishes queued messages on reconnection
3. **Idempotent operations** (each message has unique ID to avoid duplicates)

This is beyond basic MQTT - covered later in offline caching phase.

---

## Testing Your MQTT Setup

### Phase 1: Basic Connectivity Test

**Goal**: Verify ESP32 can connect to broker

1. **Local Broker Setup** (on your laptop):
   ```bash
   # Linux/Mac:
   brew install mosquitto  # or apt-get install mosquitto
   mosquitto -p 1883
   
   # Windows: Download from mosquitto.org
   ```

2. **Configure ESP32**:
   ```c
   .broker.address.uri = "mqtt://192.168.1.100:1883",  // Your laptop IP
   ```

3. **Monitor Broker**:
   ```bash
   mosquitto_sub -h 192.168.1.100 -t "#" -v
   ```

4. **Expected Output**: Connection messages in logs

### Phase 2: Publish/Subscribe Test

1. **Publish from ESP32**:
   - Configure ESP32 to publish dummy event every 5 seconds
   - Monitor on laptop: should see messages arrive

2. **Subscribe on ESP32**:
   - Terminal command: `mosquitto_pub -h 192.168.1.100 -t "attendance/test" -m "hello"`
   - ESP32 should receive and log the message

3. **Verify Event Handler**: Check all MQTT_EVENT_* cases are logged

### Phase 3: QoS Testing

Test each QoS level:
- **QoS 0**: Kill ESP32 mid-transmission (may lose message)
- **QoS 1**: Verify acknowledgment
- **QoS 2**: Verify 4-way handshake (check with `tcpdump` if needed)

### Phase 4: Offline Reconnection

1. Stop mosquitto
2. Try to publish (should queue internally)
3. Restart mosquitto
4. Verify messages eventually deliver after reconnection

---

## Key API Functions (from ESP-IDF v5.5.1)

```c
// Create/manage client
esp_mqtt_client_handle_t esp_mqtt_client_init(const esp_mqtt_client_config_t *config);
esp_err_t esp_mqtt_client_set_uri(esp_mqtt_client_handle_t client, const char *uri);
esp_err_t esp_mqtt_client_start(esp_mqtt_client_handle_t client);
esp_err_t esp_mqtt_client_stop(esp_mqtt_client_handle_t client);

// Publish/Subscribe
int esp_mqtt_client_publish(esp_mqtt_client_handle_t client,
                           const char *topic, const char *data, int len,
                           int qos, int retain);
int esp_mqtt_client_subscribe(esp_mqtt_client_handle_t client,
                             const char *topic, int qos);
int esp_mqtt_client_unsubscribe(esp_mqtt_client_handle_t client,
                               const char *topic);

// Events
esp_err_t esp_mqtt_client_register_event(esp_mqtt_client_handle_t client,
                                        esp_mqtt_event_id_t event_id,
                                        esp_event_handler_t handler,
                                        void *handler_arg);

// Connection control
esp_err_t esp_mqtt_client_disconnect(esp_mqtt_client_handle_t client);
esp_err_t esp_mqtt_client_reconnect(esp_mqtt_client_handle_t client);
```

---

## Configuration Structure Fields

**From ESP-IDF documentation**, key fields of `esp_mqtt_client_config_t`:

```c
struct {
    struct {
        struct {
            const char *uri;           // Full broker URI (mqtt://host:port)
            const char *hostname;      // Broker hostname
            uint16_t port;             // Broker port (default 1883)
        } address;
    } broker;
    
    struct {
        const char *username;
        const char *password;
        const char *client_id;        // Defaults to ESP32_%CHIPID%
    } credentials;
    
    struct {
        uint8_t protocol_ver;         // MQTT_PROTOCOL_V_3_1_1 or MQTT_PROTOCOL_V_5
        uint16_t keep_alive;          // Keep-alive timeout (default 60s)
        struct {
            const char *topic;
            const char *msg;
            int qos;
            int retain;
        } last_will;                  // Last Will & Testament message
    } session;
    
    struct {
        uint32_t refresh_connection_after_ms;
        uint32_t reconnect_timeout_ms;
    } network;
} esp_mqtt_client_config_t;
```

---

## Your Attendance System Integration

### Message Flow

```
RFID Tag Read (UART) → Tag Processing → MQTT Publish
                             ↓
                       Event Queue (FreeRTOS)
                             ↓
                       Attendance Event
                       {"tag_id": "...", "direction": "entry", ...}
                             ↓
                       Topic: attendance/tags/{location}/detected
                             ↓
                       MQTT Broker
                             ↓
                       Navigo3 Integration / REST API
```

### Recommended Topic Structure

```
attendance/
├── tags/
│   └── {location}/
│       └── detected              # Tag detection events
├── device/
│   └── {device_id}/
│       └── status                # Device online/offline (last will)
├── config/
│   └── {device_id}/
│       └── {setting}             # Configuration updates from server
└── health/
    └── {device_id}/
        ├── memory                # System health metrics
        ├── wifi_rssi
        └── uptime
```

---

## References

1. **ESP-IDF v5.5.1 MQTT Documentation**: https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/mqtt.html
2. **esp-mqtt GitHub Repository**: https://github.com/espressif/mqtt
3. **MQTT 3.1.1 Specification**: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html
4. **Official Example**: `esp-idf/examples/protocols/mqtt/tcp` in your ESP-IDF installation
5. **Mosquitto MQTT Broker**: https://mosquitto.org/

---

## Implementation Phases

1. **Phase 1** (This week): Basic connectivity test
   - Set up local Mosquitto broker
   - Configure MQTT client
   - Test connection and simple publish

2. **Phase 2**: Integration with RFID
   - Publish tag detection events
   - Test message delivery
   - Verify event handler

3. **Phase 3**: Server integration
   - Implement Navigo3 REST API bridge
   - Handle incoming configuration commands
   - Test complete workflow

4. **Phase 4**: Reliability
   - Offline message caching (NVS)
   - Reconnection logic
   - Error recovery

---

## Next Steps

Would you like me to write:
1. Complete MQTT client initialization code?
2. Event handler implementation for tag publishing?
3. Integration with your existing WiFi code?
4. Testing/verification scripts?
