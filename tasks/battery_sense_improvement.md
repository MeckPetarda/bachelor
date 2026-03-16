# Task: Battery Monitor Improvements

## Background & Root Cause

The battery monitor is producing erratic voltage readings and triggering false-positive critical shutdowns on a fully charged cell. The observed log shows swings such as 3936 mV → 3828 mV → 3668 mV → 3994 mV within 45 seconds on a near-full cell.

**Root cause:** The ADC is sampling at arbitrary moments including during active RFID inventory rounds. Battery terminal voltage collapses significantly under combined ESP32 WiFi + RFID load — confirmed by scope in DEVLOG_2026_02_25 §3 (3.5V resting → 2.7–3.0V under load on a partially discharged cell). The ADC reading is accurate; it is measuring real terminal sag that does not represent state of charge. On top of this, the current shutdown logic acts on a single sample with no confirmation, meaning one transient reading causes an irreversible system halt.

**Hardware protection floor:** The TP4056 provides hardware undervoltage cutoff at approximately 3.0V via the DW01HA protection IC (DEVLOG_2026_02_10 §1). Software protection must not replicate this — it must be tuned to avoid false positives while still catching genuine deep-discharge conditions before the hardware cutoff activates.

**ADC constraint:** ADC1 (GPIO33, channel ADC1_CH5) must be used. ADC2 shares hardware with the WiFi RF subsystem and cannot be used reliably while WiFi is active (ESP32 TRM Section 31.3.1; confirmed in DEVLOG_2026_02_25 §4). Post-eFuse-calibration total error at 11 dB attenuation (the current setting) is ±60 mV (ESP32 Datasheet v5.2, Table 4-4). This maps to ±110 mV at cell level through the R1=100 kΩ / R2=120 kΩ voltage divider (divider ratio 120/220 = 0.545). No further improvement is available from recalibration — the eFuse two-point calibration path is already active (`CONFIG_ADC_CALI_EFUSE_TP_ENABLE=y`, `CONFIG_ADC_CALI_EFUSE_VREF_ENABLE=y` confirmed in `src/lighthouse/sdkconfig`).

---

## Files to Modify

- `src/lighthouse/main/battery_monitor.c` — primary implementation file
- `src/lighthouse/main/battery_monitor.h` — public API and type definitions
- `src/lighthouse/main/Kconfig.projbuild` — add `CONFIG_BATTERY_SENSE_ENABLED`
- `src/lighthouse/main/my_mqtt_client.c` — update health payload for disabled state

**Do not modify** `src/lighthouse/main/rfid_reader.c` or `rfid_reader.h` beyond what is described in Task 3. The RFID module's internal state is accessed via its existing public API only.

---

## Existing Code Orientation

### RFID Task State (rfid_reader.c / rfid_reader.h)

The RFID module tracks inventory state in a static struct:

```c
static struct {
    bool                initialized;
    bool                inventory_active;   // ← key field for Task 3
    rfid_tag_callback_t tag_callback;
    rfid_stats_t        stats;
    TaskHandle_t        rx_task_handle;
    TaskHandle_t        health_check_task_handle;
    SemaphoreHandle_t   mutex;
    uint32_t            read_interval_ms;
    rfid_reader_state_t state;
    rfid_health_t       health;
} rfid_state;
```

The existing public API exposes:
```c
bool rfid_reader_is_inventory_active(void);  // returns rfid_state.inventory_active directly
```

The RFID polling cycle sends `R300_CMD_INVENTORY_SINGLE` (0x8B) at a configurable interval (default 250 ms, minimum 50 ms). Each active period is 18.8 ms within a 30–50 ms cycle (DEVLOG_2026_02_25 §3).

### MQTT Health Payload (my_mqtt_client.c)

`mqtt_client_publish_health_metrics()` gathers heap, WiFi RSSI, uptime, and RFID health, builds a JSON payload via `snprintf`, and publishes to `mqtt_client_get_topic("health")`. Battery fields are not yet in the payload — they will be added as part of this task. The current payload buffer is sized at ~300 bytes; extend it as needed.

### Kconfig (Kconfig.projbuild)

The existing file at `src/lighthouse/main/Kconfig.projbuild` defines a `menu "WiFi Configuration"` block. The new battery sense option must be added as a separate `menu "Hardware Configuration"` block in the same file, after the existing menu.

