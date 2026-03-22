# Task: RFID RF Debug Mode Firmware

**Purpose:** Temporary diagnostic firmware to isolate the cause of degraded RF read range on Lighthouse Unit B. This replaces the normal application flow with a sequential series of R300 module queries and a continuous RSSI-reporting inventory loop, outputting all results to the serial console.

**Files to modify:** `rfid_reader.h`, `rfid_reader.c`, `lighthouse.c`

**Files NOT to modify:** All other source files. No changes to WiFi, MQTT, provisioning, IR sensor, battery monitor, or offline cache logic.

**Protocol Reference:** R300 UHF RFID Serial Interface Protocol V2.2

---

## Overview

The debug mode replaces `app_main()`'s normal startup with a linear diagnostic sequence. It is gated behind a compile-time flag so it can be cleanly removed after debugging is complete.

The diagnostic sequence is:

1. Initialize UART and power on the RFID reader (existing code path)
2. Query and log: firmware version, output power, frequency region, working antenna, antenna connection detector status, module temperature
3. Enable the antenna connection detector
4. Run a continuous real-time inventory (`cmd 0x89`) logging every tag detection with full RSSI decode
5. Loop forever (Ctrl+C / power cycle to stop)

No WiFi, MQTT, NTP, IR sensor, battery monitor, or LED logic runs in debug mode.

---

## Step 1 — Add compile-time gate and new command constants

### `rfid_reader.h`

Add to the existing command constant block (do NOT reorganize or rename existing defines):

```c
// --- RF Debug Mode commands (R300 Protocol V2.2) ---
// §2.1.8, p.13: Query current RF output power
#define R300_CMD_GET_POWER              0x77
// §2.1.10, p.13: Query current RF frequency region
#define R300_CMD_GET_FREQUENCY          0x79
// §2.1.6, p.11: Query current working antenna
#define R300_CMD_GET_WORK_ANTENNA       0x75
// §2.1.18, p.20: Query antenna connection detector status
#define R300_CMD_GET_ANT_DETECTOR       0x63
// §2.1.17, p.19: Set antenna connection detector on/off
#define R300_CMD_SET_ANT_DETECTOR       0x62
// §2.1.12, p.14: Query reader internal temperature
#define R300_CMD_GET_TEMPERATURE        0x7B
// §2.2.8, p.27: Real-time inventory (streams tag data with RSSI)
#define R300_CMD_REAL_TIME_INVENTORY    0x89
```

Add function declarations:

```c
/**
 * RF Debug Mode diagnostic queries.
 * These are intentionally simple request/response wrappers
 * that log results directly — not designed for production use.
 *
 * All functions follow the same pattern:
 *   1. Flush UART RX
 *   2. send_command()
 *   3. Read response with 1s timeout
 *   4. Log the raw response and parsed value at INFO level
 *   5. Return ESP_OK / ESP_ERR_TIMEOUT
 */
esp_err_t rfid_debug_get_output_power(void);
esp_err_t rfid_debug_get_frequency_region(void);
esp_err_t rfid_debug_get_work_antenna(void);
esp_err_t rfid_debug_get_ant_detector_status(void);
esp_err_t rfid_debug_set_ant_detector(bool enable);
esp_err_t rfid_debug_get_temperature(void);

/**
 * Start real-time inventory with RSSI logging.
 * Uses cmd 0x89 (§2.2.8) instead of the normal 0x8B single inventory.
 * Logs every tag detection with EPC (hex), raw RSSI byte, decoded dBm,
 * antenna ID, and frequency parameter.
 *
 * This function does NOT return — it loops sending 0x89 rounds and
 * parsing responses until the device is power-cycled.
 *
 * @param channel  Frequency hopping channel count (0xFF = fastest/all)
 */
void rfid_debug_continuous_rssi_inventory(uint8_t channel);
```

### `rfid_reader.c`

At the top of the file, alongside the existing `#define` block, add nothing — the command constants live in the header. However, **`send_command()` is currently `static`**. It must remain static. The new debug functions are implemented inside `rfid_reader.c` where they have access to `send_command()` and `rfid_state`.

---

## Step 2 — Implement debug query functions in `rfid_reader.c`

Add all six query functions at the bottom of `rfid_reader.c`, before any `#endif` guards but after all existing functions. Each follows the same pattern established by `rfid_reader_get_firmware()` and `rfid_reader_set_beeper_mode()`.

### 2.1 `rfid_debug_get_output_power`

**Protocol:** `cmd 0x77` — no payload. Response: `[0xA0][0x04][Addr][0x77][Output_Power][Check]` (§2.1.8, p.13)

Parse `rx_buf[4]` as the power value in dBm. Log:
```
RFID_DBG: Output Power = XX dBm (raw: 0xYY)
```

Valid range per §2.1.7 is 20–33 (0x14–0x21). Log a warning if outside this range.

