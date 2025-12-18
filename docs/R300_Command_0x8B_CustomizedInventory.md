# R300 UHF RFID Protocol - Command 0x8B: Customized Inventory

## Overview

Command **0x8B** (`cmd_name_customized_inventory`) is an **undocumented command** in the R300 UHF RFID module protocol that provides EPC C1G2 Gen2 session and target control for inventory operations.

**Status**: Not officially documented in R300 UHF RFID reader module_protocol_.pdf V2.2
**Source**: Found in UHFDemo v3.62 C# reference implementation
**Related Commands**: 0x80 (Inventory), 0x89 (Real-time Inventory)

---

## Command Details

### Command Name
- **C# Method**: `CustomizedInventory`
- **Description**: "Customized Session and Inventoried Flag inventory"
- **Purpose**: Allows precise control over EPC C1G2 Gen2 protocol parameters (Session and Target/Inventoried Flag)

### Command Code
```
0x8B
```

---

## Host Packet Format

### Structure
```
[Head] [Len] [Address] [Cmd] [Session] [Target] [Round] [Check]
```

### Byte Layout
| Field    | Size    | Value | Description |
|----------|---------|-------|-------------|
| Head     | 1 byte  | 0xA0  | Packet header |
| Len      | 1 byte  | 0x06  | Length (6 bytes: Address + Cmd + Session + Target + Round + Check) |
| Address  | 1 byte  | 0x01 or 0xFF | Reader address (0xFF = broadcast) |
| Cmd      | 1 byte  | 0x8B  | Command code |
| Session  | 1 byte  | 0x00-0x03 | EPC Gen2 session (S0, S1, S2, S3) |
| Target   | 1 byte  | 0x00-0x01 | Inventoried flag (A=0, B=1) |
| Round    | 1 byte  | 0x01-0xFF | Q value / inventory rounds |
| Check    | 1 byte  | Calculated | Checksum: (~sum) + 1 |

### Parameters

#### Session (1 byte)
EPC C1G2 Gen2 protocol session identifier:
- **0x00**: Session S0 (volatile, short persistence)
- **0x01**: Session S1 (volatile, short persistence)
- **0x02**: Session S2 (volatile, longer persistence)
- **0x03**: Session S3 (volatile, longer persistence)

**Usage**: Different sessions allow managing multiple concurrent inventory operations without interference.

#### Target (1 byte)
EPC C1G2 Inventoried Flag target:
- **0x00**: Target A (tags with Inventoried flag = A)
- **0x01**: Target B (tags with Inventoried flag = B)

**Usage**: Controls which tags respond based on their inventoried state. Used for anti-collision and selective reading.

#### Round (1 byte)
Number of inventory rounds or Q value:
- **Range**: 0x01 to 0xFF
- **Typical**: 0x01 for single round
- **Higher values**: More rounds, better collision resolution, longer operation time

---

## Response Packet Format

### When Tags Detected

#### Tag Data Response (Multiple Packets Possible)
```
[Head] [Len] [Address] [Cmd] [Freq_Ant] [PC(2)] [EPC(N)] [RSSI] [Check]
```

| Field     | Size       | Description |
|-----------|------------|-------------|
| Head      | 1 byte     | 0xA0 |
| Len       | 1 byte     | Variable (depends on EPC length) |
| Address   | 1 byte     | Reader address |
| Cmd       | 1 byte     | 0x8B |
| Freq_Ant  | 1 byte     | **High 6 bits**: RF channel/frequency (0-63, frequency hopping index)<br>**Low 2 bits**: Antenna ID (0-3, in single-antenna systems remains 0x00) |
| PC        | 2 bytes    | Protocol Control Word from tag |
| EPC       | N bytes    | Electronic Product Code (tag ID) |
| RSSI      | 1 byte     | Signal strength (see RSSI table page 42) |
| Check     | 1 byte     | Checksum |

**Note**: Length field = 3 + PC(2) + EPC_Length + RSSI(1) = EPC_Length + 6

#### Freq_Ant Field Detail

The **Freq_Ant** byte encodes both frequency and antenna information:

**Bit Layout:**
```
[Freq(6 bits)][Ant(2 bits)]
```

**Frequency (High 6 bits)**: RF channel index used during tag detection
- **Range**: 0-63 (0x00-0x3F)
- **Interpretation**: Index into the reader's frequency hopping list
- **Practical Range Observed**: 0x07-0x39 (7-57 decimal) depending on regulatory region and hopping pattern
- **Significance**: Indicates which frequency channel the reader was tuned to when detecting this particular tag
- **Use Case**: Useful for diagnostics - can correlate channel quality with RSSI values

**Antenna (Low 2 bits)**: Physical antenna ID
- **Range**: 0-3 (0x00-0x03)
- **Single-antenna systems**: Always 0x00
- **Multi-antenna systems**: Indicates which antenna detected the tag

**Example Decoding:**
```
Freq_Ant = 0x40 (01000000 binary)
  → Frequency: 010000 = 0x10 (16 decimal) = channel index 16
  → Antenna: 00 = antenna 0 (or no antenna in single-antenna mode)

Freq_Ant = 0xBC (10111100 binary)
  → Frequency: 101111 = 0x2F (47 decimal) = channel index 47
  → Antenna: 00 = antenna 0
```

**Frequency Hopping Note**: Modern UHF RFID readers implement frequency hopping to satisfy regional regulatory requirements (FCC in US, ETSI in Europe, etc.). The reader automatically cycles through allowed frequency channels during inventory operations. Each tag detection is tagged with the frequency it responded on, enabling channel quality analysis and troubleshooting.

