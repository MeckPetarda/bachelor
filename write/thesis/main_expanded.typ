// =============================================================================
//  main.typ - Thesis entry point
// =============================================================================

#import "template/vut-fsi.typ": thesis

// Figure placeholder helper - used where actual image files do not exist yet
#let fig-placeholder(caption-text) = figure(
  rect(width: 100%, height: 5cm, fill: luma(220), stroke: luma(160),
    align(center + horizon, text(fill: luma(100), size: 10pt, style: "italic",
      [TODO: ] + caption-text + []))),
  caption: caption-text,
)

#show: thesis.with(
  title-cs: "Embedded řešení docházkového systému pro integraci do podnikové aplikace",
  title-en: "Embedded Implementation of an Attendance System for Integration into an Enterprise Application",
  author: "Jakub Hloušek",
  author-short: "Hloušek, J.",
  supervisor: "Ing. Michal Bastl, Ph.D.",
  supervisor-citation: "Ing. Michal Bastl, Ph.D.",
  faculty-cs: "Fakulta strojního inženýrství",
  faculty-en: "Faculty of Mechanical Engineering",
  institute-cs: "Ústav mechaniky těles, mechatroniky a biomechaniky",
  institute-en: "Institute of Solid Mechanics, Mechatronics and Biomechanics",
  degree: "B",

  abstract-cs: [Zde bude abstrakt.],
  abstract-en: [Abstract goes here.],
  keywords-cs: [Klíčová slova zde.],
  keywords-en: [Keywords here.],
  declaration: [Declaration text goes here.],
  acknowledgements: [Acknowledgements go here.],
)

// =============================================================================
// 1. INTRODUCTION
// =============================================================================

= Introduction <intro>

- Enterprise attendance tracking - routine operational need feeding payroll, project time allocation, compliance
- Dominant solutions (PIN terminals, HF RFID card readers, biometrics) share a common flaw: require deliberate employee
  interaction at a fixed point; friction, bottlenecks, buddy-punching
- Concrete motivation: need at Navigo Solutions s.r.o. (Brno) - passive, zero-interaction attendance recording feeding
  directly into Navigo3 HR software
- Core technical challenge: (1) passive identification at 2-3 m range through bags and pockets, (2) direction of
  traversal - arrival vs. departure - without physical gates
- UHF RFID (860-960 MHz) - only commercially mature technology meeting the passive, hands-free range requirement
- Direction detection requires two spatially separated units: a single reader cannot distinguish entry from exit;
  *portal model* - two Lighthouse units mounted on opposite sides of a doorway; raw RFID readings jointly analysed
  server-side; traversal direction inferred from temporal sequence
- Each Lighthouse: autonomous embedded device with UHF RFID reader, WiFi/MQTT, battery backup; publishes raw readings
  only - no local direction decisions
- Server hosts detection pipeline, database, operator dashboard, and enterprise integration layer
- Integration target: Navigo3; integration layer isolated behind a connector interface - extensible to other enterprise
  platforms without changes to the core pipeline

#fig-placeholder[Figure 1-1: System concept diagram - two Lighthouse units flanking a doorway, person walking through, MQTT to server, server to Navigo3]

// =============================================================================
// 2. RESEARCH
// =============================================================================

= Research <research>

== Attendance System Technologies <attendance_system_tech>

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
- *Conclusion:* UHF RFID is the only passive identification technology meeting the hands-free, 2-3 m range
  requirement; selected as the identification method for this system

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Technology][Read range][User action][Sensitive data][Selected],
    [PIN code],              [N/A],            [Yes], [No],  [No],
    [HF RFID (13.56 MHz)],  [0–10 cm],        [Yes], [No],  [No],
    [Biometric],            [Contact / ~1 m], [No],  [Yes], [No],
    [UHF RFID (860–960 MHz)],[1–12 m],        [No],  [No],  [*Yes*],
  ),
  caption: [Table 2.1-1 - Identification technology comparison],
)

== Direction Detection Methods <direction_detection_methods>

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
- *Two algorithmic families* emerge from this literature: temporal centroid and RSSI-weighted
  centroid; both require the full set of raw timestamped RSSI readings from both readers -
  per-device deduplication would destroy the signal; detailed formulations in #ref(<direction_detection_and_event_processing>)

#fig-placeholder[Figure 2.2-1: Dual RSSI curves over time for a single traversal; temporal centroids C_out and C_in marked; RSSI peaks labelled; direction arrow outside to inside]

== Hardware Platforms and Embedded Architectures <hardware_platforms_and_embedded_architectures>

=== Microcontroller Selection <microcontroller_selection>

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
  module cost (~\$3-5) make it the clear choice
- *Selected:* ESP32-WROOM-32 module

=== UHF RFID Reader Modules <uhf_rfid_reader_modules>

- The embedded-integration tier - compact modules with a UART interface, controlled directly
  by a microcontroller - was surveyed; key selection criteria: documented UART command
  protocol, 5 V supply compatibility, and unit cost suitable for small scope prototyping

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto),
    table.header[Module][RF output][Supply][Interface][Antenna][Price (approx.)],
    [Impinj R420],       [+30 dBm], [PoE],  [LLRP/Ethernet], [External], [\$800+],
    [ThingMagic M6e],    [+27 dBm], [5 V],  [UART/USB],      [External], [\$200+],
    [SparkFun M6E Nano], [+27 dBm], [3.3 V],[UART],          [External], [\$60+],
    [*YPD-R300*],        [*+25 dBm*],[*5 V*],[*UART*],       [*External*],[*~\$15*],
  ),
  caption: [Table 2.3.2-1 - UHF RFID reader module candidates],
)

- R300 selected over R200 for higher RF output (supporting the 2-3 m range requirement) and
  native 5 V supply matching the board power rail; over the integrated-antenna variant for
  external SMA connector enabling antenna substitution during range testing; over the bare chip
  for its complete carrier board and documented command protocol requiring no custom RF design
- *Vendor specification caveat:* the datasheet-stated 33 dBm ceiling is incorrect; hardware
  cap is 25 dBm - `set_power(33)` returns error `0x48`; initially missed due to absent response
  validation; a general caution on cost-tier module datasheets; full details in #ref(<uhf_rfid_scan_control>)

=== Power Supply and Battery Considerations <power_supply_and_battery_considerations>

- The Lighthouse unit must operate from USB-C mains power with a lithium battery providing backup autonomy; both sources
  must be able to power the device simultaneously with automatic, safe arbitration between them
- A single lithium cell (3.7 V nominal) cannot directly supply the ESP32 (requires 3.3 V regulated) or the RFID reader
  module (requires 5 V); a boost converter is required to raise the battery output to 5 V, from which a 3.3 V LDO can be
  derived
- Battery charging, protection (overcurrent, overvoltage, undervoltage), and source arbitration (USB vs. boost output
  via Schottky diode OR configuration) are well-defined sub-problems with established reference circuits; standard ICs
  exist for each function and were selected during hardware design (covered on #ref(<power_delivery_architecture>, form: "page"))
- Critical consideration: the UHF RFID reader draws significant peak current during active scan windows; the power
  supply design must sustain transient loads without causing voltage rail collapse - a failure mode that manifests as
  device reset and was encountered during Board v2 bring-up

=== Timekeeping Without a Hardware RTC <timekeeping_without_a_hardware_rtc>

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

== Communication Protocols and Enterprise Integration <communication_protocols_and_enterprise_integration>

- Two distinct communication paths exist in this system with different requirements: the
  firmware-to-server path (frequent small messages from a constrained embedded device on an
  unreliable network) and the server-to-enterprise path (low-frequency, high-importance
  attendance records pushed to an HR system)

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Protocol][Suitability for firmware][Decision],
    [HTTP/REST],  [Too heavy for frequent small publishes; no server push], [Rejected for firmware; used server-to-enterprise],
    [WebSocket],  [Reconnection logic burdens constrained clients],          [Rejected for firmware; used for dashboard],
    [AMQP],       [No lightweight ESP-IDF client],                           [Rejected],
    [*MQTT*],     [*Designed for constrained devices on unreliable networks*],[*Selected*],
  ),
  caption: [Table 2.4-1 - Communication protocol comparison for firmware transport],
)

- MQTT features directly applied: QoS 1 for live scan publishes (at-least-once, tolerable
  during high-frequency scan windows); QoS 2 for offline replay (exactly-once, prevents
  duplicate attendance records); LWT for automatic device-offline detection without polling
- *Offline-first:* events written to LittleFS before any transmission attempt; replayed on
  reconnection - no event discarded due to transient network unavailability
- *Server-to-enterprise path - REST:* attendance records created once per traversal event;
  stateless REST appropriate - low frequency, widely supported by enterprise software,
  idempotent by design
- *Navigo3:* integration target; Czech HR and project management platform by Navigo Solutions s.r.o.; REST API built
  on the open-source `dry-api` framework (typed JSON-over-HTTP)
  `[REF: NavigoSolutions/dry-api - github.com/NavigoSolutions/dry-api]`
  `[REF: navigo3.com/cs/api-a-predchystane-integrace]`; attendance recording endpoints extended with parametrised
  `start`/`stop` overloads in release 2026.03, co-developed with this thesis; implementation detail in section 3.4.5

== Embedded Software Frameworks <embedded_software_frameworks>

- The ESP32 platform is supported by ESP-IDF (Espressif IoT Development Framework), the official vendor SDK; it
  integrates all components needed for this project and avoids the fragmentation of assembling a firmware stack from
  independent libraries `[REF: Espressif ESP-IDF Programming Guide; Malý [3]]`
- *FreeRTOS* (integrated into ESP-IDF): preemptive real-time kernel; provides tasks, queues, semaphores, and event
  groups; the dual-core architecture allows the WiFi stack (managed by ESP-IDF) to run on Core 0 while application tasks
  (RFID control, MQTT, offline cache, LED state machine) run on Core 1 without interference; the standard choice for
  ESP32 application firmware `[REF: FreeRTOS documentation]`
- *NVS (Non-Volatile Storage):* key-value store over internal flash with transparent wear-levelling; used for WiFi
  credentials, MQTT broker address, device identity, last known good timestamp, and offline buffer pointers; simpler and
  more robust than a raw flash partition for configuration data
- *LittleFS:* wear-levelling filesystem for NOR flash, included as an ESP-IDF component; chosen over SPIFFS (the older
  alternative) for its better crash resilience and support for directories; used for the offline event cache
- *mbedTLS (AES):* TLS and cryptographic library integrated into ESP-IDF; AES-128-ECB used for encrypting WiFi
  credentials stored in NVS; the ESP32 hardware AES accelerator is used transparently via the mbedTLS API, keeping
  encryption overhead negligible `[REF: ESP32 TRM Section 14 - AES Accelerator]`
- *WiFi provisioning approach:* the ESP-IDF `wifi_provisioning` component (BLE-based) was evaluated but rejected - it
  requires a companion mobile application; a custom captive portal (SoftAP + DNS hijack + HTTP form served from SPIFFS)
  was implemented instead, working with any device browser regardless of OS

#figure(
  table(
    columns: (auto, auto),
    table.header[Component][Role],
[ FreeRTOS      ],[ Task scheduling, inter-task queues, event groups          ],
[ esp_mqtt      ],[ MQTT client - QoS 1/2, LWT, automatic reconnect           ],
[ nvs_flash     ],[ Persistent key-value storage (credentials, config, state) ],
[ esp_littlefs  ],[ Offline event cache filesystem                            ],
[ esp_sntp      ],[ NTP time synchronisation                                  ],
[ mbedTLS (AES) ],[ Credential encryption via hardware AES accelerator        ],
[ esp_wifi      ],[ STA + AP mode, captive portal provisioning                ],
  ),
  caption: [Table 2.5-1 - ESP-IDF components used and their role],
)

// =============================================================================
// 3. IMPLEMENTATION AND RESULTS
// =============================================================================

= Implementation and Results <implementation_and_results>

== System Architecture <system_architecture>

The Lighthouse attendance system is built around a portal model: two physically separate detection units are deployed on opposite sides of a doorway, with one unit designated as OUTSIDE and the other as INSIDE. These two units collectively form a single detection portal. When a person carrying a passive UHF RFID tag crosses the threshold, both units detect the tag in a temporal sequence that encodes the direction of movement. The fundamental architectural principle is that direction inference is a server-side responsibility - each Lighthouse unit operates autonomously, publishing only raw timestamped RSSI measurements over MQTT, with no knowledge of its paired counterpart and no attempt to determine direction locally. This keeps the embedded firmware thin, power-efficient, and focused on reliable tag detection and data transmission, while the detection algorithms remain centrally maintainable on the server.

