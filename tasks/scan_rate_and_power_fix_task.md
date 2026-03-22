# Task: Fix set_power Response Handling & Improve Scan Rate with Real-Time Inventory

**Files to modify:** `rfid_reader.h`, `rfid_reader.c`

**Files NOT to modify:** `io_controller.c`, `io_controller.h`, `lighthouse.c`, or any other files. The changes are entirely within the RFID reader module. Callers use the same public API; the inventory mode switch is internal.

**Protocol Reference:** R300 UHF RFID Serial Interface Protocol V2.2

---

## Context

Two issues discovered during RF debugging:

1. **`rfid_reader_set_power()` does not read the module's response.** It reports success based on UART write alone. The module has been silently rejecting `set_power(33)` with error `0x48` (OUTPUT_POWER_OUT_OF_RANGE) on every boot — the actual hardware maximum is 25 dBm. The function must read the response, check for `0x10` (command_success), and return an appropriate error if the module rejects the value.

2. **Scan rate is too low for direction detection.** The current `0x8B` polling mode at 250ms yields 3–5 tag detections per 5-second IR window. The direction detection algorithm (Phase 2 of server implementation) needs 10–20 detections per walk-past. Real-time inventory (`cmd 0x89`, §2.2.8, p.27) with `channel=0xFF` was tested in the debug firmware and produces 10–12 detections per ~600ms round, which is a dramatic improvement.

Both fixes are in `rfid_reader.c` / `rfid_reader.h` only.

---

## Part A — Fix `rfid_reader_set_power()` Response Handling

### Step A.1: Update `rfid_reader_set_power()` in `rfid_reader.c`

The current implementation:

```c
esp_err_t rfid_reader_set_power(uint8_t power_dbm)
{
    if (!rfid_state.initialized) return ESP_ERR_INVALID_STATE;
    if (power_dbm < 20) power_dbm = 20;
    if (power_dbm > 33) power_dbm = 33;

    esp_err_t ret = send_command(R300_CMD_SET_POWER, &power_dbm, 1);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Set power to %d dBm", power_dbm);
    }
    return ret;
}
```

Replace with a version that reads and validates the response:

1. Flush the UART RX buffer before sending.
2. Send `cmd 0x76` with the 1-byte power value.
3. Read response with 1-second timeout.
4. Validate: `rx_buf[0] == R300_FRAME_HEAD`, `rx_buf[3] == R300_CMD_SET_POWER` (0x76), `rx_buf[4] == 0x10` (command_success).
5. If `rx_buf[4] != 0x10`, log the error code at WARN level and return `ESP_ERR_INVALID_RESPONSE` (or `ESP_FAIL`).
6. If timeout (no response), return `ESP_ERR_TIMEOUT`.
7. On success, log the confirmed power level.

**Protocol reference:** §2.1.7, p.12. Success response: `[0xA0][0x04][Addr][0x76][0x10][Check]`. Failure response: same frame with Error_Code in byte [4]. Known error codes: `0x25` (set_output_power_error), `0x48` (output_power_out_of_range), `0x54` (fail_to_achieve_desired_output_power). See §3 Error Codes, p.39–40.

Follow the same response-reading pattern used by `rfid_reader_set_beeper_mode()` and `rfid_reader_get_firmware()`.

### Step A.2: Clamp maximum power to 25 dBm

Change the upper clamp from 33 to 25:

```c
if (power_dbm > 25) power_dbm = 25;
```

The YPD-R300 module variant in this project has a confirmed hardware maximum of 25 dBm. Values 26–33 are rejected with `0x48`. Clamping at 25 prevents the module from rejecting the command and ensures the log output is honest.

Update the doc comment on the function declaration in `rfid_reader.h` to reflect the actual range (20–25 dBm) and note that the R300 spec says 20–33 but this hardware variant caps at 25.

### Step A.3: Update callers

Search for any call to `rfid_reader_set_power()` that passes a value above 25 (the normal init sequence passes 33). Change the argument to 25. If the call site checks the return value and logs on failure, that's sufficient — no other change needed at the call site.

**Note:** The call site may be in `lighthouse.c` or `io_controller.c`. Change only the argument value and adjust the log message string if it mentions "33 dBm". Do not restructure the surrounding code.

---

## Part B — Switch to Real-Time Inventory (`cmd 0x89`) for Higher Scan Rate

### Overview

Replace the `0x8B` polling-based inventory with `0x89` real-time inventory as the active scanning mode. This changes the internal behavior of `rfid_reader_start_inventory()` and `uart_rx_task()` while keeping the public API identical — callers still call `start_inventory(callback, interval_ms)` and `stop_inventory()` the same way.

The `interval_ms` parameter becomes the delay between consecutive `0x89` round restarts (how long to wait after a round completes before sending the next `0x89` command). The minimum effective value is 10ms (to prevent command flooding, per DEVLOG_2025_12_17). If `interval_ms` is 0, use 10ms.

