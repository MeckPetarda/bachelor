# Task: SNTP Time Synchronization for Lighthouse Devices

## Problem Statement

The ESP32-based lighthouse devices have no hardware RTC with battery backup. On every boot, the system clock starts from Unix epoch (1970-01-01 00:00:00). All timestamps attached to RFID scan events are therefore boot-relative millisecond counters, not wall-clock times. The server currently interprets `timestampMs` as a Unix timestamp, producing nonsensical dates in the database.

**Example of the current broken behavior:**

```
timestamp_ms  | 42740
timestamp     | 1970-01-01 01:00:42.74+01
received_at   | 2026-03-17 02:09:20.182009+01
```

The `timestampMs` value of `42740` means "42.7 seconds after boot," not a Unix timestamp.

## Solution Overview

Implement SNTP-based time synchronization on the ESP32 firmware, using the Lighthouse server as the NTP source. The server will run an NTP daemon alongside the existing MQTT broker and PostgreSQL database. The firmware will synchronize its system clock via SNTP after WiFi connects, and all subsequent timestamps will use real wall-clock time with the correct timezone.

For situations where SNTP sync is unavailable (no WiFi on boot), the firmware will track time quality explicitly and ensure that events with unresolvable timestamps are never sent to the server as if they were real timestamps. Instead, they are flagged so the server can handle them appropriately.

---

## Part 1: Server — NTP Daemon Setup

### Objective

Run an NTP server on the same Linux machine that hosts the Lighthouse application (BunJS server, MQTT broker, PostgreSQL).

### Requirements

1. Install and configure `chrony` (preferred over `ntpd` for its lighter footprint and better behavior on systems that are themselves intermittently connected).
2. Configure `chrony` to serve time to the LAN even if the server itself has no upstream NTP source. This is critical for LAN-only deployments with no internet access. The relevant chrony directive is `local stratum 10` which makes chrony act as an authoritative time source even when it cannot reach external servers.
3. Ensure chrony listens on the LAN-facing interface (not just localhost). The `allow` directive controls which subnets may query the server.
4. The NTP server port is the standard UDP 123. This is not configurable in chrony and should not conflict with existing services.

### Configuration Reference

Chrony documentation: https://chrony-project.org/doc/4.5/chrony.conf.html

Key directives for a LAN-only deployment:

- `local stratum 10` — serve time even without upstream sync
- `allow <subnet>` — permit NTP queries from lighthouse devices (e.g., `allow 192.168.0.0/16`)
- `makestep 1.0 3` — allow large time steps on the first 3 updates (useful after server reboot)

### Verification

- `chronyc tracking` should show the server is synchronized (or operating in local-only mode).
- From any machine on the LAN: `ntpdate -q <server_ip>` should return a time response.

---

## Part 2: Firmware — SNTP Time Sync Module

### Objective

Create a time synchronization module that manages SNTP sync, tracks time quality state, and provides a clean API for the rest of the firmware to query whether wall-clock time is available.

### 2.1 Module Interface

**New files:**
- `src/lighthouse/main/time_sync.h`
- `src/lighthouse/main/time_sync.c`

**Time quality states:**

```
typedef enum {
    TIME_QUALITY_NONE,         // No time reference at all (boot-relative only)
    TIME_QUALITY_ESTIMATED,    // Has a lower-bound from NVS (last known good time from a previous boot)
    TIME_QUALITY_SYNCED        // SNTP synced — wall-clock time is authoritative
} time_quality_t;
```

**Public API (minimum):**

| Function | Purpose |
|----------|---------|
| `esp_err_t time_sync_init(const char *ntp_server_ip)` | Initialize SNTP with the given server address. Does not block. |
| `time_quality_t time_sync_get_quality(void)` | Return current time quality state. |
| `bool time_sync_is_synced(void)` | Convenience: returns `true` if quality == `TIME_QUALITY_SYNCED`. |
| `void time_sync_wait_for_sync(uint32_t timeout_ms)` | Block until synced or timeout. For use during boot sequence. |
| `int64_t time_sync_get_timestamp_ms(void)` | Return current wall-clock time as Unix milliseconds, or 0 if not synced. |
| `void time_sync_notify_shutdown(void)` | Persist current time + uptime to NVS before controlled power-down. |