### 2.2 `rfid_debug_get_frequency_region`

**Protocol:** `cmd 0x79` — no payload. Response: `[0xA0][Len][Addr][0x79][Region][StartFreq][EndFreq][Check]` (§2.1.10, p.13)

Parse `rx_buf[4]` as region (0x01=FCC, 0x02=ETSI, 0x03=CHN), `rx_buf[5]` as start freq, `rx_buf[6]` as end freq. Log:
```
RFID_DBG: Frequency Region = FCC/ETSI/CHN (0xRR), Start=0xSS, End=0xEE
```

### 2.3 `rfid_debug_get_work_antenna`

**Protocol:** `cmd 0x75` — no payload. Response: `[0xA0][0x04][Addr][0x75][Antenna_ID][Check]` (§2.1.6, p.11)

Parse `rx_buf[4]` as antenna ID (0x00–0x03). Log:
```
RFID_DBG: Working Antenna = Antenna X (0xYY)
```

### 2.4 `rfid_debug_get_ant_detector_status`

**Protocol:** `cmd 0x63` — no payload. Response: `[0xA0][0x04][Addr][0x63][DetectorStatus][Check]` (§2.1.18, p.20)

Parse `rx_buf[4]`: 0x00 = closed/disabled, 0x01 = open/enabled. Log:
```
RFID_DBG: Antenna Connection Detector = ENABLED/DISABLED (0xYY)
```

### 2.5 `rfid_debug_set_ant_detector`

**Protocol:** `cmd 0x62` — 1-byte payload (0x00=close, 0x01=open). Response: `[0xA0][0x04][Addr][0x62][Error_Code][Check]` (§2.1.17, p.19)

Check `rx_buf[4]` for `0x10` (command_success). Log:
```
RFID_DBG: Antenna Connection Detector SET to ENABLED/DISABLED — result: SUCCESS/FAIL (0xYY)
```

### 2.6 `rfid_debug_get_temperature`

**Protocol:** `cmd 0x7B` — no payload. Response: `[0xA0][0x04][Addr][0x7B][Temperature][Check]` (§2.1.12, p.14)

Parse `rx_buf[4]` as signed temperature in °C. Log:
```
RFID_DBG: Module Temperature = XX °C (raw: 0xYY)
```

---

## Step 3 — Implement continuous RSSI inventory in `rfid_reader.c`

### `rfid_debug_continuous_rssi_inventory`

This is the core diagnostic loop. It uses `cmd 0x89` (real-time inventory, §2.2.8, p.27) which, unlike the normal `0x8B` single inventory, streams tag data in real time with RSSI and frequency data per detection.

**Implementation outline:**

1. Guard on `rfid_state.initialized`.
2. Log a header banner:
   ```
   RFID_DBG: === CONTINUOUS RSSI INVENTORY START (channel=0xCC) ===
   RFID_DBG: Format: [EPC_hex] RSSI=0xRR (−XX dBm) Ant=A Freq=0xFF
   RFID_DBG: Waiting for tags... (power cycle to stop)
   ```
3. Enter infinite loop:
   a. Flush UART RX buffer.
   b. Send `cmd 0x89` with `channel` parameter (1 byte).
   c. Read responses in a polling loop with 100ms timeout per read.
   d. For each received frame:
      - If `rx_buf[3] == 0x89` and `Len > 0x08` → tag detection packet.
        Parse per §2.2.8 response format:
        - `Freq_Ant` byte: high 6 bits = frequency param, low 2 bits = antenna ID
        - `PC`: 2 bytes
        - `EPC`: N bytes (length derived from Len field)
        - `RSSI`: 1 byte before checksum
        
        Decode RSSI to dBm using the lookup logic from §5, p.42 (the RSSI parameter reference table). For the log output, a simple linear approximation is acceptable: `dBm ≈ rssi_raw - 129` which is close enough for comparative debugging. Alternatively, use the exact table if a lookup array is preferred.

        Log each detection:
        ```
        RFID_DBG: TAG [E200...1234] RSSI=0x4A (−56 dBm) Ant=0 Freq=0x0F
        ```
      - If `rx_buf[3] == 0x89` and `Len == 0x08` → inventory round completion packet.
        Parse `Ant_ID` and `Total_Read` (4 bytes). Log:
        ```
        RFID_DBG: ROUND COMPLETE Ant=X TotalReads=NNNN
        ```
      - If `rx_buf[4]` in any response is `0x22` → antenna missing error.
        Log prominently:
        ```
        RFID_DBG: *** ANTENNA MISSING ERROR (0x22) on Ant=X ***
        ```
        This is the key diagnostic outcome from the antenna connection detector (§3, p.39).
   e. After round completion, `vTaskDelay(pdMS_TO_TICKS(10))` then restart loop.

