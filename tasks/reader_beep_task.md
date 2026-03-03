# Task: Disable Reader Buzzer on Startup

**Files to modify:** `uart_reader.h`, `uart_reader.c`

**Protocol Reference:** R300 UHF RFID Serial Interface Protocol V2.2, Section 2.1.11 (`cmd_name_set_beeper_mode`, page 14-15)

---

## Step 1 — Add command constant (`uart_reader.h`)

Add `R300_CMD_SET_BEEPER_MODE` alongside the existing command defines. Also define the mode values for clarity:

```
R300_CMD_SET_BEEPER_MODE   0x7A
R300_BEEPER_MODE_QUIET     0x00
R300_BEEPER_MODE_PER_ROUND 0x01
R300_BEEPER_MODE_PER_TAG   0x02
```

Declare the public function with a doc comment referencing Protocol V2.2, Section 2.1.11.

---

## Step 2 — Implement `rfid_reader_set_beeper_mode()` (`uart_reader.c`)

Follow the same pattern as `rfid_reader_get_firmware()`:

1. Guard on `rfid_state.initialized`.
2. `uart_flush()` the RX buffer.
3. Call `send_command(R300_CMD_SET_BEEPER_MODE, &mode, 1)`.
4. Read response with a 1-second timeout.
5. Validate: `rx_buf[0] == R300_FRAME_HEAD` and `rx_buf[3] == R300_CMD_SET_BEEPER_MODE`.
6. Return `ESP_OK` on success, `ESP_ERR_TIMEOUT` if no valid response received.

**Note from protocol:** On success the module stores the value to internal flash — it persists across power cycles (Section 2.1.11). Mode `0x02` is explicitly noted to degrade anti-collision performance; it must not be used here.

---

## Step 3 — Call during initialization (`uart_reader.c`)

In `rfid_reader_init()`, after `rfid_reader_handshake()` succeeds, call:

```c
esp_err_t beeper_ret = rfid_reader_set_beeper_mode(R300_BEEPER_MODE_QUIET);
if (beeper_ret != ESP_OK) {
    ESP_LOGW(TAG, "Failed to set beeper mode (non-fatal): %s", esp_err_to_name(beeper_ret));
}
```

Failure must not block or fail initialization — log a warning and continue.

---

## Acceptance Criteria

- [ ] Reader does not beep during normal inventory operation.
- [ ] `idf.py build` completes without warnings.
- [ ] Failure to set mode produces a `LOGW` and does not affect initialization return value.
- [ ] Command constant documented with reference to Protocol V2.2, Section 2.1.11.
