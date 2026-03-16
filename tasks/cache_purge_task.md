# Task: Dual-Button Cache Purge Gesture (Dev Feature)

## Overview

Add a developer-only gesture to the IO subsystem: holding both BUTTON1 and BUTTON2 simultaneously for 10 seconds purges all unsynced events from the LittleFS offline cache. Successful purge is confirmed by a sequential LED flash sequence followed by an `esp_restart()`.

> **⚠ NO GPIO PIN MAPPING CHANGES:** This task must not alter any GPIO pin assignments. All pins used here are existing assignments already defined in `lighthouse.c`. Do not remap, reassign, or add any new GPIO allocations.

---

## Relevant Constants (from `lighthouse.c`)

```c
#define WIFI_STATUS_LED  GPIO_NUM_5   // WiFi connection status
#define MQTT_STATUS_LED  GPIO_NUM_23  // MQTT broker status
#define ACTIVITY_LED     GPIO_NUM_19  // Tag detection activity
#define SCANNING_LED     GPIO_NUM_18  // RFID scanning active

#define BUTTON1_PIN      GPIO_NUM_34  // Start/Stop RFID scanning
#define BUTTON2_PIN      GPIO_NUM_35  // Show statistics / setup mode

#define DEBOUNCE_TIME_MS 50
```

Both button pins (GPIO34, GPIO35) are **input-only** pins. Per ESP32 Datasheet Section 2.3.1 and TRM Section 6.1, GPIO34–39 have no internal pull-up/pull-down capability. External pull-ups are already in place and must not be changed.

---

## Files to Modify

- **Modify:** `src/lighthouse/main/lighthouse.c`
  - Add `combo_state` tracking struct (static, module-level)
  - Add `combo_gesture_active` flag (static, module-level)
  - Extend `process_buttons()` with combo detection and purge logic

No other files require modification. No new files are to be created.

---

## Behavioral Specification

### Trigger Conditions

Both buttons must be held **simultaneously and continuously** for the full 10-second window. If either button is released before the threshold is reached, the gesture is cancelled and all state resets. Initial press detection still goes through the existing `DEBOUNCE_TIME_MS` (50ms) filter consistent with the rest of `process_buttons()`.

### Operation Suspension

Once both buttons are detected as simultaneously pressed:

- If RFID scanning is active (`rfid_scanning == true`), call `rfid_reader_stop_inventory()` followed by `rfid_reader_power_off()`, mirroring the existing BUTTON1 stop path. Set `rfid_scanning = false`.
- Set the module-level `combo_gesture_active = true`. The IR sensor handler must check this flag at its entry point and skip triggering while it is set.
- The MQTT client and offline logger write queue require no intervention — no new RFID events will be generated while scanning is stopped.

### Progressive LED Countdown Feedback

During the 10-second hold, LEDs illuminate one by one to communicate progress. Timing is derived from `xTaskGetTickCount() * portTICK_PERIOD_MS`, consistent with the existing `process_buttons()` timing approach.

| Elapsed time | Action                              |
|-------------|-------------------------------------|
| Combo start | All LEDs turned **off**             |
| ≥ 2,500 ms  | `WIFI_STATUS_LED` turned **on**     |
| ≥ 5,000 ms  | `MQTT_STATUS_LED` turned **on**     |
| ≥ 7,500 ms  | `ACTIVITY_LED` turned **on**        |
| ≥ 10,000 ms | Purge triggered                     |

`SCANNING_LED` is reserved for the confirmation flash and is not used during the countdown.

### Purge & Confirmation Sequence

On reaching the 10,000 ms threshold:

1. Call `offline_logger_clear_all()` (declared in `offline_event_logger.h`). This resets `rtc_write_index` and `rtc_read_index` to zero under the storage mutex, effectively marking the partition as empty. Returns `ESP_OK` on success or `ESP_FAIL` on mutex timeout.

2. **On `ESP_OK`:** Execute the confirmation flash sequence, then restart:
   - Turn all four LEDs **off**.
   - For each LED in order — `WIFI_STATUS_LED` → `MQTT_STATUS_LED` → `ACTIVITY_LED` → `SCANNING_LED`:
     - Turn LED **on**, `vTaskDelay(pdMS_TO_TICKS(200))`, turn LED **off**, `vTaskDelay(pdMS_TO_TICKS(200))`.
   - Call `esp_restart()` (declared in `esp_system.h`). The device will not return from this call.

3. **On `ESP_FAIL`:** Execute the error flash sequence, then resume normal operation without restarting:
   - Flash all four LEDs together **three times**: on 200ms, off 200ms, per cycle.
   - Reset all combo state (`combo_state`, `combo_gesture_active`).
   - Turn all LEDs **off**. Normal LED states will be restored on the next main loop iteration by their respective status-tracking logic.