**Important parsing note:** The real-time inventory can return multiple tag packets per round before the completion packet. The UART RX buffer may contain multiple concatenated frames. Parse frame-by-frame using the `Len` field to determine each frame's boundary: `frame_total_bytes = rx_buf[1] + 2` (Len value + Head byte + Len byte itself).

---

## Step 4 — Add debug mode entry point in `lighthouse.c`

### Compile-time gate

At the top of `lighthouse.c`, add:

```c
// Uncomment to build RF debug firmware (replaces normal operation)
// #define RF_DEBUG_MODE
```

### Conditional `app_main()`

Wrap the debug flow in `#ifdef RF_DEBUG_MODE` inside `app_main()`. The debug path should:

1. Initialize NVS (required by ESP-IDF).
2. Call `rfid_reader_init()` — this sets up UART2 and GPIO, performs the handshake, and sets beeper mode.
3. Call `rfid_reader_power_on()`.
4. Wait 500ms for reader stabilization (`vTaskDelay(pdMS_TO_TICKS(500))`).
5. Log a clear banner:
   ```
   ╔══════════════════════════════════════════════╗
   ║         LIGHTHOUSE RF DEBUG MODE             ║
   ╠══════════════════════════════════════════════╣
   ║  WiFi/MQTT/NTP/IR — DISABLED                ║
   ║  Running R300 RF diagnostics only            ║
   ╚══════════════════════════════════════════════╝
   ```
6. Run each diagnostic query in sequence with a 100ms delay between each:
   ```c
   rfid_debug_get_output_power();
   vTaskDelay(pdMS_TO_TICKS(100));
   rfid_debug_get_frequency_region();
   vTaskDelay(pdMS_TO_TICKS(100));
   rfid_debug_get_work_antenna();
   vTaskDelay(pdMS_TO_TICKS(100));
   rfid_debug_get_temperature();
   vTaskDelay(pdMS_TO_TICKS(100));
   rfid_debug_get_ant_detector_status();
   vTaskDelay(pdMS_TO_TICKS(100));
   rfid_debug_set_ant_detector(true);  // Enable detector before inventory
   vTaskDelay(pdMS_TO_TICKS(100));
   ```
7. Log separator, then enter the continuous inventory:
   ```c
   rfid_debug_continuous_rssi_inventory(0xFF);  // All channels, fastest mode
   ```
8. The function above never returns. No code after it will execute.
9. The `#else` branch contains the existing `app_main()` body, completely untouched.

### Structure in `lighthouse.c`

```c
void app_main(void)
{
#ifdef RF_DEBUG_MODE
    // ... debug sequence above ...
#else
    // ... entire existing app_main body, unchanged ...
#endif
}
```

**Critical:** The `#else` branch must contain the existing code exactly as-is. Do not refactor, re-indent, or reorganize it.

---

## Acceptance Criteria

- [ ] `#define RF_DEBUG_MODE` is **commented out** by default — normal firmware builds are unaffected.
- [ ] When `RF_DEBUG_MODE` is uncommented and built, serial output shows:
  - Banner identifying debug mode
  - Output power (dBm), frequency region, working antenna, temperature, antenna detector status — one line each
  - Antenna detector enabled confirmation
  - Continuous tag detections with EPC, RSSI (hex + dBm), antenna ID, frequency param
  - Inventory round completion summaries
  - Antenna missing error (0x22) prominently flagged if it occurs
- [ ] No WiFi, MQTT, NTP, IR sensor, battery, or LED code executes in debug mode.
- [ ] `idf.py build` succeeds without warnings in both `RF_DEBUG_MODE` and normal mode.
- [ ] All new `#define` constants include a comment citing the R300 Protocol V2.2 section and page number.
- [ ] No existing functions are renamed, reordered, or have their signatures changed.
- [ ] `send_command()` remains `static` — debug functions are inside `rfid_reader.c`.
- [ ] The `#else` branch of `app_main()` is byte-for-byte identical to the current `app_main()` body.

---

## Usage

1. Uncomment `#define RF_DEBUG_MODE` in `lighthouse.c`.
2. `idf.py build && idf.py flash monitor`
3. Observe serial output. Compare results between the good and bad unit.
4. When done, re-comment `#define RF_DEBUG_MODE` and rebuild for normal operation.

---

## What to look for in the output

Comparing the serial output from both units side by side:

| Field | If different → likely cause |
|---|---|
| Output Power | Configuration divergence — set to 30+ dBm and retest |
| Frequency Region | Configuration divergence — match to good unit |
| Working Antenna | Wrong antenna selected — set to Antenna 1 (0x00) |
| Temperature | Significant difference (>15°C) suggests impedance mismatch / reflected power |
| Antenna detector fires 0x22 | Physical antenna connection fault — inspect IPEX connector |
| RSSI at same tag distance | >6 dB gap confirms RF chain loss — proceed to physical antenna swap test |
