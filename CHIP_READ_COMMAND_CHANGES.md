# RFID Reader Implementation Changes

## Summary

Changed the RFID reader implementation from continuous real-time inventory mode (command 0x89) to a polling-based approach using single inventory commands (command 0x8B) with configurable intervals.

## Changes Made

### 1. Protocol Command Update

- **Added**: `R300_CMD_INVENTORY_SINGLE` (0x8B) for single read operations
- **Deprecated**: `R300_CMD_INVENTORY_RT` (0x89) - marked as deprecated but kept for backwards compatibility
- **Added**: Configuration constants:
  - `DEFAULT_READ_INTERVAL_MS`: 250ms (default polling interval)
  - `MIN_READ_INTERVAL_MS`: 50ms (minimum allowed interval)

### 2. Header File Changes (`uart_reader.h`)

#### Updated Function Signature
```c
// Old:
esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback);

// New:
esp_err_t rfid_reader_start_inventory(rfid_tag_callback_t callback, uint32_t interval_ms);
```

#### New Parameter
- `interval_ms`: Configurable polling interval in milliseconds
  - Pass `0` to use default (250ms)
  - Minimum value enforced: 50ms
  - Determines how frequently the reader sends read commands

### 3. Implementation Changes (`uart_reader.c`)

#### Module State
Added `read_interval_ms` field to track the configured polling interval.

#### Command Function
Replaced `restart_inventory()` with `send_inventory_command()`:
- Sends single inventory command (0x8B) with parameters
- Parameters: antenna mask (0x00), read time (0x00), Q value (0x01)

#### UART RX Task
**Major refactor** - changed from event-driven to polling-based:

**Before:**
- Waited for continuous stream of tag events from 0x89 command
- Auto-restarted inventory when completion packet received
- Processed tags as they arrived in real-time

**After:**
- Actively sends 0x8B command at configured interval
- Waits for response after each command
- Processes tag data when received
- Repeats on interval timer

#### Start Inventory Function
- Now accepts and validates `interval_ms` parameter
- Sets default to 250ms if 0 is passed
- Enforces minimum of 50ms
- Sends first command immediately upon start
- No longer sends continuous inventory command

#### Stop Inventory Function
- Simplified - just sets flags to stop polling
- No longer needs to send reset command
- Cleaner shutdown process

### 4. Application Changes (`my_project.c`)

Updated the wrapper function to pass default interval:
```c
rfid_reader_start_inventory(on_tag_detected, 0);  // 0 = use default 250ms
```

## Benefits of Polling Approach

1. **Configurable Read Rate**: Users can adjust how frequently tags are scanned
2. **Predictable Behavior**: Commands sent at regular intervals
3. **Better Control**: Application has more control over when reads occur
4. **Resource Management**: Can adjust interval based on power/performance needs
5. **Simpler Protocol**: Single command/response cycle instead of continuous stream

## Usage Examples

### Default Interval (250ms)
```c
rfid_reader_start_inventory(callback, 0);
```

### Custom Interval (500ms)
```c
rfid_reader_start_inventory(callback, 500);
```

### Fast Polling (100ms)
```c
rfid_reader_start_inventory(callback, 100);
```

## Technical Details

### Command Format (0x8B)
Based on Arduino example and R300 protocol section 2.2.6:
```
[0xA0][0x06][0x01][0x8B][0x00][0x00][0x01][Checksum]
```

### Response Format
Same as before:
```
[Head][Len][Address][Cmd][Freq_Ant][PC(2)][EPC(N)][RSSI][Check]
```

### Timing Behavior
- Command sent every `interval_ms` milliseconds
- Task delay: 10ms between loop iterations
- First command sent immediately on start
- Polling stops cleanly when inventory is stopped

## Backwards Compatibility

- Response parser accepts both 0x8B and 0x89 command responses
- Existing data structures unchanged
- Callback interface unchanged
- Statistics tracking unchanged

## Version Update

Updated version from 1.2 to 1.3 in file header.
