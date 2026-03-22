# Task: Fix Health Check UART Collision and IR Power-On Stabilization

**Purpose:** Scan windows intermittently produce zero tag detections despite the tag being in range. Root cause analysis of serial logs identified two issues:

1. **The health check task sends a firmware query (`cmd 0x72`) on UART2 while a `0x89` real-time inventory round is in progress.** This corrupts the inventory round — the module aborts the current round to respond to the `0x72`, no completion packet is sent for the `0x89` round, `round_in_progress` stays `true` permanently, and no further `0x89` commands are sent for the remainder of the scan window. This is a shared-UART collision.

2. **The IR fast-start path (`ir_trigger_start_scan` in `io_controller.c`) sends the first `0x89` command immediately after power rail confirmation with zero stabilization delay.** The R300 module needs time to initialize its RF subsystem after power-on. If the first `0x89` arrives before the module is ready, the module silently drops it, the `round_in_progress` flag gets set but no response ever comes, and the scan window is dead from the start.

**Files to modify:** `rfid_reader.c`, `io_controller.c`

**Files NOT to modify:** `rfid_reader.h`, `lighthouse.c`, or any other files. No public API changes.

---

## Part A — Prevent Health Check from Colliding with Active Inventory

### Step A.1: Guard `health_check_task()` in `rfid_reader.c`

The current implementation:

```c
static void health_check_task(void *arg)
{
    ESP_LOGI(TAG, "Health check task started (interval=%d ms)", HEALTH_CHECK_INTERVAL_MS);

    while (1)
    {
        vTaskDelay(pdMS_TO_TICKS(HEALTH_CHECK_INTERVAL_MS));

        ESP_LOGD(TAG, "Performing periodic health check...");
        rfid_reader_handshake(NULL, NULL);
    }
}
```

Add a guard at the top of the loop body that skips the handshake if inventory is active:

```c
while (1)
{
    vTaskDelay(pdMS_TO_TICKS(HEALTH_CHECK_INTERVAL_MS));

    // Do not send commands on the shared UART while inventory is active.
    // The 0x89 real-time inventory streams autonomously and any interleaved
    // command (e.g. 0x72 firmware query) aborts the current round, causing
    // round_in_progress to stay true permanently and killing the scan window.
    if (rfid_state.inventory_active)
    {
        ESP_LOGD(TAG, "Health check skipped — inventory active");
        continue;
    }

    ESP_LOGD(TAG, "Performing periodic health check...");
    rfid_reader_handshake(NULL, NULL);
}
```

This is the primary fix. The health check is a low-priority diagnostic; skipping it during a 5-second scan window is perfectly acceptable.

### Step A.2: Add a `round_in_progress` timeout as a safety net

In `uart_rx_task()`, the `round_in_progress` flag is set when a `0x89` command is sent and cleared when a completion packet arrives. If the completion packet is lost (due to UART corruption, module glitch, or any other transient issue), `round_in_progress` stays `true` forever and no new commands are sent.

Add a timeout: if `round_in_progress` has been `true` for longer than 2 seconds without any data arriving, force-clear it and allow a new `0x89` to be sent.

In `uart_rx_task()`, add a timestamp variable alongside the existing `round_in_progress`:

```c
bool     round_in_progress     = false;
uint32_t round_start_time_ms   = 0;
```

When `round_in_progress` is set to `true` (where `send_inventory_command()` is called), also record the time:

```c
send_inventory_command();
round_in_progress   = true;
round_start_time_ms = xTaskGetTickCount() * portTICK_PERIOD_MS;
last_read_time      = current_time;
```

In the command-sending guard at the top of the loop (the `if (rfid_state.inventory_active && !round_in_progress)` block), add a timeout check before it:

```c
// Safety net: if a round has been "in progress" for >2s with no completion
// packet, the round was likely aborted or lost. Force-clear to allow retry.
if (round_in_progress)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if ((now - round_start_time_ms) > 2000)
    {
        ESP_LOGW(TAG, "Round timeout — no completion packet after 2000ms, resetting");
        round_in_progress = false;
    }
}
```

Place this immediately before the existing `if (rfid_state.inventory_active && !round_in_progress)` check.

---

## Part B — Add Stabilization Delay After IR Power-On

### Step B.1: Add delay in `ir_trigger_start_scan()` in `io_controller.c`

The current implementation goes directly from power rail confirmation to `rfid_reader_start_inventory()`:

```c
// Step 2: Bounded poll on GPIO22 power-rail sense
...
    ESP_LOGI(TAG, "IR trigger: power rail HIGH after %lld ms", elapsed_ms);
    break;
}

// Step 3: Rail confirmed — start inventory immediately, no handshake.
esp_err_t ret = rfid_reader_start_inventory(tag_callback, 0);
```

Add a 200ms stabilization delay between Step 2 and Step 3. The R300 module's RF subsystem needs time to initialize after the power rail comes up — the power rail sense pin going HIGH only confirms the voltage regulator is supplying power, not that the module's internal firmware has completed its boot sequence.

```c
    ESP_LOGI(TAG, "IR trigger: power rail HIGH after %lld ms", elapsed_ms);
    break;
}

// Step 2.5: Wait for module RF subsystem to initialize after power-on.
// The power rail sense confirms voltage is present, but the R300 needs
// additional time to boot its internal firmware before it can process
// inventory commands. Without this delay, the first 0x89 may be silently
// dropped, causing a dead scan window.
vTaskDelay(pdMS_TO_TICKS(200));

// Step 3: Rail confirmed and stabilized — start inventory.
esp_err_t ret = rfid_reader_start_inventory(tag_callback, 0);
```

200ms is chosen based on observed behavior: the successful scan windows in the debug firmware had ~300ms between power-on and first tag detection, and the module's reset command documentation (§2.1.1) implies a startup sequence. 200ms provides margin without significantly impacting the user-perceived latency (the IR trigger already has some inherent delay from the PIR sensor's detection characteristics).

---

## Part C — Remove Trace Logging

### Step C.1: Remove all `RFID_TRACE` log statements

The diagnostic instrumentation from the previous task has served its purpose. Remove all `ESP_LOGI("RFID_TRACE", ...)` statements from `rfid_reader.c`. This includes all lines added in the "Add Diagnostic Logging to Real-Time Inventory Pipeline" task.

Do NOT remove the existing `ESP_LOGD(TAG, ...)` or `ESP_LOGI(TAG, ...)` statements that were present before the trace logging was added.

---

## Acceptance Criteria

### Part A (health check collision fix)
- [ ] `health_check_task()` skips the handshake when `rfid_state.inventory_active` is `true`.
- [ ] A `LOGD` message is emitted when the health check is skipped.
- [ ] `round_in_progress` has a 2-second timeout that force-clears it with a `LOGW`.
- [ ] `round_start_time_ms` is set when a `0x89` command is sent.
- [ ] The timeout check runs every loop iteration, before the command-sending guard.

### Part B (IR stabilization delay)
- [ ] A `vTaskDelay(pdMS_TO_TICKS(200))` is present between power rail confirmation and `start_inventory()` in `ir_trigger_start_scan()`.
- [ ] The delay has a comment explaining why it exists.

### Part C (trace removal)
- [ ] No `RFID_TRACE` tagged log statements remain in `rfid_reader.c`.
- [ ] Existing `ESP_LOGD`/`ESP_LOGI` with tag `RFID` are preserved.

### General
- [ ] `idf.py build` succeeds without warnings.
- [ ] Multiple consecutive IR-triggered scan windows produce tag detections consistently when the tag is in range (no more intermittent dead windows).
