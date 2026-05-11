# Task: implement Application-Layer ACK for offline ring buffer replay

**Purpose:** The firmware advances its ring buffer read pointer based on MQTT-layer queue success rather than
server-side DB commit. When the server shuts down mid-replay, the QoS 2 handshake is abandoned, the pointer is not
advanced, and the same entries are re-delivered on every subsequent reconnection — including entries from prior
sessions. This task adds an application-layer acknowledgement: the server publishes an ACK after committing replayed
scans to the database, and the firmware advances its read pointer only upon receiving that ACK.

**Files to modify (server):**

- `server/src/mqtt/handlers/scan.ts`
- `server/src/mqtt/broker.ts`
- One new Drizzle migration file under `server/drizzle/` (follow the existing migration file naming convention in that
  directory)

**Files to modify (firmware):**

- `lighthouse/main/offline_event_logger.h`
- `lighthouse/main/offline_event_logger.c`
- `lighthouse/main/my_mqtt_client.c`

**Files NOT to modify:** All other files. Do not touch `lighthouse.c`, `io_controller.c`, `rfid_reader.c`, the
provisioning code, or any server route handlers outside `scan.ts`. Do not modify the existing `raw_scans` Drizzle schema
definition directly — use a migration.

---

## Overview / context

`offline_event_logger.c` stores scan events in a 48-byte fixed-size ring buffer on LittleFS. Two pointers —
`rtc_write_index` and `rtc_read_index` — are mirrored in RTC memory and NVS. The replay task (`offline_replay_task`)
loops while `get_pending_count_internal() > 0`, reads the entry at `rtc_read_index`, calls `replay_offline_event()` in
`my_mqtt_client.c`, and **currently advances `rtc_read_index` only if that callback returns `ESP_OK`**. `ESP_OK` is
returned when `esp_mqtt_client_publish()` succeeds in queuing the message — not when the server commits it to the
database. If the MQTT connection drops before the QoS 2 handshake completes, the pointer is not advanced and the entry
is re-sent on the next reconnection.

The fix: decouple pointer advancement from MQTT-layer delivery. The replay task publishes entries without advancing the
pointer. The server publishes an ACK after a successful DB insert. The firmware advances the pointer only on receipt of
the ACK.

The `offline_event_t` struct currently has a `uint8_t reserved[4]` field at its end (confirmed 48-byte total). These
four bytes will become `uint32_t seq_no`, a monotonically increasing counter per device, embedded in the MQTT payload
and echoed back in the ACK.

---

## Part a — server

### Step a.1 — publish ACK after offline scan insert in `scan.ts`

Locate `handleScanMessage()`. It currently:

1. Parses the JSON array payload
2. Identifies offline entries by `entry.offline === true` and marks `source` as `"offline_sync"`
3. Inserts into `raw_scans` via Drizzle
4. Broadcasts to WebSocket clients

After the Drizzle insert succeeds for a batch that contains at least one offline entry, add a publish step:

- Extract the device MAC from the MQTT topic. The topic format is `attendance/lighthouse/{MAC}/scans` — the MAC is
  already parsed to identify the lighthouse; reuse that value.
- Find the maximum `seqNo` value across all offline entries in the batch. Each offline entry will carry a `seqNo` field
  in its JSON object (added by the firmware in Part B). If no entry carries `seqNo` (legacy entries before this firmware
  update), use `0`.
- Publish to topic `attendance/lighthouse/{MAC}/ack`, QoS 1, not retained:

  ```json
  { "ackedSeqNo": <max_seq_no>, "ts": "<ISO timestamp of publish>" }
  ```

- The publish must use the Aedes broker instance that is already accessible in `scan.ts` (check how `broker.ts` exports
  or passes the broker to handlers — use the same pattern). Do not import a new MQTT client.
- If the Drizzle insert throws, do not publish the ACK. The try/catch structure already present must wrap both the
  insert and the ACK publish, with the ACK publish inside the success path only.
- For live (non-offline) scan batches, do not publish an ACK.

### Step a.2 — subscribe to nothing (server is ACK sender only)

No new subscription is needed on the server. The ACK flow is unidirectional: server → firmware. Do not add a
subscription for `attendance/lighthouse/+/ack` on the server side.

### Step a.3 — add deduplication index migration