### 2.2 SNTP Configuration

**ESP-IDF SNTP API reference:** ESP-IDF component `esp_netif` provides `esp_sntp.h`.

Key configuration points:

- **Operating mode:** `SNTP_OPMODE_POLL` — the ESP32 periodically queries the server.
- **Server address:** Use the MQTT broker IP already stored in NVS (key `mqtt_ip` in namespace `ss`). The NTP server runs on the same machine. No additional NVS key is needed for the NTP address; the port is always UDP 123 (standard, not configurable).
- **Sync interval:** ESP-IDF default is 1 hour (`CONFIG_LWIP_SNTP_UPDATE_DELAY`). This is adequate. Can be overridden via `sntp_set_sync_interval()` if needed.
- **Sync mode:** `SNTP_SYNC_MODE_IMMED` for the first sync (allows a large time jump), then `SNTP_SYNC_MODE_SMOOTH` for subsequent updates (gradual adjustments via `adjtime()`).
- **Timezone:** Set via `setenv("TZ", "<tz_string>", 1)` followed by `tzset()`. The POSIX TZ string for CET/CEST is `"CET-1CEST,M3.5.0,M10.5.0/3"`. This handles automatic daylight saving transitions. This must be set **before** SNTP init so that `localtime()` / `gettimeofday()` return correctly offset values.
- **Sync notification callback:** Register via `sntp_set_time_sync_notification_cb()`. This callback fires when SNTP successfully adjusts the clock. Use it to transition time quality from `TIME_QUALITY_NONE` / `TIME_QUALITY_ESTIMATED` to `TIME_QUALITY_SYNCED`, and to persist the newly known good time to NVS.

**ESP32 Datasheet Reference:** Section 3.3.4 (RTC) — the ESP32's RTC timer runs from a 150kHz internal oscillator with typical drift of ~5% (7.5 minutes/day). This confirms that periodic re-sync is necessary for any deployment running longer than minutes. The 1-hour default re-sync interval is more than sufficient for attendance-level accuracy.

### 2.3 NVS Persistence (Last Known Good Time)

**Purpose:** Provide a time lower-bound for boots where SNTP sync is not immediately available.

**NVS namespace:** `time_sync` (new, separate from existing `ss` and `offline_log` namespaces — avoids key collisions).

**Keys:**

| Key | Type | Description |
|-----|------|-------------|
| `last_unix_s` | `int64_t` | Last known Unix time in seconds |
| `last_uptime_ms` | `int64_t` | `esp_timer_get_time() / 1000` at the moment `last_unix_s` was captured |

**When to persist:**
- On every successful SNTP sync callback (update both keys, commit).
- On controlled shutdown via `time_sync_notify_shutdown()` — called from the graceful disconnect path before `esp_restart()`.

**On boot (when SNTP is not yet available):**
1. Load `last_unix_s` and `last_uptime_ms` from NVS.
2. If both exist, set time quality to `TIME_QUALITY_ESTIMATED`. The firmware knows that the current real time is *at least* `last_unix_s` (it could be much later if the device was off for a long time, but never earlier).
3. If neither exists (first boot ever, or NVS was erased), time quality remains `TIME_QUALITY_NONE`.

**Important:** The `TIME_QUALITY_ESTIMATED` state does **not** mean the firmware should use `last_unix_s + current_uptime` as a wall-clock guess. That calculation is wrong because it omits the unknown powered-off duration. The estimated state only provides a lower bound for server-side reconstruction. Events logged in this state carry the `estimated` time basis flag.

### 2.4 Integration into Boot Sequence

The current boot sequence is (from project knowledge):

1. GPIO init
2. WiFi provisioning init (loads credentials, connects to WiFi)
3. Wait for WiFi ready
4. MQTT client init (loads broker IP from NVS)
5. RFID reader init
6. Main task loop