### Step B.1: Add protocol constants in `rfid_reader.c`

Add alongside the existing command defines:

```c
#define R300_CMD_REAL_TIME_INVENTORY  0x89  // §2.2.8, p.27
#define R300_REAL_TIME_CHANNEL_ALL    0xFF  // All channels, fastest mode (30-50ms rounds)
```

Note: `R300_CMD_REAL_TIME_INVENTORY` may already exist from the debug task. If so, do not duplicate it. If it's in `rfid_reader.h`, that's fine too — just use it.

### Step B.2: Modify `send_inventory_command()` in `rfid_reader.c`

Current implementation sends `0x8B`:

```c
static void send_inventory_command(void)
{
    if (rfid_state.inventory_active)
    {
        uint8_t params[3] = {0x00, 0x00, 0x01};
        send_command(R300_CMD_INVENTORY_SINGLE, params, 3);
    }
}
```

Change to send `0x89` with `channel=0xFF`:

```c
static void send_inventory_command(void)
{
    if (rfid_state.inventory_active)
    {
        // Real-time inventory (cmd 0x89, §2.2.8, p.27)
        // Channel=0xFF: all frequency hopping channels, fastest mode (30-50ms rounds)
        // Tag data streamed in real time with RSSI, not buffered internally
        uint8_t channel = R300_REAL_TIME_CHANNEL_ALL;
        send_command(R300_CMD_REAL_TIME_INVENTORY, &channel, 1);
    }
}
```

### Step B.3: Modify `uart_rx_task()` to handle `0x89` responses

The `0x89` response format differs from `0x8B`. A single `0x89` round produces:

- **Zero or more tag detection packets:** `[0xA0][Len][Addr][0x89][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]` where `Len > 0x08`
- **One round completion packet:** `[0xA0][0x08][Addr][0x89][Ant_ID][Total_Read(4)][Check]` where `Len == 0x08`

The UART RX buffer may contain multiple concatenated frames from a single round. Each frame's total byte length is `rx_buf[1] + 2` (the Len field value plus the Head and Len bytes themselves).

**Changes to `uart_rx_task()`:**

The current task structure is a loop that: (a) sends an inventory command at the configured interval, (b) reads UART with a 50ms timeout, (c) attempts to parse a single `0x8B` response.

Modify as follows:

**a) Command sending logic:** Keep the interval-based sending, but change the interval semantics. After a round completion packet is received, wait `read_interval_ms` before sending the next `0x89`. Between command send and round completion, do NOT send additional commands — `0x89` streams autonomously until the round finishes. Use a boolean flag `round_in_progress` to track this:

```
if inventory_active AND NOT round_in_progress:
    if (current_time - last_read_time) >= interval:
        send_inventory_command()
        round_in_progress = true
        last_read_time = current_time
```

**b) Response parsing:** Replace the existing single-frame `parse_inventory_response()` call with a multi-frame parser that processes all complete frames in the RX buffer:

```
offset = 0
while offset < len:
    if rx_buf[offset] != 0xA0:
        offset++
        continue  // skip garbage bytes, resync on frame header

    if offset + 1 >= len:
        break  // incomplete, need more data

    frame_len = rx_buf[offset + 1] + 2  // total bytes for this frame

    if offset + frame_len > len:
        break  // incomplete frame, need more data

    // Validate checksum
    calc_check = r300_checksum(&rx_buf[offset], frame_len - 1)
    if calc_check != rx_buf[offset + frame_len - 1]:
        offset++
        continue  // bad checksum, skip and resync

    cmd_byte = rx_buf[offset + 3]

    if cmd_byte == 0x89:
        pkt_len_field = rx_buf[offset + 1]

        if pkt_len_field > 0x06:
            // Tag detection packet — parse tag data
            // Freq_Ant at offset+4, PC at offset+5..6, EPC at offset+7.., RSSI at offset+frame_len-2
            parse_realtime_tag(&rx_buf[offset], frame_len, &event)
            // invoke callback if valid

        else if pkt_len_field == 0x06:
            // Round completion packet
            // Ant_ID at offset+4, Total_Read (4 bytes) at offset+5..8
            round_in_progress = false
            // log round stats at DEBUG level

    offset += frame_len
```

**c) Tag detection parsing for `0x89`:** Create a new static function `parse_realtime_tag()` (or adapt the existing `parse_inventory_response()`). The frame layout per §2.2.8:

| Offset | Field | Size |
|---|---|---|
| 0 | Head (0xA0) | 1 |
| 1 | Len | 1 |
| 2 | Address | 1 |
| 3 | Cmd (0x89) | 1 |
| 4 | Freq_Ant | 1 (high 6 bits = freq param, low 2 bits = antenna ID) |
| 5–6 | PC | 2 |
| 7 to Len+2-3 | EPC | N bytes (derived from Len: `epc_len = Len - 6`) |
| Len+2-2 | RSSI | 1 |
| Len+2-1 | Check | 1 |

