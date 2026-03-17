# Task: Fix MQTT Publish Blocking During Server Unavailability

## Problem Statement

When the Lighthouse server becomes unavailable, the ESP32 continues to believe it is
connected for up to 90 seconds (1.5× the 60s MQTT keepalive). If an IR-triggered RFID scan
occurs during this stale-connected window, the `on_tag_detected()` callback calls
`esp_mqtt_client_publish()` with QoS 2. This call blocks on a dead TCP socket for up to 10
seconds (default network timeout), freezing the UART RX task. Because `on_tag_detected()`
runs synchronously inside the UART RX task (called from `uart_rx_task` in `rfid_reader.c`
after `parse_inventory_response` succeeds), no further RFID polling or tag reads can occur
while the publish is blocked. The device appears completely frozen.

A secondary issue: the callback also calls `vTaskDelay(pdMS_TO_TICKS(50))` for LED
flashing, which is an unnecessary 50ms blocking delay inside the priority-10 UART RX task.

## Root Cause Chain

1. **Keepalive too slow:** `.session.keepalive = 60` → PINGREQ sent every ~30s → dead
   broker undetected for 30–60s.
   *Ref: ESP-IDF MQTT docs — "the client attempts to communicate with the broker at half
   the interval that is actually set."*

2. **Blocking publish API:** `esp_mqtt_client_publish()` performs the TCP write in the
   caller's task context and can block for the network timeout (default 10s).
   *Ref: ESP-IDF MQTT API — "This API might block for several seconds, either due to
   network timeout (10s) or if publishing payloads longer than internal buffer."*

3. **Callback runs in UART RX task:** The `tag_callback` is invoked directly from
   `uart_rx_task` (rfid_reader.c), blocking all RFID I/O for the duration of the callback.

4. **`MQTT_SKIP_PUBLISH_IF_DISCONNECTED` disabled:** The sdkconfig confirms
   `# CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED is not set`, so even the internal
   disconnected state of ESP-MQTT doesn't short-circuit the publish attempt.

## Files to Modify

| File | Fixes |
|------|-------|
| `src/lighthouse/main/my_mqtt_client.c` | Fix 1 (keepalive + timeout), Fix 2 (enqueue) |
| `src/lighthouse/main/lighthouse.c` | Fix 3 (remove vTaskDelay), Fix 4 (cache-first) |
| `src/lighthouse/sdkconfig.defaults` | Fix 5 (MQTT_SKIP_PUBLISH_IF_DISCONNECTED) |

**Do not modify** any other files. `rfid_reader.c`, `rfid_reader.h`, `my_mqtt_client.h`,
and `offline_event_logger.c/h` remain untouched.

---

## Fix 1: Reduce MQTT Keepalive and Network Timeout

**File:** `src/lighthouse/main/my_mqtt_client.c`

**Location:** Inside `mqtt_client_init()`, in the `esp_mqtt_client_config_t mqtt_cfg`
struct initialization.

**Change A — Keepalive:** Find the line:

```c
.session.keepalive    = 60, // Keep-alive interval (seconds)
```

Replace with:

```c
.session.keepalive    = 15, // Keep-alive interval (seconds)
```

**Change B — Network timeout:** In the same struct, find:

```c
.network.reconnect_timeout_ms        = 4000, // Wait 4s before retry
.network.refresh_connection_after_ms = 0,    // 0 = disabled
```

Add a new line immediately after `.network.refresh_connection_after_ms`:

```c
.network.timeout_ms                  = 5000, // TCP socket timeout (default 10s)
```

**Rationale:**
- Keepalive 15s → PINGREQ every ~7.5s → dead broker detected within ~15–22s.
- Network timeout 5s → `esp_mqtt_client_publish()` blocks at most 5s instead of 10s on a
  dead socket. This is a safety net; Fix 2 eliminates the blocking entirely.
- The provisioning test client in `wifi_http_server.c` already uses `keepalive = 10` for
  its test connections, so 15s for the production client is conservative.
- `reconnect_timeout_ms` (4000) remains unchanged.

**Ref:** ESP-IDF MQTT Programming Guide — `esp_mqtt_client_config_t` session and network
sub-structs. MQTT 3.1.1 Section 3.1.2.10 (Keep Alive timer).

**Verification:** After this change, with the server stopped, the serial log should show
`MQTT_EVENT_DISCONNECTED` within ~22 seconds instead of the previous ~90 seconds.

---

## Fix 2: Replace Blocking Publish with Non-Blocking Enqueue

**File:** `src/lighthouse/main/my_mqtt_client.c`

**Location:** Inside `mqtt_client_publish_tag_event()`, the publish call block.

**Find this exact code block:**

```c
    const char *scans_topic = mqtt_client_get_topic("scans");
    int         msg_id      = esp_mqtt_client_publish(s_mqtt_client, scans_topic, payload,
                                                      0,                   // Use default length
                                                      MQTT_QOS_TAG_EVENTS, // QoS 2
                                                      0);                  // Don't retain

    if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to publish tag event");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }
```