Create a new Drizzle migration file. The migration must add a **partial unique index** on `raw_scans`:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS raw_scans_offline_dedup
ON raw_scans (lighthouse_id, epc, timestamp_ms)
WHERE source = 'offline_sync';
```

This prevents duplicate rows if the same offline entry is delivered twice before the ACK is received. Follow the
existing migration file naming convention exactly (check the filenames already present in `server/drizzle/`).

---

## Part b — firmware

### Step b.1 — add `seq_no` to `offline_event_t` in `offline_event_logger.h`

Locate the `offline_event_t` struct. It currently ends with `uint8_t reserved[4]`. Replace those four bytes with
`uint32_t seq_no`. The total struct size must remain 48 bytes — verify with a
`_Static_assert(sizeof(offline_event_t) == 48, "...")` if one does not already exist; add it if not.

Also add the following to `offline_event_logger.h`:

- Constant `NVS_KEY_SEQ_COUNTER "seq_ctr"` alongside the existing NVS key constants.
- Function declaration: `void offline_logger_ack_received(uint32_t acked_seq_no);`

### Step b.2 — maintain seq counter in `offline_event_logger.c`

Add an RTC-backed seq counter:

```c
RTC_DATA_ATTR static uint32_t rtc_seq_counter = 0;
```

In the initialization path (wherever `rtc_initialized` is checked and NVS pointers are loaded on first boot), also load
`NVS_KEY_SEQ_COUNTER` from NVS into `rtc_seq_counter`. If the key does not exist (first boot after this firmware
update), initialize `rtc_seq_counter = 1` and write it to NVS. If it exists, load the stored value.

In `logging_task()`, immediately before writing an `offline_event_t` to flash, set:

```c
event.seq_no = rtc_seq_counter;
rtc_seq_counter++;
```

After incrementing, persist the new counter to NVS using the existing NVS write pattern for `NVS_KEY_SEQ_COUNTER`. Do
this every write — the counter must survive power loss.

Existing ring buffer entries (written before this firmware update) have `reserved[4] = {0,0,0,0}`, which reads as
`seq_no = 0`. This is intentional and handled correctly by the ACK logic in Step B.4.

### Step b.3 — remove pointer advance from replay loop in `offline_event_logger.c`

Locate `offline_replay_task()` (or `replay_task()` — whichever name is used). The current loop reads an entry, calls the
registered callback, and advances `rtc_read_index` + calls `nvs_save_pointers()` on `ESP_OK`.

Change the loop behaviour:

- Call the callback (publish the entry). Do not check its return value for pointer advancement.
- Do **not** advance `rtc_read_index` here under any condition.
- Do **not** call `nvs_save_pointers()` here.
- Keep the throttle delay (the existing `vTaskDelay` that enforces the 10 events/s rate limit).
- The loop termination condition remains `get_pending_count_internal() > 0`.

The replay task now publishes all pending entries unconditionally and exits. Pointer advancement is the exclusive
responsibility of `offline_logger_ack_received()`.

On the next reconnect, the replay task starts again from `rtc_read_index` — which reflects only ACKed entries — and
re-publishes anything not yet ACKed. This is correct and intentional.

### Step b.4 — implement `offline_logger_ack_received()` in `offline_event_logger.c`

Implement the function declared in Step B.1:

```c
void offline_logger_ack_received(uint32_t acked_seq_no)
```

Behaviour:

- Acquire `logger_state.storage_mutex`.
- Starting from `rtc_read_index`, read entries forward through the ring buffer.
- For each entry at or before the acked position: if `entry.seq_no <= acked_seq_no` AND `entry.seq_no != 0`
  (non-legacy), advance `rtc_read_index` by one and call `nvs_save_pointers()`.
- Special case for legacy entries (`seq_no == 0`): if `acked_seq_no == 0`, advance past all contiguous legacy entries
  from the current read position.
- Stop advancing when an entry has `seq_no > acked_seq_no` or the buffer is empty (`rtc_read_index == rtc_write_index`).
- Release the mutex.
- Log the number of entries advanced at `ESP_LOGI` level.

Do not call this function from within the replay task itself — it is called exclusively from the MQTT event handler in
`my_mqtt_client.c`.

### Step b.5 — subscribe to ACK topic and handle in `my_mqtt_client.c`

**In `MQTT_EVENT_CONNECTED` handler:**

Alongside the existing subscriptions, subscribe to:

```text
attendance/lighthouse/{MAC}/ack
```

at QoS 1. Use the same MAC string construction used for the existing topic subscriptions.

**In `MQTT_EVENT_DATA` handler:**

Add a branch that matches the incoming topic against `attendance/lighthouse/{MAC}/ack`. If matched:

- Parse the JSON payload. Extract `ackedSeqNo` as a `uint32_t`.
- Call `offline_logger_ack_received(ackedSeqNo)`.
- Log receipt at `ESP_LOGI` level: `"Received ACK for seqNo %" PRIu32, ackedSeqNo`.
- Do not call `esp_restart()` or modify any other state.

**In `replay_offline_event()`:**

Add `"seqNo": %" PRIu32` (the entry's `seq_no` field) to the JSON payload of replayed events. Place it alongside the
existing `"offline": true` and `"timeBasis"` fields. Do not change the topic, QoS level, or any other part of the
payload.

---

## Migration safety note

The 48-byte ring buffer record layout change is backward-compatible for existing flash contents: `reserved[4]` was
zero-initialised and `seq_no = 0` is the correct legacy sentinel. No flash erase or ring buffer reset is required. The
firmware will replay existing entries from `rtc_read_index` as before; the first ACK from the server (carrying
`ackedSeqNo: 0`) will advance the pointer past all legacy entries.

---

## Acceptance criteria

- [ ] `idf.py build` succeeds without new warnings
- [ ] `sizeof(offline_event_t) == 48` — static assert passes at compile time
- [ ] On reconnection after offline traversal, firmware serial log shows `"Received ACK for seqNo N"` within 30 s
- [ ] After ACK is received, firmware serial log shows `rtc_read_index` advanced past the replayed entries
- [ ] On a second reconnection after ACK was received, the replay task publishes zero entries (buffer shows empty)
- [ ] Server log shows `attendance/lighthouse/{MAC}/ack` published after each offline scan batch insert
- [ ] `raw_scans` contains no duplicate rows with identical `(lighthouse_id, epc, timestamp_ms)` after two consecutive
  replays of the same offline session
- [ ] Live (realtime) scan path is unaffected — no ACK is published for non-offline batches
- [ ] Existing NVS keys `write_idx` and `read_idx` are unchanged in format and namespace
- [ ] The deduplication migration applies cleanly via the existing migration runner without errors
