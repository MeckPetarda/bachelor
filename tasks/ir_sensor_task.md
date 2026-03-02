# Task: IR Sensor Scan Trigger Implementation

## Objective

Integrate the AM312 PIR sensor on GPIO26 as a scan trigger. On a rising edge detection, a
time-bounded RFID scan burst starts and runs for `IR_SCAN_DURATION_MS` (default 5000ms).
Subsequent IR triggers while a burst is active restart the timer without interrupting the
ongoing inventory. A button-owned scan is not affected by IR triggers.

---

## Files to Modify

- `src/lighthouse/main/lighthouse.c`

No other files require changes.

---

## Step 1: Pin and Timing Constants

**Location:** Pin definition block at the top of `lighthouse.c`, alongside existing
`WIFI_STATUS_LED`, `BUTTON1_PIN`, etc.

**Add:**

```c
#define IR_SENSOR_PIN        GPIO_NUM_26
#define IR_SCAN_DURATION_MS  5000        // Duration of IR-triggered scan burst (ms)
                                         // Adjustable: increase for longer detection windows
```

---

## Step 2: State Variables

**Location:** State tracking section in `lighthouse.c`, alongside the existing `rfid_scanning`
and `mqtt_initialized` booleans.

**Add:**

```c
static volatile bool ir_trigger_pending  = false;  // Set in ISR, cleared in main loop
static bool          ir_scan_active      = false;   // true = current scan was IR-initiated
static uint32_t      ir_scan_end_time_ms = 0;       // Tick timestamp when burst should stop
```

`ir_trigger_pending` is `volatile` because it is written in ISR context and read in task
context. Per ESP32 TRM Section 6 (GPIO Matrix), ISR handlers run outside normal task
scheduling and compiler reordering must be prevented.

---

## Step 3: ISR Handler

**Location:** Add as a new static function above `gpio_init()` in `lighthouse.c`.

The handler must be placed in IRAM to guarantee execution even during flash cache misses.
This is the standard ESP-IDF requirement for GPIO ISR handlers — see ESP32 TRM Section 6,
`GPIO_PINn_INT_ENA` register description, and ESP-IDF Programming Guide (GPIO & RTC GPIO,
"GPIO Interrupt").

```c
static void IRAM_ATTR ir_sensor_isr_handler(void *arg)
{
    ir_trigger_pending = true;
    // No task notification needed — main loop polls ir_trigger_pending every 10ms
}
```

Task notification via `vTaskNotifyGiveFromISR` is omitted deliberately. The main loop
already runs on a 10ms tick (`vTaskDelay(pdMS_TO_TICKS(10))`), making the polling latency
acceptable and avoiding the added complexity of a notification + wakeup path.

---

## Step 4: GPIO Configuration

**Location:** Inside `gpio_init()` in `lighthouse.c`, after the existing button configuration
block.

**Add the following in two parts:**

**4a — Pin configuration:**

Configure GPIO26 as input with internal pull-down enabled and rising-edge interrupt type.
Pull-down is required to guarantee a defined LOW idle state on the AM312 output pin. Per
ESP32 Datasheet Section 4.2, Table 4-2, GPIO26 supports internal pull-down. Per ESP32 TRM
Section 6 (`GPIO_PINn_REG`, `GPIO_PINn_INT_TYPE` field), rising edge interrupt corresponds
to type `0x01`.

```c
gpio_config_t ir_config = {
    .pin_bit_mask = (1ULL << IR_SENSOR_PIN),
    .mode         = GPIO_MODE_INPUT,
    .pull_up_en   = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,
    .intr_type    = GPIO_INTR_POSEDGE,
};
gpio_config(&ir_config);
```

**4b — ISR service and handler registration:**

`gpio_install_isr_service` is not currently called anywhere in `lighthouse.c`. It must be
called once before any `gpio_isr_handler_add` calls. Flag `0` uses the default ISR
allocation (non-IRAM-safe service, which is fine here since the handler itself is
`IRAM_ATTR`).

```c
gpio_install_isr_service(0);
gpio_isr_handler_add(IR_SENSOR_PIN, ir_sensor_isr_handler, NULL);
```

Add a log line consistent with the existing GPIO init logging:

```c
ESP_LOGI(TAG, "  IR Sensor: GPIO %d (burst duration: %d ms)", IR_SENSOR_PIN, IR_SCAN_DURATION_MS);
```

---

## Step 5: Main Loop — IR Processing Function

**Location:** Add a new static function `process_ir_sensor()` in `lighthouse.c`, placed
after `process_buttons()` and before `main_task()`.

This function handles both the pending trigger check and the burst expiry check in a single
call per loop iteration.

**Logic:**

```
current_time = xTaskGetTickCount() * portTICK_PERIOD_MS

--- Trigger check ---
if ir_trigger_pending:
    clear ir_trigger_pending

    if !rfid_scanning:
        // No active scan — start one
        rfid_reader_start_inventory_wrapper()
        ir_scan_active      = true
        ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS
        log "IR trigger: scan started"

    else if ir_scan_active:
        // IR-owned scan in progress — restart the timer only
        ir_scan_end_time_ms = current_time + IR_SCAN_DURATION_MS
        log "IR trigger: burst timer restarted"

    else:
        // Button-owned scan in progress — discard
        log "IR trigger: ignored (button scan active)"

--- Burst expiry check ---
if ir_scan_active AND ir_scan_end_time_ms != 0 AND current_time >= ir_scan_end_time_ms:
    rfid_reader_stop_inventory()
    rfid_reader_power_off()
    rfid_scanning       = false
    ir_scan_active      = false
    ir_scan_end_time_ms = 0
    gpio_set_level(SCANNING_LED, 0)
    log "IR burst expired: scan stopped"
```

---

## Step 6: Main Loop — Call Site

**Location:** `main_task()` function in `lighthouse.c`.

Add `process_ir_sensor()` call after `process_buttons()`:

```
process_buttons()       // existing
process_ir_sensor()     // new
vTaskDelay(10ms)        // existing
```

---

## Step 7: Button Stop Path — State Cleanup

**Location:** Inside `process_buttons()`, in the BUTTON1 stop-scan branch.

When the button manually stops an active scan, `ir_scan_active` and `ir_scan_end_time_ms`
must be cleared to prevent the burst expiry check from triggering a redundant stop on the
next loop iteration.

**Add to the existing button stop block:**

```c
ir_scan_active      = false;
ir_scan_end_time_ms = 0;
```

This is a one-line addition to an already-existing else branch — no structural change to
button handling is required.

---

## Verification Criteria

1. Walking past the AM312 triggers a rising edge; `ir_trigger_pending` is set; scan starts
   within one 10ms loop tick.
2. Scan stops automatically after 5 seconds with no button interaction; `rfid_scanning`,
   `ir_scan_active`, and `ir_scan_end_time_ms` all return to their idle values.
3. A second IR trigger arriving while a burst is active restarts `ir_scan_end_time_ms`
   without stopping and restarting the inventory. No tag detection gap occurs.
4. Repeated re-triggers produce correct timer extension each time; scan never expires
   earlier than 5 seconds after the most recent trigger.
5. A button-triggered scan is not stopped or affected by an IR trigger arriving mid-scan;
   the "ignored" log message appears.
6. Manually stopping a button-initiated scan via BUTTON1 leaves `ir_scan_active = false`
   and `ir_scan_end_time_ms = 0`; no spurious expiry fires.
7. No spurious triggers observed during device boot from AM312 power-on transients
   (AM312 has an internal ~2s stabilisation period before its first output pulse, which
   should prevent false triggers at startup).
