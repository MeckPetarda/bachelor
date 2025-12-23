# Technical Report: Network Resilience and Offline Event Logging Architecture
## ESP32 Attendance System Lighthouse Implementation

**Date:** December 22, 2025  
**Project:** Embedded Attendance System for Navigo3 Integration  
**Document Scope:** Memory selection and offline event persistence strategy

---

## 1. Executive Summary

The lighthouse (detector unit) must operate resilientally during network outages by locally caching RFID detection events with timestamps. Upon network restoration, cached events must be transmitted with a grace period to allow the server to reconstruct historical data while not disrupting real-time event processing. This report determines appropriate storage mechanisms based on ESP32 hardware capabilities and project requirements.

---

## 2. Storage Requirements Analysis

### 2.1 Functional Requirements

1. **Event Buffering:** Cache RFID tag detection events locally during network unavailability
2. **Timestamp Preservation:** Attach precise timestamps to each cached event
3. **Non-Blocking Real-Time:** Real-time event detection must not be blocked by storage operations
4. **Power Safety:** Storage must survive power cycles and be resistant to corruption
5. **Graceful Synchronization:** Replay buffered events with appropriate delays to avoid overwhelming the server
6. **Differentiation:** Clearly mark replayed events to distinguish from live detections

### 2.2 Capacity Estimation

Assuming operational requirements:
- **Peak tag detection rate:** 2-5 tags per second during high activity periods
- **Event record size:** ~64 bytes per event (EPC + timestamp + metadata)
- **Maximum outage duration:** Design for 4-8 hour offline periods (typical facility outage)

**Capacity calculation:**
- Worst-case scenario: 5 tags/sec × 3600 sec/hour × 8 hours = 144,000 events
- Storage needed: 144,000 × 64 bytes = 9.2 MB

---

## 3. ESP32 Storage Inventory

Based on ESP32-WROOM-32 specifications (from provided datasheet):

### 3.1 Built-In Memory Resources

**Internal SRAM (RAM):**
- **Total:** 520 KB internal SRAM (shared across both cores)
- **RTC Memory:** 16 KB RTC SRAM (ultra-low-power, survives deep sleep)
- **Constraint:** NOT suitable as primary storage—volatile, limited capacity, needed for active operations

**Flash Memory:**
- **Internal Flash:** 4 MB (typically, varies by module)
- **Partitioning:** Consumed by bootloader, firmware, and spiffs filesystem
- **Available for data:** 1-2 MB after firmware (varies by build configuration)
- **Advantage:** Non-volatile, survives power cycles
- **Limitation:** 512 KB is insufficient for 8-hour outage buffering

### 3.2 External Memory Expansion Options

The ESP32-WROOM-32 supports external memory via QSPI interface:

**Option A: External PSRAM (Pseudo-SRAM)**
- **Specification:** 2 MB PSRAM variants available (common)
- **Interface:** Quad SPI (QSPI) - 6 GPIOs required
- **Volatility:** Volatile—does NOT survive power loss
- **Assessment:** Unsuitable for this use case (loses data on power outage)

**Option B: External SPI Flash Storage**
- **Specification:** SPI NAND or NOR flash modules (8 MB, 16 MB, 32 MB available)
- **Interface:** SPI—4-6 GPIOs required (CS, CLK, MOSI, MISO, WP, HOLD)
- **Non-Volatility:** Non-volatile—survives power cycles
- **Assessment:** Suitable, but requires additional hardware module

---

## 4. Recommended Storage Architecture

### 4.1 Primary Storage: Internal Flash with LittleFS

**Rationale:**
- Eliminates additional hardware complexity and cost
- Leverages existing flash partitioning infrastructure in ESP-IDF
- Sufficient capacity exists for realistic outage scenarios (4-6 hours)
- Non-volatile persistence across power cycles

**Implementation Details:**

**Flash Partition Layout:**
```
Bootloader:           0x1000   - 0x8000      (28 KB)
Partition table:      0x8000   - 0x9000      (4 KB)
NVS (calibration):    0x9000   - 0xB000      (8 KB)
Firmware:             0x10000  - 0x200000    (1920 KB)
LittleFS (Events):    0x200000 - 0x400000    (2 MB)  ← Event storage
Reserved:             0x400000 - 0x400000    (End of 4MB flash)
```