**Modified sequence:**

1. GPIO init
2. WiFi provisioning init (loads credentials, connects to WiFi)
3. Wait for WiFi ready
4. **Time sync init** — call `time_sync_init(broker_config.broker_ip)` using the already-loaded MQTT broker IP
5. **Wait for SNTP sync** — call `time_sync_wait_for_sync(timeout_ms)` with a reasonable timeout (e.g., 5000ms). If sync succeeds within the timeout, quality becomes `TIME_QUALITY_SYNCED`. If it times out (NTP server unreachable), quality remains `TIME_QUALITY_NONE` or `TIME_QUALITY_ESTIMATED` depending on NVS state.
6. MQTT client init
7. RFID reader init
8. Main task loop

**Rationale for placement:** SNTP sync requires WiFi to be connected (step 3 complete). It must complete before RFID scanning begins (step 7) so that the first scan events already have correct timestamps. Placing it between WiFi and MQTT is natural — MQTT connection is not time-dependent, and the SNTP timeout prevents indefinite blocking.

**If SNTP sync times out:** The device continues normal operation. It will keep retrying SNTP in the background (ESP-IDF handles this automatically via the poll interval). When sync eventually succeeds, the callback fires and time quality upgrades. Any events logged before sync completes are handled by the time-quality-aware publishing logic (Part 3).

---

## Part 3: Firmware — MQTT Payload Changes

### 3.1 Updated Real-Time Scan Payload

The current payload from `my_mqtt_client.c` (real-time path):

```json
{
  "epc": "E28011704000021D53D80D0A",
  "timestampMs": 42740,
  "rssiDbm": -70,
  "antennaId": 0,
  "frequency": 47,
  "deviceId": "AA:BB:CC:DD:EE:FF",
  "offline": false
}
```

**Updated payload:**

```json
{
  "epc": "E28011704000021D53D80D0A",
  "timestampMs": 1742169600000,
  "rssiDbm": -70,
  "antennaId": 0,
  "frequency": 47,
  "deviceId": "AA:BB:CC:DD:EE:FF",
  "offline": false,
  "timeBasis": "synced"
}
```

**Changes:**

| Field | Before | After |
|-------|--------|-------|
| `timestampMs` | Boot-relative milliseconds | Unix milliseconds (wall-clock) when `timeBasis` is `synced`. Boot-relative otherwise. |
| `timeBasis` | *(new field)* | `"synced"` / `"estimated"` / `"relative"` |

**`timeBasis` values:**

| Value | Meaning | Server action |
|-------|---------|---------------|
| `"synced"` | SNTP-synced wall-clock time. `timestampMs` is a real Unix timestamp. | Use `timestampMs` directly as the event timestamp. |
| `"estimated"` | NVS-derived lower bound. `timestampMs` is boot-relative. | Store with flag. Use `received_at` as best-effort timestamp. These events occurred *after* the NVS-persisted time but exact placement is unknown. |
| `"relative"` | No time reference at all. `timestampMs` is boot-relative. | Store with flag. Use `received_at` as best-effort timestamp. Relative ordering within the session is preserved. |

**Publishing logic (pseudocode):**

```
when scan event occurs:
    quality = time_sync_get_quality()

    if quality == TIME_QUALITY_SYNCED:
        timestampMs = current wall-clock time in Unix ms (from gettimeofday)
        timeBasis = "synced"
    else if quality == TIME_QUALITY_ESTIMATED:
        timestampMs = boot-relative ms (esp_timer_get_time / 1000)
        timeBasis = "estimated"
    else:
        timestampMs = boot-relative ms
        timeBasis = "relative"

    publish payload with timestampMs and timeBasis
```

**Critical rule:** The firmware **never** constructs a synthetic Unix timestamp from estimated data. If time quality is not `SYNCED`, the `timestampMs` value is explicitly boot-relative, and the `timeBasis` field tells the server not to interpret it as Unix time.

### 3.2 Updated Offline Replay Payload

The current offline replay payload includes `replayTime`. This continues to work but now also includes `timeBasis`:

```json
{
  "epc": "E28011704000021D53D80D0A",
  "timestampMs": 1742169600000,
  "rssiDbm": -70,
  "antennaId": 0,
  "frequency": 47,
  "deviceId": "AA:BB:CC:DD:EE:FF",
  "offline": true,
  "replayTime": 1742170200000,
  "timeBasis": "synced"
}
```

**For offline events:** The `timeBasis` reflects the time quality **at the moment the event was originally recorded**, not at replay time. The offline event record's existing `rtc_timestamp_s` field (4 bytes in the 48-byte `offline_event_t` struct, see `offline_event_logger.h`) should be populated as follows:

| Original time quality | `rtc_timestamp_s` value | `timeBasis` on replay |
|----------------------|------------------------|-----------------------|
| `SYNCED` | Unix seconds at detection time | `"synced"` |
| `ESTIMATED` | 0 | `"estimated"` |
| `NONE` | 0 | `"relative"` |

When replaying, if `rtc_timestamp_s > 0`, use it (converted to ms) as `timestampMs` with `timeBasis: "synced"`. If `rtc_timestamp_s == 0`, use the boot-relative `timestamp_ms` from the record and set `timeBasis` to `"estimated"` or `"relative"` — the distinction can be encoded in the `reserved` bytes of the offline event record (1 byte is sufficient).

### 3.3 Offline Event Record Modification

The existing `offline_event_t` struct has 4 bytes of `reserved` padding. Use 1 byte to store the time quality at recording time:

| Field | Offset | Use |
|-------|--------|-----|
| `reserved[0]` | byte 44 | `time_quality_t` value (0=NONE, 1=ESTIMATED, 2=SYNCED) |
| `reserved[1..3]` | bytes 45-47 | Remain unused |

This preserves the 48-byte record size and maintains backward compatibility with any existing cached events (whose `reserved[0]` will be 0, mapping to `TIME_QUALITY_NONE` — the safe default).

---

## Part 4: Server — Scan Handler Changes

### 4.1 Updated `ScanPayload` Interface

**File:** `src/server/src/mqtt/handlers/scan.ts`

Add `timeBasis` to the existing `ScanPayload` interface:

```typescript
export interface ScanPayload {
  epc: string;
  timestampMs: number;
  rssiDbm?: number;
  antennaId?: number;
  frequency?: number;
  deviceId?: string;
  offline?: boolean;
  replayTime?: number;
  timeBasis?: "synced" | "estimated" | "relative";  // NEW
}
```

### 4.2 Timestamp Interpretation Logic

In `handleScanMessage`, replace the current timestamp calculation:

```typescript
// CURRENT (broken):
let scanTimestamp: Date;
if (scanData.timestamp) {
  scanTimestamp = new Date(scanData.timestamp);
} else {
  scanTimestamp = new Date(Number(scanData.timestampMs));
}
```

**New logic:**

```
if timeBasis == "synced":
    scanTimestamp = new Date(timestampMs)   // It's a real Unix timestamp
else:
    scanTimestamp = received_at             // Fall back to server receipt time
```

The `timestampMs` value is still stored in the `timestamp_ms` column of `raw_scans` regardless of time basis (it preserves relative ordering for forensic analysis), but the `timestamp` column should only contain meaningful wall-clock times.

### 4.3 Database Schema Consideration

The `raw_scans` table should store the `timeBasis` value. Options:

- Add a `time_basis` column (`varchar` or `enum`) to `raw_scans`. This is the cleanest approach and enables straightforward filtering of uncertain records.
- Alternatively, encode it in the existing `source` column by extending the enum (e.g., `realtime_synced`, `realtime_estimated`, `offline_sync_synced`, etc.) — but this conflates two dimensions and is less maintainable.

**Recommendation:** Add a `time_basis` column with values `synced`, `estimated`, `relative`. Default to `synced` for backward compatibility with any existing data.

---

## Part 5: Verification Criteria

### Firmware