Each Lighthouse unit is an embedded device built around the ESP32-WROOM-32 microcontroller communicating with a YPD-R300 UHF RFID reader module over UART (per ESP32 TRM Section 7; YPD-R300 Protocol Section 1.2). The unit includes onboard power management (USB-C input and lithium-ion battery backup), local offline event caching to a LittleFS partition on the ESP32's flash memory, and WiFi/MQTT connectivity for scan data upload and health telemetry reporting. Four status LEDs provide visual feedback on WiFi connection state, MQTT broker connectivity, active RFID scanning, and tag detection events. Two buttons allow manual control of scan mode and WiFi provisioning entry, and an AM312 PIR motion sensor triggers automatic RFID scan windows when movement is detected near the portal.

Lighthouse units are logically paired on the server into a *group*, which becomes the unit of direction detection. Raw scans are clustered and processed per (tag EPC, group) pair. A Lighthouse can belong to at most one group at any given time; scans from ungrouped Lighthouses are orphaned by the event processing pipeline after a configurable timeout. Each group has independently tunable parameters: `activityTimeoutMs` (default 4 000 ms) defines how long after the last scan a cluster is considered closed and ready for processing, while `orphanTimeoutMs` (default 8 000 ms) determines when scans from misconfigured or unpaired devices are discarded.

The server is a single BunJS process that hosts an embedded Aedes MQTT broker, a PostgreSQL-backed REST API built with the Hono framework, and a WebSocket gateway for real-time dashboard updates. It also serves the SolidJS web dashboard as a static build from the same process. The server's responsibilities include: ingesting raw scan batches from MQTT and persisting them to the `raw_scans` table; running the EventSweeper background poller that clusters unprocessed scans and invokes both direction detection algorithms; managing user accounts and tag-to-user assignments; and pushing successfully processed events to the Navigo3 REST API with a retry-on-failure mechanism. The Navigo3 integration is isolated behind a connector interface controlled by environment variables, allowing the system to be extended to other enterprise platforms without modifications to the core event processing pipeline.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Component][Technology][Responsibility],
    [Lighthouse unit (×2)],  [ESP32-WROOM-32 + YPD-R300],         [Passive UHF RFID detection; raw scan publish via MQTT],
    [Server],                [BunJS, Hono, Aedes, PostgreSQL],     [Scan ingestion, direction detection, user management, API; embedded MQTT broker and chrony NTP server],
    [Dashboard],             [SolidJS SPA],                        [Operator interface: device management, event monitoring, user setup],
    [Navigo3 integration],   [REST connector + background poller], [Translates processed events into attendance records in Navigo3],
  ),
  caption: [Table 3.1-1 - System components and their responsibilities],
)

The end-to-end event lifecycle from tag detection to attendance record creation proceeds as follows. An IR motion sensor detects movement near the portal, triggering the firmware to open a 5-second RFID scan window. The YPD-R300 reader runs continuous real-time inventory (command `0x89` per YPD-R300 Protocol Section 2.4) during this window, with detections batched on the firmware side and published to the MQTT topic `lighthouse/{id}/scans` as timestamped RSSI arrays. The server's scan handler ingests each batch, validates individual elements, and persists valid scans to the `raw_scans` table while preserving the `timeBasis` field (`synced` / `estimated` / `relative`) that indicates timestamp quality. The EventSweeper background poller runs every 2 seconds, clustering unprocessed scans by (EPC, group). Once a cluster is considered closed (no new scans for `activityTimeoutMs`), both direction detection algorithms execute and each produces an independent row in the `processed_events` table. The processed event is immediately pushed to Navigo3 via its `attendance/embedded/start` or `stop` endpoint depending on the detected direction. If the push fails, a separate background retry sweep picks it up within the configured `NAVIGO3_RETRY_INTERVAL_MS`. If connectivity is lost before the firmware can publish to MQTT, scans are cached to a LittleFS ring buffer on the ESP32's flash and replayed in order on reconnection with QoS 2 for delivery guarantees.

#figure(
  image("./images/3.1-1_system_architecture.png", width: 80%),
  caption: [Figure 3.1-1: System architecture block diagram - Lighthouse A and B communicating via MQTT to Server; Server connected bidirectionally to Web Client via REST + WebSocket; Server connected to Navigo3 via REST API]
)

== Hardware Design <hardware_design>

=== Board v1 - Breadboard Prototype <board_v1_-_breadboard_prototype>

The first functional prototype was assembled on a breadboard using four off-the-shelf breakout modules: an ESP32-WROOM-32 development board (38-pin variant), a YPD-R300 UHF RFID reader module on its carrier board, an SX1308 step-up DC-DC converter module, and a TP4056 lithium battery charger module with integrated DW01HA protection IC and FS8205A dual MOSFET. None of these modules shipped with complete engineering documentation beyond basic pinout labels, so each was reverse-engineered prior to integration. This reverse-engineering process involved hands-on measurements with a multimeter, selective desoldering of components to trace internal routing, and cross-referencing against datasheets for identifiable ICs where available. The resulting schematics captured component values, internal connections, and undocumented design decisions, and became the baseline for the Board v2 custom PCB design. The goal was to reproduce and then improve upon the combined functionality of these four modules on a single integrated board.

#figure(
  image("./images/IMG_20260305_011321.jpg", width: 80%),
  caption: [Figure 3.2.1-1: Photograph of the two Board v1 breadboard prototypes; components labelled: ESP32 dev board, YPD-R300 on carrier, SX1308 boost module, TP4056 charger, battery holder, PIR sensor, status LEDs, buttons, antenna with coaxial pigtail]
)

Component selection and concurrency architecture were validated on the breadboard. The ESP32-WROOM-32 proved capable of running the WiFi network stack, MQTT client, and UART-driven RFID operations concurrently using the dual-core Xtensa LX6 architecture, with the WiFi stack pinned to Core 0 and application logic running on Core 1 (per ESP32 TRM Section 1.1). The YPD-R300 reader communicates with the ESP32 via UART at 115 200 baud (per YPD-R300 Protocol Section 1.2). GPIO assignments for UART TX/RX, status LEDs, buttons, PIR motion sensor input, and the BC337 NPN transistor-based RFID power switch were established during breadboard testing and carried forward unchanged to Board v2. Power delivery on the breadboard used point-to-point wiring between the four modules, which introduced uncontrolled trace impedance and measurable voltage drops under pulsed RFID load, motivating the decision to move to a purpose-designed PCB with calculated trace widths and dedicated decoupling capacitance positioned close to load switching points.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Module][Key components identified][Disposition in Board v2],
    [ESP32 dev board (38-pin)], [AMS1117-3.3 LDO, CP2102 USB-UART, EN/BOOT buttons],            [ESP32-WROOM-32 module placed directly; AMS1117 retained; CP2102 removed],
    [YPD-R300 carrier board],   [R300 module, SMA connector, decoupling capacitors],            [R300 module placed directly; SMA replaced with IPEX/U.FL footprint],
    [SX1308 boost module],      [SX1308 IC, 4.7 µH inductor, Schottky diode, feedback divider], [Circuit reproduced with confirmed component values],
    [TP4056 charger module],    [TP4056 IC, DW01HA protection, FS8205A dual MOSFET],            [Circuit reproduced; charge current set via programming resistor],
  ),
  caption: [Table 3.2.1-1 - Reverse-engineered modules and their Board v2 disposition],
)

=== Board v2 - Custom PCB <board_v2_-_custom_pcb>

Board v2 is a single two-layer PCB integrating all functionality of the four breadboard modules plus additional circuitry for power switching, fuse protection, battery voltage monitoring, and consolidated USB-C connectivity. The board was designed in KiCad with the schematic split into four hierarchical sheets (see Appendix A): a top-level Lighthouse sheet, a Charger submodule sheet, a Step-up DC/DC converter sheet, and a UHF RFID reader sheet. This hierarchical structure mirrors the modular nature of the breadboard prototype and keeps each functional block's schematic content manageable and self-contained. The CP2102 USB-UART bridge present on the original ESP32 development board was intentionally omitted from Board v2 to reduce component cost and simplify SMD assembly. In its place, UART TX, RX, and GND are broken out to a 3-pin header, allowing firmware debugging and flashing via an external USB-UART adapter. The reader is assumed to have the complete schematic sheets from Appendix A available for side-by-side reference; the following subsections describe key design decisions and deviations from the baseline breadboard design rather than replicating full schematic content.

#fig-placeholder[Figure 3.2.2-1: KiCad 3D render of the assembled Board v2 PCB - top view showing component placement: ESP32-WROOM-32 module, USB-C connector, UART pin header, status LEDs, PIR sensor, buttons, SX1308 boost section, TP4056 charger section, battery holder, RFID reader footprint with IPEX antenna connector]

==== GPIO Assignments <gpio_assignments>

The Board v2 schematic defines all GPIO connections between the ESP32-WROOM-32 module and peripherals. These assignments were validated during breadboard testing and are documented in the top-level Lighthouse schematic sheet (Appendix A, Sheet 1).

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[GPIO][Peripheral][Function],
    [GPIO4],  [LED1 (green)],      [WiFi + MQTT combined status indicator],
    [GPIO21], [LED2 (green)],      [IR mode / AP provisioning indicator],
    [GPIO26], [LED3 (red)],        [Active RFID scan indicator],
    [GPIO25], [LED4 (yellow)],     [Tag detection flash / battery status],
    [GPIO22], [BUTTON1],           [Scan mode control (with external pull-up)],
    [GPIO23], [BUTTON2],           [Status message / WiFi setup trigger (with external pull-up)],
    [GPIO19], [IR_SENSOR],         [AM312 PIR motion sensor input],
    [GPIO16], [R300 UART RX],      [UART receive from YPD-R300],
    [GPIO17], [R300 UART TX],      [UART transmit to YPD-R300],
    [GPIO5],  [RFID_POWER_SWITCH], [BC337 base drive for R300 power control],
    [GPIO33], [BATTERY_SENSE],     [ADC1_CH5 for battery voltage monitoring],
  ),
  caption: [Table 3.2.2-1 - ESP32 GPIO assignments on Board v2],
)

GPIO5 is a strapping pin on the ESP32 (per ESP32 Datasheet Section 2.3) and must be held high during boot to select SPI boot mode. The Board v2 schematic includes a 10 kΩ pull-up resistor on GPIO5 to ensure reliable boot behaviour while still allowing it to function as a general-purpose output for the BC337 base drive after boot completes. GPIO33 was selected for battery voltage monitoring because it is connected to ADC1_CH5, which remains available for use during active WiFi operation; ADC2 channels share hardware with the WiFi RF subsystem and cannot be sampled reliably while WiFi is active (per ESP32 TRM Section 31.4.2).

==== USB-C Connector <usb-c_connector>

The breadboard prototype used two separate USB connectors: one for power input and one for the CP2102 UART bridge used for firmware flashing and debug serial output. Board v2 consolidates power input into a single USB-C connector carrying only VBUS and GND. The UART debug interface is separated to the dedicated 3-pin header mentioned above, accessed via an external USB-UART adapter during development. USB-C UFP (Upstream Facing Port) identification requires 5.1 kΩ pull-down resistors on both CC1 and CC2 pins to signal to the USB power source that the device is drawing power rather than supplying it (per USB Type-C Cable and Connector Specification Section 4.5.1). Without these resistors, only certain USB chargers will supply VBUS - an issue that was observed during breadboard testing where some phone chargers and USB power banks refused to provide power until the CC termination was added.

==== Power Delivery Architecture <power_delivery_architecture>

