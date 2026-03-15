# Task: LED Indicator and Button Behaviour Refactor

## Overview

Refactor the LED status indicator logic and Button 1 behaviour to reflect the
finalized physical IO of the Lighthouse enclosure. The four LEDs are reassigned
new semantic roles and the two buttons are updated accordingly. Button 2 and its
existing WiFi-setup / status-message behaviour are **not changed**.

---

## Current State (reference)

### GPIO assignments (`lighthouse.c`)
| Constant        | GPIO | Current role              |
|-----------------|------|---------------------------|
| `WIFI_STATUS_LED` | 4  | WiFi connection status    |
| `MQTT_STATUS_LED` | 23 | MQTT connection status    |
| `SCANNING_LED`    | 18 | Active scan indicator     |
| `ACTIVITY_LED`    | 19 | Tag detected / battery    |
| `BUTTON1_PIN`     | 34 | Toggle RFID scan          |
| `BUTTON2_PIN`     | 35 | Status msg / WiFi setup   |

> **Note:** GPIO34 and GPIO35 are input-only pins with no internal pull
> resistors. External pull-ups are required.  
> Reference: ESP32 Datasheet v5.2, Section 4.8.1 — "Input Only Pins".

### `wifi_provisioning.c`
`wifi_provisioning_init()` currently takes a single `led_pin` argument and
blinks that pin during `WIFI_STATE_AP_ACTIVE` and `WIFI_STATE_CONNECTING`
states at a 500 ms toggle interval (1 s period).

---

## Target Behaviour

### LED1 — WiFi + MQTT combined indicator (GPIO4, green)

| Condition                        | LED1 state                    |
|----------------------------------|-------------------------------|
| No WiFi connection               | Off                           |
| WiFi connected, no MQTT          | Blinking, 1 s period (500 ms on / 500 ms off) |
| WiFi connected + MQTT connected  | Solid on                      |
| AP provisioning active           | Blinking (overrides above) until WiFi confirmed, then solid |

### LED2 — IR mode / AP provisioning indicator (GPIO23, green)

| Condition                        | LED2 state                    |
|----------------------------------|-------------------------------|
| IR auto-scan mode active         | Solid on                      |
| Manual mode active               | Off                           |
| AP provisioning active           | Blinking until MQTT confirmed, then solid |

> During AP provisioning the two LEDs signal sequential milestones:
> LED1 blinks → WiFi established → LED1 solid.
> LED2 blinks → MQTT confirmed → LED2 solid.
> This overrides the normal WiFi/IR semantics for the duration of provisioning.

### LED3 — Active scan indicator (GPIO18, red) — **unchanged**

No changes to this LED or its driving logic.

### LED4 — Tag activity / battery (GPIO19, yellow) — **unchanged**

No changes to this LED or its driving logic.

---

### Button 1 — Scan mode control (GPIO34)

Button 1 now owns all scan-mode toggling. Its behaviour depends on the current
scan mode.

#### IR Mode (default, LED2 solid on)

| Gesture              | Action                                                  |
|----------------------|---------------------------------------------------------|
| Short press          | No-op (ignored)                                         |
| 3-second hold        | Stop RFID scanning if running → turn LED2 off → enter Manual Mode |

#### Manual Mode (LED2 off)

| Gesture              | Action                                                  |
|----------------------|---------------------------------------------------------|
| Short press          | Toggle RFID scanner (first press on, second press off, alternating) |
| 3-second hold        | Stop RFID scanning if running → turn LED2 on → return to IR Mode |

> The 3-second hold transitions back to IR Mode from **either** the RFID-on or
> RFID-off state in Manual Mode. RFID is always stopped before the mode switch
> in both directions.

### Button 2 — **unchanged**

| Gesture              | Existing action retained                              |
|----------------------|-------------------------------------------------------|
| Short press          | Send status / statistics message                      |
| 5-second hold        | Enter WiFi AP setup (`wifi_provisioning_setup_button_pressed()`) |

No changes to Button 2 handling code.

---

## Scan Mode State Machine

Introduce a module-level enum and variable to track scan mode:

```c
typedef enum {
    SCAN_MODE_IR,     // default; IR sensor drives RFID on/off
    SCAN_MODE_MANUAL, // button short-press drives RFID on/off
} scan_mode_t;

static scan_mode_t scan_mode = SCAN_MODE_IR; // default on boot
```

IR mode entry actions (called on 3 s hold from Manual, or on boot):
1. If RFID scanning is active → stop inventory → power off reader.
2. Set `scan_mode = SCAN_MODE_IR`.
3. Set LED2 solid on.
4. Resume listening to IR sensor trigger events.

Manual mode entry actions (called on 3 s hold from IR):
1. If RFID scanning is active → stop inventory → power off reader.
2. Set `scan_mode = SCAN_MODE_MANUAL`.
3. Set LED2 off.
4. Disable IR sensor trigger (do not process IR events while in manual mode).

---

## LED Driver Changes

### LED1 blinking task / logic

The existing `wifi_provisioning.c` LED blink logic drives a single pin. This
must be extended to drive two pins with independent completion conditions.

Proposed change: pass both pins to `wifi_provisioning_init()` or add a second
setter before provisioning starts. The provisioning state machine then:

- Blinks `led1_pin` until `WIFI_STATE_CONNECTED` is reached → sets `led1_pin`
  solid on.
- Blinks `led2_pin` until MQTT connection is confirmed → sets `led2_pin` solid
  on.

Outside of provisioning, LED1 must be driven by a lightweight periodic check
(run inside `wifi_provisioning_process()` or a dedicated helper called from the
main loop) that reflects the three-state WiFi/MQTT condition described in the
target behaviour table above.

Blink timing for LED1 in normal operation: 500 ms on / 500 ms off (1 s period),
consistent with the existing `LED_BLINK_INTERVAL_MS = 500` constant in
`wifi_provisioning.c`.

---

## Files to Modify

| File | Nature of change |
|------|-----------------|
| `main/lighthouse.c` | Button 1 press handling; scan mode state machine; LED1/LED2 drive logic outside provisioning |
| `components/wifi_provisioning/wifi_provisioning.c` | Extend LED control to two pins; sequential WiFi→MQTT milestone logic during provisioning |
| `components/wifi_provisioning/wifi_provisioning.h` | Update `wifi_provisioning_init()` signature if pin count changes |

---

## Verification Criteria

- [ ] LED1 is off with no WiFi; blinks at 1 s with WiFi but no MQTT; solid with both.
- [ ] LED2 is solid in IR mode; off in manual mode.
- [ ] Short press of Button 1 in IR mode does nothing.
- [ ] 3 s hold of Button 1 in IR mode stops RFID, turns LED2 off, enters manual mode.
- [ ] Short press of Button 1 in manual mode toggles RFID on/off alternately.
- [ ] 3 s hold of Button 1 in manual mode stops RFID, turns LED2 on, enters IR mode.
- [ ] Button 2 short press still sends status message; Button 2 5 s hold still enters WiFi AP setup.
- [ ] During AP provisioning: LED1 blinks until WiFi confirmed (then solid); LED2 blinks until MQTT confirmed (then solid).
- [ ] LED3 and LED4 behaviour is unaffected.
- [ ] IR sensor trigger is ignored while in manual mode.
- [ ] RFID is always powered off before any scan-mode transition.
