# Task: Minimize IR Trigger-to-Scan Latency

## Problem

The current IR trigger path has three sequential blocking operations before `start_inventory()` is called, producing an observed ~2000ms delay from IR trip to active scanning:

| Step | Location | Delay |
|---|---|---|
| `RFID_POWER_STABILIZATION_MS` fixed delay | `rfid_reader_power_on()` in `rfid_reader.c` | ~500ms |
| `POWER_ON_GRACE_PERIOD_MS` fixed delay | IR trigger handler in `lighthouse.c` | ~500ms |
| Handshake (`get_firmware_version` 0x72) | IR trigger handler in `lighthouse.c` | up to ~1000ms |

None of these are necessary on the hot path. The only required check on trigger is confirming the reader power rail is live (GPIO22). Everything else is to be deferred to the post-scan or periodic health check.

---

## Solution: Poll-to-Ready Power-On

Replace all fixed delays and the handshake in the IR trigger path with a bounded poll loop on the power rail sense pin (GPIO22). The moment the rail goes high, `start_inventory()` is called directly.

The true reader hardware boot time is currently unknown — the existing delays were conservative guesses made when the handshake was the verification mechanism. The poll loop will reveal the actual boot time via elapsed-time logging, which can later be used to replace the loop with a single fixed delay if desired.

---

## Changes Required

### 1. `rfid_reader.c` — Split `rfid_reader_power_on()`

The existing `rfid_reader_power_on()` blocks for `RFID_POWER_STABILIZATION_MS` after asserting GPIO5. This delay must be removed from the function body and ownership handed to the caller.

Remove the `vTaskDelay(pdMS_TO_TICKS(RFID_POWER_STABILIZATION_MS))` call from `rfid_reader_power_on()`. The function should assert GPIO5 HIGH, update state to `RFID_STATE_STARTUP_PENDING`, and return immediately. The power rail sense check that follows in the existing implementation should also be removed from this function — it will be handled by the caller's poll loop.

The `RFID_POWER_STABILIZATION_MS` constant can be retained as a reference value but should no longer be used in the power-on function itself.

### 2. `rfid_reader.h` — Expose new state

Add `RFID_STATE_SCANNING` to the `rfid_reader_state_t` enum. This state represents the reader being active but not yet verified by a post-boot handshake. It is distinct from `RFID_STATE_RESPONSIVE`, which is reserved exclusively for states confirmed by a successful handshake (periodic health check path).

```
RFID_STATE_POWERED_OFF     → GPIO5 LOW, rail confirmed down
RFID_STATE_STARTUP_PENDING → GPIO5 HIGH, rail not yet confirmed
RFID_STATE_SCANNING        → Rail confirmed, inventory running, no handshake yet
RFID_STATE_RESPONSIVE      → Handshake confirmed (periodic health check only)
RFID_STATE_UNRESPONSIVE    → Powered but handshake failed
```

### 3. `lighthouse.c` — Replace IR trigger scan-start sequence

The current IR trigger handler calls `rfid_reader_power_on()`, waits a grace period, runs the handshake, then calls `start_inventory()`. Replace this entire sequence with the following logic:

**Step 1:** Call `rfid_reader_power_on()` (now returns immediately after asserting GPIO5).

**Step 2:** Enter a bounded poll loop reading GPIO22. Use `esp_timer_get_time()` for elapsed measurement (microsecond resolution per ESP32 TRM Section 17.3). Yield each iteration with `vTaskDelay(pdMS_TO_TICKS(1))` to avoid starving other tasks. On each iteration:
- If GPIO22 HIGH: log elapsed milliseconds at INFO level, break out of loop and proceed.
- If elapsed > timeout (2000ms): log error, abort — do not call `start_inventory()`, power off reader, return.

**Step 3:** Call `rfid_reader_start_inventory()` immediately after the rail is confirmed. Update state to `RFID_STATE_SCANNING`.

The handshake call and the `POWER_ON_GRACE_PERIOD_MS` delay are removed entirely from this path.

### 4. `lighthouse.c` — Handshake demotion

The handshake (`rfid_reader_handshake()`) is retained but demoted to two remaining call sites only:

- **Periodic health check task** (60s interval) — no change to this path.
- **Post-scan cleanup** — after `rfid_reader_stop_inventory()` is called and before `rfid_reader_power_off()`, optionally run the handshake to confirm state and log firmware version. This is non-blocking relative to any new scan trigger.

The `rfid_reader_handshake()` function itself requires no changes.

---

## Files to Modify

| File | Change |
|---|---|
| `rfid_reader.c` | Remove blocking delay from `rfid_reader_power_on()` |
| `rfid_reader.h` | Add `RFID_STATE_SCANNING` to state enum |
| `lighthouse.c` | Replace IR trigger scan-start sequence with poll-to-ready loop; remove handshake from trigger path |

---

## Verification

After implementation, the poll loop log output will give the true reader boot time. If measurements across several power cycles are consistent and fall below a known ceiling (e.g. consistently under 200ms), the poll loop can be replaced with a single `vTaskDelay` of that value plus a small margin, eliminating the polling overhead entirely. Measure first across several cycles before committing to a fixed value.

---

## Reference Documentation

- ESP32 TRM Section 17.3: `esp_timer_get_time()` — 64-bit microsecond counter, suitable for elapsed time measurement in polling loops
- ESP32 Datasheet Section 4.8.1: GPIO interface — digital input characteristics for GPIO22 power rail sense
- R300 Protocol V2.2 Section 2.1.3 (page 8): `get_firmware_version` command (0x72) — retained for periodic health check use only