Board v2 implements a dual-input power architecture with automatic source selection. The primary power source is USB 5 V from the USB-C connector. The backup source is a single-cell lithium-ion battery (nominal 3.7 V, operating range 3.2 V to 4.2 V) stepped up to 5 V by an SX1308 boost converter. Two SS24A Schottky diodes (DO-214AC package, 2 A / 40 V rating, typical forward drop ~0.3–0.4 V) are arranged in an OR configuration to prevent backfeed between the two sources (see Step-up DC/DC Converter sheet, Appendix A). SF-1206SP100-2 slow-blow fuses (1 A, 63 VDC, 1206 package) are placed on each input path upstream of the diodes. The slow-blow type was selected to tolerate the YPD-R300 reader's power-on inrush current without spurious tripping. A DPDT slide switch (SLW-1678105-6A-N-D, 1 A / 12 VDC, through-hole) is positioned after the fuses and before the diode junction, switching both input paths simultaneously to provide complete power isolation while keeping the fuses always in-circuit for protection.

The 5 V rail downstream of the diode OR junction feeds an AMS1117-3.3 LDO regulator (per AMS1117 datasheet) which produces the 3.3 V rail for the ESP32-WROOM-32 module and peripheral logic. The YPD-R300 RFID reader operates directly from the 5 V rail and is switched on and off via a BC337-25 NPN transistor used as a low-side switch (see RFID Reader Power Switching subsection below). When USB power is present, the TP4056 charger IC draws current from VBUS to charge the lithium-ion cell; the DW01HA protection IC and FS8205A dual MOSFET provide overcharge, overdischarge, and overcurrent protection (per TP4056 and DW01HA datasheets). When USB power is removed, the system switches seamlessly to battery power via the SX1308 boost converter with no interruption to operation.

#figure(
  image("./images/3.2.2-2_power_delivery.svg", width: 80%),
  caption: [Figure 3.2.2-2: Power delivery block diagram - USB-C VBUS and battery cell as inputs -> fuses -> DPDT switch -> SS24A diode OR -> 5 V rail -> AMS1117-3.3 LDO -> 3.3 V rail; battery path includes SX1308 boost (3.2-4.2 V -> 5 V); TP4056/DW01HA charges battery from VBUS when present]
)

==== RFID Reader Power Switching <rfid_reader_power_switching>

The YPD-R300 reader draws approximately 380 mA at 5 V during active RFID inventory operations (per YPD-R300 datasheet). To conserve power when the reader is idle, Board v2 includes a BC337-25 NPN transistor (TO-92 package) configured as a low-side switch in the reader's ground return path, controlled by ESP32 GPIO5. The BC337-25 was selected for its low saturation voltage (V_CE(sat) ~300 mV at 380 mA collector current per BC337 datasheet) and 800 mA maximum collector current rating, providing comfortable headroom over the reader's nominal draw. A 150 Ω base resistor provides approximately 17 mA of base drive current when GPIO5 is high (3.3 V), forcing the transistor into hard saturation with a forced beta of approximately 22 at 380 mA collector current. This ensures V_CE(sat) remains low, keeping the ground offset introduced by the switch small enough to not affect the YPD-R300's operation.

==== Supply Stabilisation and Decoupling <supply_stabilisation_and_decoupling>

The YPD-R300 reader draws current in sustained 18.8 ms RF transmission pulses occurring at 30–50 ms intervals during continuous inventory operations. This pulsed load profile requires bulk capacitance rather than ceramic-only decoupling to prevent supply rail droop that could cause brownout resets on the ESP32. Board v2 uses a combination of electrolytic bulk capacitors and ceramic bypass capacitors positioned close to each load.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Location][Capacitance][Type / Notes],
    [R300 5 V rail],        [470 µF + 100 nF], [Electrolytic bulk + ceramic bypass],
    [ESP32 3.3 V rail],     [100 µF + 100 nF], [Electrolytic bulk + ceramic bypass],
    [SX1308 output (5 V)],  [100 µF],          [Electrolytic; per SX1308 reference design],
    [AMS1117 input (5 V)],  [10 µF],           [Electrolytic; per AMS1117 datasheet],
    [AMS1117 output (3.3 V)], [22 µF],         [Electrolytic; per AMS1117 datasheet],
  ),
  caption: [Table 3.2.2-2 - Decoupling capacitance placement],
)

The 470 µF electrolytic capacitor on the R300 5 V rail was sized to limit voltage droop during the reader's 18.8 ms RF pulses to less than 200 mV, based on the measured current draw and acceptable ripple tolerance. Ceramic 100 nF bypass capacitors are placed immediately adjacent to the power pins of the R300 module and the ESP32-WROOM-32 module to suppress high-frequency switching noise. The SX1308 boost converter and AMS1117 LDO capacitor values follow the respective datasheets' recommended application circuits.

=== Antenna and RF Considerations <antenna_and_rf_considerations>

UHF RFID operates in the 860–960 MHz range (ETSI band 865–868 MHz in Europe, FCC 902–928 MHz in North America). At these frequencies, signal integrity of the connection between the R300 module's RF output and the antenna is critical to maintaining detection range. The YPD-R300 module's RF output is specified for 50 Ω impedance (per YPD-R300 datasheet Section 3.1); any mismatch in the feed path causes reflected power, reducing effective radiated power and read range. Board v2 was designed with an IPEX/U.FL surface-mount coaxial receptacle footprint on the PCB edge, connected to the R300 module's RF output pad via a 2 cm microstrip trace. However, the first fabricated unit was assembled with this footprint unpopulated due to parts availability constraints at the time of assembly, and the antenna connection was instead made by hand-soldering a coaxial pigtail cable directly to the R300 RF output pad, bypassing the PCB trace entirely.

This first unit achieved consistent 3 m detection range with a 4 dBi circularly polarised panel antenna. When the second unit was assembled, the same hand-solder approach was attempted but yielded only 0.5 m range despite using an identical R300 module, identical firmware, and the same antenna model. Multiple attempts were made to rework the solder joint on the second unit in an effort to recover range, but performance never improved beyond the initial 0.5 m baseline and in some cases worsened during rework. These repeated failures demonstrated that hand-soldered RF joints at 900 MHz are unreliable and sensitive to mechanical inconsistencies that are difficult to control or reproduce. The hand-solder approach was abandoned in favour of proper coaxial connectors.

The second unit was rebuilt with the IPEX receptacle properly populated and a snap-on coaxial cable connecting to the antenna. However, even with the proper connector, this unit did not match the 3 m range of the first unit when using the same 4 dBi antenna. Both the second and third units were subsequently upgraded to 5.5 dBi antennas, and in combination with a firmware change to real-time inventory mode (command `0x89` per YPD-R300 Protocol Section 2.4, increasing scan density from ~4 tags per 250 ms polling window to ~60 tags per 5 s scan burst), both units now achieve 5 m unobstructed detection range. The fact that the second unit with a proper IPEX connector and 2 cm PCB trace initially underperformed the first unit with a direct hand-solder bypass suggests that the PCB trace introduces a meaningful impedance discontinuity at 900 MHz.

Board v2's 2 cm microstrip trace between the R300 RF pad and the IPEX footprint was not impedance-controlled during layout. Achieving 50 Ω characteristic impedance on a microstrip trace requires specific trace width relative to the PCB substrate thickness, dielectric constant, and copper weight - constraints that were not explicitly calculated or verified during the Board v2 design process. This is identified as a known limitation discovered post-fabrication. While the current units with 5.5 dBi antennas perform adequately at 5 m range, they are likely still subject to some degree of impedance mismatch loss and would probably achieve better range if the trace were eliminated or properly impedance-controlled. A future board revision should reposition the IPEX/U.FL receptacle immediately adjacent to the R300 RF output pad to eliminate the trace entirely, removing the impedance discontinuity and the associated RF loss.

#fig-placeholder[Figure 3.2.3-1: Annotated photograph or diagram comparing the two antenna connection methods - (a) coaxial pigtail soldered directly to R300 RF pad bypassing PCB trace (Unit 1), (b) signal routed through 2 cm PCB trace to board-edge IPEX connector (Units 2 and 3); impedance discontinuity at the trace highlighted as suspected loss source]

=== Enclosure <enclosure>

A prototype enclosure was designed in FreeCAD to house the Board v2 PCB, battery, PIR sensor, and antenna in a wall-mountable form factor suitable for doorway deployment. The design addresses several constraints imposed by the operational requirements of a passive detection system. The PIR sensor window must face the detection zone to trigger RFID scan windows when personnel approach the portal. The antenna must be oriented toward the doorway with minimal physical obstruction to maintain the detection range validated during board testing. The USB-C port must remain accessible for charging and firmware updates without disassembling the enclosure. The four status LEDs must be visible to operators for diagnostic purposes, implemented via light pipes from the PCB-mounted LEDs to the enclosure front face. The two push buttons must remain accessible for manual scan mode control and WiFi provisioning entry.

#figure(
  image("./images/3.2.4-1_case.png", width: 80%),
  caption: [Figure 3.2.4-1: CAD model screenshot - front/side view of the enclosure showing PIR window, antenna position, LED light pipes, and USB-C port access]
)

#figure(
  image("./images/3.2.4-2_case.png", width: 80%),
  caption: [Figure 3.2.4-2: CAD model screenshot - exploded or open view showing internal component placement: PCB, battery, antenna mounting]
)

Three enclosures were manufactured via 3D printing and assembled, one for each fabricated Board v2 unit currently in operation. Full technical drawings of the enclosure including dimensioned orthographic projections and section views are provided in Appendix B.

== Firmware <firmware>

The Lighthouse firmware is written in C using ESP-IDF v5.x with FreeRTOS as the underlying real-time operating system. The entire application runs on a single ESP32-WROOM-32 module, taking advantage of the dual-core Xtensa LX6 architecture to separate concerns between networking and application logic. By default, ESP-IDF pins the WiFi stack to Core 0, leaving Core 1 available for application tasks including RFID reader communication, offline event caching, and the main control loop (per ESP32 TRM Section 1.1). This isolation ensures that WiFi stack operations do not interfere with the timing-sensitive UART communication with the YPD-R300 reader module.

The firmware binary is identical across all Lighthouse units deployed in the field - no unit-specific configuration is compiled in at build time. All per-device settings are configured at runtime via the provisioning system and stored persistently in the ESP32's NVS. This design allows a single firmware image to be flashed to multiple devices during manufacturing or field deployment, with each device then individually configured via the captive portal interface without requiring a recompile or reflash.

=== System Initialization and WiFi Provisioning <system_initialization_and_wifi_provisioning>

On boot, the firmware executes a sequential initialization across multiple subsystems. The boot sequence begins with GPIO configuration to set up pin modes and initial states for LEDs, buttons, and the BC337 RFID power switch. Next, the battery monitor initializes to enable voltage sensing on GPIO33 (ADC1_CH5). The WiFi provisioning subsystem then loads credentials from NVS if present and attempts to connect in Station (STA) mode; if no credentials are stored, the boot sequence blocks after GPIO initialization and waits for the user to manually trigger the provisioning flow. Once WiFi is connected, SNTP (Simple Network Time Protocol) synchronizes the system clock against the MQTT broker's IP address, which also runs a chrony NTP server for timekeeping. With time synchronized, the MQTT client initializes and connects to the broker, followed by the offline event logger which mounts the LittleFS partition and prepares the ring buffer for caching scans during network outages. Finally, the RFID reader initializes and the main task loop begins.

If the device has never been configured - indicated by the absence of a "configured" flag in the NVS partition - the boot sequence blocks after GPIO initialization and the firmware logs a message instructing the user to press and hold BUTTON2 for 5 seconds to enter setup mode. The device will not proceed to initialize the RFID reader or attempt any network operations until valid WiFi credentials have been provisioned and the device has successfully connected to the network.

==== Provisioning Flow <provisioning_flow>

Provisioning is triggered by a 5-second continuous hold of BUTTON2, at which point it sets a flag in RTC-backed memory and calls `esp_restart()` to reboot the ESP32. On the subsequent boot, the firmware detects the presence of this RTC flag during early initialization and transitions into Access Point (AP) mode instead of attempting STA mode connection. This reboot-based transition ensures a clean state with no residual tasks or network connections from the previous operational mode.

In AP mode, the ESP32 broadcasts an open WiFi network with the SSID "Lighthouse-Setup" and starts an HTTP server listening on port 80. The server serves a minimal HTML configuration form stored in the firmware's SPIFFS virtual filesystem partition. Concurrently, a lightweight DNS server is started that responds to all DNS queries. This DNS hijacking enables captive portal detection on iOS, Android, Windows, and macOS; when a user's device connects to the "Lighthouse-Setup" network, the operating system automatically detects the captive portal and opens a system browser window to the provisioning page without requiring the user to manually navigate to an IP address.

