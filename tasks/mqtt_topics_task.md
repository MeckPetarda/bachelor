# MQTT Topic Standardization - Implementation Task

## Context

This task implements the changes outlined in `mqtt_topic_standardization_plan.md`. The goal is to standardize MQTT topics across firmware and server, implement health/status tracking with database persistence, and add configuration command infrastructure.

**Reference Documents:**
- `/mnt/project/mqtt_topic_standardization_plan.md` - Full technical plan
- `/mnt/project/esp32_datasheet_en.pdf` - ESP32 datasheet (MAC address retrieval)
- `/mnt/project/esp32_technical_reference_manual_en.pdf` - eFuse controller details (Section 4.4)

---

## Task 1: Server - Topic Patterns and Utilities

**Files to create:**
- `src/server/src/mqtt/topics.ts`

**Requirements:**

1. Define topic base constant:
   ```typescript
   export const TOPIC_BASE = "attendance/lighthouse/";
   ```

2. Define RegExp patterns for each topic type. MAC format is `AA:BB:CC:DD:EE:FF` (17 characters):
   - `SCAN_TOPIC_PATTERN` - matches `.../scans`
   - `STATUS_TOPIC_PATTERN` - matches `.../status`
   - `HEALTH_TOPIC_PATTERN` - matches `.../health`
   - `CONFIG_TOPIC_PATTERN` - matches `.../config/{key}` (capture key as second group)

3. Create utility functions:
   - `extractMacAddress(topic: string): string | null` - extracts MAC from any lighthouse topic
   - `buildConfigTopic(mac: string, key: string): string` - constructs config topic for publishing
   - `buildStatusTopic(mac: string): string` - constructs status topic
   - `buildHealthTopic(mac: string): string` - constructs health topic
   - `buildScanTopic(mac: string): string` - constructs scan topic

4. Export all patterns and utilities.

**Acceptance Criteria:**
- All patterns correctly match valid topics and reject invalid ones
- MAC extraction works for all topic types
- Topic builders produce correctly formatted strings

---

## Task 2: Server - Database Schema Updates

**Files to modify:**
- `src/server/src/database/schema.ts`

**Requirements:**

1. Add `label` column to `lighthouses` table:
   - Type: `varchar({ length: 255 })`
   - Nullable: yes

2. Create `lighthouseHealthSnapshots` table:
   ```
   id: bigserial primary key
   lighthouseId: integer (FK → lighthouses.id, NOT NULL)
   uptimeSec: integer
   freeHeapBytes: integer
   minFreeHeapBytes: integer
   wifiRssiDbm: integer
   rfidState: varchar(50)
   rfidIsResponsive: boolean
   rfidPowerRailPresent: boolean
   rfidFwVersion: varchar(20)
   rfidLastError: integer
   recordedAt: timestamp with time zone (default now, NOT NULL)
   ```
   
   Indexes:
   - `idx_health_snapshots_lighthouse_recorded` on `(lighthouseId, recordedAt)`
   - `idx_health_snapshots_recorded` on `(recordedAt)` - for retention cleanup queries

3. Create `lighthouseConnectionEvents` table:
   ```
   id: bigserial primary key
   lighthouseId: integer (FK → lighthouses.id, NOT NULL)
   eventType: varchar(20) NOT NULL — "connected" | "disconnected"
   isGraceful: boolean (nullable, only meaningful for disconnects)
   recordedAt: timestamp with time zone (default now, NOT NULL)
   ```
   
   Indexes:
   - `idx_connection_events_lighthouse_recorded` on `(lighthouseId, recordedAt)`
   - `idx_connection_events_recorded` on `(recordedAt)` - for retention cleanup queries

4. Generate Drizzle migration:
   ```bash
   cd src/server && bun run drizzle-kit generate
   ```

**Acceptance Criteria:**
- Migration generates without errors
- Migration applies successfully to database
- Foreign key constraints are correct

---

## Task 3: Server - Configuration Updates

**Files to modify:**
- `src/server/src/config.ts`

**Requirements:**

1. Add new configuration options:
   ```typescript
   healthRetentionDays: number    // env: HEALTH_RETENTION_DAYS, default: 7
   connectionRetentionDays: number // env: CONNECTION_RETENTION_DAYS, default: 30
   ```