---

## Task 1: Build-Time Battery Sense Disable Flag

**Problem:** The USB-only dev board has no battery. The battery sense ADC code must be manually edited before flashing it, which is error-prone.

**What to add to `Kconfig.projbuild`:**

```kconfig
menu "Hardware Configuration"

    config BATTERY_SENSE_ENABLED
        bool "Enable battery voltage sensing"
        default y
        help
            Enable ADC-based battery voltage monitoring on GPIO33 (ADC1_CH5).
            Disable for boards powered exclusively by USB with no battery connected
            (e.g., the USB-only development board).
            When disabled, all battery monitor functions return safe stub values
            and no ADC initialisation occurs.
            Set to 'n' in sdkconfig.defaults for USB-only board configurations.

endmenu
```

**Changes to `battery_monitor.c` and `battery_monitor.h`:**

1. Wrap all ADC initialisation, task creation, GPIO config, and the sampling loop body inside `#if CONFIG_BATTERY_SENSE_ENABLED ... #endif`.

2. All public functions must still exist and compile when `CONFIG_BATTERY_SENSE_ENABLED=n`. Return stub values:
   - `battery_monitor_init()` → `ESP_OK` (no-op)
   - `battery_monitor_get_voltage_mv()` → `0`
   - `battery_monitor_get_soc_percent()` → `0`
   - `battery_monitor_get_state()` → `BATTERY_STATE_SENSE_DISABLED`

3. Add `BATTERY_STATE_SENSE_DISABLED` to the battery state enum in `battery_monitor.h`.

**Changes to `my_mqtt_client.c`:**

In `mqtt_client_publish_health_metrics()`, the battery JSON section must be conditional:

- When `CONFIG_BATTERY_SENSE_ENABLED=n`:
  ```json
  "battery": { "sense_enabled": false }
  ```
- When enabled: full object as described in the final section of this task.

**Acceptance Criteria:**
- `idf.py build` succeeds with both `CONFIG_BATTERY_SENSE_ENABLED=y` and `=n`, no warnings.
- With `=n`, no `adc1_get_raw` or `esp_adc_cal_characterize` calls execute at runtime.
- Health MQTT payload with `=n` contains `"battery": {"sense_enabled": false}`.

---

## Task 2: ADC Multisampling with Averaging

**Problem:** A single ADC sample has ±60 mV total error at 11 dB attenuation (Datasheet Table 4-4). The datasheet explicitly recommends taking multiple samples and averaging to improve DNL (Table 4-3, Notes). Currently a single sample is taken per reading cycle.

**What to change in `battery_monitor.c`:**

1. Define:
   ```c
   #define BATTERY_ADC_SAMPLE_COUNT 16
   ```

2. Replace the single `adc1_get_raw()` call with:
   ```c
   uint32_t raw_sum = 0;
   for (int i = 0; i < BATTERY_ADC_SAMPLE_COUNT; i++) {
       raw_sum += adc1_get_raw(BATTERY_ADC_CHANNEL);
   }
   uint32_t raw_avg = raw_sum / BATTERY_ADC_SAMPLE_COUNT;
   ```

3. Pass `raw_avg` into `esp_adc_cal_raw_to_voltage()`. Averaging must happen at the raw count level before voltage conversion to avoid accumulated rounding error.

4. Preserve the existing calibration initialisation chain: `ESP_ADC_CAL_VAL_EFUSE_TP` → `ESP_ADC_CAL_VAL_EFUSE_VREF` → `ESP_ADC_CAL_VAL_DEFAULT_VREF` fallback, unchanged.

**ADC channel reference:** GPIO33 = `ADC1_CHANNEL_5`. Attenuation `ADC_ATTEN_DB_11`, effective range 150–2450 mV (Datasheet Table 4-4). Divider output range for 3.2–4.2 V cell: 1.75–2.29 V — fully within the measurement window.

**Acceptance Criteria:**
- Serial log shows stable readings without the large inter-sample swings from the original log.
- `BATTERY_ADC_SAMPLE_COUNT` is a named constant — no inline magic number.

---

## Task 3: Load-Aware Idle Sampling Gate

**Problem:** Readings taken during active RFID inventory rounds capture real terminal voltage sag under load. The RFID active period is 18.8 ms within a 30–50 ms cycle. This sag does not represent SoC.