The provisioning form collects four fields: WiFi SSID, WiFi password, MQTT broker IP address, and MQTT broker port. Client-side JavaScript validates the input format before allowing submission. When the user submits the form, the device attempts to connect to the specified WiFi network in STA mode while keeping the AP active. If the connection succeeds, the firmware then attempts to connect to the MQTT broker at the provided IP and port to verify end-to-end connectivity. The results of both tests are reported back to the browser. The device then reboots when the user clicks the restart button on the page letting the device to begin normal operation.

Credentials are encrypted before being written to NVS. The firmware uses AES-128 in ECB mode via the mbedTLS library utilizing ESP32's hardware AES accelerator to perform encryption and decryption (per ESP32 TRM Section 14). The encryption key is a device-specific 16-byte constant defined at compile time in a configuration header; in a production deployment, this key would be unique per device and generated during the firmware build process. The SSID is zero-padded to 32 bytes (two AES blocks) and the password is zero-padded to 64 bytes (four AES blocks) before encryption. The encrypted blobs are stored in a dedicated NVS namespace within the `nvs_settings` partition, separate from other configuration data to reduce the risk of corruption during writes. On subsequent boots, the credentials are loaded from NVS, decrypted in memory, and used to automatically connect to the provisioned WiFi network without user intervention.

#figure(
  image("./images/3.3.1-1_boot_sequence.svg", width: 80%),
  caption: [Figure 3.3.1-1: Provisioning state machine diagram]
)

#figure(
  image("./images/3.3.1-2_page.png", height: 8cm),
  caption: [Figure 3.3.1-2: Screenshot of the provisioning web form as rendered on a mobile device - showing WiFi SSID/password fields, MQTT broker IP/port fields, test buttons, and status display area]
)

=== UHF RFID Scan Control <uhf_rfid_scan_control>

The YPD-R300 UHF RFID reader module communicates with the ESP32 via UART at 115 200 baud, configured on GPIO16 (RX) and GPIO17 (TX) using UART2 (per R300 Protocol V2.2 Section 1.2; ESP32 TRM Section 7.8). RFID scanning is performed using the real-time inventory command `0x89` (`cmd_name_real_time_inventory`) with channel parameter `0xFF` to enable full-spectrum frequency hopping and minimize round duration, and a 10 ms inter-round delay configured in firmware (per R300 Protocol Section 2.2.8, page 27). In real-time inventory mode, the reader streams tag detection packets to the ESP32 as they occur during each RF transmission round, rather than buffering them internally and sending a consolidated response at the end. Each packet contains the tag's Electronic Product Code (EPC) identifier, received signal strength indicator (RSSI) in dBm, frequency channel and antenna ID, and the ISO 18000-6C protocol control (PC) word. Under typical operating conditions with a single tag in range, a 5-second scan window produces approximately 60 individual tag detection packets - corresponding to roughly 12 RF rounds per second with an average of 5 detections per round.

==== IR-Triggered Scanning <ir-triggered_scanning>

The AM312 PIR (passive infrared) motion sensor mounted on GPIO19 detects movement in the doorway and triggers RFID scan bursts via a GPIO interrupt configured for rising edge detection with an IRAM-safe interrupt service routine (`IRAM_ATTR` attribute ensures the ISR code is loaded into internal RAM to avoid flash cache misses during interrupt execution). When the IR sensor fires, the firmware powers on the R300 module by driving the BC337-25 NPN transistor base via GPIO5, waits 200 ms for the reader's internal oscillator to stabilize, performs a UART handshake by sending a firmware version query command (`0x72`) to verify that the reader is responsive and correctly initialized, and then starts real-time inventory. The scan burst runs for a duration defined by `IR_SCAN_DURATION_MS`, defaulting to 5s. If additional IR triggers arrive while a scan burst is already active, the burst timer is restarted without interrupting the ongoing inventory operation - this extends the scan window when a person lingers near the doorway rather than passing directly through, ensuring that all tag detections during their presence are captured. When the burst timer expires with no further IR triggers received, the inventory command is stopped by sending a `0x28` stop command to the R300 module, and the module is powered off via the transistor switch to conserve battery power.

==== MQTT Batch Accumulator <mqtt_batch_accumulator>

The firmware initially published one MQTT message per tag detection packet received from the R300, producing approximately 60 individual MQTT publishes during a 5-second scan window. This high-frequency publish pattern saturated the ESP-MQTT client's internal outbox queue and triggered TCP connection resets (errno 104 "Connection reset by peer") from the Aedes MQTT broker running on the server. To resolve this, tag detections are now accumulated in a time-windowed batch buffer on the firmware side before transmission. The accumulator collects tag detection events for up to `scan_batch_ms` milliseconds (default 150 ms, configurable) or until the buffer reaches its capacity of `MQTT_SCAN_BATCH_MAX_ENTRIES` (64 entries), whichever occurs first. When either condition is met, the firmware flushes the batch as a single JSON array to the MQTT topic `lighthouse/{id}/scans`. The live scan publish path uses QoS 1 to reduce the overhead of the four-way handshake required by QoS 2; the reduction in MQTT protocol overhead combined with the batching allows the firmware to sustain high scan rates without overwhelming the broker. The offline replay path, which delivers historically cached events after network restoration, retains QoS 2 to guarantee exactly-once delivery and prevent duplicate attendance records.

==== Power Cap Discovery <power_cap_discovery>

During initial range testing, firmware configured the R300 transmit power to 33 dBm using the `set_power` command (`0x76` per R300 Protocol Section 2.1.7, page 12) under the assumption that the module supported the full range specified in the datasheet (20–33 dBm). However, the YPD-R300 hardware variant used in this project has a power amplifier cap at 25 dBm; attempts to set power above this threshold return error code `0x48` ("output_power_out_of_range" per R300 Protocol Section 3, page 39). This error was silently ignored for an extended period because the firmware did not initially read or validate R300 command responses - it assumed that all commands succeeded. The firmware now reads the response packet following every `set_power` command and validates that the response contains success code `0x10`. Transmit power is clamped to the range 20–25 dBm in firmware to prevent rejected commands, and the validated power level is logged on successful configuration to confirm that the R300 accepted the requested setting.

=== Timekeeping and Timestamp Quality <timekeeping_and_timestamp_quality>

The ESP32 does not include a battery-backed hardware Real-Time Clock (RTC); the internal RTC timer runs from a 150 kHz oscillator with approximately 5% drift under typical operating conditions (per ESP32 Datasheet Section 3.3.4). After a power cycle or hard reset, the system clock starts from an undefined epoch and must be synchronized via SNTP before timestamps represent meaningful wall-clock time. To ensure that the server can correctly interpret every event timestamp regardless of when it was recorded relative to SNTP synchronization, the firmware implements a three-tier time quality model in which every scan event payload includes a `timeBasis` field that declares the trustworthiness of its accompanying timestamp.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Quality level][timeBasis value][Condition][Accuracy],
    [Synced],    [`synced`],     [SNTP synchronisation completed successfully],                                    [Millisecond-level (network + NTP jitter)],
    [Estimated], [`estimated`],  [No SNTP sync yet, but last-known-good time recovered from NVS],                  [Seconds to minutes (RTC drift ~5% at 150 kHz)],
    [Relative],  [`relative`],   [No NVS time available; first boot or NVS lost],                                  [Boot-relative milliseconds only; not a real wall-clock time],
  ),
  caption: [Table 3.3.3-1 - Time quality tiers],
)

==== SNTP Synchronisation <sntp_synchronisation>

The firmware uses the ESP-IDF SNTP client component in polling mode, configured to synchronize against a chrony NTP server running on the same host as the MQTT broker. On successful synchronization, an SNTP callback registered via `sntp_set_time_sync_notification_cb()` upgrades the time quality state from `TIME_QUALITY_NONE` or `TIME_QUALITY_ESTIMATED` to `TIME_QUALITY_SYNCED`, and persists both the current Unix timestamp (in seconds) and the ESP32 uptime counter value (in milliseconds from `esp_timer_get_time()`) to NVS under keys `last_unix_s` and `last_uptime_ms` in the `time_sync` namespace. This timestamp-uptime pair allows the firmware on the next boot to estimate wall-clock time even before SNTP synchronization completes, by loading the persisted values and recognizing that the current time must be at least `last_unix_s` seconds past the Unix epoch (it cannot be earlier, even if the device was powered off for an extended period). The timezone is set to Central European Time with automatic daylight saving transitions (`TZ=CET-1CEST,M3.5.0,M10.5.0/3`) via `setenv("TZ", ...)` and `tzset()` before SNTP initialization, ensuring that `localtime()` and `gmtime()` return correctly offset local time immediately upon successful synchronization.

==== Offline Degradation <offline_degradation>

If SNTP synchronization does not complete within a reasonable timeout (for example, if the NTP server is unreachable due to network configuration issues or server downtime), the firmware continues normal operation with `estimated` or `relative` timestamp quality rather than blocking indefinitely. Events logged during this degraded time state carry the `timeBasis` field set to `estimated` if a last-known-good time was recovered from NVS, or `relative` if no NVS time is available (first boot after flash erase). The server-side scan ingestion handler reads the `timeBasis` field on every incoming scan and uses it to decide whether the scan is eligible for direction detection processing. Scans with `timeBasis` values other than `synced` are flagged and handled by orphan processing logic on the server, which either rejects them entirely or uses the MQTT message arrival timestamp (`received_at`) as a best-effort fallback for temporal ordering.

=== MQTT Communication and Offline Caching <mqtt_communication_and_offline_caching>

==== MQTT Client <mqtt_client>

The firmware connects to the MQTT broker using the `esp_mqtt_client` component included with ESP-IDF, with connection parameters (broker IP address and port number) loaded from NVS where they were stored during the WiFi provisioning flow. The MQTT client ID is derived from the ESP32's eFuse MAC address (a factory-programmed unique identifier burned into one-time-programmable memory per ESP32 TRM Section 4.4), ensuring that each device has a unique client ID to prevent broker-side connection conflicts when multiple Lighthouse units connect to the same broker. A Last Will and Testament (LWT) message is registered when the MQTT connection is established, configured to publish a disconnection notification to the topic `lighthouse/{id}/lwt` with QoS 1 and the retain flag set. This allows the server to detect unexpected disconnections (such as power loss or network failure) without relying on periodic keepalive polling; if the ESP32 disconnects without sending a graceful DISCONNECT packet, the broker automatically publishes the LWT message on the client's behalf.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Topic][Direction][QoS][Content],
    [`lighthouse/{id}/scans`],  [Publish (live)],   [1], [Batched JSON array of tag detections],
    [`lighthouse/{id}/scans`],  [Publish (replay)], [2], [Replayed offline-cached events],
    [`lighthouse/{id}/health`], [Publish],          [1], [Periodic health telemetry (system, RFID, battery)],
    [`lighthouse/{id}/config`], [Subscribe],        [1], [Runtime configuration updates from server],
  ),
  caption: [Table 3.3.4-1 - MQTT topics and QoS levels],
)

==== Offline Event Caching <offline_event_caching>

When the MQTT connection is unavailable - either because the broker is unreachable, the network link is down, or the device has not yet completed WiFi association - tag detection events are stored to a dedicated LittleFS partition on the ESP32's internal flash memory. This partition is entirely separate from the SPIFFS partition used to store the WiFi provisioning HTML form; SPIFFS is a read-only filesystem image compiled into the firmware binary at build time using the `spiffs_create_partition_image()` CMake function, whereas LittleFS is a writable wear-leveling filesystem mounted at runtime and used exclusively for offline event storage. Events are written to a ring buffer file named `events.bin` stored in the root of the LittleFS mount point, with each event entry protected by a CRC32 checksum to detect corruption from partial writes or flash wear. Write and read index pointers are persisted to two independent locations: RTC memory (a small region of SRAM that survives soft resets triggered by `esp_restart()` but is cleared on hard power-down) for fast recovery after watchdog resets or firmware updates, and NVS (Non-Volatile Storage) for recovery after power loss.

