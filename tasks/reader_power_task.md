# Task: GPIO Pin Migration for RFID Power Control and Supply Sensing

## Objective
Migrate power rail control and sensing away from GPIO2 (strapping pin) to eliminate firmware flashing conflicts. Implement RFID reader transistor control and power rail digital sensing on non-strapping GPIO pins.

## Problem Context
GPIO2 is an ESP32 boot-time strapping pin used for determining boot mode. When GPIO2 is held HIGH during power-on, it prevents the ROM bootloader from entering flashing mode, requiring manual power cycling for firmware updates.

**Reference:** ESP32 Datasheet Section 3 "Boot Configurations", Table 3-3 "Chip Boot Mode Control"

---

## Changes Required

### 1. RFID Reader Power Control (Transistor Base)
**Current:** Not yet implemented  
**Target:** GPIO5

**Implementation Details:**
- S9013 NPN transistor base connection
- Base resistor: 240Ω (empirically verified for 10.2mA base current)
- Control logic: GPIO HIGH = reader powered, GPIO LOW = reader disabled
- No pull-up/pull-down resistor needed on GPIO5 itself

### 2. Power Rail Sense (Voltage Monitoring)
**Current:** GPIO2 (strapping pin)  
**Target:** GPIO22

**Implementation Details:**
- Digital level detection only (no ADC required)
- Replace existing GPIO2 sensing code with GPIO22
- Maintain same logic level thresholds and debouncing if previously used
- No special configuration needed—standard digital input

---

## Implementation Steps

### Phase 1: GPIO Configuration & Initialization
1. **Define GPIO pins as constants**
   - `RFID_POWER_CONTROL_PIN = GPIO5`
   - `POWER_RAIL_SENSE_PIN = GPIO22`

2. **Initialize GPIO5 as output (push-pull)**
   - Set direction: OUTPUT
   - Set initial state: LOW (reader OFF at startup)
   - No pull-up/pull-down required

3. **Initialize GPIO22 as input**
   - Set direction: INPUT
   - Configure debouncing if needed (maintain existing logic)

### Phase 2: Reader Power Management Logic
1. **Implement reader power ON function**
   - Called before any RFID scanning/reading operation
   - Sets GPIO5 HIGH
   - Add small delay (~100ms) for reader stabilization (check datasheet for power-up time)
   - Can add verification: read GPIO2 (existing sense) or GPIO22 (new) to confirm rail powered

2. **Implement reader power OFF function**
   - Called after all RFID operations complete
   - Sets GPIO5 LOW
   - Reader enters sleep mode (<100µA per YR300 datasheet)

3. **Integrate into operational flow**
   - Power ON at start of scanning/inventory session
   - Keep powered during active tag reading operations
   - Power OFF when operation complete or idle timeout reached
   - Update state machine/event handlers to call these functions appropriately

### Phase 3: Verify Hardware Connections
1. Confirm S9013 base resistor (240Ω) connects to GPIO5
2. Confirm power rail sense circuit connects to GPIO22 (not GPIO2)

### Phase 4: Testing & Verification
1. **Boot and flashing**
   - Confirm firmware flashes successfully without manual power cycling
   - GPIO5 remains LOW during boot (reader OFF)

2. **Power control operation**
   - Manually call reader ON function → GPIO5 HIGH → reader powers on
   - Manually call reader OFF function → GPIO5 LOW → reader powers off
   - Verify current draw changes (check bench meter or sense pin if available)

3. **Power rail sensing**
   - Verify power rail sense reads correctly on GPIO22
   - Confirm debouncing works as expected

4. **Operational sequence**
   - Test complete flow: startup → power ON reader → scan tags → power OFF reader → idle
   - Monitor current consumption before/after reader power control
   - Verify no unexpected resets or GPIO state conflicts

---

## Reference Documentation
- ESP32 Datasheet: Section 2 "Pins" (pin layout)
- ESP32 Datasheet: Section 3 "Boot Configurations" (strapping pin explanation)
- Project memory: S9013 base resistor = 240Ω, YR300 current draw = 300-380mA (operating), <100µA (sleep)
- Task context: GPIO2 strapping pin conflict prevents flashing during high state
- YR300 Datasheet Section 4: Operating current 300-380mA, sleep mode <100µA, EN pin high level enable

## Operational Notes
- Reader should be powered ON only during active scanning/operation to minimize power consumption
- Reader sleep mode (<100µA) allows for extended offline operation with offline caching
- Power OFF during idle periods supports the "lighthouse detector" duty-cycle model
- This aligns with offline capability requirement: reader can be cycled on/off as needed for detection windows