1. After boot with WiFi available: `time_sync_get_quality()` returns `TIME_QUALITY_SYNCED` within the configured timeout.
2. Serial log shows SNTP sync success with the received time and configured timezone.
3. Scan events published via MQTT contain `timeBasis: "synced"` and `timestampMs` is a valid Unix timestamp (not boot-relative).
4. After WiFi disconnect and reconnect: SNTP re-syncs automatically (ESP-IDF handles this).
5. After clean reboot: NVS contains valid `last_unix_s` and `last_uptime_ms` values.
6. Boot without WiFi: time quality is `ESTIMATED` (if NVS has data) or `NONE` (first boot). Events are logged to offline cache with correct `time_quality_t` in `reserved[0]`.
7. Offline event replay after reconnect: events with `rtc_timestamp_s > 0` are published with `timeBasis: "synced"` and correct Unix timestamps. Events with `rtc_timestamp_s == 0` are published with appropriate `timeBasis`.

### Server

1. NTP daemon responds to queries from the LAN.
2. Scan handler correctly interprets `timeBasis` field.
3. `raw_scans.timestamp` contains real wall-clock times for `synced` events.
4. `raw_scans.timestamp` uses `received_at` for `estimated` and `relative` events.
5. `raw_scans.time_basis` column is populated correctly.
6. Existing tests in `mqtt-broker.test.ts` continue to pass (backward compatibility — payloads without `timeBasis` default to `synced` for backward compat during rollout, or the test payloads are updated to include the field).

---

## Part 6: Server — Test Suite for Time Basis Handling

### Objective

Add a dedicated test file `tests/time-basis.test.ts` covering the scan handler's new `timeBasis`-aware timestamp logic and the `time_basis` database column. Follow the existing test conventions established in `tests/mqtt-broker.test.ts`.

### 6.1 Test File Setup

**File:** `src/server/tests/time-basis.test.ts`

**Framework:** `bun:test` (same as all existing tests — uses `describe`, `it`, `expect`, `beforeAll`, `afterAll`, `beforeEach`).

**Infrastructure:** The test must manage its own lifecycle identically to the existing MQTT broker tests:

- `beforeAll`: call `initDatabase()`, insert a test lighthouse record (use a distinct `TEST_LIGHTHOUSE_ID` such as `997` and device ID such as `AA:BB:CC:DD:EE:03` to avoid collisions with existing test suites), call `startMqttBroker()`, wait 500ms for broker readiness.
- `afterAll`: disconnect any MQTT clients, delete test data from `raw_scans` and `lighthouses`, call `closeMqttBroker()` and `closeDatabase()`.
- `beforeEach`: clean up `raw_scans` for the test lighthouse to ensure test isolation.

**MQTT client helper:** Use the `mqtt` npm package (already a project dependency) to connect a test client and publish scan payloads to the scan topic for the test device. Use `buildScanTopic(TEST_DEVICE_ID)` from `src/mqtt/topics.ts` for topic construction.

**Wait helper:** Reuse the same `waitFor` polling pattern from `mqtt-broker.test.ts` — poll a condition with 100ms interval and 5000ms timeout.

### 6.2 Required Test Cases

Each test publishes a scan payload via MQTT and verifies the resulting row in `raw_scans`.

**Test 1: `timeBasis: "synced"` — timestamp used directly**

Publish a scan with `timeBasis: "synced"` and `timestampMs` set to a known Unix millisecond value (e.g., `1742169600000` = 2025-03-17T00:00:00Z). Verify:
- `raw_scans.timestamp` matches the provided `timestampMs` (within 1 second tolerance for Date conversion).
- `raw_scans.time_basis` is `"synced"`.
- `raw_scans.timestamp_ms` stores the raw value unchanged.

**Test 2: `timeBasis: "estimated"` — falls back to `received_at`**

Publish a scan with `timeBasis: "estimated"` and `timestampMs` set to a small boot-relative value (e.g., `45000`). Verify:
- `raw_scans.timestamp` is approximately `now` (within a few seconds of `received_at`), **not** 1970.
- `raw_scans.time_basis` is `"estimated"`.
- `raw_scans.timestamp_ms` stores the raw boot-relative value `45000` unchanged.