**Capacity with 2 MB allocation:**
- Events storable: 32,000 @ 64 bytes per event
- Duration coverage: ~1.8 hours @ 5 events/second
- Acceptable for typical facility outages (extends to 3-4 hours with compression)

**Source Reference:** ESP-IDF documentation on partition tables and LittleFS integration

### 4.2 Secondary Consideration: External SPI Flash Module

**When to implement:**
- If operational analysis shows outages exceeding 6 hours are common
- If peak detection rates exceed 5 events/second

**Hardware Requirements:**
- SPI flash module (8 MB minimum: GD25Q64, W25Q64)
- 4-6 GPIO pins (SPI0/SPI1 available on ESP32)
- Standard SPI level shifter if 3.3V/5V interface required

**Implementation Advantage:** Modular—can be added to current design without firmware rework (using `esp_partition` API)

---

## 5. Event Storage Schema

### 5.1 Event Record Structure

```c
typedef struct {
    uint64_t timestamp_ms;      // 8 bytes - milliseconds since boot
    uint32_t rtc_timestamp_s;   // 4 bytes - unix time (set during sync)
    uint8_t  epc[24];           // 24 bytes - EPC buffer (96-bit max)
    uint8_t  epc_length;        // 1 byte - actual EPC length
    uint8_t  reader_id;         // 1 byte - which reader (A=1, B=2)
    uint16_t rssi;              // 2 bytes - signal strength
    // Total: 40 bytes (can optimize further)
} offline_event_t;
```

**Recommended size:** 48 bytes (aligned, includes padding for alignment)
- Fits 42,666 events in 2 MB
- 8.5+ hours coverage @ 5 events/second

### 5.2 Storage Organization

**Approach: Circular Ring Buffer**
- Single LittleFS file with fixed record count
- Write pointer maintained in RTC memory (survives deep sleep, lost on hard reset)
- Read pointer advanced after successful server transmission
- Overflow handling: oldest events overwritten if buffer full (graceful degradation)

**Alternative: Sequential Log Files**
- New file per day/outage session
- Better for audit trails but increased filesystem fragmentation
- Recommended if retention/logging is critical

---

## 6. Synchronization Strategy

### 6.1 Replay Timeline

**Upon network restoration:**

```
T+0s:  Network detected available
T+1s:  Query server for grace period (default: 30 seconds)
T+1-30s: Continue detecting new tags → separate queue
T+30s: Begin replaying cached events
       - Throttle replay: max 10 events/second
       - Add 'offline_period' flag to MQTT payload
T+30-180s: Continue replay while monitoring new events
T+180s: Transition to real-time mode
```

**Server-side expectations:**
- Consume offline events with grace period
- Use timestamps to reconstruct sequence
- Deduplicate based on EPC + reader_id + timestamp window
- Update attendance status asynchronously

### 6.2 MQTT Payload Structure

**Real-time events:**
```json
{
  "type": "attendance",
  "timestamp": 1703251200000,
  "epc": "E2003A4F03E57CB42EB9",
  "reader_id": 1,
  "offline": false
}
```

**Offline replay events:**
```json
{
  "type": "attendance",
  "timestamp": 1703250900000,
  "epc": "E2003A4F03E57CB42EB9",
  "reader_id": 1,
  "offline": true,
  "replay_time": 1703251200000
}
```

---

## 7. Implementation Checklist

### 7.1 Firmware Components

- [ ] **LittleFS Integration**
  - Partition table modified for event storage allocation
  - Reference: ESP-IDF `esp_littlefs` component
  
- [ ] **Ring Buffer Management**
  - Write/read pointers maintained in RTC_SLOW_MEM
  - Overflow handling and wrap-around logic
  - CRC verification for data integrity

- [ ] **Event Logging Task**
  - FreeRTOS task running on Core 1 (RFID processing core)
  - Mutex-protected writes to shared storage
  - Non-blocking I/O (asynchronous flash operations)

