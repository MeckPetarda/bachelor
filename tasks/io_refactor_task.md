# Task: Extract IO Controller from lighthouse.c

## Objective

Move all GPIO, button, LED, IR sensor, and scan-mode logic from `lighthouse.c` into a new `io_controller.c` / `io_controller.h` module. The goal is to reduce `lighthouse.c` to application-level orchestration (init sequence, main loop dispatch, MQTT config handler, battery shutdown) while the new module owns all hardware IO state and processing.

**Constraint:** This is a pure code-move refactor. No behavioral changes, no new features, no bug fixes. The firmware must produce identical serial output and identical runtime behavior before and after.

---

## Files to Create

- `src/lighthouse/main/io_controller.h`
- `src/lighthouse/main/io_controller.c`

## Files to Modify

- `src/lighthouse/main/lighthouse.c` — remove relocated code, add `#include "io_controller.h"`, call new API
- `src/lighthouse/main/CMakeLists.txt` — add `io_controller.c` to SRCS

---

## What Moves to `io_controller.c`

### GPIO Pin Definitions (all `#define` constants)

```
LED1_PIN          GPIO_NUM_4
LED2_PIN          GPIO_NUM_21
SCANNING_LED      GPIO_NUM_26
ACTIVITY_LED      GPIO_NUM_25
BUTTON1_PIN       GPIO_NUM_22
BUTTON2_PIN       GPIO_NUM_23
IR_SENSOR_PIN     GPIO_NUM_19
IR_SCAN_DURATION_MS  5000
DEBOUNCE_TIME_MS  50
HOLD_3S_MS        3000
```

These become internal to `io_controller.c` (not exposed in the header). The header exposes only the pin numbers that other modules genuinely need (currently: none — all consumers go through getter/setter functions or the RFID module has its own pin defines).

### Type Definitions

```c
typedef struct {
    uint32_t last_press_time;
    uint8_t  last_stable_state;
    uint8_t  press_count;
} button_state_t;

typedef enum {
    SCAN_MODE_IR,
    SCAN_MODE_MANUAL,
} scan_mode_t;
```