2. Add to config schema/validation as appropriate.

**Acceptance Criteria:**
- Config loads defaults when env vars not set
- Config correctly parses env vars when present

---

## Task 4: Server - Runtime State Management

**Files to create:**
- `src/server/src/mqtt/state.ts`

**Requirements:**

1. Define interfaces:
   ```typescript
   interface HealthPayload {
     uptimeSec: number;
     freeHeapBytes: number;
     minFreeHeapBytes: number;
     wifiRssiDbm: number;
     rfid: {
       state: string;
       isResponsive: boolean;
       powerRailPresent: boolean;
       fwVersion: string;
       lastError: number;
     };
   }

   interface LighthouseRuntimeState {
     isConnected: boolean;
     connectedAt: Date | null;
     disconnectedAt: Date | null;
     lastHealthAt: Date | null;
     latestHealth: HealthPayload | null;
   }
   ```

2. Create state store (Map-based):
   - `getLighthouseState(mac: string): LighthouseRuntimeState | undefined`
   - `setLighthouseConnected(mac: string): void`
   - `setLighthouseDisconnected(mac: string, graceful: boolean): void`
   - `updateLighthouseHealth(mac: string, health: HealthPayload): void`
   - `getAllLighthouseStates(): Map<string, LighthouseRuntimeState>`
   - `clearAllStates(): void` - for testing

3. Initialize state as disconnected; only mark connected when status "online" received.

**Acceptance Criteria:**
- State correctly tracks connection status
- Health updates preserve connection status
- State is retrievable for API/dashboard consumption

---

## Task 5: Server - Status Message Handler

**Files to create:**
- `src/server/src/mqtt/handlers/status.ts`

**Requirements:**

1. Export `handleStatusMessage(topic: string, payload: Buffer): Promise<void>`