#### Inventory Completion/Status Packet

After tag data responses, the reader sends a **status/completion packet**:

```
[Head] [Len] [Address] [Cmd] [Status_0] [Status_1] [Status_2] [Status_3] [Status_4] [Check]
```

| Field       | Size    | Value | Description |
|-------------|---------|-------|-------------|
| Head        | 1 byte  | 0xA0  | Packet header |
| Len         | 1 byte  | 0x0A  | Length (10 bytes) |
| Address     | 1 byte  | 0x01  | Reader address |
| Cmd         | 1 byte  | 0x8B  | Command echo |
| Status_0-3  | 4 bytes | 0x00  | Status/padding fields (observed: 0x00 0x00 0x0B 0x00) |
| Status_4    | 1 byte  | 0x00  | Additional status (observed: 0x00) |
| Check       | 1 byte  | 0x01  | Checksum (varies) |

**Example from actual scans:**
```
A0 0A 01 8B 00 00 0B 00 00 00 01 BE
```

**Significance**: This packet signals that the inventory operation has completed and all tag data has been transmitted. It appears to be consistent across all operations (same structure, typically same status bytes).

**Note**: This packet format is **not formally documented** in the R300 protocol specification - it was identified through actual hardware testing. Implementation should expect this packet after tag responses and either consume or discard it depending on application requirements.

---

## RSSI Support Status

### Based on Analysis

**RSSI is SUPPORTED in command 0x8B**, similar to command 0x89 (Real-time Inventory).

### Evidence
1. **C# Reference Code**: Processes RSSI byte in 0x8B responses
2. **Response Format**: Identical to 0x89 which includes RSSI
3. **Protocol Consistency**: All inventory commands return RSSI data
4. **Hardware Validation**: Extensive testing with actual R300 reader confirms RSSI values consistently present and valid

### Hardware Test Results

Testing with four distinct RFID tags across multiple scans confirmed:

- **All RSSI values within specification range**: 31-98 decimal (0x1F-0x62 hex)
- **Valid data captured**: No zero values or out-of-range readings
- **Consistent packet structure**: 19-byte tag response packets received correctly
- **Single-antenna system**: Freq_Ant antenna bits (low 2 bits) consistently 0x00

**Test Summary:**
- **Tag 1**: 5 scans, RSSI 55-67 dBm (average 62.6 dBm)
- **Tag 2**: 3 scans, RSSI 70-73 dBm (average 71.0 dBm, most stable)
- **Tag 3**: 8 scans, RSSI 64-81 dBm (average 72.1 dBm)
- **Tag 4**: 7 scans, RSSI 71-86 dBm (average 81.4 dBm, strongest readings)

### Previous Issue Resolution

Your earlier report of `RSSI: -129 dBm (raw: 0)` was caused by **incorrect byte indexing during packet parsing**. The byte position calculation for extracting the RSSI field was off, causing adjacent bytes to be read.

**Correct Implementation:**
```c
// Packet structure: [Head][Len][Addr][Cmd][Freq_Ant][PC(2)][EPC(15)][RSSI][Check]
// Byte positions:    0     1     2     3     4        5-6    7-21     22    23

// For 15-byte EPC (example from testing):
int rssi_position = 4 + 1 + 2 + 15;  // = 22
uint8_t rssi = data[rssi_position];  // Extract RSSI at position 22

// Or more generally:
int rssi_position = 4 + 1 + 2 + epc_length;
uint8_t rssi = data[rssi_position];
```

**Validation**: Current implementation successfully captures RSSI values matching expectations (55-86 dBm for typical indoor tag reading distances).

---

## Comparison with Related Commands

### 0x8B vs 0x89 (Real-time Inventory)

| Feature | 0x8B (Customized) | 0x89 (Real-time) |
|---------|-------------------|------------------|
| **Control** | Session + Target + Rounds | Only Rounds |
| **Mode** | Single inventory per command | Continuous until stopped |
| **Parameters** | 3 bytes (Session, Target, Round) | 1 byte (Channel) |
| **Response** | Tag data + completion | Continuous tag stream + completion |
| **RSSI** | Yes (byte in response) | Yes (byte in response) |
| **Use Case** | Fine-grained control, advanced applications | Simple continuous scanning |

### 0x8B vs 0x80 (Standard Inventory)

| Feature | 0x8B (Customized) | 0x80 (Standard) |
|---------|-------------------|-----------------|
| **Buffer** | No (real-time responses) | Yes (stores to internal buffer) |
| **Session Control** | Yes (explicit parameter) | No (uses default) |
| **Target Control** | Yes (A/B selection) | No (automatic) |
| **RSSI** | In real-time response | Stored with buffered data |

---

## Implementation Recommendations

### Recommended Parameters (Based on C# Code)

```c
// For basic inventory (similar to 0x89):
uint8_t session = 0x00;  // Session S0
uint8_t target = 0x00;   // Target A
uint8_t round = 0x01;    // Single round

uint8_t params[3] = {session, target, round};
send_command(0x8B, params, 3);
```

### Advanced Usage

```c
// For anti-collision with session management:
uint8_t session = 0x02;  // Session S2 (longer persistence)
uint8_t target = 0x00;   // Start with Target A
uint8_t round = 0x03;    // Multiple rounds for better collision resolution

// First pass - Target A
send_command(0x8B, (uint8_t[]){session, 0x00, round}, 3);
// Process responses...

// Second pass - Target B (tags flagged as inventoried from first pass)
send_command(0x8B, (uint8_t[]){session, 0x01, round}, 3);
```