- [ ] **Network Restoration Detection**
  - MQTT disconnection/reconnection callbacks
  - Grace period query to server via REST API
  - Event replay scheduler

- [ ] **Timestamp Management**
  - System time synchronization via NTP (when online)
  - Fallback to boot time counter (milliseconds) when offline
  - Timestamp correction upon reconnection

### 7.2 Testing Strategy

- [ ] **Capacity Testing:** Write maximum duration events (8 hours) and verify storage
- [ ] **Power Cycle Testing:** Hard reset during writes; verify no corruption
- [ ] **Network Interruption Simulation:** Kill WiFi during active detection
- [ ] **Server Integration:** Verify deduplication and timestamp ordering
- [ ] **Stress Testing:** 10 events/second for sustained periods

---

## 8. Risk Assessment and Mitigations

### 8.1 Identified Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Flash wear (write cycles) | Medium | Low | Implement wear leveling via LittleFS; typical flash rated 100K cycles |
| Buffer overflow | Low | Medium | Graceful overwrite; server-side duplicate detection |
| Timestamp drift | Medium | Medium | NTP sync immediately on reconnection; server timestamp validation |
| Filesystem corruption | Low | High | CRC per record; journaling via LittleFS; recovery partition |
| Network flakiness (repeated connect/disconnect) | Medium | Low | Hysteresis on network state; minimum 5-second offline before buffering |

### 8.2 Recovery Procedures

**Filesystem Corruption Detection:**
- Implement per-record CRC32 checksum
- Detect corruption on read; skip corrupted records
- Log corruption events for debugging

**Full Reset Option:**
- If filesystem damaged beyond recovery, erase partition via USB JTAG
- Implements recovery mode accessible via GPIO button
- Reference: ESP-IDF documentation on partition operations

---

## 9. Comparison: Internal Flash vs. External Flash

| Criteria | Internal Flash (2MB LittleFS) | External SPI Flash (8MB) |
|----------|------------------------------|------------------------|
| **Capacity** | 2 MB (~8.5 hrs @ 5 evt/s) | 8 MB (~34 hrs @ 5 evt/s) |
| **Cost** | $0 (integrated) | $2-5 (module) |
| **Latency** | <5 ms writes | <10 ms writes (SPI) |
| **Power Consumption** | Minimal | Minimal |
| **Firmware Complexity** | Low | Medium (SPI driver) |
| **PCB Impact** | None | 4-6 GPIO, level shifter |
| **Time to Deploy** | 1-2 weeks | 3-4 weeks (PCB revision) |

**Recommendation:** **Start with internal Flash (2 MB LittleFS)**. If outage analysis shows requirements exceed 3-4 hours, migrate to external SPI flash in next hardware revision.

---

## 10. Design Decision Summary

**Storage Method:** LittleFS on internal flash (2 MB partition)

**Rationale:**
1. No additional hardware required—simplifies deployment
2. Sufficient for typical 4-hour facility outages
3. Non-volatile persistence across power cycles
4. Proven reliability in ESP32 ecosystem
5. Graceful fallback if buffer fills (oldest events overwritten)

**Architecture:**
- Events written asynchronously (non-blocking RFID detection)
- Ring buffer with fixed capacity
- Grace period before replay to allow server deduplication
- Throttled event replay (10 events/sec max)

**Future Scaling:**
- External SPI flash module for extended outage support
- Database migration to local SQLite for advanced querying
- Compression algorithms for density improvement

---

## 11. References and Documentation Sources

- **ESP32 Datasheet:** Section 2.4 "Memory" — Total SRAM: 520 KB internal + 16 KB RTC
- **ESP-IDF Technical Reference Manual:** Part II "Memory Organization" (Chapter 3-4)
  - Section 3.3.2: Embedded memory architecture
  - Section 17: External memory encryption (applicable to SPI flash)
- **LittleFS Specification:** https://github.com/littlefs-project/littlefs
- **ESP-IDF Partition Table Documentation:** https://docs.espressif.com/projects/esp-idf/
- **MQTT QoS 2 Message Ordering:** MQTT 3.1.1 Specification Section 4.6

---

## Appendix A: Configuration Templates

### A.1 Verified Partition Table (Current Implementation)