2. Implementation:
   - Extract MAC address from topic using utility from `topics.ts`
   - Parse payload as string ("online" or "offline")
   - Look up lighthouse by `deviceId` (MAC) in database
   - If unknown lighthouse, log warning and return (don't create - registration is separate concern)
   - Update runtime state via `state.ts` functions
   - Determine `isGraceful`:
     - For "online": not applicable (null)
     - For "offline": check if previous runtime state was connected; if we never saw "online", assume ungraceful (LWT triggered)
   - Insert record into `lighthouseConnectionEvents` table

3. Handle edge cases:
   - Invalid payload (not "online" or "offline") - log warning, skip
   - Unknown lighthouse - log warning, skip database insert but could still update runtime state

**Acceptance Criteria:**
- Online/offline messages correctly update runtime state
- Connection events are persisted to database
- Graceful flag is set appropriately for disconnects

---

## Task 6: Server - Health Message Handler

**Files to create:**
- `src/server/src/mqtt/handlers/health.ts`

**Requirements:**

1. Export `handleHealthMessage(topic: string, payload: Buffer): Promise<void>`

2. Define payload validation (expected JSON structure):
   ```typescript
   interface HealthMessagePayload {
     uptime_sec: number;
     free_heap_bytes: number;
     min_free_heap_bytes: number;
     wifi_rssi_dbm: number;
     rfid: {
       state: string;
       is_responsive: boolean;
       power_rail_present: boolean;
       fw_version: string;
       last_error: number;
     };
   }
   ```

3. Implementation:
   - Extract MAC address from topic
   - Parse JSON payload
   - Validate required fields exist and have correct types
   - Look up lighthouse by `deviceId` (MAC) in database
   - If unknown lighthouse, log warning and return
   - Update runtime state with latest health
   - Insert record into `lighthouseHealthSnapshots` table

4. Handle edge cases:
   - Malformed JSON - log error, skip
   - Missing required fields - log warning, skip
   - Unknown lighthouse - log warning, skip

**Acceptance Criteria:**
- Valid health messages are stored in database
- Runtime state is updated for real-time access
- Invalid payloads are handled gracefully without crashing

---

## Task 7: Server - Config Publisher

**Files to create:**
- `src/server/src/mqtt/handlers/config.ts`

**Requirements:**

1. Export `publishConfig(mac: string, key: string, value: unknown): void`

2. Implementation:
   - Build topic using `buildConfigTopic(mac, key)` from `topics.ts`
   - Create payload structure:
     ```typescript
     {
       value: <the value>,
       timestamp: new Date().toISOString()
     }
     ```
   - Serialize to JSON
   - Publish via broker's `publishMessage()` function with QoS 1

3. Export type for config payload:
   ```typescript
   interface ConfigPayload<T = unknown> {
     value: T;
     timestamp: string;
   }
   ```

**Acceptance Criteria:**
- Config messages are published to correct topic
- Payload includes value and timestamp
- Function is callable from other server components (API routes, etc.)

---

## Task 8: Server - Retention Cleanup

**Files to create:**
- `src/server/src/database/cleanup.ts`

**Requirements:**

1. Export `cleanupOldHealthSnapshots(): Promise<number>` - returns count of deleted rows

2. Export `cleanupOldConnectionEvents(): Promise<number>` - returns count of deleted rows

3. Implementation:
   - Use config values for retention periods
   - Delete records where `recordedAt < NOW() - INTERVAL 'X days'`
   - Log deletion counts

4. Export `runRetentionCleanup(): Promise<void>` - runs both cleanups, logs summary

5. Integrate into server startup:
   - Call `runRetentionCleanup()` once on startup
   - Optionally set up daily interval (use `setInterval` with 24-hour period)

**Acceptance Criteria:**
- Old records are deleted based on configured retention
- Recent records are preserved
- Cleanup runs on server startup
- Cleanup runs daily thereafter

---

## Task 9: Server - Broker Handler Routing

**Files to modify:**
- `src/server/src/mqtt/broker.ts`

**Requirements:**

1. Import topic patterns from `topics.ts`

2. Import handlers:
   - `handleStatusMessage` from `handlers/status.ts`
   - `handleHealthMessage` from `handlers/health.ts`

3. Update the `aedes.on("publish", ...)` handler:
   - Keep existing scan handling, update to use imported `SCAN_TOPIC_PATTERN`
   - Add status topic matching and routing
   - Add health topic matching and routing

4. Ensure all handlers are called with `await` and errors are caught/logged.

**Acceptance Criteria:**
- Scan messages continue to work as before
- Status messages are routed to status handler
- Health messages are routed to health handler
- Errors in one handler don't affect others

---

## Task 10: Server - Update Existing Scan Handler

**Files to modify:**
- `src/server/src/mqtt/handlers.ts`

**Requirements:**

1. Remove local `SCAN_TOPIC_PATTERN` definition

2. Import `SCAN_TOPIC_PATTERN` and `extractMacAddress` from `topics.ts`

3. Replace `extractDeviceId()` function with call to `extractMacAddress()`

4. Rename internal variable references from `deviceId` to `macAddress` for clarity (the column in the database is still `deviceId`, so the query uses that)

**Acceptance Criteria:**
- Scan handling continues to work
- No duplicate pattern definitions
- Code uses shared utilities

---

## Task 11: Server - Update Tests

**Files to modify:**
- `src/server/tests/mqtt-broker.test.ts`

**Requirements:**

1. Update `TEST_DEVICE_ID` to valid MAC format: `"AA:BB:CC:DD:EE:01"`

2. Update all topic strings in tests to match new pattern:
   - `attendance/lighthouse/AA:BB:CC:DD:EE:01/scans`

3. Update test lighthouse fixture to use MAC as `deviceId`

4. Add new test cases:

   **Status handling:**
   - `"should update runtime state on online message"`
   - `"should record connection event on status change"`
   - `"should mark lighthouse disconnected on offline message"`
   - `"should handle unknown lighthouse gracefully"`

   **Health handling:**
   - `"should store health snapshot from valid message"`
   - `"should update runtime health state"`
   - `"should reject malformed health payload"`
   - `"should handle unknown lighthouse gracefully"`

5. Import and use topic builders from `topics.ts` where appropriate.

**Files to create:**
- `src/server/tests/retention-cleanup.test.ts`

**Requirements:**

1. Test cases:
   - `"should delete health snapshots older than retention period"`
   - `"should preserve health snapshots within retention period"`
   - `"should delete connection events older than retention period"`
   - `"should preserve connection events within retention period"`
   - `"should handle empty tables gracefully"`

2. Use test database, insert records with backdated `recordedAt` timestamps.

**Acceptance Criteria:**
- All existing tests pass with updated topics
- New tests cover status and health handling
- Retention cleanup is tested

---

## Task 12: Firmware - MAC Address Retrieval and Topic Building

**Files to modify:**
- `src/lighthouse/main/my_mqtt_client.h`

**Requirements:**

1. Remove hardcoded defines:
   - `MQTT_CLIENT_ID`
   - `MQTT_TOPIC_TAG_DETECTED`
   - `MQTT_TOPIC_DEVICE_STATUS`
   - `MQTT_TOPIC_CONFIG_BASE`
   - `MQTT_TOPIC_HEALTH_BASE`

2. Add new defines:
   ```c
   #define MQTT_TOPIC_BASE "attendance/lighthouse/"
   #define MQTT_MAC_STR_LEN 18  // "AA:BB:CC:DD:EE:FF" + null terminator
   ```

3. Add function declarations:
   ```c
   /**
    * Get the device's MAC address as formatted string
    * Format: "AA:BB:CC:DD:EE:FF"
    * 
    * @return Pointer to static buffer containing MAC string
    * 
    * Reference: ESP32 Technical Reference Manual Section 4.4
    */
   const char* mqtt_client_get_device_mac(void);
   
   /**
    * Get the full topic string for a given suffix
    * Example: mqtt_client_get_topic("scans") returns "attendance/lighthouse/AA:BB:CC:DD:EE:FF/scans"
    *
    * @param suffix Topic suffix (e.g., "scans", "status", "health")
    * @return Pointer to static buffer containing full topic
    * 
    * Note: Uses single static buffer - not reentrant. Copy result if needed.
    */
   const char* mqtt_client_get_topic(const char* suffix);
   ```

**Files to modify:**
- `src/lighthouse/main/my_mqtt_client.c`

**Requirements:**

1. Add static buffers:
   ```c
   static char s_device_mac[MQTT_MAC_STR_LEN] = {0};
   static char s_topic_buffer[128] = {0};
   ```

2. Implement MAC retrieval (in `mqtt_client_init()` or separate init function):
   ```c
   uint8_t mac[6];
   esp_efuse_mac_get_default(mac);  // Or esp_wifi_get_mac() if WiFi already init
   snprintf(s_device_mac, sizeof(s_device_mac), 
            "%02X:%02X:%02X:%02X:%02X:%02X",
            mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
   ```
   
   **Reference:** ESP32 datasheet Section 4.4, `esp_efuse_mac_get_default()` retrieves factory-programmed MAC.

3. Implement `mqtt_client_get_device_mac()`:
   ```c
   const char* mqtt_client_get_device_mac(void)
   {
       return s_device_mac;
   }
   ```

4. Implement `mqtt_client_get_topic()`:
   ```c
   const char* mqtt_client_get_topic(const char* suffix)
   {
       snprintf(s_topic_buffer, sizeof(s_topic_buffer),
                "%s%s/%s", MQTT_TOPIC_BASE, s_device_mac, suffix);
       return s_topic_buffer;
   }
   ```

5. Update `mqtt_client_init()`:
   - Initialize MAC string before configuring MQTT client
   - Use `s_device_mac` as MQTT client ID
   - Update LWT topic to use `mqtt_client_get_topic("status")`
   - LWT message remains `"offline"` with retain=1

6. Update `MQTT_EVENT_CONNECTED` handler:
   - Publish to `mqtt_client_get_topic("status")` with payload `"online"`

7. Update `mqtt_client_disconnect()`:
   - Publish to `mqtt_client_get_topic("status")` with payload `"offline"`

8. Update `mqtt_client_subscribe_config()`:
   - Build wildcard topic: `attendance/lighthouse/{MAC}/config/+`
   - Use `snprintf` with `mqtt_client_get_device_mac()` and append `/config/+`

9. Update `mqtt_client_publish_tag_event()`:
   - Use `mqtt_client_get_topic("scans")` instead of hardcoded topic

**Acceptance Criteria:**
- MAC address is correctly retrieved and formatted
- All topics use dynamic MAC-based paths
- MQTT client ID is the MAC address
- LWT is configured with correct topic

---

## Task 13: Firmware - Consolidated Health Metrics

**Files to modify:**
- `src/lighthouse/main/my_mqtt_client.c`

**Requirements:**

1. Refactor `mqtt_client_publish_health_metrics()`:
   - Remove individual publishes to separate topics
   - Build single consolidated JSON payload
   - Publish to `mqtt_client_get_topic("health")`

2. New payload format:
   ```json
   {
     "uptime_sec": 3600,
     "free_heap_bytes": 45000,
     "min_free_heap_bytes": 38000,
     "wifi_rssi_dbm": -52,
     "rfid": {
       "state": "RESPONSIVE",
       "is_responsive": true,
       "power_rail_present": true,
       "fw_version": "1.2",
       "last_error": 0
     }
   }
   ```

3. Implementation approach:
   - Gather all metrics as before (heap, WiFi RSSI, uptime, RFID health)
   - Use `snprintf` to build JSON string (existing pattern in codebase)
   - Single `esp_mqtt_client_publish()` call with QoS 0

4. Ensure buffer is large enough for full payload (~300 bytes should suffice).

**Acceptance Criteria:**
- Single health message published per interval
- JSON structure matches expected server format
- All metrics included in payload

---

## Task 14: Firmware - Config Message Parsing (Stub)

**Files to modify:**
- `src/lighthouse/main/my_mqtt_client.c`
- `src/lighthouse/main/lighthouse.c`

**Requirements:**

1. Update `on_mqtt_config_message()` callback in `lighthouse.c` to handle new payload format:
   ```c
   // Expected payload: {"value": <value>, "timestamp": "..."}
   ```

2. For now, implement as logging stub:
   - Parse JSON to extract `value` field
   - Log received config key and value
   - Do not apply settings yet (future task)

3. Consider using cJSON library (already available in ESP-IDF) for parsing.

**Acceptance Criteria:**
- Config messages are received and logged
- JSON payload is parsed correctly
- No crashes on malformed payloads

---

## Task 15: Integration Testing

**Manual testing steps after implementation:**

1. **Server startup:**
   - Verify retention cleanup runs and logs
   - Verify MQTT broker starts

2. **Lighthouse connection:**
   - Flash updated firmware
   - Verify lighthouse connects with MAC-based client ID
   - Check server logs for "online" status message handling
   - Verify `lighthouse_connection_events` record created

3. **Health reporting:**
   - Wait for health interval (60 seconds)
   - Verify consolidated health message received by server
   - Check `lighthouse_health_snapshots` record created
   - Verify runtime state updated

4. **Scan events:**
   - Trigger tag scan
   - Verify scan message uses new topic format
   - Verify `raw_scans` record created (existing functionality)

5. **Disconnection:**
   - Power off lighthouse
   - Verify LWT triggers "offline" message
   - Verify connection event recorded with `isGraceful: false`

6. **Graceful disconnection:**
   - Trigger restart via button/command
   - Verify "offline" published before disconnect
   - Verify connection event recorded with `isGraceful: true`

7. **Config publishing (server side):**
   - Call `publishConfig()` from server (via test or temporary API endpoint)
   - Verify lighthouse receives and logs config message

---

## Execution Order

Recommended implementation sequence:

1. **Task 1** - Topic patterns (foundation for everything else)
2. **Task 2** - Database schema (needed before handlers)
3. **Task 3** - Config updates (needed for retention)
4. **Task 4** - Runtime state (needed by handlers)
5. **Task 5** - Status handler
6. **Task 6** - Health handler
7. **Task 7** - Config publisher
8. **Task 8** - Retention cleanup
9. **Task 9** - Broker routing (connects handlers)
10. **Task 10** - Update scan handler
11. **Task 11** - Update tests
12. **Task 12** - Firmware MAC/topics
13. **Task 13** - Firmware health consolidation
14. **Task 14** - Firmware config stub
15. **Task 15** - Integration testing

Server tasks (1-11) can be completed and tested independently before firmware tasks (12-14).

---

## Notes for Implementation Agent

- Run `bun test` after each server task to catch regressions
- Run `idf.py build` after firmware changes to verify compilation
- The project uses Drizzle ORM - follow existing patterns in `schema.ts`
- The project uses BunJS - use Bun-native APIs where appropriate
- Firmware uses ESP-IDF v5.x patterns - follow existing code style
- Keep logging consistent with existing `ESP_LOGI`/`ESP_LOGW`/`ESP_LOGE` patterns
- Reference the plan document for detailed rationale on design decisions