The EPC length can also be cross-checked against the PC word: bits 15–11 of PC give the EPC length in 16-bit words. Use whichever validation logic the existing `parse_inventory_response()` uses — the field layout is the same between `0x8B` and `0x89` from Freq_Ant onward.

Apply the same validation rules as the existing parser: RSSI range 31–98 (§5, p.42), minimum EPC length 8 bytes, reject all-zero EPCs.

Fill the `rfid_tag_event_t` struct and invoke `rfid_state.tag_callback()` exactly as the current code does for `0x8B` detections.

**d) Antenna missing error (0x22):** If the antenna connection detector is enabled and the antenna is disconnected, `0x89` returns `[0xA0][0x05][Addr][0x89][Ant_ID][0x22][Check]` (§2.2.9, p.29 — same error format applies to 0x89). Check for `pkt_len_field == 0x03` with `rx_buf[offset + 5] == 0x22` and log at ERROR level. Treat as round completion (set `round_in_progress = false`).

### Step B.4: Update interval defaults

Change the defaults to match `0x89` behavior:

```c
#define DEFAULT_READ_INTERVAL_MS 10   // was 250; delay between 0x89 rounds
#define MIN_READ_INTERVAL_MS     10   // was 50; 10ms minimum per DEVLOG_2025_12_17
```

The `start_inventory(callback, interval_ms)` call from `io_controller.c` currently passes `0` which triggers the default. With the new default of 10ms, consecutive `0x89` rounds will fire as fast as possible with just enough delay to prevent command flooding. No change needed at the call site.

### Step B.5: Ensure clean stop

`rfid_reader_stop_inventory()` currently sets `inventory_active = false` and waits 50ms for the RX task to see the flag. This is sufficient — when the RX task sees `inventory_active == false`, it stops sending new `0x89` commands. The current round may still produce a few more tag packets before the completion packet arrives, but those will be processed normally by the callback. No change needed to `stop_inventory()`.

However, if the module is mid-round when stop is called, the completion packet will arrive after the active flag is cleared. The RX task should handle this gracefully — just discard tag packets and completion packets when `inventory_active == false`. Add a guard at the top of the tag detection handling:

```c
if (!rfid_state.inventory_active)
{
    // Draining residual packets after stop — discard
    offset += frame_len;
    continue;
}
```

---

## Acceptance Criteria

### Part A (set_power fix)
- [ ] `rfid_reader_set_power()` reads the module response and checks byte [4] for `0x10`.
- [ ] Returns `ESP_FAIL` or `ESP_ERR_INVALID_RESPONSE` if the module returns an error code.
- [ ] Returns `ESP_ERR_TIMEOUT` if no response received.
- [ ] Power clamped to 20–25 dBm range.
- [ ] Doc comment in `rfid_reader.h` updated to reflect 20–25 range and note hardware cap.
- [ ] Any call site passing 33 is changed to 25.
- [ ] `idf.py build` succeeds without warnings.

### Part B (scan rate improvement)
- [ ] `send_inventory_command()` sends `cmd 0x89` with `channel=0xFF`.
- [ ] `uart_rx_task()` correctly parses multi-frame `0x89` responses (tag packets + completion packet).
- [ ] Tag detections invoke `rfid_state.tag_callback()` with correctly populated `rfid_tag_event_t`.
- [ ] Round completion sets `round_in_progress = false` and logs at DEBUG level.
- [ ] RSSI validation (range 31–98), EPC length validation (min 8 bytes), and all-zero rejection remain in effect.
- [ ] Antenna missing error (`0x22`) logged at ERROR level.
- [ ] Default interval changed to 10ms.
- [ ] `stop_inventory()` works cleanly — no stale callbacks after stop returns.
- [ ] The public API (`start_inventory`, `stop_inventory`, `is_inventory_active`, `get_stats`) is unchanged in signature.
- [ ] `idf.py build` succeeds without warnings.
- [ ] Tag detection rate during a 5-second IR scan window is measurably higher than the previous `0x8B` polling mode (target: 10+ detections per walk-past at the good unit's working range).

---

## Files Summary

| File | Changes |
|---|---|
| `rfid_reader.h` | Update `set_power` doc comment (20–25 range, hardware cap note). Add `R300_CMD_REAL_TIME_INVENTORY` define if not already present. |
| `rfid_reader.c` | Rewrite `set_power()` with response reading. Change `send_inventory_command()` to use `0x89`. Rewrite `uart_rx_task()` response parsing for multi-frame `0x89` format. Update interval defaults. Add `parse_realtime_tag()` or adapt existing parser. |
| Call site (likely `lighthouse.c` or `io_controller.c`) | Change `set_power(33)` argument to `25`. |