> Blocking with `vTaskDelay` inside the confirmation and error sequences is acceptable here. Both are terminal operations from the perspective of this gesture — either the device restarts, or the gesture is fully over before returning to the normal loop.

---

## New State to Add

Add the following at module scope in `lighthouse.c`, alongside the existing `button_states[2]` and `rfid_scanning` declarations:

```c
// Dual-button cache purge gesture state
static struct {
    bool     active;           // Both buttons currently held
    uint32_t combo_start_time; // Tick time (ms) when combo was first detected
    uint8_t  leds_lit;         // Countdown LEDs currently on (0–3)
} combo_state = {0};

static bool combo_gesture_active = false;
```

---

## Detection Logic in `process_buttons()`

The combo detection block must run **at the top** of `process_buttons()`, before the existing BUTTON1 and BUTTON2 individual blocks. The individual blocks must be guarded to skip their normal logic while `combo_state.active` is true (see guard note below).

```
Read BUTTON1 level: uint32_t b1 = gpio_get_level(BUTTON1_PIN)
Read BUTTON2 level: uint32_t b2 = gpio_get_level(BUTTON2_PIN)

If b1 == 0 AND b2 == 0:  // Both buttons pressed (active-low)

    If combo_state.active == false:
        // Rising edge of combo — initialise
        Stop RFID if rfid_scanning == true
        combo_gesture_active = true
        combo_state.active = true
        combo_state.combo_start_time = current_time
        combo_state.leds_lit = 0
        Turn all four LEDs off

    // Update countdown LEDs
    elapsed = current_time - combo_state.combo_start_time

    If elapsed >= 2500 && combo_state.leds_lit < 1:
        gpio_set_level(WIFI_STATUS_LED, 1)
        combo_state.leds_lit = 1

    If elapsed >= 5000 && combo_state.leds_lit < 2:
        gpio_set_level(MQTT_STATUS_LED, 1)
        combo_state.leds_lit = 2

    If elapsed >= 7500 && combo_state.leds_lit < 3:
        gpio_set_level(ACTIVITY_LED, 1)
        combo_state.leds_lit = 3

    If elapsed >= 10000:
        Execute purge & confirmation/error sequence (see above)

Else:  // One or both buttons released

    If combo_state.active == true:
        // Gesture cancelled — restore clean state
        combo_state.active = false
        combo_gesture_active = false
        combo_state.leds_lit = 0
        Turn all four LEDs off
        // Normal LED states restored on next loop iteration

    // Fall through to individual BUTTON1 / BUTTON2 handlers
```

### Guard on Individual Button Handlers

Wrap each of the existing BUTTON1 and BUTTON2 handler blocks with a check on `combo_state.active`. When the combo is active, still update `last_stable_state` so that the state machine does not produce spurious press events on release, but skip all action logic:

```
// BUTTON1 block
if (combo_state.active) {
    button_states[0].last_stable_state = gpio_get_level(BUTTON1_PIN);
} else {
    // existing BUTTON1 logic unchanged
}

// BUTTON2 block
if (combo_state.active) {
    button_states[1].last_stable_state = gpio_get_level(BUTTON2_PIN);
} else {
    // existing BUTTON2 logic unchanged
}
```

---

## Notes & Cautions

- **`offline_logger_clear_all()` resets pointers only** — it does not erase underlying file bytes on LittleFS. This is correct and sufficient: with both indices at zero the logger treats the partition as empty and new events overwrite old bytes. This matches the existing implementation in `offline_event_logger.c`. Do not call `offline_logger_format_partition()` — that performs a full LittleFS format which is not appropriate for this use case.

- **LED state after cancellation** — The four LEDs are each driven by independent status-tracking logic in the main loop (WiFi status, MQTT status, activity, scanning). Turning them all off on cancellation is safe; their correct states will be reapplied on the very next main loop pass without any special restoration code.

- **`esp_restart()` reference** — Declared in `esp_system.h`. Performs a full chip restart equivalent to a power cycle. All tasks terminate, peripherals reset, and the bootloader re-runs from flash.

- **No GPIO pin mapping changes** — This task uses only pin constants that already exist. No new `gpio_config_t` calls, no pin reassignments, no additions to `gpio_init()`.

---

## References

- ESP32 Datasheet v5.2, Section 2.3.1 — *Restrictions for GPIOs and RTC_GPIOs* (input-only pins GPIO34–39)
- ESP32 TRM v5.6, Section 6.1 — *IO MUX and GPIO Matrix Overview* (GPIO34–39 input-only, no internal pull resistors)
- `src/lighthouse/main/offline_event_logger.h` — `offline_logger_clear_all()` API
- `src/lighthouse/main/offline_event_logger.c` — `offline_logger_clear_all()` implementation (mutex, RTC pointer reset)
- ESP-IDF System API — `esp_restart()` in `esp_system.h`
- Devlog `DEVLOG_2025_12_15.md` — GPIO34/35 input-only constraint, external pull-up requirement
