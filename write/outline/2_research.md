# OSNOVA PLUS - 2. research

---

## 2.1 attendance system technologies

- Automated employee attendance tracking requires a reliable method of identifying a person at a physical boundary
  (doorway, turnstile, office entrance) without manual interaction from staff or administrator
- Three broad categories of identification technology are used in commercially available attendance systems:
  knowledge-based (PIN code), biometric (fingerprint, facial recognition), and token-based (card/tag carried by the
  employee)
- PIN-based systems require the employee to actively stop and enter a code at a terminal; prone to buddy-punching (one
  employee entering a code on behalf of another); fully unsuitable for passive, hands-free operation
- Biometric systems (fingerprint readers, facial recognition cameras) can eliminate deliberate user action but involve
  the collection and processing of sensitive personal data; classified as special category data under GDPR Article 9
  (Regulation (EU) 2016/679); high unit cost; rejected on privacy and cost grounds `[REF: GDPR Article 9 — EUR-Lex]`
- Token-based systems use a physical tag or card carried by the employee; identification is passive from the employee's
  perspective; read range is the critical differentiating parameter between technologies:
  - HF RFID (13.56 MHz, ISO 14443 / ISO 15693): 0–10 cm; requires deliberate card presentation at a reader — effectively
    equivalent to PIN in user experience
  - UHF RFID (860–960 MHz, EPC Gen2 / ISO 18000-63): 1–12 m; passive tag, no battery, no user action; tag can be
    detected while carried in a bag or pocket at walking pace
- **Conclusion:** UHF RFID is the only passive identification technology meeting the hands-free, 2–3 m range
  requirement; selected as the identification method for this system

**Table 2.1-1** — Identification technology comparison

| Technology             | Read range     | User action | Sensitive data | Selected |
| ---------------------- | -------------- | ----------- | -------------- | -------- |
| PIN code               | N/A            | Yes         | No             | No       |
| HF RFID (13.56 MHz)    | 0–10 cm        | Yes         | No             | No       |
| Biometric              | Contact / ~1 m | No          | Yes            | No       |
| UHF RFID (860–960 MHz) | 1–12 m         | No          | No             | **Yes**  |

`[REF: GS1 EPC Gen2 / ISO 18000-63 standard — cite for UHF RFID protocol background]`

---

## 2.2 direction detection methods

- A single identification point can confirm that a person carrying a tag was present at a location, but cannot determine
  which way they were travelling; for an attendance system distinguishing arrivals from departures, direction of
  traversal through the portal must be established
- The natural starting observation: if two spatially separated sensors are placed on opposite sides of a doorway, the
  order in which they detect the same tag encodes the direction of travel — outside-first implies entry, inside-first
  implies exit
- This principle is technology-agnostic and applies to any detection modality (optical break-beams, pressure mats, IR
  sensors, RFID readers); the challenge in UHF RFID specifically is that detection is probabilistic — a passive tag may
  not respond on every interrogation cycle, so a single first-detection comparison is unreliable
- A more robust approach is to collect all detections from both sensors over the duration of the traversal and compare
  the temporal centre of mass (centroid) of each sensor's detection group; the sensor with the earlier centroid is the
  one the person approached first
- RSSI (Received Signal Strength Indicator) provides a complementary directional signal: as a person approaches a
  reader, signal strength increases; as they move away, it decreases; the trend of RSSI over time therefore also encodes
  direction and can be used to weight the centroid calculation or independently confirm the temporal result
- Both approaches are well-established observations in RF sensing; this work applies them to UHF RFID portal detection
  and implements both as parallel algorithms for empirical comparison

**[Figure 2.2-1: Diagram of a two-sensor portal — doorway cross-section; Lighthouse A (outside) and Lighthouse B
(inside) on opposite sides; two traversal scenarios shown (entry and exit) with arrows; detection event sequences
illustrated beneath each scenario]**

`[REF: if a paper on RFID portal direction detection is found — cite here; otherwise note this section is based on first-principles reasoning from RF propagation fundamentals]`

---

## 2.3 hardware platforms and embedded architectures

### 2.3.1 microcontroller selection