**As deployed on Jacob's system (December 23, 2025):**

```csv
# ESP-IDF Partition Table
# Name,         Type,  SubType,    Offset,    Size,    Flags
nvs,            data,  nvs,        0x9000,    24K,
phy_init,       data,  phy,        0xf000,    4K,
factory,        app,   factory,    0x10000,   1M,
offline_events, data,  littlefs,   0x110000,  2M,
```

**Memory Layout Breakdown:**

```
Address Range    Size      Partition          Purpose
0x000000-0x008000   32 KB   Bootloader         (implicit, managed by ESP-IDF)
0x008000-0x009000   4 KB    Partition Table    Partition metadata
0x009000-0x00B000   24 KB   NVS                WiFi credentials, settings
0x00F000-0x010000   4 KB    PHY Init           RF calibration data
0x010000-0x110000   1 MB    Factory App        Compiled firmware (924 KB actual)
0x110000-0x310000   2 MB    offline_events     ← RFID Event Storage (LittleFS)
0x310000-0x400000   960 KB  (Reserved)         Future expansion
```

**Capacity Verification:**
- Partition size: 2,097,152 bytes (2 MB)
- Event record size: 48 bytes (optimized with alignment)
- Maximum events: 43,690 events
- Coverage @ 5 events/sec: 8,738 seconds ≈ **2.43 hours**
- Coverage @ 3 events/sec: **3.65 hours**

**Note:** Actual outage tolerance depends on peak detection rate. Conservative estimate: 2-3 hours per 2 MB partition. If longer coverage needed, partition can be extended to 3 MB (0x110000-0x410000) using reserved space.

### A.2 LittleFS Configuration

```c
// In CMakeLists.txt or IDF_COMPONENT_EXTRA_REQUIRES
#define CONFIG_LITTLEFS_PAGE_SIZE 256
#define CONFIG_LITTLEFS_BLOCK_SIZE 4096
#define CONFIG_LITTLEFS_CACHE_SIZE 512
```

---

---

## Appendix B: Implementation Status & Validation

### B.1 System Specification (Jacob Hloušek - December 23, 2025)

**Firmware Characteristics:**
- Compiled size: 924 KB (well under 1 MB allocation)
- Build system: ESP-IDF with CMake
- Target device: ESP32-WROOM-32
- Flash capacity: 4 MB total

**Partition Configuration Status:**
- ✅ Partition table created and verified
- ✅ LittleFS selected as filesystem
- ✅ offline_events partition allocated at 0x110000 (2 MB)
- ⏳ Ready for firmware integration (event logging code implementation)

**Deployment Readiness:**
- Partition table verified via `idf.py partition-table`
- Can be flashed via: `idf.py -p /dev/ttyUSB0 partition-table-flash`
- No conflicts with existing firmware (924 KB << 1 MB factory partition)
- 960 KB reserved space available for future expansion

---

## Appendix C: LittleFS Integration Checklist

Once partition table is flashed, implement these components:

- [ ] **Initialization Code**
  - Mount `/offline_events` partition at startup
  - Configure format-on-mount if missing
  - Verify free space availability

- [ ] **Event Writer Task**
  - Create FreeRTOS task on Core 1 (RFID processor)
  - Implement ring buffer with write pointer in RTC_SLOW_MEM
  - Add CRC32 per event for corruption detection

- [ ] **Storage Format**
  - Fixed 48-byte event records
  - Binary format (not JSON) for density
  - Single file or segmented by hour (decision needed)

- [ ] **Network Restoration Handler**
  - Detect WiFi reconnection
  - Query server for grace period
  - Initiate throttled replay (10 events/sec max)

- [ ] **Testing & Validation**
  - Write 10,000+ events; verify all readable
  - Power cycle during writes; check integrity
  - Simulate 4-hour outage; measure storage usage
  - Stress test: 5 events/sec for 1 hour

---

**Document Status:** Partition Design Phase ✅ Complete  
**Next Phase:** Firmware integration (event logging code implementation)  
**Review Date:** After initial storage testing (target: 2 weeks)  
**Last Updated:** December 23, 2025 — Partition table verified and deployed