**Test 3: `timeBasis: "relative"` — falls back to `received_at`**

Same as Test 2 but with `timeBasis: "relative"`. Verify identical fallback behavior and correct `time_basis` column value.

**Test 4: Missing `timeBasis` field — backward compatibility**

Publish a scan payload **without** the `timeBasis` field at all (simulates pre-update firmware). Verify:
- The scan is stored without error.
- `raw_scans.time_basis` defaults to `"synced"` (backward compat assumption — existing firmware always had WiFi before scanning, so pre-update timestamps were boot-relative but the system treated them as Unix. After the update, all pre-update lighthouses should be reflashed, but the server should not crash on old payloads during rollout).
- Alternatively, if the implementation chooses a different default, document and test that.

**Test 5: Offline replay with `timeBasis: "synced"`**

Publish a scan with `offline: true`, `replayTime: <now_ms>`, `timeBasis: "synced"`, and `timestampMs` set to a Unix value earlier than `replayTime`. Verify:
- `raw_scans.timestamp` uses the provided `timestampMs` (the original detection time, not replay time).
- `raw_scans.source` is `"offline_sync"`.
- `raw_scans.time_basis` is `"synced"`.

**Test 6: Offline replay with `timeBasis: "relative"`**

Publish a scan with `offline: true`, `replayTime: <now_ms>`, `timeBasis: "relative"`, and `timestampMs` set to a boot-relative value. Verify:
- `raw_scans.timestamp` falls back to approximately `received_at`.
- `raw_scans.source` is `"offline_sync"`.
- `raw_scans.time_basis` is `"relative"`.

**Test 7: Batch of mixed `timeBasis` values**

Publish 3 scans rapidly — one `synced`, one `estimated`, one `relative` — and verify all three are stored with correct and independent `time_basis` and `timestamp` values. This confirms no state leakage between sequential scan processing.

### 6.3 Package Script

Add a test script entry to `package.json`:

```json
"test:time-basis": "bun test tests/time-basis.test.ts"
```

This follows the existing pattern (`test:mqtt`, `test:api`, `test:retention`, `test:dashboard`).

### 6.4 Implementation Notes for the Agent

- The Drizzle schema file (`src/database/schema.ts`) will need the new `time_basis` column added to the `rawScans` table definition before the tests can reference it. This is part of the scan handler update (Part 4.3) and must be done first.
- The scan handler logic change (Part 4.2) must also be in place before the tests will pass — the tests verify the *new* behavior, not the old.
- Existing tests in `mqtt-broker.test.ts` that publish scan payloads should be updated to include `timeBasis: "synced"` in their payloads so they continue to pass after the handler change. Alternatively, verify that the backward-compat default handles them gracefully — either approach is acceptable but must be tested.
- All database assertions should query `raw_scans` using the test lighthouse ID filter to avoid interference with other test suites.

---

## Execution Order

1. **Server: NTP daemon** — install and configure chrony. Verify with `ntpdate` from another machine.
2. **Firmware: `time_sync` module** — create `time_sync.h` / `time_sync.c`. Implement SNTP init, quality tracking, NVS persistence, and the public API.
3. **Firmware: Boot sequence integration** — insert time sync init and wait between WiFi ready and MQTT init.
4. **Firmware: MQTT payload update** — modify `my_mqtt_client.c` to include `timeBasis` and use wall-clock `timestampMs` when synced.
5. **Firmware: Offline logger integration** — populate `rtc_timestamp_s` and `reserved[0]` in offline events. Update replay path to use stored time quality.
6. **Server: Scan handler update** — update `ScanPayload` interface, timestamp interpretation logic, and database schema (`time_basis` column).
7. **Server: Test suite** — create `tests/time-basis.test.ts` per Part 6. Run with `bun test tests/time-basis.test.ts` and verify all cases pass. Also run `bun test` to confirm no regressions in existing suites.
8. **Integration test** — end-to-end verification per criteria in Part 5.
