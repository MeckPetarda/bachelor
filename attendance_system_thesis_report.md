# Bachelor's Thesis: Embedded Attendance System - Project Report

## Project Overview
**Title:** Embedded Implementation of an Attendance System for Integration into an Enterprise Application  
**Institution:** Brno University of Technology, Faculty of Mechanical Engineering  
**Student:** Jakub Hloušek  
**Supervisor:** Ing. Michal Bastl, Ph.D.

---

## Core Requirements & Constraints

### Key Design Requirements
- **Detection Range:** 2-3 meters (hands-free operation through bags/purses)
- **User Interaction:** Zero - completely passive detection
- **Integration Target:** Navigo3 HR/Project Management Software
- **Deployment:** Indoor/outdoor capability with PoE support
- **Direction Detection:** Dual sensors to determine entry/exit
- **Offline Capability:** Local storage with automatic sync when reconnected

### Primary Goals
- Cost-effective solution
- Easy enterprise integration via REST API
- Excellent user experience (no interaction required)
- High reliability with low maintenance

---

## Critical Technology Decision

### ⚠️ **MUST USE UHF RFID (NOT Standard RFID/NFC)**
- **Standard RFID/NFC:** Only 0-10cm range (unsuitable)
- **UHF RFID (860-960 MHz):** 1-12 meter range (perfect for requirements)

This is the most important technical decision that affects all hardware choices.

---

## Key Research Areas

### 1. **UHF RFID Technology** (Priority 1)
- EPC Gen2 UHF RFID Protocol
- LLRP (Low Level Reader Protocol) specification
- UHF reader modules: SparkFun M6E Nano, ThingMagic M6e, Impinj R420
- Cost-effective alternatives: Chinese JRD-4035 modules

### 2. **Direction Detection Algorithms** (Priority 1)
- RSSI-based direction detection
- Time-of-arrival (TOA) differencing
- Research: "RFID portal systems" and "RFID gate detection"
- Implementation: Two-sensor setup with entry/exit logic

### 3. **Communication & Integration** (Priority 2)
- MQTT with QoS 2 for guaranteed delivery
- REST API design (idempotent operations)
- Message queuing for reliability
- WebSocket for real-time dashboards
- Offline operation with local caching (SQLite)

### 4. **Hardware Platform** (Priority 2)
- ESP32 + UHF RFID module + PoE splitter
- Alternative: Raspberry Pi 4 with PoE HAT
- Weatherproof enclosure design
- Power backup considerations

---

## Implementation Architecture

```
[UHF Tag] → [UHF Reader A] → [ESP32/Pi] → [Local Queue] → [Navigo3 API]
         ↘ [UHF Reader B] ↗               ↓
                                    [Local Storage]
                                    (SQLite/SD Card)
```

### Data Flow
1. UHF readers detect tags at 2-3m range
2. Direction determined by sensor detection order
3. Event immediately pushed to Navigo3 (if available)
4. Failed transmissions queued locally
5. Automatic retry on reconnection

---

## Development Phases

### Phase 1: Proof of Concept
- USB UHF reader testing with laptop
- Range validation with various tag types
- Basic direction detection algorithm
- Simple REST API prototype

### Phase 2: Embedded Implementation
- Port to ESP32/Raspberry Pi
- Local storage implementation
- MQTT integration
- PoE support addition

### Phase 3: Production Ready
- Weatherproof enclosure
- Redundancy mechanisms
- Full Navigo3 integration
- Monitoring dashboard

---

## Technical Challenges to Address

1. **Tag Collision:** Multiple simultaneous tag reads
2. **Signal Interference:** Environmental factors affecting range
3. **Cost Optimization:** UHF readers are expensive ($200-500)
4. **Power Management:** Especially for battery backup
5. **Environmental Durability:** Weather resistance for outdoor units

---

## What to SKIP (Not Relevant)

- ❌ Biometric systems and GDPR biometric regulations
- ❌ Face recognition implementations
- ❌ Standard RFID/NFC (RC522, PN532) - too short range
- ❌ Access control/door lock integration
- ❌ Most Arduino RFID tutorials (wrong technology)

---

## Recommended Reading Order

1. **ESP32 prakticky** - Martin Malý (from bibliography)
2. UHF RFID fundamentals and EPC Gen2 protocol
3. MQTT protocol and message queuing patterns
4. REST API design for IoT systems
5. Edge computing for offline-capable systems

---

## Key Differentiators

- **Zero-interaction attendance:** 2-3m passive detection
- **Direction awareness:** Entry/exit detection without gates
- **Self-contained system:** Works independently with API integration
- **Cost-effective:** Targeting lower cost than commercial solutions
- **Flexible integration:** Generic REST API for any enterprise system

---

## Critical Success Factors

1. Achieving reliable 2-3m detection range
2. Accurate direction detection without false positives
3. Robust offline operation and sync
4. Cost under commercial alternatives
5. Simple, maintenance-free operation

---

## Next Steps

1. **Immediate:** Source UHF RFID development kit
2. **Week 1-2:** Validate range and tag detection
3. **Week 3-4:** Implement direction detection algorithm
4. **Week 5-6:** Build REST API and Navigo3 integration
5. **Week 7-8:** Develop embedded prototype
6. **Week 9-10:** Testing and refinement

---

## Contact & Resources

**Target Integration:** Navigo3 by Navigo Solutions s.r.o. (Brno)  
**Testing Location:** Company offices (pilot deployment)

---

*Report Generated: November 2025*  
*Last Updated: Based on initial project consultation*