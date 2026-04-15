**Title:** Embedded Implementation of an Attendance System for Integration into an Enterprise Application
**Author:** Jakub Hloušek | **Supervisor:** Ing. Michal Bastl, Ph.D.
**Institution:** Brno University of Technology, Faculty of Mechanical Engineering

---

# 0. assignment

---

# 1. introduction

- Context and motivation for automated attendance tracking in enterprise environments
- Problem statement: limitations of existing solutions and the case for a passive, hands-free system
- Scope refinement: UHF RFID as the selected identification technology
- Integration target: Navigo3 HR software; the integration layer is designed to be extensible to other systems
- Overview of the system concept: paired Lighthouse units forming a detection portal, server-side processing, and a web dashboard

---

# 2. research

## 2.1 attendance system technologies

- Survey of identification methods and their limitations
- Case for choosing UHF RFID

## 2.2 direction detection methods

- IR break-beam triggering as scan activation
- Temporal ordering and RSSI-based approaches

## 2.3 hardware platforms and embedded architectures

### 2.3.1 microcontroller selection

- ESP32-WROOM-32: architecture, WiFi, power characteristics

### 2.3.2 UHF RFID reader modules

- Market survey, YPD-R300 selection rationale

### 2.3.3 power supply and battery considerations

- power source, battery backup, current draw constraints

### 2.3.4 timekeeping without a hardware RTC

- Absence of battery-backed RTC on ESP32 and implications for timestamp integrity

## 2.4 communication protocols and enterprise integration

- MQTT, offline-first patterns, REST API design, Navigo3 interface

## 2.5 embedded software frameworks

- FreeRTOS, ESP-IDF, NVS, LittleFS, provisioning

---

# 3. implementation and results

## 3.1 system architecture

- End-to-end architecture: Lighthouse units -> MQTT -> server -> Navigo3
- Paired-unit portal model and the case for server-side direction detection
- Data flow and event lifecycle from tag detection to attendance record
- Design for extensibility (Navigo3 as the implemented integration target, architecture open to other systems)

## 3.2 hardware design

### 3.2.1 board v1 - breadboard prototype

- Component selection validation, initial wiring and power architecture
- Reverse-engineering of used modules

### 3.2.2 board v2 - custom PCB

- KiCad schematic and layout decisions
- PCB creation, assembly and testing

### 3.2.3 antenna and RF considerations

- Coaxial feed requirement at 900 MHz, IPEX/U.FL connector

### 3.2.4 enclosure

- Prototype enclosure design

## 3.3 firmware

### 3.3.1 system initialization and WiFi provisioning

- Captive portal provisioning flow for device setup, NVS-backed configuration

### 3.3.2 UHF RFID scan control

- Real-time inventory mode, scan window management, IR trigger integration
- MQTT batch accumulator: time-windowed publish to avoid broker saturation

### 3.3.3 timekeeping and timestamp quality

- SNTP sync against local chrony server, CET/CEST timezone handling
- NVS persistence of last known good time, offline degradation behaviour

### 3.3.4 MQTT communication and offline caching

- QoS levels per event type, Last Will and Testament
- LittleFS offline event cache, replay on reconnect, non-blocking publish

### 3.3.5 user interaction: buttons, LEDs, and gestures

- Button and LED state machines

## 3.4 server

### 3.4.1 infrastructure and stack

- BunJS, Hono, PostgreSQL + Drizzle ORM, embedded Aedes MQTT broker

### 3.4.2 event ingestion and raw scan storage

- MQTT scan handler, batched payload parsing, raw event persistence

### 3.4.3 direction detection and event processing

- Cluster-based traversal detection, gap-based activity timeout segmentation
- Algorithm 1: temporal centroid
- Algorithm 2: RSSI-weighted centroid with trend analysis
- Dual-algorithm design: independent result rows per algorithm for empirical comparison

### 3.4.4 user and tag management

- User/tag data model, EPC assignment, live RFID event capture via WebSocket

### 3.4.5 navigo3 integration

- Integration with Navigo3 REST API
- Immediate push per event, periodic background retry sweep

## 3.5 dashboard

### 3.5.1 architecture and stack

- SolidJS, routing, WebSocket real-time updates

### 3.5.2 pages

- Lighthouses: device status and health
- Groups: portal grouping of lighthouse pairs
- Events: live raw scan monitor
- Processed Events: direction detection output with per-event detail and algorithm visualisation
- Users: user and tag management

## 3.6 system verification

### 3.6.1 lab validation

- End-to-end test: tag traversal producing attendance entry in Navigo3
- Detection range measurements per unit

### 3.6.2 field testing

- Deployment in a real office environment
- Evaluation criteria and expected outcomes

### 3.6.3 algorithm comparison

- Temporal vs. RSSI-weighted direction detection: accuracy and confidence findings
- Discussion of results and recommendation for deployment

---

# 4. conclusion

- Summary of the designed and implemented system: two Lighthouse units, custom PCB, firmware, server pipeline, dashboard, and Navigo3 integration
- Assessment of results against the four thesis goals from the assignment
- Evaluation of direction detection algorithm performance: temporal vs. RSSI-weighted comparison findings
- Known limitations: absence of hardware RTC, single antenna per unit
- Potential for practical deployment and extensibility to other enterprise systems
- Directions for future work: hardware RTC on a future board revision, firmware io_controller refactor, extended field testing

---

# 5. references

---

# 6. appendices

- A: PCB Schematics, Rev. 1 (4 sheets)
  - Lighthouse (top-level)
  - Charger submodule
  - Step-up DC/DC converter
  - UHF RFID reader
- B: YPD-R300 protocol command reference summary
- C: Navigo3 API interface description (subject to confidentiality review)
- D: Source code repository reference