On MQTT reconnection, a background replay task (`offline_replay_task`) is spawned with lower priority than the main event logging task to ensure that real-time tag detections are not delayed by replay activity. The replay task reads cached events from the LittleFS ring buffer and publishes them to the same MQTT topic (`lighthouse/{id}/scans`) at a throttled rate of at most 10 events per second, with each replayed event carrying QoS 2 for exactly-once delivery guarantees. The firmware adds an `offline: true` boolean flag and a `replayTime` field containing the Unix timestamp at the moment of replay to each replayed event payload, allowing the server to distinguish replayed historical events from live real-time detections and to reconstruct the timeline accounting for the period during which the device was offline.

#figure(
  image("./images/3.3.4-1_offline_replay.svg", width: 80%),
  caption: [Figure 3.3.4-1: Offline caching and replay sequence diagram]
)

=== User Interaction: Buttons, LEDs, and Gestures <user_interaction>

The IO subsystem manages four status LEDs, two tactile buttons, and one passive infrared motion sensor. All GPIO configuration, button debouncing, LED state management, and scan mode logic are encapsulated in a dedicated `io_controller` module (`io_controller.c` and `io_controller.h`), keeping the main application file (`lighthouse.c`) limited to orchestration responsibilities and MQTT/offline event routing. This separation improves maintainability and allows the IO logic to be tested and modified independently of the higher-level application state machine.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Constant][GPIO][Function],
    [LED1_PIN],      [4],  [WiFi + MQTT combined status (green)],
    [LED2_PIN],      [21], [IR mode / AP provisioning indicator (green)],
    [SCANNING_LED],  [26], [Active RFID scan indicator (red)],
    [ACTIVITY_LED],  [25], [Tag detection flash / battery status (yellow)],
    [BUTTON1_PIN],   [22], [Scan mode control],
    [BUTTON2_PIN],   [23], [Status message / WiFi setup trigger],
    [IR_SENSOR_PIN], [19], [AM312 PIR motion sensor],
  ),
  caption: [Table 3.3.5-1 - GPIO pin assignments],
)

GPIO22 and GPIO23 (button inputs) use external pull-up resistors on the PCB; the ESP32's internal pull-ups are disabled in firmware configuration. Debounce filtering is applied in software using a simple time-threshold approach: a button state change is only registered if the GPIO level remains stable for at least 50 ms after the initial transition. This 50 ms debounce threshold effectively suppresses mechanical contact bounce without introducing perceptible delay in the user experience.

==== Scan Modes <scan_modes>

The firmware operates in one of two scan modes, selectable via a 3-second hold of BUTTON1. The mode determines whether RFID scan bursts are triggered automatically by IR motion detection or manually by button press. The two modes are mutually exclusive and do not persist across soft resets (the mode state is re-initialized to IR Mode on every boot).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Mode][LED2 state][IR sensor][BUTTON1 short press][Entry condition],
    [IR Mode (default)], [Solid on], [Active - triggers 5 s scan bursts], [No-op],              [3 s hold from Manual / Boot],
    [Manual Mode],       [Off],      [Ignored],                           [Toggle RFID on/off], [3 s hold from IR Mode],
  ),
  caption: [Table 3.3.5-2 - Scan mode behavior],
)

Before any mode transition executes, the firmware unconditionally stops any active RFID inventory operation by sending the `0x28` stop command to the R300 module and powers off the reader via the BC337 transistor to ensure a clean state. This prevents mode transitions from leaving the RFID reader in an undefined operational state or consuming power unnecessarily.

#figure(
  image("./images/3.3.5-1_scan_mode_fsm.svg", width: 80%),
  caption: [Figure 3.3.5-1: Scan mode state machine - two states (IR Mode, Manual Mode); transitions: 3-second BUTTON1 hold in either direction; entry actions listed for each state (stop RFID, set LED2, enable/disable IR)]
)

==== Button Gestures <button_gestures>

The firmware recognizes both short-press (momentary tap) and long-hold gestures on each button, as well as a dual-button combo gesture for developer-level cache purge operations. Long-hold thresholds are detected by tracking the elapsed time since the initial button press and firing the associated action only once when the threshold is crossed.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Button][Gesture][Action],
    [BUTTON1], [Short press], [Toggle RFID scan (Manual Mode only; no-op in IR Mode)],
    [BUTTON1], [3 s hold],    [Switch between IR Mode and Manual Mode],
    [BUTTON2], [Short press], [Publish status/statistics message via MQTT],
    [BUTTON2], [5 s hold],    [Enter WiFi AP provisioning (triggers reboot into setup mode)],
    [Both],    [10 s hold],   [Cache purge: clear offline event cache, confirmation LED sequence, restart],
  ),
  caption: [Table 3.3.5-3 - Complete button gesture reference],
)

==== Cache Purge Combo Gesture <cache_purge_combo_gesture>

Holding both BUTTON1 and BUTTON2 simultaneously for 10 seconds triggers a developer cache purge gesture that clears the offline event ring buffer. During the 10-second hold period, LEDs illuminate sequentially as a visual countdown: LED1 at 2.5 seconds, LED2 at 5 seconds, ACTIVITY_LED at 7.5 seconds, and SCANNING_LED at 10 seconds (all LEDs then illuminated). At the 10-second threshold, the firmware calls `offline_logger_clear_all()` to reset the LittleFS ring buffer read and write pointers to zero, plays a confirmation flash sequence (each LED flashed in order at 200 ms intervals), and calls `esp_restart()` to reboot the device. Releasing either button before the 10-second threshold is reached cancels the gesture immediately and restores all LEDs to their normal operational states. While the combo gesture is active, RFID scanning is stopped if in progress, and IR trigger events are suppressed to prevent interference with the gesture countdown.

==== LED Indicator Behavior <led_indicator_behavior>

LED1 (green) provides combined status indication for WiFi and MQTT connectivity. When the WiFi connection is not established, LED1 remains off. When WiFi is connected but the MQTT client has not yet successfully connected to the broker, LED1 blinks at a 1-second period (500 ms on, 500 ms off). When both WiFi and MQTT are connected, LED1 is solid on. LED2 (green) indicates the current scan mode: solid on when IR Mode is active, off when Manual Mode is active. During WiFi provisioning, LED2 is controlled by the provisioning subsystem and blinks until the MQTT connectivity test passes, at which point it turns solid on as a final confirmation before reboot. SCANNING_LED (red) is on whenever an RFID inventory operation is in progress and off otherwise. ACTIVITY_LED (yellow) flashes briefly (100 ms pulse) each time a tag detection event is logged; this flash is superimposed on the battery status pattern when running on battery power.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[LED][Condition][State],
    [LED1 (green)],      [No WiFi connection],        [Off],
    [LED1 (green)],      [WiFi connected, no MQTT],   [Blinking 1 s period],
    [LED1 (green)],      [WiFi + MQTT connected],     [Solid on],
    [LED2 (green)],      [IR Mode active],            [Solid on],
    [LED2 (green)],      [Manual Mode active],        [Off],
    [SCANNING_LED (red)],    [RFID inventory in progress], [On],
    [SCANNING_LED (red)],    [No active inventory],        [Off],
    [ACTIVITY_LED (yellow)], [Tag detected],               [Brief 100 ms flash],
  ),
  caption: [Table 3.3.5-4 - LED states during normal operation],
)

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[LED][Provisioning phase][State],
    [LED1 (green)], [AP active, WiFi test not yet passed], [Blinking],
    [LED1 (green)], [WiFi test passed],                    [Solid on],
    [LED2 (green)], [AP active, MQTT test not yet passed], [Blinking],
    [LED2 (green)], [MQTT test passed],                    [Solid on],
  ),
  caption: [Table 3.3.5-5 - LED states during AP provisioning],
)

==== Battery Status LED Patterns (ACTIVITY_LED, Battery Power Only) <battery_status_led_patterns>

When the device is running on battery power (USB not connected), ACTIVITY_LED provides continuous battery level indication via repeating pulse patterns with different cadences corresponding to charge percentage thresholds. When USB power is connected, the battery status pattern is suppressed and ACTIVITY_LED is used exclusively for tag detection flashes. The battery LED patterns are generated in a dedicated FreeRTOS task (`battery_led_task`) running at low priority; this task yields between pattern iterations to avoid interfering with the brief 100 ms tag detection flashes that are triggered synchronously from the RFID event handler.

#figure(
  table(
    columns: (auto, auto),
    table.header[Battery level][LED pattern],
    [USB powered],    [Off (tag detection flashes only)],
    [Battery > 10%],  [Brief flash every 5 seconds],
    [Battery 5–10%],  [Pulsing 500 ms on/off],
    [Battery < 5%],   [Rapid pulsing 200 ms on/off],
  ),
  caption: [Table 3.3.5-6 - Battery level indication],
)

== Server <server>

=== Infrastructure and Stack <infrastructure_and_stack>

The server component runs as a single BunJS process that consolidates all backend subsystems: the HTTP REST API, an embedded MQTT broker, a WebSocket gateway for real-time dashboard updates, and several background pollers responsible for event processing and external system integration. This monolithic-process architecture eliminates the operational complexity of managing multiple service processes while maintaining clear internal component boundaries through modular TypeScript code organization.

BunJS was selected as the JavaScript runtime for its native TypeScript support, rapid cold-start performance, and integrated tooling. Unlike Node.js, which requires transpilation and external build tooling, Bun executes TypeScript files directly, reducing development friction and deployment complexity. The runtime's built-in test framework further streamlines the development workflow.

The HTTP layer is implemented using Hono, a lightweight web framework designed for edge and serverless environments. Hono provides Express-like middleware composition and routing while avoiding the runtime overhead of legacy frameworks. The framework's TypeScript-native design ensures type safety across request handlers and eliminates an entire class of routing and parameter mismatches that would only surface at runtime in untyped systems.

PostgreSQL serves as the system's primary data store. The choice of a relational database over document stores or key-value systems was driven by the need for transactional consistency in the event processing pipeline and the relational nature of lighthouse groupings, tag assignments, and user records. Drizzle ORM provides type-safe query construction while maintaining a thin abstraction layer over SQL-the schema definitions in TypeScript generate corresponding SQL migrations, and all database queries are statically type-checked at compile time. Drizzle's column name casing configuration maps between JavaScript's camelCase conventions and PostgreSQL's snake_case standards automatically, eliminating a common source of runtime field name mismatches.

Aedes, a Node.js-native MQTT broker, is embedded directly into the server process. This design decision trades horizontal scalability for operational simplicity-the embedded broker removes the need to deploy and configure an external MQTT service like Mosquitto or VerneMQ. For the target deployment scale (dozens of Lighthouse units, not thousands), the embedded broker's throughput is sufficient, and in-process message handling enables direct synchronous database writes from MQTT message callbacks without the latency and failure modes introduced by inter-process communication.

The dashboard frontend is built with SolidJS and compiled to static HTML/CSS/JavaScript at build time. The server process serves these static assets directly through Hono's static file middleware, eliminating the need for a separate web server or CDN for the administrative interface. Real-time updates from the backend to connected dashboard clients are delivered via WebSocket connections managed by Bun's native WebSocket implementation.

Background processing tasks-namely the event sweeper (which detects completed RFID scan clusters and invokes direction detection algorithms) and the Navigo3 integration poller (which retries failed external system pushes)-run as interval-based polling loops within the same process. The event sweeper queries the database every 2 seconds for unprocessed scan clusters, while the Navigo3 poller operates on a configurable interval to re-attempt synchronization of events that failed initial delivery to the enterprise system.

This architecture delivers a single deployable artifact-one process, one repository, one configuration surface-while preserving internal modularity through TypeScript's module system and Hono's middleware composition. The entire server can be version-controlled, deployed, and monitored as a unit, significantly reducing the cognitive and operational overhead compared to microservice-based alternatives.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Component][Technology][Role],
    [HTTP API],          [Hono],                     [REST endpoints, JWT auth],
    [MQTT Broker],       [Aedes],                    [Receives firmware scan/health messages],
    [Database],          [PSQL + Drizzle], [Persistent event and user storage],
    [WebSocket Gateway], [Bun WebSocket],             [Real-time push to dashboard clients],
    [Navigo3 Poller],    [Custom interval],           [Periodic retry of unsynced events],
    [Event Sweeper],     [Custom interval],           [Cluster detection and direction processing],
  ),
  caption: [Table 3.4.1-1 - Server component responsibilities],
)

#fig-placeholder[Figure 3.4.1-1: Server internal component diagram - showing message flow from MQTT broker through scan handler to DB, and from event sweeper through algorithm layer to processed_events and WebSocket broadcast]