**Mechanism:** Use `rfid_reader_is_inventory_active()` (already exported in `rfid_reader.h`) to gate sampling. Do not introduce an EventGroup or shared global — polling the existing function is sufficient.

**New constants in `battery_monitor.c`:**
```c
#define BATTERY_IDLE_WAIT_TIMEOUT_MS  2000  // max wait for RFID to go idle
#define BATTERY_IDLE_SETTLE_DELAY_MS    50  // settle time after reader goes idle
```

**Logic to add at the start of the sampling function, before any ADC read:**

```c
uint32_t waited_ms = 0;
while (rfid_reader_is_inventory_active() && waited_ms < BATTERY_IDLE_WAIT_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(10));
    waited_ms += 10;
}
if (rfid_reader_is_inventory_active()) {
    ESP_LOGW(TAG, "Battery sample skipped - RFID reader still active after %d ms",
             BATTERY_IDLE_WAIT_TIMEOUT_MS);
    return;
}
vTaskDelay(pdMS_TO_TICKS(BATTERY_IDLE_SETTLE_DELAY_MS));
// proceed with ADC read from Task 2
```

The 50 ms settle delay also provides margin for WiFi beaconing intervals (typically 100 ms beacon period), which are not directly observable at this abstraction level.

**Acceptance Criteria:**
- Serial log no longer shows voltage dips coinciding with inventory activity.
- A `LOGW` is emitted if a sample is skipped due to timeout.
- Both constants are named — no magic numbers.

---

## Task 4: Confirmatory Shutdown with Hysteresis

**Problem:** A single ADC reading below the critical threshold triggers irreversible deep-sleep. Given ±110 mV effective error at cell level and the possibility of remaining load transients, a single reading is insufficient grounds for a destructive action.

**New constants in `battery_monitor.c`:**

```c
// Shutdown arm threshold. Below this for N consecutive readings triggers shutdown.
// Set above TP4056/DW01HA hardware cutoff (~3.0V) to catch deep discharge before
// hardware protection activates. ±110mV divider-amplified ADC error provides
// the rationale for the 200mV margin above the hardware floor.
#define BATTERY_CRITICAL_THRESHOLD_MV      3400

// Hysteresis cancel level. A reading above this resets the consecutive counter.
// Must be strictly greater than BATTERY_CRITICAL_THRESHOLD_MV.
#define BATTERY_CRITICAL_CLEAR_MV          3500

// Consecutive readings required below BATTERY_CRITICAL_THRESHOLD_MV before shutdown.
// Each reading is taken at the normal polling interval, not back-to-back.
#define BATTERY_CRITICAL_CONSECUTIVE_COUNT    3
```

**Module-level state to add:**
```c
static int s_critical_count = 0;
```

**Replace existing single-sample shutdown check with:**

```c
if (voltage_mv < BATTERY_CRITICAL_THRESHOLD_MV) {
    s_critical_count++;
    ESP_LOGW(TAG, "Battery critical reading %d/%d: %d mV",
             s_critical_count, BATTERY_CRITICAL_CONSECUTIVE_COUNT, voltage_mv);
    if (s_critical_count >= BATTERY_CRITICAL_CONSECUTIVE_COUNT) {
        ESP_LOGE(TAG, "Battery critical shutdown triggered: %d consecutive readings "
                 "below %d mV (last: %d mV)",
                 BATTERY_CRITICAL_CONSECUTIVE_COUNT, BATTERY_CRITICAL_THRESHOLD_MV,
                 voltage_mv);
        // invoke existing shutdown / deep-sleep call here
    }
} else if (voltage_mv > BATTERY_CRITICAL_CLEAR_MV) {
    if (s_critical_count > 0) {
        ESP_LOGI(TAG, "Battery critical counter reset (%d mV above clear threshold)",
                 voltage_mv);
    }
    s_critical_count = 0;
}
// Readings between THRESHOLD and CLEAR_MV do not increment or reset the counter.
```

**Acceptance Criteria:**
- A single low reading does not trigger deep sleep.
- Three consecutive readings below `BATTERY_CRITICAL_THRESHOLD_MV` trigger shutdown with the counter increment visible in the log at each step.
- A reading above `BATTERY_CRITICAL_CLEAR_MV` after 1 or 2 low
