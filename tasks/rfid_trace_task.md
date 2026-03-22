# Task: Add Diagnostic Logging to Real-Time Inventory Pipeline

**Purpose:** Zero tag callbacks are firing after the switch from `0x8B` to `0x89` inventory. We need to see exactly where data is being dropped. This adds temporary INFO-level log statements at every decision point in the pipeline.

**Files to modify:** `rfid_reader.c`

**Files NOT to modify:** Everything else. This is temporary instrumentation only.

---

## Changes

All log statements below use `ESP_LOGI` (not `LOGD`) so they appear at default log level. Tag: `"RFID_TRACE"`.

### 1. In `send_inventory_command()` — confirm command is actually sent

After the `send_command()` call (line ~261), add:

```c
ESP_LOGI("RFID_TRACE", "TX 0x89 channel=0x%02X", channel);
```

### 2. In `uart_rx_task()` — instrument every decision point

**a)** After `uart_read_bytes` returns (after line ~316), if `len > 0`, log the raw byte count and first 8 bytes:

```c
ESP_LOGI("RFID_TRACE", "RX %d bytes: %02X %02X %02X %02X %02X %02X %02X %02X",
         len,
         len > 0 ? rx_buf[0] : 0, len > 1 ? rx_buf[1] : 0,
         len > 2 ? rx_buf[2] : 0, len > 3 ? rx_buf[3] : 0,
         len > 4 ? rx_buf[4] : 0, len > 5 ? rx_buf[5] : 0,
         len > 6 ? rx_buf[6] : 0, len > 7 ? rx_buf[7] : 0);
```

**b)** Inside the frame parsing loop, after computing `frame_len_field` and `frame_total_bytes` (after line ~340), log:

```c
ESP_LOGI("RFID_TRACE", "FRAME at offset=%d: Len=0x%02X total=%d cmd=0x%02X",
         offset, frame_len_field, frame_total_bytes,
         (offset + 3 < len) ? rx_buf[offset + 3] : 0xFF);
```

**c)** After the checksum validation fails (the `offset++; continue;` path around line ~359), log:

```c
ESP_LOGI("RFID_TRACE", "CHECKSUM FAIL at offset=%d: calc=0x%02X recv=0x%02X",
         offset, calc_check, rx_buf[offset + frame_total_bytes - 1]);
```

(Place this BEFORE the `offset++; continue;`)

**d)** After `cmd_byte` is extracted (after line ~363), if `cmd_byte != R300_CMD_REAL_TIME_INVENTORY`, log:

```c
if (cmd_byte != R300_CMD_REAL_TIME_INVENTORY)
{
    ESP_LOGI("RFID_TRACE", "SKIP non-0x89 frame: cmd=0x%02X", cmd_byte);
}
```

**e)** Inside the `cmd_byte == R300_CMD_REAL_TIME_INVENTORY` block, at each branch:

Before the `frame_len_field > 0x08` check (line ~376), log:

```c
ESP_LOGI("RFID_TRACE", "0x89 frame: Len=0x%02X (tag threshold: >0x08, completion: ==0x08)", frame_len_field);
```

If the tag detection branch is entered (line ~378), log before calling `parse_realtime_tag`:

```c
ESP_LOGI("RFID_TRACE", "-> TAG packet, calling parse_realtime_tag (frame_bytes=%d)", frame_total_bytes);
```

If `parse_realtime_tag` returns false, log:

```c
ESP_LOGI("RFID_TRACE", "-> parse_realtime_tag REJECTED this packet");
```

If it returns true but `tag_callback` is NULL, log:

```c
if (!rfid_state.tag_callback)
{
    ESP_LOGI("RFID_TRACE", "-> tag_callback is NULL, detection dropped!");
}
```

If the completion branch is entered (line ~399), log:

```c
ESP_LOGI("RFID_TRACE", "-> ROUND COMPLETE, clearing round_in_progress");
```

If the `!rfid_state.inventory_active` discard branch is entered (line ~368), log:

```c
ESP_LOGI("RFID_TRACE", "-> DISCARD (inventory_active=false)");
```

### 3. In `parse_realtime_tag()` — log every rejection path

At each `return false` in the function, add a log statement immediately before it:

- Line ~138 (frame too short): already has `ESP_LOGD`. Change to `ESP_LOGI("RFID_TRACE", "parse: frame too short: %d < 17", len);`
- Line ~146 (invalid header/cmd): change to `ESP_LOGI("RFID_TRACE", "parse: bad header=0x%02X or cmd=0x%02X (expected 0x%02X)", data[0], data[3], R300_CMD_REAL_TIME_INVENTORY);`
- Line ~159 (incomplete packet): change to `ESP_LOGI("RFID_TRACE", "parse: incomplete: have %d need %d", len, packet_total_len);`
- Line ~171 (checksum mismatch): change to `ESP_LOGI("RFID_TRACE", "parse: checksum fail: calc=0x%02X recv=0x%02X", calc_check, data[packet_total_len - 1]);`
- Line ~197 (invalid EPC length): change to `ESP_LOGI("RFID_TRACE", "parse: bad EPC len=%d (PC=0x%04X)", event->epc_len, pc_word);`
- Line ~239 (all-zero EPC): change to `ESP_LOGI("RFID_TRACE", "parse: all-zero EPC rejected");`

At the successful `return true` (line ~244), add:

```c
ESP_LOGI("RFID_TRACE", "parse: SUCCESS epc_len=%d rssi=%d", event->epc_len, event->rssi);
```

### 4. In `rfid_reader_start_inventory()` — confirm callback is registered

After the callback is stored (where `rfid_state.tag_callback = callback;`), add:

```c
ESP_LOGI("RFID_TRACE", "start_inventory: callback=%p interval=%lu", (void *)callback, interval_ms);
```

---

## Acceptance Criteria

- [ ] `idf.py build` succeeds without warnings.
- [ ] All log statements use tag `"RFID_TRACE"` and level `ESP_LOGI`.
- [ ] Every decision point in the RX pipeline produces a log line.
- [ ] No behavioral changes — only logging added.