- The Lighthouse unit must perform several concurrent tasks: UART communication with the RFID reader module, WiFi
  connectivity and MQTT messaging, local event storage, and GPIO management (IR sensor, LEDs, buttons); the platform
  must support all of these within a single self-contained embedded unit
- Requirements: integrated WiFi (no external module), at least one hardware UART, sufficient RAM to run a network stack
  concurrently with application logic, adequate flash for firmware and a local event cache filesystem, low enough power
  draw for battery-backed operation, mature development ecosystem, and low unit cost
- Single-board computers (e.g. Raspberry Pi) satisfy the connectivity and processing requirements but run a full Linux
  OS, draw substantially more power, depend on an SD card for storage (a known reliability concern in embedded
  deployments), and are oversized for a single-peripheral embedded task; rejected
- Microcontrollers with integrated WiFi and a mature SDK narrow the field considerably; the ESP32 (Espressif Systems)
  stands out: dual-core Xtensa LX6 at up to 240 MHz, 520 KB SRAM, 4 MB flash (module), integrated WiFi and Bluetooth,
  rich peripheral set including multiple UARTs, I²C, SPI, ADC, and hardware cryptographic accelerators; dual-core
  architecture allows the WiFi/network stack to be isolated on Core 0 while application logic runs uninterrupted on Core
  1 `[REF: ESP32 TRM Section 1.1; Malý [3]]`
- The ESP-IDF framework provides a complete, production-grade SDK: FreeRTOS kernel, WiFi stack, MQTT client, NVS,
  LittleFS, SNTP, mbedTLS — all maintained by the silicon vendor; large community, extensive documentation, and low
  module cost (~$3–5) make it the clear choice
- **Selected:** ESP32-WROOM-32 module

### 2.3.2 UHF RFID reader modules

*[pinned — to be completed separately]*

### 2.3.3 power supply and battery considerations

- The Lighthouse unit must operate from USB-C mains power with a lithium battery providing backup autonomy; both sources
  must be able to power the device simultaneously with automatic, safe arbitration between them
- A single lithium cell (3.7 V nominal) cannot directly supply the ESP32 (requires 3.3 V regulated) or the RFID reader
  module (requires 5 V); a boost converter is required to raise the battery output to 5 V, from which a 3.3 V LDO can be
  derived
- Battery charging, protection (overcurrent, overvoltage, undervoltage), and source arbitration (USB vs. boost output
  via Schottky diode OR configuration) are well-defined sub-problems with established reference circuits; standard ICs
  exist for each function and were selected during hardware design (covered in Section 3.2)
- Critical consideration: the UHF RFID reader draws significant peak current during active scan windows; the power
  supply design must sustain transient loads without causing voltage rail collapse — a failure mode that manifests as
  device reset and was encountered during Board v2 bring-up

`[REF: relevant IC datasheets cited in Section 3.2 hardware design]`

### 2.3.4 timekeeping without a hardware RTC

- The ESP32-WROOM-32 module does not include a battery-backed hardware RTC; the internal RTC counter runs only while the
  device is powered and loses its value on cold boot `[REF: ESP32 TRM Section 9.3.6]`
- For an attendance system, all events must carry timestamps traceable to real calendar time; a boot-relative counter is
  insufficient
- SNTP (Simple Network Time Protocol) synchronisation over WiFi is the standard approach for ESP32 timekeeping; ESP-IDF
  provides a built-in SNTP component; accuracy is adequate for attendance timestamping (sub-second error after sync)
  `[REF: IETF RFC 4330 — SNTPv4]`
- The limitation of SNTP-only timekeeping is that time is lost when the device is powered off or loses network access; a
  `timeBasis` field (`synced` / `estimated` / `relative`) is declared on every event payload to communicate timestamp
  quality to the server, which can then apply appropriate handling
- A hardware RTC IC with coin cell backup would eliminate this limitation and is identified as the primary hardware
  improvement for a future board revision

---

## 2.4 communication protocols and enterprise integration

- The Lighthouse units must transmit detection events to a server reliably, including in conditions of intermittent
  network availability; the communication protocol must support constrained embedded clients, handle reconnection
  gracefully, and not require a persistent open connection from the device side