=== Event Ingestion and Raw Scan Storage <event_ingestion_and_raw_scan_storage>

The firmware publishes RFID tag detection data to the server via MQTT using the topic pattern `lighthouse/{id}/scans`, where `{id}` is the device's MAC address. As described in #ref(<mqtt_batch_accumulator>), the firmware batches tag detections into JSON arrays to avoid saturating the MQTT broker with individual per-tag publishes during high-density scan windows. Each array element represents a single tag detection and contains the following fields: `epc` (the tag's Electronic Product Code), `rssiDbm` (received signal strength in decibels-milliwatts), `timestampMs` (the detection time as a Unix timestamp in milliseconds), and `timeBasis` (a quality indicator with values `synced`, `estimated`, or `relative`, as defined by the firmware's time synchronization subsystem in Section 3.3.3).

The server-side scan handler validates each array element independently. Malformed elements-those missing required fields or containing invalid data types-are logged and discarded without aborting processing of the remaining valid elements in the batch. This per-element validation strategy ensures that transient firmware bugs or data corruption in transit cannot cause entire scan batches to be lost. Valid scan entries are persisted to the `raw_scans` table immediately upon receipt.

The `raw_scans` table functions as an immutable audit log. Once inserted, scan records are never updated or deleted by normal system operation; they serve as the authoritative source of truth for all downstream event processing and forensic analysis. The table schema includes the following key fields:

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Field][Type][Description],
    [`id`],           [`bigint`],                 [Auto-increment primary key],
    [`lighthouseId`], [`int`],                    [FK to lighthouses],
    [`epc`],          [`varchar`],                [Tag EPC identifier],
    [`rssiDbm`],      [`int (nullable)`],         [Signal strength in dBm],
    [`timestamp`],    [`timestamptz`],            [Tag detection time (from firmware)],
    [`timeBasis`],    [`enum`],                   [`synced` / `estimated` / `relative`],
    [`processedAt`],  [`timestamptz (nullable)`], [Set when cluster is processed],
    [`orphanedAt`],   [`timestamptz (nullable)`], [Set when scan is orphaned],
  ),
  caption: [Table 3.4.2-1 - `raw_scans` table key fields],
)

The `processedAt` and `orphanedAt` columns both default to `NULL` at insertion time, marking the scan as pending. The event sweeper (described in #ref(<direction_detection_and_event_processing>)) queries for scans where both fields are `NULL`, clusters them by tag EPC and lighthouse group, and invokes direction detection algorithms. Scans that successfully contribute to a detected entry or exit event have their `processedAt` field updated to the current timestamp; scans that remain isolated beyond the configured activity timeout are marked as orphans by setting `orphanedAt`.

The `timeBasis` field is stored verbatim and is not interpreted during ingestion. The decision to accept or reject scans based on timestamp quality is deferred to the event sweeper. During cluster formation, scans with `timeBasis` other than `synced` are filtered out, as only SNTP-synchronized timestamps provide the temporal precision required for direction detection. Non-synced scans are immediately marked as orphans and excluded from event processing. This separation of concerns keeps the ingestion path simple and fast while concentrating time quality logic in a single downstream component.

Health telemetry-system uptime, free heap memory, WiFi signal strength, and RFID reader responsiveness-is published by the firmware to a separate MQTT topic, `lighthouse/{id}/health`. These messages are stored in a dedicated `lighthouse_health_snapshots` table but are not part of the event processing pipeline. Health data is used exclusively for operational monitoring and diagnostics via the dashboard.

The ingestion architecture is designed for append-only, high-throughput write patterns. Database writes occur synchronously in the MQTT message handler callback, leveraging PostgreSQL's write-ahead logging to ensure durability without blocking the broker's event loop. Upon successful insertion, the server broadcasts a real-time scan event to all connected WebSocket clients, enabling live tag detection visualization in the dashboard without requiring client polling.

#figure(
  image("./images/3.4.2-1_mqtt_ingestion.svg", width: 80%),
  caption: [Figure 3.4.2-1: MQTT ingestion sequence - firmware batch publish -> broker -> scan handler -> per-element validation -> DB insert -> WebSocket broadcast of raw scan event]
)

=== Direction Detection and Event Processing <direction_detection_and_event_processing>

==== Cluster detection and event sweeper <cluster_detection_and_event_sweeper>

The event sweeper is a background polling service that identifies completed RFID scan clusters and invokes the direction detection pipeline. A cluster represents all raw scan records associated with a single tag traversal attempt through a portal-scans from both the inside and outside Lighthouse units, spanning the time interval during which the tag was within detection range of at least one unit. The sweeper runs at a fixed 2-second interval, decoupled from both the MQTT ingestion rate and the algorithmic processing time of individual clusters.

A cluster is defined as the set of all `raw_scans` records matching a specific `(epc, groupId)` tuple where the most recent scan timestamp is older than the group's configured `activityTimeoutMs` threshold. The default activity timeout is 4 seconds-this value establishes the maximum permissible gap between consecutive detections before the system considers the tag to have exited the detection zone. The timeout is stored per-group in the database and can be adjusted via the REST API to account for differences in walking speed, portal geometry, or reader sensitivity across deployment sites.

The cluster detection query operates on the `raw_scans` table, grouping unprocessed records (those with `processedAt IS NULL` and `orphanedAt IS NULL`) by `(epc, groupId)` and filtering the resulting groups with the condition `MAX(timestamp) < NOW() - activityTimeoutMs`. This temporal filter ensures that only clusters whose tag activity has conclusively ended are passed to the processing pipeline-scans from ongoing traversals remain pending until the activity timeout expires. The query additionally filters out scans from Lighthouse units that have no assigned group, as these cannot participate in paired direction detection.

To bound the computational cost of each sweeper cycle and prevent a backlog of unprocessed clusters from causing unbounded processing delays, the sweeper processes a maximum of 50 clusters per tick. If more than 50 closed clusters exist at a given poll, the excess clusters are deferred to the next cycle. This cap ensures that the sweeper's execution time remains predictable and does not starve other server subsystems of CPU time during periods of high tag traversal density.

Scans from ungrouped Lighthouse units-those with `groupId IS NULL`-are handled separately. Such scans represent a system misconfiguration: a Lighthouse unit is publishing data but has not been assigned to a portal. These scans cannot contribute to direction detection and are orphaned immediately once they exceed a fixed 10-second timeout. The orphan reason is set to `misconfigured_group`, and the scans are excluded from all future processing. This separation prevents ungrouped units from polluting the event stream while preserving a record of the misconfiguration for diagnostic purposes.


#figure(
  image("./images/3.4.3-1_event_sweeper.svg", width: 80%),
  caption: [Figure 3.4.3-1: Event sweeper cycle flowchart]
)

==== Algorithm 1 - Temporal Centroid (C₁) <algorithm_1_temporal_centroid>

Algorithm 1 determines traversal direction by comparing the arithmetic mean detection timestamps of the outside and inside scan groups. The temporal centroid of each group is computed as the simple average of all scan timestamps from that Lighthouse:

$ overline(t)_"out" = 1 / N_"out" sum_(i=1)^(N_"out") t_i^"out", quad overline(t)_"in" = 1 / N_"in" sum_(i=1)^(N_"in") t_i^"in" $

Direction is inferred from the ordering of these centroids. If the outside centroid precedes the inside centroid ($overline(t)_"out" < overline(t)_"in"$), the tag entered the portal from outside, and the event is classified as an entry (IN). Conversely, if the inside centroid precedes the outside centroid ($overline(t)_"in" < overline(t)_"out"$), the tag exited, and the event is classified as an exit (OUT). If the absolute difference between the centroids is less than or equal to 1 millisecond-within the margin of timestamp quantization-the direction is marked as unknown.

The confidence score for Algorithm 1 is the product of three independent dimensionless factors, each quantifying a distinct aspect of cluster quality. All factors are clamped to the range [FLOOR, 1.0], where FLOOR is a tunable constant (currently 0.1) that prevents any single degenerate factor from reducing the confidence to zero.

The *centroid separation factor* (CSF) measures the temporal distinctness of the two scan groups relative to the overall cluster duration:

$ "CSF" = (|overline(t)_"out" - overline(t)_"in"|) / (t_"cluster\_end" - t_"cluster\_start") $

A traversal where the outside and inside detections are well-separated in time produces a CSF approaching 1.0, indicating clear temporal sequencing. Overlapping scan groups-common when a person moves slowly or pauses within the detection zone-yield lower CSF values. If the cluster duration is zero (all scans occurred at the same timestamp, an edge case that can arise from firmware clock issues or extremely brief transits), CSF is clamped to FLOOR to prevent division by zero.

The *cluster size factor* (CSzF) rewards clusters with a larger total number of scans, up to a saturation threshold of 10 scans:

$ "CSzF" = min(1.0, (n_"total" - 2) / 8) $

This factor is predicated on the observation that a traversal with many detections provides more statistical evidence for direction than a cluster with only two or three scans. The saturation at 10 scans prevents the factor from indefinitely increasing with scan density, which would bias the confidence metric toward slower-moving individuals or tags with higher RFID responsiveness.

The *bilateral coverage factor* (BCF) quantifies the balance of scan distribution between the two Lighthouses:

$ "BCF" = (min(n_"in", n_"out")) / (max(n_"in", n_"out")) $

A perfectly balanced cluster-equal scan counts on both sides-yields BCF = 1.0. Asymmetric clusters, where one Lighthouse detects the tag many times while the other detects it only once or twice, produce lower BCF values, reflecting the reduced reliability of direction inference when one side of the portal contributes minimal data. This factor penalizes edge cases where a tag is detected primarily by one unit, which can occur if the tag is carried along the extreme edge of the portal or if one unit's antenna has degraded range.

The final confidence for Algorithm 1 is the product of these three factors:

$ C_1 = "CSF" times "CSzF" times "BCF" $

#figure(
  image("./images/3.4.3-2_dashboard.png", width: 80%),
  caption: [Figure 3.4.3-2: Cluster timeline diagram - horizontal time axis; two event types (Blue Lighthouse = inside, Orange Lighthouse = outside); scan detections shown as vertical ticks; cluster start/end markers],
)

==== Algorithm 2 - RSSI-Weighted Centroid (C₂) <algorithm_2_rssi-weighted_centroid>

Algorithm 2 extends the temporal centroid approach by incorporating RFID signal strength (RSSI) as a weighting factor in the centroid calculation. The underlying hypothesis is that scans with stronger signal strength are more indicative of the tag's true position relative to the reader at that instant, and therefore should be weighted more heavily in the temporal centroid. A tag held close to a reader antenna produces a high RSSI value and should shift the effective centroid toward that scan's timestamp; distant detections with weak signals contribute less to the centroid's position.

Each scan's RSSI value is transformed into a weight via a monotonically increasing function $w_i = f("RSSI"_i)$. The specific form of this function is implementation-defined but must satisfy the constraint that stronger signals yield higher weights. The weighted centroid for one Lighthouse group is then computed as:

$ overline(t)_w = (sum_i w_i dot t_i) / (sum_i w_i) $

This weighted mean replaces the arithmetic mean from Algorithm 1. Direction inference proceeds identically: $overline(t)_("w,out") < overline(t)_("w,in")$ implies entry; $overline(t)_("w,in") < overline(t)_("w,out")$ implies exit. The key advantage of RSSI weighting is that it can resolve direction even in cases where the arithmetic temporal centroids are nearly equal or where scan distributions overlap heavily in time-scenarios where Algorithm 1 would produce an unknown result or a low CSF confidence.

In addition to the weighted centroids, Algorithm 2 performs an independent linear regression analysis of RSSI versus time for each Lighthouse group. For the outside group, the regression computes the slope $m_"out"$ of the best-fit line through the points $(t_i^"out", "RSSI"_i^"out")$; similarly, the inside group yields slope $m_"in"$. The sign of these slopes encodes information about the tag's movement pattern. For an entry traversal (IN), the expected behavior is that the tag's signal weakens over time at the outside reader (negative slope, as the person moves away from the outside antenna) and strengthens at the inside reader (positive slope, as the person approaches the inside antenna). For an exit traversal (OUT), the trend reverses: inside slope negative, outside slope positive.

The RSSI trend consistency factor (RTCF) quantifies the agreement between the observed regression slopes and the slopes expected for the direction call produced by the weighted centroids:

- RTCF = 1.0 when both trends agree with the expected direction (both slopes have the correct sign).
- RTCF = FLOOR when both trends contradict the expected direction (both slopes have the wrong sign).
- RTCF = 0.5 when the regression is inconclusive-this occurs if either Lighthouse group has fewer than 3 scans (insufficient data for meaningful regression), if the coefficient of determination $R^2$ is below 0.1 (indicating a poor linear fit), or if one trend agrees while the other is inconclusive.

The use of a neutral 0.5 penalty rather than full contradiction (FLOOR) for inconclusive cases reflects the fact that real-world RFID data often contains noise, multipath interference, and orientation-dependent signal variation that degrade the linearity of the RSSI-time relationship. The RTCF factor rewards traversals where the physical movement pattern is clearly reflected in the signal trend while avoiding overpenalization of noisy but otherwise valid detections.

The confidence for Algorithm 2 incorporates RTCF as a fourth multiplicative factor:

$ C_2 = "CSF"_w times "CSzF" times "BCF" times "RTCF" $

The CSF, CSzF, and BCF factors are computed identically to Algorithm 1, except that the centroid separation factor uses the RSSI-weighted centroids rather than the arithmetic means. Algorithm 2 thus retains all the statistical rigor of the temporal centroid method while augmenting it with signal strength information that can disambiguate difficult cases.

==== Orphan handling <orphan_handling>

Not all scan clusters can be successfully processed into directional events. Three distinct failure modes exist, each resulting in scans being marked as orphans with a specific reason code stored in the `orphanReason` field of the `raw_scans` table.

The `insufficient_data` reason applies to clusters where only one Lighthouse in the group contributed scans. This can occur if a tag was detected by the outside reader but never entered the range of the inside reader, or vice versa. Such single-sided clusters lack the bilateral information required for direction detection and cannot produce a valid traversal event. However, these scans are not orphaned immediately upon cluster closure. Instead, they remain in the pending state until the cluster's age exceeds the group's `orphanTimeoutMs` threshold (distinct from the `activityTimeoutMs` used to determine cluster closure). The default orphan timeout is 8 seconds. This delayed orphaning allows for the possibility that additional scans from the missing Lighthouse might arrive late-due to firmware batching delays, MQTT retransmission, or offline cache replay-and complete the cluster retroactively. Only after the orphan timeout expires are the scans marked with `orphanedAt` and `orphanReason = insufficient_data`.

The `unsyncable` reason applies when all scans in a cluster have a `timeBasis` value other than `synced`. As described in #ref(<timekeeping_and_timestamp_quality>), the firmware attaches a time quality indicator to every scan event. Scans with `timeBasis` of `estimated` or `relative` lack the absolute timestamp accuracy required for centroid calculations and are therefore ineligible for direction detection algorithms. If a cluster consists entirely of non-synced scans, those scans are orphaned immediately with the `unsyncable` reason. If a cluster contains a mix of synced and non-synced scans, only the non-synced scans are orphaned; the synced scans remain in the pending state and may pair with future scans from the same tag and group.

The `misconfigured_group` reason applies to scans from Lighthouse units that have no `groupId` assigned in the database. Such units are not part of any portal and therefore cannot participate in paired direction detection. These scans are orphaned immediately upon detection by the sweeper, once they exceed the fixed 10-second ungrouped timeout. The rapid orphaning of misconfigured scans prevents them from accumulating indefinitely in the pending state and provides a clear diagnostic signal that a Lighthouse unit requires administrative intervention to be assigned to a group.

=== User and Tag Management <user_and_tag_management>

The system maintains an internal user registry separate from the external enterprise system to allow for decoupled operation and to support deployment scenarios where no external integration exists. Users are identified internally by a UUID primary key (`id`) that is never exposed to external systems. The `syncId` field stores the numeric user identifier from the external system-in this implementation, Navigo3-and serves as the foreign key for integration API calls. This dual-identifier design isolates the attendance system's data model from changes to external user ID formats or migration events where user IDs are reassigned in the enterprise system.

A user record can exist with or without a `syncId` value. Users created locally through the dashboard initially have `syncId` set to null and function as standalone entities within the Lighthouse system-their tag traversals are detected and logged, but no attempt is made to synchronize these events to Navigo3. When a `syncId` is later assigned via the dashboard or API, all past unsynced events for that user become eligible for retroactive integration push via the Navigo3 retry sweep. This design supports phased rollout scenarios where users are onboarded to the physical RFID system before their accounts are provisioned in the external software.

Each user can have multiple RFID tag EPCs assigned simultaneously. This accommodation reflects the practical reality that individuals may carry multiple tagged items-a lanyard-mounted tag, a second tag embedded in a wallet or bag, or temporary tags issued during badge replacement. Tag assignments are stored in a separate `tag_assignments` table with a many-to-one relationship to users. Each assignment includes an `assignedAt` timestamp and a nullable `deactivatedAt` timestamp. When a tag is reassigned to a different user, the previous assignment is soft-deleted by setting `deactivatedAt` to the current time rather than being removed from the database, preserving a complete audit trail of tag ownership history.

A database constraint enforces that at most one active assignment exists per tag EPC at any given time-two users cannot simultaneously claim the same tag. The uniqueness constraint is implemented as a partial index: `UNIQUE (tagEpc) WHERE deactivatedAt IS NULL`. This structure allows a tag to appear in the `tag_assignments` table multiple times across its lifecycle, with all historical assignments retained but only the most recent active assignment participating in user resolution during event processing.

=== Navigo3 Integration <navigo3_integration>

The Navigo3 integration layer is implemented as an isolated service module that consumes processed events from the direction detection pipeline and forwards them to the Navigo3 REST API. Integration is enabled or disabled entirely via the presence of environment variables: if `NAVIGO3_BASE_URL`, `NAVIGO3_USERNAME`, and `NAVIGO3_PASSWORD` are absent from the environment at server startup, the integration service initializes in a disabled state and imposes zero runtime overhead on the event processing pipeline-no eligibility checks are performed, no HTTP connections are established, and no polling threads are spawned.

When enabled, the integration service establishes an authenticated session with the Navigo3 API during server startup. The Navigo3 API uses a proprietary session-based authentication mechanism where a username and password are exchanged for a session token via a `POST /api/login` request, and this token is included as a bearer token in all subsequent requests. The session remains valid until the server process terminates or the Navigo3 instance invalidates it. Upon successful authentication, the service queries Navigo3 for the numeric `typeId` corresponding to the `atWork` attendance type-this identifier is required for all attendance record creation calls and is cached in-process for the lifetime of the server.

Every processed event-whether from Algorithm 1 or Algorithm 2-undergoes an eligibility check before any integration attempt. An event is eligible if and only if: (1) its `algorithmId` matches the value specified in the `NAVIGO3_ALGORITHM_ID` environment variable (either `temporal_centroid` or `rssi_weighted_centroid`), (2) its `direction` is either `in` or `out` (events with `direction: unknown` are never pushed), and (3) the associated user has a non-null `syncId`. This configuration-based algorithm filtering allows the system operator to select which detection method feeds the enterprise system while retaining both algorithms' outputs in the database for empirical comparison.

==== Immediate push <immediate_push>

Upon completion of the event processing transaction-after both algorithm result rows are written to the `processed_events` table and all constituent raw scans are marked with `processedAt`-the event processor invokes the integration service's `pushEvent()` function asynchronously. This call is wrapped in a non-blocking `setImmediate()` block to ensure that integration failures do not propagate exceptions back into the core event processing logic or delay the event sweeper's next cycle.

The `pushEvent()` function maps the event to one of two Navigo3 API endpoints based on direction. Entry events (`direction: in`) are sent to `POST /api/attendance/embedded/start`, which registers the person's arrival at the workplace. The request payload includes the user's numeric `userId` (parsed from `syncId`), the event timestamp formatted in Navigo3's required ISO 8601 variant, the cached `atWork` type identifier, and an empty comment field. Exit events (`direction: out`) are sent to `POST /api/attendance/embedded/stop`, which registers departure. The `stop` endpoint requires the same fields except for `typeId`, which is omitted as it is inferred from the most recent open attendance interval for that user.

On successful API response (HTTP 200), the `syncedToIntegration` flag on the `processed_events` row is set to `true`, marking the event as synchronized and excluding it from future retry attempts. If the HTTP request fails-due to network errors, authentication expiration, or Navigo3-side validation failures-the flag remains `false`, and the event is left in the unsynced state for the retry sweep to handle. No exceptions are thrown from the `setImmediate` block, ensuring that transient integration failures do not disrupt the core attendance detection pipeline.

==== Paired upsert <paired_upsert>

If a counterpart event already exists in the database-defined as an event for the same user (`userId`), opposite direction, and same calendar day-the integration service invokes `pushPair()` instead of `pushEvent()`. The counterpart check is performed via a database query that looks for an event matching these criteria with `syncedToIntegration: false`, indicating that both sides of the attendance interval are now available but neither has been pushed individually.

Paired events are sent to the `POST /api/attendance/embedded/upsert` endpoint, which creates or updates a closed attendance interval in Navigo3. This endpoint is semantically idempotent: if an interval for the given user and day already exists, the API updates the timestamps; otherwise, it creates a new record. The request payload includes `userId`, `day` (calendar date extracted from the entry event's timestamp), `timeFrom` (entry timestamp formatted as `HH:mm:ss`), `timeTo` (exit timestamp formatted as `HH:mm:ss`), `createdFrom` and `createdTo` (full ISO 8601 timestamps for audit purposes), the `atWork` type identifier, an empty comment, and a `changedBy` field.

The `changedBy` field nominally identifies the user who modified the attendance record, but Navigo3's API implementation overwrites this value server-side with the authenticated session user's ID regardless of the value sent in the request. The field is included in the payload with a placeholder value of `0` solely to satisfy Navigo3's schema validation-omitting the field causes the request to be rejected as malformed. This design constraint reflects the fact that the Navigo3 API was originally designed for interactive user-driven record editing rather than automated system-to-system synchronization, and certain fields carry legacy requirements that are irrelevant in the embedded context.

The `upsert` endpoint returns a JSON response containing a single `id` field, which is the numeric primary key of the attendance record in Navigo3's database. This value is stored in the `navigo3RecordId` column of both the entry and exit event rows, creating a bidirectional link between the Lighthouse system's event records and Navigo3's attendance intervals. Upon successful upsert, both events' `syncedToIntegration` flags are atomically updated to `true` in a single database transaction, ensuring that the pair is never reprocessed even if the server restarts between the API call and the database update.

==== Retry sweep <retry_sweep>

A background polling service, the Navigo3 poller, runs at a configurable interval (default 60 seconds, adjustable via `NAVIGO3_RETRY_INTERVAL_MS`) to re-attempt synchronization of events that failed initial push. The poller queries the database for up to 100 eligible events where `syncedToIntegration: false`, ordered by timestamp ascending to prioritize older unsynchronized records. The query respects the same eligibility criteria as the immediate push path: matching `algorithmId`, non-unknown direction, and valid `syncId`.

For each retrieved event, the retry logic first checks whether a counterpart now exists. If a matching opposite-direction event for the same user and day is found and is also unsynced, the poller invokes `pushPair()` to send the closed interval to Navigo3. If no counterpart exists or the counterpart has already been synced individually, the poller falls back to invoking `pushEvent()` to push the isolated entry or exit. This two-tier retry strategy maximizes the likelihood of sending complete intervals to Navigo3 rather than isolated transitions, improving the semantic quality of the attendance data in the enterprise system.

Errors encountered during retry are logged with the event ID and exception details but do not abort the sweep-the poller continues processing the remaining events in the batch. Failed events remain in the unsynced state and are retried on subsequent polling cycles until they either succeed or are manually marked as synced by an administrator. The poller is non-blocking: if a retry sweep is still in progress when the next polling interval elapses, the new cycle is skipped rather than running concurrently, preventing runaway thread accumulation in pathological failure scenarios where the Navigo3 API is unreachable for extended periods.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Endpoint][Direction][Description],
    [`attendance/embedded/start`], [in], [Register arrival],
    [`attendance/embedded/stop`], [out], [Register departure],
    [`attendance/embedded/upsert`], [in+out pair], [Create/update closed attendance interval],
  ),
  caption: [Table 3.4.5-1 - Navigo3 API endpoints used],
)