**Replace with:**

```c
    const char *scans_topic = mqtt_client_get_topic("scans");
    int         msg_id      = esp_mqtt_client_enqueue(s_mqtt_client, scans_topic, payload,
                                                      0,                   // Use default length
                                                      MQTT_QOS_TAG_EVENTS, // QoS 2
                                                      0,                   // Don't retain
                                                      true);               // Store in outbox

    if (msg_id == -2)
    {
        ESP_LOGW(TAG, "MQTT outbox full - cannot enqueue tag event");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }
    else if (msg_id < 0)
    {
        ESP_LOGE(TAG, "Failed to enqueue tag event");
        s_stats.publish_errors++;
        return ESP_FAIL;
    }
```

**Rationale:** `esp_mqtt_client_enqueue()` writes the message to the internal outbox and
returns immediately. The actual TCP transmission and QoS 2 handshake occur asynchronously
in the MQTT task (a separate FreeRTOS task). This completely eliminates the blocking
behavior in the caller's context.

The additional `store` parameter (set to `true`) ensures the message is persisted in the
outbox. The ESP-MQTT library will retry transmission after reconnection.

Return code `-2` indicates a full outbox (new in recent ESP-IDF versions), which is logged
separately from general failures.

**Ref:** ESP-IDF MQTT Programming Guide — `esp_mqtt_client_enqueue()`: "This API generates
and stores the publish message into the internal outbox and the actual sending to the
network is performed in the mqtt-task context. Thus, it could be used as a non-blocking
version of `esp_mqtt_client_publish()`."

**Verification:** With the server stopped, trigger an IR scan. The device must remain
responsive — RFID polling must continue and subsequent tags must be detected. The serial log
should show the enqueue succeeding (or failing gracefully) without a multi-second stall.

---

## Fix 3: Remove Blocking vTaskDelay from Tag Callback

**File:** `src/lighthouse/main/lighthouse.c`

**Location:** Inside `on_tag_detected()`, at the end of the function.

**Find these lines (at the end of on_tag_detected):**

```c
    // Turn off LED after brief flash
    vTaskDelay(pdMS_TO_TICKS(50));
    gpio_set_level(ACTIVITY_LED, 0);
```

**Replace with:**

```c
    // LED-off is handled by the main loop (process_activity_led)
    // Do NOT call vTaskDelay here — this callback runs in the UART RX task
    s_activity_led_off_time = xTaskGetTickCount() * portTICK_PERIOD_MS + 50;
```

**Additionally, add the state variable** in the state tracking section of `lighthouse.c`,
alongside `ir_trigger_pending`, `ir_scan_active`, etc.:

```c
static uint32_t s_activity_led_off_time = 0; // Timestamp (ms) to turn off activity LED
```

**Additionally, add the LED-off check** to the main loop in `main_task()`. Insert the
following block after the `process_ir_sensor()` call and before the combo check:

```c
        // Turn off activity LED after tag flash duration
        if (s_activity_led_off_time != 0)
        {
            uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
            if (now >= s_activity_led_off_time)
            {
                gpio_set_level(ACTIVITY_LED, 0);
                s_activity_led_off_time = 0;
            }
        }
```

**Rationale:** The `on_tag_detected()` callback runs in the UART RX task context (priority
10, 4096 byte stack). Calling `vTaskDelay()` here blocks the entire RFID polling pipeline
for 50ms per tag detection. With a 250ms polling interval, that is 20% of the budget wasted
on LED blinking. The main loop already runs on a 10ms tick, so the LED-off will fire within
10ms of the target — close enough for a visual flash.

**Ref:** FreeRTOS documentation — `vTaskDelay()` blocks the calling task. ESP-IDF GPIO API —
`gpio_set_level()` is safe to call from any task context.

**Verification:** Tag detections should produce a brief activity LED flash as before, but
the RFID polling cadence should be unaffected. No `vTaskDelay` calls should remain inside
`on_tag_detected()`.

---

## Fix 4: Always-Cache-First in Tag Callback

**File:** `src/lighthouse/main/lighthouse.c`

**Location:** Inside `on_tag_detected()`, the MQTT publish / offline store logic block.

**Find this exact code block:**

```c
    // Publish tag event to MQTT broker (if connected)
    if (mqtt_initialized && mqtt_client_is_connected())
    {
        esp_err_t ret = mqtt_client_publish_tag_event(event, false);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event published to MQTT broker");
        }
        else
        {
            ESP_LOGW(TAG, "  ✗ Failed to publish tag event to MQTT");
        }
    }
    else
    {
        ESP_LOGW(TAG, "  ⚠ MQTT not connected - storing event offline");
        // Store in offline logger for later transmission
        esp_err_t ret = offline_logger_store_event(event);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event stored offline (%lu pending)", offline_logger_get_pending_count());
        }
        else
        {
            ESP_LOGE(TAG, "  ✗ Failed to store event offline");
        }
    }
```

**Replace with:**