- Candidate protocols considered:
  - **HTTP/REST (polling or push):** Simple to implement; stateless; but each transmission requires a full TCP handshake
    and HTTP request/response cycle — high overhead for frequent small messages from a battery-constrained embedded
    device; no native push from server to device; rejected for the device-to-server path
  - **WebSocket:** Persistent full-duplex TCP connection; suitable for browser-to-server real-time updates (used for the
    dashboard); not ideal for embedded clients where maintaining a persistent connection consumes memory and complicates
    reconnection logic; rejected for firmware
  - **AMQP:** Full-featured message queuing protocol; broker-heavy, complex handshake, no lightweight embedded client
    libraries for ESP-IDF; rejected
  - **MQTT (Message Queuing Telemetry Transport):** Publish-subscribe, minimal packet overhead, designed explicitly for
    constrained devices on unreliable networks; persistent sessions, Last Will and Testament (LWT) for disconnect
    detection, three QoS levels; mature ESP-IDF client component (`esp_mqtt`); selected
    `[REF: OASIS MQTT 3.1.1 specification]`
- MQTT QoS levels applied selectively: QoS 2 (exactly-once, four-way handshake) for offline event replay where
  duplicates in the enterprise system must be prevented; QoS 1 (at-least-once) for live scan publishes during active
  scan windows where publish frequency makes QoS 2 overhead unsustainable
- LWT mechanism enables real-time device status monitoring: each Lighthouse registers an "offline" will message on
  connect; the broker publishes it automatically on abnormal disconnect, without any active polling
- **Offline-first design:** events are written to local LittleFS storage before any network transmission; if the broker
  is unreachable, the device queues events and replays them on reconnection — no event is ever discarded due to
  transient network unavailability

---

## 2.5 embedded software frameworks

- The ESP32 platform is supported by ESP-IDF (Espressif IoT Development Framework), the official vendor SDK; it
  integrates all components needed for this project and avoids the fragmentation of assembling a firmware stack from
  independent libraries `[REF: Espressif ESP-IDF Programming Guide; Malý [3]]`
- **FreeRTOS** (integrated into ESP-IDF): preemptive real-time kernel; provides tasks, queues, semaphores, and event
  groups; the dual-core architecture allows the WiFi stack (managed by ESP-IDF) to run on Core 0 while application tasks
  (RFID control, MQTT, offline cache, LED state machine) run on Core 1 without interference; the standard choice for
  ESP32 application firmware `[REF: FreeRTOS documentation]`
- **NVS (Non-Volatile Storage):** key-value store over internal flash with transparent wear-levelling; used for WiFi
  credentials, MQTT broker address, device identity, last known good timestamp, and offline buffer pointers; simpler and
  more robust than a raw flash partition for configuration data
- **LittleFS:** wear-levelling filesystem for NOR flash, included as an ESP-IDF component; chosen over SPIFFS (the older
  alternative) for its better crash resilience and support for directories; used for the offline event cache
- **mbedTLS (AES):** TLS and cryptographic library integrated into ESP-IDF; AES-128-ECB used for encrypting WiFi
  credentials stored in NVS; the ESP32 hardware AES accelerator is used transparently via the mbedTLS API, keeping
  encryption overhead negligible `[REF: ESP32 TRM Section 14 — AES Accelerator]`
- **WiFi provisioning approach:** the ESP-IDF `wifi_provisioning` component (BLE-based) was evaluated but rejected — it
  requires a companion mobile application; a custom captive portal (SoftAP + DNS hijack + HTTP form served from SPIFFS)
  was implemented instead, working with any device browser regardless of OS

**Table 2.5-1** — ESP-IDF components used and their role

| Component     | Role                                                      |
| ------------- | --------------------------------------------------------- |
| FreeRTOS      | Task scheduling, inter-task queues, event groups          |
| esp_mqtt      | MQTT client — QoS 1/2, LWT, automatic reconnect           |
| nvs_flash     | Persistent key-value storage (credentials, config, state) |
| esp_littlefs  | Offline event cache filesystem                            |
| esp_sntp      | NTP time synchronisation                                  |
| mbedTLS (AES) | Credential encryption via hardware AES accelerator        |
| esp_wifi      | STA + AP mode, captive portal provisioning                |