`scan_mode_t` should be exposed in the header (lighthouse.c's main loop reads it for LED2 updates — but actually that LED2 update logic also moves, so this can stay internal). Verify during implementation: if nothing in `lighthouse.c` needs `scan_mode_t` after the move, keep it `static` in `io_controller.c`.

### State Variables

All of the following move out of `lighthouse.c`:

```c
static button_state_t button_states[2];
static bool           rfid_scanning;

// Combo gesture
static struct { bool active; uint32_t combo_start_time; uint8_t leds_lit; } combo_state;
static bool combo_gesture_active;

// IR sensor
static volatile bool ir_trigger_pending;
static bool          ir_scan_active;
static uint32_t      ir_scan_end_time_ms;

// Scan mode
static scan_mode_t scan_mode;

// LED1 blink state
static uint32_t led1_last_toggle_ms;
static uint8_t  led1_blink_state;
```

### Functions That Move

| Function | Notes |
|----------|-------|
| `gpio_init()` | Entire function including LED, button, and IR sensor config + ISR install |
| `ir_sensor_isr_handler()` | ISR — must remain `IRAM_ATTR` |
| `process_buttons()` | Entire function including combo gesture and both button handlers |
| `process_ir_sensor()` | Entire function including `ir_burst_check` label |
| `ir_trigger_start_scan()` | Static helper called by `process_ir_sensor` |
| `rfid_reader_start_inventory_wrapper()` | Wraps power-on + handshake + start_inventory sequence |
| `stop_rfid_if_active()` | Shared helper for mode transitions |
| `enter_ir_mode()` | Scan mode transition |
| `enter_manual_mode()` | Scan mode transition |
| `flash_activity_led()` | Brief LED pulse for tag detection |
| `battery_status_led_task()` | FreeRTOS task — its `xTaskCreate` call also moves |
| LED1/LED2 update block from `main_task` | The `wifi_connected`/`mqtt_connected` → LED1 blink logic, and the LED2 scan-mode indicator update |

### The `on_tag_detected` Callback — Special Case

This callback is currently defined in `lighthouse.c` and passed to `rfid_reader_start_inventory()`. It does three things:

1. Calls `flash_activity_led()` (moves to io_controller)
2. Publishes to MQTT or stores offline (needs `mqtt_initialized`, `mqtt_client_is_connected()`, `mqtt_client_publish_tag_event()`, `offline_logger_store_event()`)
3. Logs tag data

Option A: Move the callback to `io_controller.c` and have it call back into lighthouse for the MQTT/offline part via a registered function pointer.
Option B: Keep the callback in `lighthouse.c` and have it call `io_flash_activity_led()` from the io_controller.

**Recommended: Option B.** The callback's primary logic is application-level (MQTT publish vs offline store). The LED flash is a one-liner call. Moving the whole callback would require io_controller to depend on `my_mqtt_client.h` and `offline_event_logger.h`, which breaks the separation we're trying to achieve. So `on_tag_detected` stays in `lighthouse.c`, and `io_controller.h` exposes `io_flash_activity_led()`.

---

## Public API: `io_controller.h`

```c
#ifndef IO_CONTROLLER_H
#define IO_CONTROLLER_H

#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

/**
 * Initialize all GPIO: LEDs, buttons, IR sensor, ISR service.
 * Must be called once from app_main() before any other io_ function.
 */
void io_init(void);

/**
 * Process button state machines (debounce, combo gesture, mode toggle).
 * Call once per main loop iteration (~10 ms).
 */
void io_process_buttons(void);

/**
 * Process IR sensor trigger and burst expiry.
 * Call once per main loop iteration (~10 ms).
 */
void io_process_ir_sensor(void);

/**
 * Update LED1 and LED2 indicators based on connectivity and scan mode.
 * Call once per main loop iteration after processing buttons/IR.
 *
 * @param wifi_connected  true if WiFi STA is connected
 * @param mqtt_connected  true if MQTT broker session is active
 */
void io_update_status_leds(bool wifi_connected, bool mqtt_connected);

/**
 * Start the battery status LED background task.
 * Call once during init, after battery_monitor_init().
 */
void io_start_battery_led_task(void);

/**
 * Brief flash on the activity LED (tag detection feedback).
 * Blocks for ~100 ms. Safe to call from any task context.
 */
void io_flash_activity_led(void);

// =========================================================================
// State Getters / Setters
// =========================================================================

/** @return true if RFID inventory is currently active (IR or manual) */
bool io_is_scanning(void);

/** Set the scanning state. Called by lighthouse.c when it stops scanning externally. */
void io_set_scanning(bool active);

/** @return true if the combo gesture (dual-button hold) is in progress */
bool io_is_combo_active(void);

/**
 * Start the RFID inventory sequence (power on, handshake, start).
 * Sets scanning state and SCANNING_LED on success.
 * Requires a tag callback — register it first with io_set_tag_callback().
 */
void io_start_rfid_scan(void);

/**
 * Register the tag detection callback that will be passed to
 * rfid_reader_start_inventory(). Must be called before io_process_buttons()
 * or io_process_ir_sensor() can start a scan.
 */
typedef void (*io_tag_callback_t)(const rfid_tag_event_t *event);
void io_set_tag_callback(io_tag_callback_t cb);

#endif // IO_CONTROLLER_H
```

### Design Rationale

- **`io_update_status_leds(wifi, mqtt)`** takes connectivity state as parameters rather than calling `wifi_manager_is_connected()` / `mqtt_client_is_connected()` internally. This keeps io_controller free of WiFi/MQTT header dependencies. `lighthouse.c` already queries these in its main loop, so it passes the values through.

- **`io_set_tag_callback()`** decouples the RFID callback registration from the io_controller module. `lighthouse.c` calls `io_set_tag_callback(on_tag_detected)` during init, and `io_controller.c` stores the pointer and passes it to `rfid_reader_start_inventory()` when starting scans.

- **`io_is_scanning()` / `io_set_scanning()`** are needed because `lighthouse.c`'s `battery_critical_shutdown()` reads and modifies `rfid_scanning`, and `on_tag_detected` checks it indirectly via MQTT/offline routing. The setter also handles the SCANNING_LED.

- Pin defines do **not** appear in the header. No external module needs to know which GPIO number drives LED1. If a future module needs a specific pin, it can be added then.

---

## What Stays in `lighthouse.c`

| Item | Reason |
|------|--------|
| `app_main()` | Entry point, init orchestration |
| `main_task()` | Main loop — now just calls `io_process_buttons()`, `io_process_ir_sensor()`, `io_update_status_leds()`, `wifi_provisioning_process()`, health publish, battery check |
| `init_wifi_provisioning()` | Cross-subsystem glue (provisioning + NVS + LED pin registration) |
| `init_wifi()` | Cross-subsystem glue (wifi_manager + logging + IP display) |
| `init_mqtt()` | Cross-subsystem glue (mqtt + provisioning notification + config subscribe) |
| `init_offline_event_logger()` | Thin wrapper |
| `init_rfid_reader()` | Cross-subsystem glue (rfid_reader + power/frequency config) |
| `on_tag_detected()` | Application-level routing: MQTT publish or offline store, calls `io_flash_activity_led()` |
| `on_mqtt_config_message()` | MQTT config parser (moves in a later pass) |
| `battery_critical_shutdown()` | Application-level policy — reads `io_is_scanning()`, calls `io_set_scanning(false)` |
| `mqtt_initialized` | MQTT state flag — application-level |
| `HEALTH_PUBLISH_INTERVAL` | Main loop timing constant |

### Post-refactor `main_task()` Sketch

```c
static void main_task(void *arg)
{
    uint32_t health_publish_counter = 0;

    while (1)
    {
        wifi_provisioning_process();

        io_process_buttons();
        io_process_ir_sensor();

        if (io_is_combo_active())
        {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        bool wifi_ok = wifi_manager_is_connected();
        bool mqtt_ok = mqtt_initialized && mqtt_client_is_connected();

        io_update_status_leds(wifi_ok, mqtt_ok);

        // Health publish
        health_publish_counter++;
        if (mqtt_ok && health_publish_counter >= HEALTH_PUBLISH_INTERVAL)
        {
            battery_monitor_update(io_is_scanning());
            mqtt_client_publish_health_metrics();
            health_publish_counter = 0;
        }

        // Battery critical check
        if (battery_monitor_is_critical())
        {
            battery_critical_shutdown();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

---

## CMakeLists.txt Change

```cmake
idf_component_register(
    SRCS "lighthouse.c" "io_controller.c" "rfid_reader.c" "wifi_manager.c" "my_mqtt_client.c" "offline_event_logger.c" "battery_monitor.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos esp_driver_uart esp_wifi esp_netif nvs_flash mqtt joltwallet__littlefs wifi_provisioning
    PRIV_REQUIRES esp_driver_gpio esp_event esp_adc
)
```

Only change: `"io_controller.c"` added to SRCS.

---

## Dependencies of `io_controller.c`

The new module needs to `#include`:

```c
#include "io_controller.h"
#include "rfid_reader.h"          // rfid_reader_start_inventory, _stop_inventory, _power_on/off, _handshake, _is_powered
#include "wifi_provisioning.h"    // wifi_provisioning_is_led2_controlled, _setup_button_pressed
#include "battery_monitor.h"      // battery_monitor_is_critical, _get_status, _is_usb_present
#include "offline_event_logger.h" // offline_logger_clear_all (combo gesture purge)
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
```

Note that `io_controller.c` does **not** include `my_mqtt_client.h`, `wifi_manager.h`, or `esp_wifi.h`. This is intentional — all connectivity awareness is passed in via function parameters.

The one exception is `offline_event_logger.h` which is needed for the combo gesture's `offline_logger_clear_all()` call. This is acceptable since the combo gesture is fundamentally a cache-purge operation.

---

## Verification Criteria

1. **`idf.py build` succeeds** with zero warnings related to the refactored files.
2. **No behavioral change:** Serial output, LED behavior, button responses, IR trigger behavior, and combo gesture all work identically to the pre-refactor firmware.
3. **`lighthouse.c` no longer contains** any GPIO pin defines, `button_state_t`, `scan_mode_t`, `combo_state`, `process_buttons()`, `process_ir_sensor()`, `gpio_init()`, `ir_sensor_isr_handler()`, `battery_status_led_task()`, `flash_activity_led()`, `enter_ir_mode()`, `enter_manual_mode()`, `stop_rfid_if_active()`, `rfid_reader_start_inventory_wrapper()`, or `ir_trigger_start_scan()`.
4. **`io_controller.c` does not include** `my_mqtt_client.h` or `wifi_manager.h`.
5. **`io_controller.h` does not expose** any GPIO pin numbers.
