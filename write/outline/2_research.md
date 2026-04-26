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
  (Regulation (EU) 2016/679); high unit cost; rejected on privacy and cost grounds `[REF: GDPR Article 9 - EUR-Lex]`
- Token-based systems use a physical tag or card carried by the employee; identification is passive from the employee's
  perspective; read range is the critical differentiating parameter between technologies:
  - HF RFID (13.56 MHz, ISO 14443 / ISO 15693): 0-10 cm; requires deliberate card presentation at a reader - effectively
    equivalent to PIN in user experience
  - UHF RFID (860-960 MHz, EPC Gen2 / ISO 18000-63): 1-12 m; passive tag, no battery, no user action; tag can be
    detected while carried in a bag or pocket at walking pace
- **Conclusion:** UHF RFID is the only passive identification technology meeting the hands-free, 2-3 m range
  requirement; selected as the identification method for this system

**Table 2.1-1** - Identification technology comparison

| Technology             | Read range     | User action | Sensitive data | Selected |
| ---------------------- | -------------- | ----------- | -------------- | -------- |
| PIN code               | N/A            | Yes         | No             | No       |
| HF RFID (13.56 MHz)    | 0-10 cm        | Yes         | No             | No       |
| Biometric              | Contact / ~1 m | No          | Yes            | No       |
| UHF RFID (860-960 MHz) | 1-12 m         | No          | No             | **Yes**  |

`[REF: GS1 EPC Gen2 / ISO 18000-63 standard - cite for UHF RFID protocol background]`

---

## 2.2 direction detection methods

- A single reader confirms a tag was present at a location but cannot determine direction of
  traversal; for an attendance system, arrival vs. departure must be distinguished
- Fundamental principle: two spatially separated readers on opposite sides of a doorway encode
  direction in the temporal sequence of their detections - outside-first implies entry,
  inside-first implies exit
- Naive first-read comparison is unreliable: passive UHF tags respond probabilistically;
  occasional reads at RF null points or from reflected waves can invert the apparent detection
  order - Oikawa (2009) demonstrates this failure mode experimentally and proposes comparing
  the read-count-weighted temporal centroid of each antenna's full detection group instead
  `[REF: Oikawa, Y. - Tag movement direction estimation methods in an RFID gate system.
  IEEE ISWCS 2009, pp. 41-45]`
- A complementary signal is available in RSSI: as a tag moves through a portal, RSSI at each
  reader rises, peaks at closest approach, then falls; the reader whose RSSI peaks first is the
  one the tag passed first - follows directly from the Friis transmission equation
  `[REF: Jie et al. - RF-Access: Barrier-Free Access Control Systems with UHF RFID.
  Applied Sciences 12(22), MDPI 2022 - Section 2.1, Eqs. 1-2]`
- **Two algorithmic families** emerge from this literature: temporal centroid and RSSI-weighted
  centroid; both require the full set of raw timestamped RSSI readings from both readers -
  per-device deduplication would destroy the signal; detailed formulations in Section 3.4.3

`[Figure 2.2-1: Dual RSSI curves over time for a single traversal; temporal centroids C_out
and C_in marked; RSSI peaks labelled; direction arrow outside -> inside]`

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
  LittleFS, SNTP, mbedTLS - all maintained by the silicon vendor; large community, extensive documentation, and low
  module cost (~$3-5) make it the clear choice
- **Selected:** ESP32-WROOM-32 module

## 2.3.2 UHF RFID reader modules

- The embedded-integration tier - compact modules with a UART interface, controlled directly
  by a microcontroller - was surveyed; key selection criteria: documented UART command
  protocol, 5 V supply compatibility, and unit cost suitable for small scope prototyping

**Table 2.3.2-1** - UHF RFID reader module candidates

| Module                              | RF output                   | Supply  | Interface  | Antenna           | Price (approx.)  | Decision                                                                                   |
| ----------------------------------- | --------------------------- | ------- | ---------- | ----------------- | ---------------- | ------------------------------------------------------------------------------------------ |
| YPD-R200                            | 15-26 dBm                   | 3.3-5 V | UART / SPI | External, SMA     | ~300 CZK         | Lower RF output; rejected                                                                  |
| YPD-R200 integrated antenna variant | 15-26 dBm                   | 3.3-5 V | UART       | Integrated PCB    | ~300 CZK         | No antenna modularity; rejected                                                            |
| Yanpodo bare chip (R-series)        | up to 30 dBm                | 3.3 V   | SPI        | External          | ~1 200-2 500 CZK | Requires custom RF front-end; cost and complexity unjustified at prototype stage; rejected |
| **YPD-R300**                        | spec 33 dBm / actual 25 dBm | **5 V** | **UART**   | **External, SMA** | **~800 CZK**     | **Selected**                                                                               |

- R300 selected over R200 for higher RF output (supporting the 2-3 m range requirement) and
  native 5 V supply matching the board power rail; over the integrated-antenna variant for
  external SMA connector enabling antenna substitution during range testing; over the bare chip
  for its complete carrier board and documented command protocol requiring no custom RF design