```c
    // Always store to offline cache first (non-blocking queue write)
    esp_err_t store_ret = offline_logger_store_event(event);
    if (store_ret != ESP_OK)
    {
        ESP_LOGE(TAG, "  ✗ Failed to store event offline");
    }

    // Additionally enqueue to MQTT if connected (non-blocking via enqueue)
    if (mqtt_initialized && mqtt_client_is_connected())
    {
        esp_err_t ret = mqtt_client_publish_tag_event(event, false);
        if (ret == ESP_OK)
        {
            ESP_LOGI(TAG, "  ✓ Tag event enqueued to MQTT (cached offline: %s)",
                     store_ret == ESP_OK ? "yes" : "no");
        }
        else
        {
            ESP_LOGW(TAG, "  ✗ Failed to enqueue tag event to MQTT (cached offline: %s)",
                     store_ret == ESP_OK ? "yes" : "no");
        }
    }
    else
    {
        ESP_LOGW(TAG, "  ⚠ MQTT not connected - event cached offline (%lu pending)",
                 offline_logger_get_pending_count());
    }
```

**Rationale:** The current code only stores offline when MQTT is known-disconnected. During
the stale-connected window (before Fix 1 takes effect), events would be enqueued to MQTT
but if the outbox is full or the enqueue fails for any reason, the event is lost. By
caching first, every event is guaranteed to reach persistent storage regardless of MQTT
state.

The offline replay mechanism already handles duplicate delivery — replayed events carry
`"offline": true` and `"replayTime"` fields. The server-side must deduplicate based on
`epc` + `timestampMs` + `deviceId`. If this deduplication is not yet implemented
server-side, it should be added as a follow-up task — but the firmware change is safe to
deploy regardless, since duplicate delivery is always preferable to data loss for an
attendance system.

**Important note on `offline_logger_store_event()`:** This function writes to a FreeRTOS
queue (`xQueueSend`) which is non-blocking (or at most waits the configured queue timeout).
The actual LittleFS write happens in the separate `logging_task`. This is confirmed in
`offline_event_logger.c`. Therefore calling it from the UART RX task context is safe.

**Verification:** With the server running, trigger a scan. The serial log should show both
"cached offline: yes" and "enqueued to MQTT" for each tag. With the server stopped, only
the offline cache message should appear. After server restart, offline replay should
deliver the cached events.

---

## Fix 5: Enable MQTT_SKIP_PUBLISH_IF_DISCONNECTED

**File:** `src/lighthouse/sdkconfig.defaults`

If the file does not exist, create it at `src/lighthouse/sdkconfig.defaults`.

**Add the following line** (or append to the existing file):

```
CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED=y
```

**After adding this line,** the agent must also delete or update the generated `sdkconfig`
so that it picks up the new default. Run:

```bash
cd src/lighthouse && idf.py reconfigure
```

Or alternatively, manually update the line in `src/lighthouse/sdkconfig` from:

```
# CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED is not set
```

to:

```
CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED=y
```

**Rationale:** This is a defense-in-depth safety net. When enabled, `esp_mqtt_client_publish()`
(and by extension `esp_mqtt_client_enqueue()`) will return `-1` immediately when the
ESP-MQTT library internally knows it is disconnected, even before our `MQTT_EVENT_DISCONNECTED`
handler fires and updates `s_connection_state`. This closes the remaining edge case where
the internal ESP-MQTT state transitions before our event handler runs.

**Ref:** ESP-IDF MQTT Programming Guide — "If MQTT_SKIP_PUBLISH_IF_DISCONNECTED is enabled,
this API will not attempt to publish when the client is not connected and will always
return -1." Available under `idf.py menuconfig` → Component config → ESP-MQTT Configuration.

**Verification:** Confirm via `idf.py menuconfig` or `grep CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED sdkconfig`
that the option is now enabled.

---

## Execution Order

The fixes are independent and can be applied in any order. However, the recommended order
for testing is:

1. **Fix 5** (sdkconfig) — zero-risk, immediate safety net
2. **Fix 1** (keepalive/timeout) — reduces detection window
3. **Fix 2** (enqueue) — eliminates the blocking publish (the critical fix)
4. **Fix 3** (remove vTaskDelay) — eliminates secondary blocking in callback
5. **Fix 4** (cache-first) — improves data resilience

## Acceptance Criteria

- [ ] With the server stopped and an IR-triggered scan active, the device remains fully
      responsive — subsequent tags are detected, LEDs function, button input works.
- [ ] Serial log shows `MQTT_EVENT_DISCONNECTED` within ~22 seconds of server shutdown.
- [ ] No `vTaskDelay` calls remain inside `on_tag_detected()`.
- [ ] Every detected tag is stored in the offline cache regardless of MQTT state.
- [ ] `CONFIG_MQTT_SKIP_PUBLISH_IF_DISCONNECTED=y` is set in the final sdkconfig.
- [ ] The project builds cleanly with `idf.py build` — no new warnings.
- [ ] Existing functionality (offline replay on reconnect, health publishing, config
      subscription, LWT) is unaffected.