#figure(
  image("./images/3.4.5-1_navigo3_sequence.svg", width: 80%),
  caption: [Figure 3.4.5-1: Navigo3 integration sequence diagram - new processed event → eligibility check → immediate pushEvent/pushPair → on success: syncedToIntegration = true; on failure: left false → retry poller picks up on next cycle],
)


== Dashboard <dashboard>

=== Architecture and Stack

- The dashboard is a single-page application built with SolidJS, chosen for its small bundle size and fine-grained
  reactivity model (no virtual DOM diffing)
- Routing uses `@solidjs/router` with five client-side routes; the SPA is served as a static build from the same BunJS
  process that hosts the API and MQTT broker
- Styling uses CSS modules scoped per component
- Real-time updates are delivered via a WebSocket connection established on application mount (`App.tsx`); the WebSocket
  store dispatches incoming messages to page-specific reactive stores, so each page updates independently without
  polling
- Authentication is out of scope for this prototype; the REST API and dashboard are accessible without credentials on
  the local network; session management and role-based access are identified as future work

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ Message type     ],[ Trigger                          ],[ Consumer page(s) ],
[ `scan`           ],[ New raw scan ingested            ],[ Events           ],
[ `device:online`  ],[ Lighthouse MQTT connect          ],[ Lighthouses      ],
[ `device:offline` ],[ Lighthouse MQTT disconnect / LWT ],[ Lighthouses      ],
[ `device:health`  ],[ Health telemetry received        ],[ Lighthouses      ],
[ `device:pending` ],[ Unknown device connects          ],[ Lighthouses      ],
[ `event:new`      ],[ Processed event created          ],[ Processed Events ],
[ `event:orphaned` ],[ Scans orphaned by sweeper        ],[ Processed Events ],
  ),
  caption: [Table 3.5.1-1 - WebSocket message types],
)

=== Pages

==== Lighthouses (`/`)

- Lists all registered Lighthouse devices with live status: online/offline indicator, last health telemetry (uptime,
  WiFi RSSI, RFID reader state)
- Health data updates in real time via `device:health` WebSocket messages without page refresh
- Pending (unregistered) devices that connect to the MQTT broker appear in a separate section; the operator can claim a
  pending device by assigning it a name and placement (inside/outside)
- Device registration uses the ESP32's eFuse MAC address as the stable device identifier

==== Groups (`/groups`)

- Groups pair two Lighthouses (one outside, one inside) into a detection portal
- `activityTimeoutMs` (default 4 000 ms) and `orphanTimeoutMs` (default 8 000 ms) are stored per-group in the database
  and configurable via the API; the dashboard Groups page manages group label and description only - UI controls for
  timeout values are out of scope for this prototype
- A lighthouse can belong to at most one group; ungrouped lighthouses have their scans orphaned by the event sweeper

==== Events (`/events`)

- Real-time feed of raw scan events as they arrive from Lighthouse units; new scans are prepended to the table via the
  `scan` WebSocket message
- Filterable by lighthouse, EPC (partial match), scan source (`realtime` / `offline_sync`), and date range
- Serves as a debugging and monitoring tool - the operator can verify that tags are being detected and that both units
  in a portal are reporting scans

==== Processed events (`/processed`)

- Displays the output of the direction detection pipeline: one row per processed event, showing direction
  (in/out/unknown), confidence, algorithm, tag EPC, user (if assigned), group, and timestamp
- Filterable by algorithm, direction, user, group, and date range
- Each row expands into a detail modal with three tabs:

*Overview tab:*

- Direction, confidence percentage, tag EPC, user, group, algorithm name, timestamp, and cluster time span
- Confidence factor breakdown displayed as horizontal progress bars: centroid separation, cluster size, bilateral
  coverage, and (for Algorithm 2) RSSI trend consistency
- Link to the companion event (same cluster, other algorithm) for side-by-side comparison

*Raw Scans tab:*

- Lists all raw scans belonging to the cluster, grouped by lighthouse (inside vs. outside), showing EPC, RSSI,
  timestamp, and time basis

*Timeline tab:*

- Scan timing histogram: horizontal time axis with bars representing scan detections per time bucket, colour-coded by
  lighthouse (blue = outside, orange = inside); centroid markers for the selected algorithm shown as dashed vertical
  lines
- For Algorithm 2: RSSI-over-time scatter plot below the histogram, with per-lighthouse regression lines illustrating
  the RSSI trend used in RTCF calculation

![Figure 3.5.2-1: Processed event detail modal - Overview tab showing direction, confidence, confidence factor bars,
and companion algorithm link.](./images/3.5.2-1_modal.png)

![Figure 3.5.2-2: Processed event detail modal - Timeline tab showing scan timing histogram with centroid markers and
RSSI-over-time scatter plot with regression lines.](./images/3.5.2-2_modal.png)

==== Users (`/users`)

- Manages user records: name, email, and Navigo3 sync ID for integration
- Each user can have multiple EPC tags assigned at a time; any orphaned tag assignments are preserved with a
  `revokedAt` timestamp for audit

== System Verification

=== Lab Validation

- Test hardware: two Board v2 units in final enclosures (not breadboard prototypes); production firmware
- Test environment: two units mounted at doorway-width separation in a controlled indoor space; server running on LAN;
  Navigo3 test instance connected
- Test protocol: controlled tag traversals at fixed distances and walking speeds; each traversal logged as a processed
  event and verified end-to-end in Navigo3

==== Detection range

- Per-unit detection range measured by approaching a passive UHF tag toward the antenna at a fixed angle; furthest
  distance at which the tag is reliably detected within a single 5 s scan window recorded
- Both units measured independently; range difference between units documented and attributed to antenna feed path
  quality (per #ref(<antenna_and_rf_considerations>))

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Unit][Antenna connection method][Max reliable range \[m\]][Notes],
    [Unit 1], [TODO], [TODO], [],
    [Unit 2], [TODO], [TODO], [],
  ),
  caption: [Table 3.6.1-1 - Detection range per unit],
)

==== Direction detection accuracy

- N controlled traversals performed: equal split IN and OUT; both algorithms evaluated on each traversal
- Accuracy = fraction of traversals where the algorithm produced a correct direction call (IN/OUT); unknown calls
  treated as incorrect for accuracy purposes
- Confidence distribution recorded alongside accuracy

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Algorithm][Correct \[n\]][Incorrect \[n\]][Unknown \[n\]][Accuracy \[%\]],
    [Temporal Centroid (C₁)], [TODO], [TODO], [TODO], [TODO],
    [RSSI-Weighted (C₂)],     [TODO], [TODO], [TODO], [TODO],
  ),
  caption: [Table 3.6.1-2 - Direction detection accuracy per algorithm],
)

#fig-placeholder[Figure 3.6.1-1: Confidence distribution histogram - both algorithms overlaid; x-axis confidence [0,1]; y-axis traversal count; separate bars for correct / incorrect / unknown per algorithm]

==== End-to-end processing time

- The pipeline has a deterministic minimum delay: 5 s scan window + `activityTimeoutMs`
  (4 s default) + sweeper polling interval (2 s) + Navigo3 HTTP round-trip; theoretical
  minimum ~11 s under ideal conditions

#figure(
  table(
    columns: (auto, auto),
    table.header[Metric][Value \[s\]],
    [Theoretical minimum], [\~11],
    [Mean measured],       [TODO],
    [Min measured],        [TODO],
    [Max measured],        [TODO],
  ),
  caption: [Table 3.6.1-3 - End-to-end processing time (IR trigger → Navigo3 record)],
)

==== Offline replay verification

- Server taken offline during N tag traversals; firmware caches events to LittleFS ring
  buffer; server brought back online; replay verified: all cached scans ingested, clusters
  reconstructed, processed events created with correct timestamps and `timeBasis` field,
  Navigo3 records created

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Events cached][Events replayed][Events lost][Navigo3 records created][Notes],
    [TODO], [TODO], [TODO], [TODO], [],
  ),
  caption: [Table 3.6.1-4 - Offline replay results],
)

=== Field Testing

- *Status:* planned - deployment at Navigo Solutions s.r.o. offices pending; this section will be completed or 
  replaced with an expanded lab evaluation depending on whether field deployment is feasible before submission
- Intended deployment: single doorway at Navigo Solutions office; real employees with passive UHF tags on lanyards or
  in bags; system running against live Navigo3 instance
- Evaluation criteria: detection reliability over a full working day, false positive rate, employee feedback on
  zero-interaction experience
- If field testing is not completed: this subsection documents the intended methodology and evaluation criteria; lab
  validation results in 3.6.1 are the primary verification evidence


=== Algorithm comparison

- Head-to-head comparison of Algorithm 1 (Temporal Centroid, C1) and Algorithm 2 (RSSI-Weighted Centroid, C2) on the
  same traversal dataset collected in 3.6.1 (and 3.6.2 if available)
- Both algorithms run on every cluster independently; results stored as separate rows per #ref(<direction_detection_and_event_processing>); comparison is
  a post-hoc analysis of stored outputs - no re-processing required
- Dataset source: `<PLACEHOLDER - real lab traversals / real field traversals / both>`

#figure(
  table(
    columns: (auto, auto),
    table.header[ Metric                          ][ C1 Temporal ][ C2 RSSI-Weighted ],
[ Overall accuracy [%]            ],[ `<PH>`      ],[ `<PH>`           ],
[ Mean confidence (correct calls) ],[ `<PH>`      ],[ `<PH>`           ],
[ Mean confidence (incorrect)     ],[ `<PH>`      ],[ `<PH>`           ],
[ Unknown rate [%]                ],[ `<PH>`      ],[ `<PH>`           ],
[ Agreement rate [%]              ],[ `<PH>`      ],[ N/A              ],
  ),
  caption: [Table 3.6.3-1 - Algorithm comparison summary],
)

#fig-placeholder[Figure 3.6.3-1: Scatter plot - C1 confidence vs. C2 confidence per traversal; colour-coded by correctness agreement (both correct / disagree / both incorrect); diagonal reference line]

- Cases where algorithms disagree: direction call differs between C1 and C2; analysed separately to understand when
  RSSI weighting helps or harms
- Recommendation: which algorithm to use in production deployment and under what conditions; based on accuracy and
  confidence calibration findings

// =============================================================================
// 4. CONCLUSION
// =============================================================================

= Conclusion

- A passive, hands-free UHF RFID attendance system was designed and implemented from the ground up: three custom
  Lighthouse units, a BunJS/PostgreSQL server with an embedded MQTT broker, a SolidJS operator dashboard, and a Navigo3
  integration layer
- The system achieves the goal of zero employee interaction: tags are detected passively at walking pace without
  any deliberate action from the tag carrier
- All four thesis goals from the assignment were addressed:
  - (1) review of identification technologies and direction detection methods - completed in Chapter 2
  - (2) architecture design - portal model with server-side processing documented in Chapter 3
  - (3) prototype implementation - three Board v2 units in enclosures, full firmware and server pipeline
  - (4) system verification - lab validation performed; field deployment at Navigo Solutions pending
- Lab validation confirmed end-to-end operation: tag traversal through the portal produces a correctly
  directed attendance record in Navigo3; detection range and direction detection accuracy measured and documented
  in Section 3.6.1
- Both direction detection algorithms (Temporal Centroid C1, RSSI-Weighted Centroid C2) were implemented and
  evaluated; algorithm comparison findings and the deployment recommendation are in Section 3.6.3
- Known limitations of the current prototype:
  - Absence of a hardware RTC on the ESP32 - timekeeping relies on SNTP; timestamp quality degrades during
    prolonged network outages (mitigated by `timeBasis` field and NVS-persisted last-known time)
  - Single antenna per unit - no spatial diversity; detection reliability is sensitive to antenna placement
    and the quality of the RF feed path (antenna cable joint)
- The integration layer is isolated behind a connector interface - the system is not inherently tied to Navigo3
  and can be extended to other enterprise platforms
- Directions for future work:
  - Hardware RTC on a future board revision to eliminate timestamp degradation during offline periods
  - Repositioning the IPEX/U.FL receptacle adjacent to the R300 RF output pad on a future board revision to
    eliminate the PCB trace and the associated impedance mismatch
  - Extended field testing over a full working day with real employee traffic
  - Further software and firmware improvements identified during development
  - Improved API and web interface with proper authentication and session management