- **Vendor specification caveat:** the datasheet-stated 33 dBm ceiling is incorrect; hardware
  cap is 25 dBm - `set_power(33)` returns error `0x48`; initially missed due to absent response
  validation; a general caution on cost-tier module datasheets; full details in Section 3.3.2

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
  supply design must sustain transient loads without causing voltage rail collapse - a failure mode that manifests as
  device reset and was encountered during Board v2 bring-up

`[REF: relevant IC datasheets cited in Section 3.2 hardware design]`

### 2.3.4 timekeeping without a hardware RTC

- The ESP32-WROOM-32 module does not include a battery-backed hardware RTC; the internal RTC counter runs only while the
  device is powered and loses its value on cold boot `[REF: ESP32 TRM Section 9.3.6]`
- For an attendance system, all events must carry timestamps traceable to real calendar time; a boot-relative counter is
  insufficient
- SNTP (Simple Network Time Protocol) synchronisation over WiFi is the standard approach for ESP32 timekeeping; ESP-IDF
  provides a built-in SNTP component; accuracy is adequate for attendance timestamping (sub-second error after sync)
  `[REF: IETF RFC 4330 - SNTPv4]`
- The limitation of SNTP-only timekeeping is that time is lost when the device is powered off or loses network access; a
  `timeBasis` field (`synced` / `estimated` / `relative`) is declared on every event payload to communicate timestamp
  quality to the server, which can then apply appropriate handling
- A hardware RTC IC with coin cell backup would eliminate this limitation and is identified as the primary hardware
  improvement for a future board revision

---

## 2.4 communication protocols and enterprise integration

- Two distinct communication paths exist in this system with different requirements: the
  firmware-to-server path (frequent small messages from a constrained embedded device on an
  unreliable network) and the server-to-enterprise path (low-frequency, high-importance
  attendance records pushed to an HR system)

**Table 2.4-1** - Device-to-server protocol candidates

| Protocol  | Overhead                               | Embedded suitability                                          | Decision                                                    |
| --------- | -------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------- |
| HTTP/REST | Full TCP + HTTP round-trip per message | Poor - too heavy for frequent small publishes; no server push | Rejected for firmware; used on server-to-enterprise path    |
| WebSocket | Persistent full-duplex TCP             | Moderate - reconnection logic burdens constrained clients     | Rejected for firmware; used for dashboard real-time updates |
| AMQP      | Broker-heavy, complex handshake        | Poor - no lightweight ESP-IDF client                          | Rejected                                                    |
| **MQTT**  | Minimal fixed header, pub/sub          | **Designed for constrained devices on unreliable networks**   | **Selected** `[REF: OASIS MQTT 3.1.1]`                      |

- MQTT features directly applied: QoS 1 for live scan publishes (at-least-once, tolerable
  during high-frequency scan windows); QoS 2 for offline replay (exactly-once, prevents
  duplicate attendance records); LWT for automatic device-offline detection without polling
- **Offline-first:** events written to LittleFS before any transmission attempt; replayed on
  reconnection - no event discarded due to transient network unavailability
- **Server-to-enterprise path - REST:** attendance records created once per traversal event;
  stateless REST appropriate - low frequency, widely supported by enterprise software,
  idempotent by design
- **Navigo3:** integration target; Czech HR and project management platform by Navigo Solutions s.r.o.; REST API built
  on the open-source `dry-api` framework (typed JSON-over-HTTP)
  `[REF: NavigoSolutions/dry-api - github.com/NavigoSolutions/dry-api]`
  `[REF: navigo3.com/cs/api-a-predchystane-integrace]`; attendance recording endpoints extended with parametrised
  `start`/`stop` overloads in release 2026.03, co-developed with this thesis; implementation detail in section 3.4.5

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
  encryption overhead negligible `[REF: ESP32 TRM Section 14 - AES Accelerator]`
- **WiFi provisioning approach:** the ESP-IDF `wifi_provisioning` component (BLE-based) was evaluated but rejected - it
  requires a companion mobile application; a custom captive portal (SoftAP + DNS hijack + HTTP form served from SPIFFS)
  was implemented instead, working with any device browser regardless of OS

**Table 2.5-1** - ESP-IDF components used and their role

| Component     | Role                                                      |
| ------------- | --------------------------------------------------------- |
| FreeRTOS      | Task scheduling, inter-task queues, event groups          |
| esp_mqtt      | MQTT client - QoS 1/2, LWT, automatic reconnect           |
| nvs_flash     | Persistent key-value storage (credentials, config, state) |
| esp_littlefs  | Offline event cache filesystem                            |
| esp_sntp      | NTP time synchronisation                                  |
| mbedTLS (AES) | Credential encryption via hardware AES accelerator        |
| esp_wifi      | STA + AP mode, captive portal provisioning                |
