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

= Introduction

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

= Research

== Attendance System Technologies

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

== Direction Detection Methods

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
  per-device deduplication would destroy the signal; detailed formulations in Section 3.4.3

#fig-placeholder[Figure 2.2-1: Dual RSSI curves over time for a single traversal; temporal centroids C_out and C_in marked; RSSI peaks labelled; direction arrow outside to inside]

== Hardware Platforms and Embedded Architectures

=== Microcontroller Selection

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

=== UHF RFID Reader Modules

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
  validation; a general caution on cost-tier module datasheets; full details in Section 3.3.2

=== Power Supply and Battery Considerations

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

=== Timekeeping Without a Hardware RTC

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

== Communication Protocols and Enterprise Integration

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

== Embedded Software Frameworks

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

= Implementation and Results

== System Architecture

- The system is built around a portal model: two Lighthouse units are deployed on opposite sides of a doorway (one
  designated OUTSIDE, one INSIDE), collectively forming a single detection portal; a person crossing the threshold is
  detected by both units in a temporal sequence that encodes direction
- Each Lighthouse unit is an autonomous embedded device: ESP32-WROOM-32 microcontroller communicating with a YPD-R300
  UHF RFID reader module over UART, with onboard power management, local offline event cache, and WiFi/MQTT connectivity
- All direction inference logic resides on the server, not the firmware; each Lighthouse unit publishes only raw
  timestamped RSSI readings - it has no knowledge of the other unit in its group and makes no direction decisions; this
  keeps the firmware thin and the detection logic centrally maintainable
- Lighthouse units are logically paired on the server into a *group*; the group is the unit of direction detection -
  scans are clustered and processed per (tag EPC, group) pair; a Lighthouse can belong to at most one group
- The server exposes a REST API and embedded MQTT broker; it hosts the direction detection pipeline, user/tag
  management, Navigo3 integration, and serves the web dashboard as a static build from the same process
- Navigo3 is the implemented enterprise integration target; the integration layer is isolated behind an
  environment-variable-controlled connector, making the architecture open to other systems without changes to the core
  event pipeline

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Component][Technology][Responsibility],
    [Lighthouse unit (×2)],  [ESP32-WROOM-32 + YPD-R300],         [Passive UHF RFID detection; raw scan publish via MQTT],
    [Server],                [BunJS, Hono, Aedes, PostgreSQL],     [Scan ingestion, direction detection, user management, API],
    [Dashboard],             [SolidJS SPA],                        [Operator interface: device management, event monitoring, user setup],
    [Navigo3 integration],   [REST connector + background poller], [Translates processed events into attendance records in Navigo3],
  ),
  caption: [Table 3.1-1 - System components and their responsibilities],
)

- End-to-end event lifecycle from tag detection to attendance record:
  - IR sensor detects motion -> firmware opens a 5-second RFID scan window
  - YPD-R300 runs continuous real-time inventory; detections batched and published to `lighthouse/{id}/scans` over MQTT
    (QoS 1) as timestamped RSSI arrays
  - Server scan handler ingests each batch; raw scans stored in `raw_scans` table with `timeBasis` field (`synced` /
    `estimated` / `relative`) preserved verbatim
  - EventSweeper background poller clusters unprocessed scans by (EPC, group); once a cluster is closed (no new scans
    for `activityTimeoutMs`), both direction detection algorithms run and produce a processed event row each
  - Processed event is immediately pushed to Navigo3 (`start` or `stop` endpoint); on failure, a background retry sweep
    picks it up within `NAVIGO3_RETRY_INTERVAL_MS`
  - If connectivity is lost before MQTT publish, the firmware caches events to a LittleFS ring buffer on flash and
    replays them on reconnection

#figure(
  image("./images/3.1-1_system_architecture.png", width: 80%),
  caption: [Figure 3.1-1: System architecture block diagram - Lighthouse A and B communicating via MQTT to Server; Server connected bidirectionally to Web Client via REST + WebSocket; Server connected to Navigo3 via REST API]
)

== Hardware Design

=== Board v1 - Breadboard Prototype

- The first prototype was assembled on a breadboard using off-the-shelf breakout modules: ESP32-WROOM-32 development
  board, YPD-R300 UHF RFID reader module on carrier board, SX1308 DC-DC boost converter module, and
  TP4056/DW01HA lithium battery charger/protection module
- Each module was reverse-engineered prior to integration and schematics were traced from the physical PCBs to identify
  component values, internal routing, and undocumented connections; this was necessary because none of the modules
  shipped with engineering documentation beyond basic pinout labels
- The reverse-engineered schematics became the baseline for the Board v2 custom PCB design - the goal was to reproduce
  and then improve upon the combined functionality of these four modules on a single board

#figure(
  image("./images/IMG_20260305_011321.jpg", width: 80%),
  caption: [Figure 3.2.1-1: Photograph of the two Board v1 breadboard prototypes; components labelled: ESP32 dev board, YPD-R300 on carrier, SX1308 boost module, TP4056 charger, battery holder, PIR sensor, status LEDs, buttons, antenna with coaxial pigtail]
)

- Component selection was validated on the breadboard: ESP32-WROOM-32 confirmed as capable of running WiFi, MQTT, and
  UART-driven RFID operations concurrently using the dual-core architecture (WiFi stack pinned to Core 0, application
  logic on Core 1; per ESP32 TRM Section 1.1)
- YPD-R300 communicates with ESP32 via UART at 115 200 baud (per R300 Protocol Section 1.2); GPIO assignments for UART
  TX/RX, status LEDs, buttons, PIR input, and RFID power switch were established and carried forward to Board v2
- Power delivery on the breadboard used point-to-point wiring between modules; this introduced uncontrolled impedance
  and voltage drops under load, motivating the move to a purpose-designed PCB

#figure(
  table(
    columns: (auto, auto),
    table.header[Module][Key components identified],
[ ESP32 dev board (38-pin) ],[ AMS1117-3.3 LDO, CP2102 USB-UART, EN/BOOT buttons            | ESP32-WROOM-32 module placed directly; AMS1117 retained; CP2102 removed in favour of a BoB ],
[ YPD-R300 carrier board   ],[ R300 module, SMA connector, decoupling capacitors            | R300 module placed directly; SMA replaced with IPEX/U.FL footprint                         ],
[ SX1308 boost module      ],[ SX1308 IC, 4.7 µH inductor, Schottky diode, feedback divider | Circuit reproduced with confirmed component values                                         ],
[ TP4056 charger module    ],[ TP4056 IC, DW01HA protection, FS8205A dual MOSFET            | Circuit reproduced; charge current set via programming resistor                            ],
  ),
  caption: [Table 3.2.1-1 - Reverse-engineered modules and their Board v2 disposition],
)

=== Board v2 - Custom PCB

- Board v2 is a single two-layer PCB integrating all functionality of the four breadboard modules plus additional
  circuitry for power switching, fuse protection, battery monitoring, and consolidated USB-C connectivity
- Designed in KiCad; schematic split into four hierarchical sheets (see Appendix <>): top-level Lighthouse sheet,
  Charger submodule, Step-up DC/DC converter, and UHF RFID reader
- The CP2102 USB-UART bridge present on the original ESP32 dev board was omitted from Board v2 to reduce component cost
  and simplify SMD assembly; UART TX, RX, and GND are instead broken out to a pin header, allowing debug and flashing
  via an external USB-UART adapter
- The reader is assumed to have the schematic sheets from Appendix <> available for side-by-side reference; the
  following subsections describe key design decisions and deviations from the baseline breadboard design rather than
  replicating the full schematic content

#fig-placeholder[Figure 3.2.2-1: KiCad schematic - top-level Lighthouse board showing ESP32, YPD-R300, SX1308, TP4056/DW01A, power path, and peripheral connections]

==== USB-C connector

- The breadboard prototype used two separate USB connectors - one for power, one for CP2102 UART debug/flashing
- Board v2 consolidates power input into a single USB-C connector carrying only VBUS; the UART debug interface is
  separated to a dedicated pin header for use with an external USB-UART adapter
- USB-C UFP identification requires 5.1 kΩ pull-down resistors on CC1 and CC2 pins (per USB Type-C Specification Section
  4.5.1); without these, only certain USB sources will supply VBUS - an issue observed during breadboard testing where
  some chargers refused to provide power

==== Power delivery architecture

- Dual-input power with automatic source selection: USB 5 V (primary) and Li-ion battery via SX1308 boost converter
  (backup)
- SS24A Schottky diodes (DO-214AC, 2 A / 40 V, ~0.3-0.4 V forward drop) in OR configuration prevent backfeed between
  sources (see Step-up DC/DC converter sheet, Appendix <>)
- SF-1206SP100-2 slow-blow fuses (1 A, 63 VDC, 1206) on each input path, placed before the diodes; slow-blow type
  selected to tolerate RFID reader power-on inrush current
- DPDT slide switch after fuses and before diode junction provides complete power isolation of both input paths
  simultaneously while keeping fuses always in-circuit

#figure(
  image("./images/3.2.2-2_power_delivery.svg", width: 80%),
  caption: [Figure 3.2.2-2: Power delivery block diagram - USB-C VBUS and battery cell as inputs -> fuses -> DPDT switch -> SS24A diode OR -> 5 V rail -> AMS1117-3.3 LDO -> 3.3 V rail; battery path includes SX1308 boost (3.2-4.2 V -> 5 V); TP4056/DW01HA charges battery from VBUS when present]
)

==== RFID reader power switching

- BC337-25 NPN transistor (TO-92, CBE pinout flat face) used as low-side switch for the YPD-R300 power supply,
  controlled by ESP32 GPIO (see RFID reader sheet, Appendix <>)
- BC337-25 selected for low V_CE(sat) (~300 mV at 380 mA load), keeping the GND offset small enough to not affect R300
  operation; I_C(max) of 800 mA provides comfortable headroom over the reader's ~380 mA draw
- Base resistor: 150 Ω providing ~17 mA base drive for forced beta ~22 at 380 mA collector current, ensuring hard
  saturation

==== Supply stabilisation and decoupling

- The RFID reader draws current in sustained 18.8 ms pulses at 30-50 ms intervals during inventory; this profile
  requires bulk capacitance rather than ceramic-only decoupling


#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Location][Capacitance][Purpose],
[ RFID reader VCC input ],[ 1000 µF electrolytic | Bulk reservoir for reader current pulses ],
[ ESP32 5 V VIN         ],[ 1000 µF electrolytic | Bulk supply stabilisation                ],
[ ESP32 3.3 V rail      ],[ 100 µF electrolytic  | LDO output stabilisation                 ],
  ),
  caption: [Table 3.2.2-1 - Decoupling capacitance],
)

- ESP32 brownout detector disabled (`CONFIG_ESP_BROWNOUT_DET=n`); protection against supply collapse is instead provided
  by overlapping hardware mechanisms: TP4056 undervoltage cutoff, input fusing, and software battery voltage monitoring
  via ADC1/GPIO33

==== Battery voltage monitoring

- GPIO33 (ADC1_CH5) selected for cell voltage monitoring; ADC1 is safe for concurrent WiFi operation - ADC2 shares
  hardware with the WiFi RF subsystem and cannot be used reliably while WiFi is active (per ESP32 TRM Section 31.3)
- Voltage divider: R1 = 100 kΩ, R2 = 120 kΩ scales the 3.2-4.2 V cell range to 1.75-2.29 V, within ADC1 effective
  measurement range at 11 dB attenuation (per ESP32 Datasheet Table 4-4)

=== Antenna and RF Considerations

- UHF RFID operates in the 860-960 MHz range (ETSI band 865-868 MHz in Europe); at these frequencies, signal integrity
  of the connection between the R300 module's RF output and the antenna is critical
- A parallel wire pair is not viable at 900 MHz - the wavelength (~33 cm) means that even short unshielded runs act as
  radiating elements with uncontrolled impedance; 50 Ω coaxial cable is required for the antenna feed
- The YPD-R300 module's RF output is specified for 50 Ω impedance; any mismatch in the feed path causes reflected power,
  reducing effective radiated power and read range

==== Range disparity between units

- The different Board v2 units exhibited significantly different read ranges: one unit achieved ~3 m, the other ~0.5 m
- Probable cause identified as antenna cable joint quality:
  - The better-performing unit had its coaxial pigtail soldered directly onto the R300 module's RF output pad,
  bypassing all PCB tracesthe
  - The worse unit used the designated PCB edge mounted coaxial socket at ~2cm lead traces which while more principled
  yielded consistently worse results.
- Both R300 modules are firmware-identical and produce the same `set_power` response, confirming the RF feed path - not
  the module - as the variable

==== PCB trace impedance

- Board v2 routes a short PCB trace between the R300 module RF pad and the antenna connector footprint
- This trace should be impedance-controlled to 50 Ω; on a two-layer board with standard FR-4 substrate, achieving 50 Ω
  requires specific trace width relative to substrate thickness and copper weight - a constraint not explicitly verified
  during Board v2 layout
- The direct-solder unit consistently outperforms the connector units, suggesting the PCB trace introduces a meaningful
  impedance mismatch at 900 MHz
- Future board revision should place the IPEX/U.FL receptacle immediately adjacent to the R300 RF output pad to
  eliminate the trace, or route the RF path on an inner layer with a continuous ground plane reference

#fig-placeholder[Figure 3.2.3-1: Annotated photograph or diagram comparing the two antenna connection methods - (a) coaxial pigtail
soldered directly to R300 RF pad, (b) signal routed through ~20 mm PCB trace to board-edge IPEX connector; impedance
discontinuity at the trace highlighted]

=== Enclosure

- A prototype enclosure designed in FreeCAD to house the Board v2 PCB, battery, PIR
  sensor, and antenna in a wall-mountable form factor
- Design constraints: PIR sensor window faces the detection zone; antenna oriented toward
  the doorway with minimal obstruction; USB-C port accessible; status LEDs visible;
  buttons accessible for provisioning trigger

#figure(
  image("./images/3.2.4-1_case.png", width: 80%),
  caption: [Figure 3.2.4-1: CAD model screenshot - front/side view of the enclosure showing PIR window, antenna position, LED light pipes, and USB-C port access]
)

#figure(
  image("./images/3.2.4-2_case.png", width: 80%),
  caption: [Figure 3.2.4-2: CAD model screenshot - exploded or open view showing internal component placement: PCB, battery, antenna mounting]
)

- Full technical drawings of the enclosure are provided in Appendix

== Firmware

- Firmware is written in C using ESP-IDF v5.x with FreeRTOS; the entire application runs on a single ESP32-WROOM-32
  module
- The dual-core Xtensa LX6 architecture allows separation of concerns: the WiFi stack is pinned to Core 0 by ESP-IDF
  configuration, leaving Core 1 available for application logic including RFID communication and the main task loop (per
  ESP32 TRM Section 1.1)
- The firmware is identical across all Lighthouse units - no unit-specific configuration is compiled in; all per-device
  settings (WiFi credentials, MQTT broker address, lighthouse identity) are configured at runtime via the provisioning
  system and stored in NVS

=== System Initialization and WiFi Provisioning

- On boot, the firmware executes a sequential initialization: GPIO configuration -> battery monitor -> WiFi provisioning
  (credentials load + STA connection) -> SNTP time synchronisation (broker IP as NTP server) -> MQTT client -> offline
  event logger -> RFID reader -> main task loop
- If the device has never been configured (no credentials in NVS), the boot sequence blocks after GPIO initialization
  and waits for the user to trigger provisioning via a 5-second hold of BUTTON2

==== Provisioning flow

- Provisioning is triggered by a 5-second hold of BUTTON2, which sets a flag in RTC memory and calls `esp_restart()`; on
  the subsequent boot, the firmware detects the flag and enters AP mode instead of STA mode
- In AP mode, the device broadcasts an open WiFi network ("Lighthouse-Setup") and starts an HTTP server on port 80
  serving a minimal HTML configuration form from firmware flash via the SPIFFS virtual filesystem
- A lightweight DNS server responds to all DNS queries with the device's AP IP address (192.168.4.1), enabling captive
  portal detection on iOS, Android, Windows, and macOS; the user's device automatically opens a browser to the
  provisioning page
- The form collects four fields: WiFi SSID, WiFi password, MQTT broker IP, and MQTT broker port; client-side JavaScript
  validates input format before submission
- On form submission, the device attempts a STA connection with the provided WiFi credentials; if successful, it tests
  MQTT connectivity; results are reported back to the browser via a JSON response
- The browser displays success/failure and a restart button; the device only restarts when the user explicitly clicks
  restart, ensuring the browser receives the response before the AP shuts down
- Credentials are encrypted with AES-128-ECB via the mbedTLS library, which utilises the ESP32 hardware AES accelerator
  (per ESP32 TRM Section 14), and stored in a dedicated NVS partition; on subsequent boots, credentials are loaded from
  NVS and used for automatic STA connection

#figure(
  image("./images/3.3.1-1_boot_sequence.svg", width: 80%),
  caption: [Figure 3.3.1-1: Provisioning state machine diagram - states: UNCONFIGURED, SETUP_REQUESTED, AP_ACTIVE, CONNECTING, CONNECTED, OFFLINE; transitions labelled with triggering events (button press, credential submission, connection success/failure, reboot)]
)

#figure(
  image("./images/3.3.1-2_page.png", height: 8cm),
  caption: [Figure 3.3.1-2: Screenshot of the provisioning web form as rendered on a mobile device - showing WiFi SSID/password fields, MQTT broker IP/port fields, test buttons, and status display area]
)

=== UHF RFID Scan Control

- The YPD-R300 UHF RFID reader module communicates with the ESP32 via UART at 115 200 baud (per R300 Protocol Section
  1.2)
- RFID scanning uses the real-time inventory command `cmd 0x89` (`cmd_name_real_time_inventory`) with channel parameter
  `0xFF` (minimized inventory duration) and 10 ms inter-round delay (per R300 Protocol Section 2.2.8)
- In real-time inventory mode, the reader streams tag detection packets as they occur rather than buffering them
  internally; each packet contains the tag's EPC, RSSI, frequency/antenna ID, and protocol control (PC) word
- A scan window lasts approximately 5 seconds, producing ~60 individual tag detections per window under typical
  conditions

==== IR-triggered scanning

- The AM312 PIR sensor on GPIO19 detects motion in the doorway and triggers RFID scan bursts via a GPIO interrupt
  (rising edge, `IRAM_ATTR` ISR handler)
- On IR trigger, the firmware powers on the R300 module via the BC337-25 transistor switch, performs a UART handshake to
  verify reader responsiveness, and starts real-time inventory
- The scan burst runs for `IR_SCAN_DURATION_MS` (default 5 s); if additional IR triggers arrive during an active
  burst, the timer is restarted without interrupting the ongoing inventory - this extends the scan window when a person
  lingers in the doorway
- When the burst timer expires with no further IR triggers, the inventory is stopped and the R300 module is powered off
  to conserve energy

==== MQTT batch accumulator

- To avoid saturating the MQTT connection with ~60 individual publishes during a 5-second scan window, detections are
  accumulated in a time-windowed batch buffer on the firmware side
- The accumulator collects tag detections for up to `scan_batch_ms` (default 150 ms, configurable 50-2 000 ms) or until
  the buffer reaches `MQTT_SCAN_BATCH_MAX_ENTRIES`, then flushes the batch as a single JSON array to MQTT topic
  `lighthouse/{id}/scans`
- Each element in the flushed array carries its individual `epc`, `rssiDbm`, `antennaId`, `frequency`, and `deviceId`
  fields; the `timestampMs` and `timeBasis` fields are computed once at flush time and are shared across all elements in
  the batch - timestamp resolution is therefore bounded by the batch interval (minimum 50 ms, default 150 ms)
- The live scan publish path uses QoS 1 to reduce the four-way handshake overhead of QoS 2; the offline replay path
  retains QoS 2 for exactly-once delivery of historically cached events

==== Power cap discovery

- The YPD-R300 hardware power cap is 25 dBm, despite the datasheet specifying 33 dBm; the `set_power(33)` command
  returns error code `0x48` (parameter out of range) which was initially ignored due to missing response validation
- The firmware now reads and validates all R300 command responses; transmit power is clamped to the 20-25 dBm range

=== Timekeeping and Timestamp Quality

- The ESP32 does not include a battery-backed hardware RTC; after a power cycle, the system clock starts from an
  undefined epoch and must be synchronised via SNTP before timestamps are meaningful
- The firmware implements a three-tier time quality model to ensure that every event payload declares the
  trustworthiness of its timestamp

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Quality level][timeBasis value][Condition][Accuracy],
[ Synced        ],[ `synced`          ],[ SNTP synchronisation completed successfully                   ],[ Millisecond-level (network + NTP jitter)                                          ],
[ Estimated     ],[ `estimated`       ],[ No SNTP sync yet, but last-known-good time recovered from NVS ],[ Seconds to minutes (RTC drift ~5 % at 150 kHz; per ESP32 Datasheet Section 3.3.4) ],
[ Relative      ],[ `relative`        ],[ No NVS time available; first boot or NVS lost                 ],[ Boot-relative milliseconds only; not a real wall-clock time                       ],
  ),
  caption: [Table 3.3.3-1 - Time quality tiers],
)

=== SNTP synchronisation

- The firmware uses the ESP-IDF SNTP client in polling mode against a chrony NTP server on the local network
- On successful sync, a callback upgrades the time quality to `synced` and persists the current Unix timestamp alongside
  the ESP32 uptime counter to NVS; this pair allows the next boot to estimate wall-clock time even before SNTP completes
- Timezone is set to CET/CEST (`TZ=CET-1CEST,M3.5.0,M10.5.0/3`) before SNTP initialisation so that `localtime()` returns
  correct local time immediately on sync

=== Offline degradation

- If SNTP sync does not complete (e.g. NTP server unreachable), the firmware continues operating with `estimated` or
  `relative` timestamps
- The `timeBasis` field is attached to every scan event payload; the server uses this to decide whether scans are
  eligible for direction detection processing - non-synced scans are handled by the orphan processing logic on the
  server side

=== MQTT Communication and Offline Caching

==== MQTT client

- The firmware connects to the MQTT broker using the `esp_mqtt_client` component with connection parameters loaded from
  NVS (broker IP and port configured during provisioning)
- The MQTT client ID is derived from the ESP32's eFuse MAC address, ensuring uniqueness across devices (per ESP32 TRM
  Section 4.4)
- A Last Will and Testament (LWT) message is registered on connect, allowing the server to detect unexpected
  disconnections

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

==== Offline event caching

- When the MQTT connection is unavailable, tag detections are stored to a dedicated LittleFS partition on the ESP32's
  flash memory; this is a separate partition from the SPIFFS partition used by the provisioning HTML - SPIFFS is a
  read-only image compiled into the firmware binary, while LittleFS is a writable filesystem used exclusively for
  offline event storage
- Events are written to a ring buffer file (`events.bin`) with CRC32 validation per entry; write and read indices are
  persisted to both RTC memory (survives soft reset) and NVS (survives power loss)
- On MQTT reconnection, a background replay task reads cached events and publishes them at a throttled rate (max 10
  events/second) with QoS 2, adding an `offline: true` flag and a `replayTime` field to each payload
- The replay task runs at lower priority than the main logging task, ensuring real-time detections are not delayed by
  replay activity

#figure(
  image("./images/3.3.4-1_offline_replay.svg", width: 80%),
  caption: [Figure 3.3.4-1: Offline caching and replay sequence diagram - tag detected while offline -> event queued -> logging task writes to LittleFS ring buffer -> NVS pointers updated -> MQTT reconnects -> replay task reads from ring buffer -> publishes with offline flag -> server ingests as normal scan with replay metadata]
)

=== User Interaction: Buttons, LEDs, and Gestures

- The IO subsystem manages four LEDs, two buttons, and one IR sensor; all IO logic is encapsulated in a dedicated
  `io_controller` module, keeping the main application file (`lighthouse.c`) limited to orchestration and MQTT/offline
  routing

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ Constant      ][ GPIO ][ Function                                      ],
[ LED1_PIN      ],[ 4    ],[ WiFi + MQTT combined status (green)           ],
[ LED2_PIN      ],[ 21   ],[ IR mode / AP provisioning indicator (green)   ],
[ SCANNING_LED  ],[ 26   ],[ Active RFID scan indicator (red)              ],
[ ACTIVITY_LED  ],[ 25   ],[ Tag detection flash / battery status (yellow) ],
[ BUTTON1_PIN   ],[ 22   ],[ Scan mode control                             ],
[ BUTTON2_PIN   ],[ 23   ],[ Status message / WiFi setup trigger           ],
[ IR_SENSOR_PIN ],[ 19   ],[ AM312 PIR motion sensor                       ],
  ),
  caption: [Table 3.3.5-1 - GPIO pin assignments],
)

- GPIO22 and GPIO23 (buttons) use external pull-up resistors; debounce filtering is applied in software with a 50 ms
  debounce threshold

==== Scan modes

- The firmware operates in one of two scan modes, selectable via BUTTON1 3-second hold:

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[ Mode ][ LED2 state ][ IR sensor                         ][ BUTTON1 short press ][ Entry condition             ],
[ IR Mode (default) ],[ Solid on   ],[ Active - triggers 5 s scan bursts ],[ No-op               ],[ 3 s hold from Manual / Boot ],
[ Manual Mode       ],[ Off        ],[ Ignored                           ],[ Toggle RFID on/off  ],[ 3 s hold from IR Mode       ],
  ),
  caption: [Table 3.3.5-2 - Scan mode behavior],
)

- RFID scanning is always stopped and the reader powered off before any mode transition

#figure(
  image("./images/3.3.5-1_scan_mode_fsm.svg", width: 80%),
  caption: [figure 3.3.5-1: scan mode state machine - two states (ir mode, manual mode); transitions: 3-second button1 hold in either direction; entry actions listed for each state (stop rfid, set led2, enable/disable ir)]
)

==== Button gestures

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ Button  ][ Gesture     ][ Action    ],                                 
[ BUTTON1 ],[ Short press ],[ Toggle RFID scan (Manual Mode only; no-op in IR Mode)                      ],
[ BUTTON1 ],[ 3 s hold    ],[ Switch between IR Mode and Manual Mode                                     ],
[ BUTTON2 ],[ Short press ],[ Publish status/statistics message via MQTT                                 ],
[ BUTTON2 ],[ 5 s hold    ],[ Enter WiFi AP provisioning (triggers reboot into setup mode)               ],
[ Both    ],[ 10 s hold   ],[ Cache purge: clear offline event cache, confirmation LED sequence, restart ],
  ),
  caption: [Table 3.3.5-3 - Complete button gesture reference],
)

==== Cache purge combo gesture

- Holding both buttons simultaneously for 10 seconds triggers a developer cache purge gesture
- During the hold, LEDs illuminate sequentially as a countdown: LED1 at 2.5 s, LED2 at 5 s, ACTIVITY_LED at 7.5 s
- At 10 s, `offline_logger_clear_all()` resets the ring buffer pointers; a confirmation flash sequence (each LED flashed
  in order, 200 ms on/off) plays before `esp_restart()`
- Releasing either button before the 10-second threshold cancels the gesture and restores normal LED states
- While the combo gesture is active, RFID scanning is stopped and IR triggers are suppressed

==== LED indicator behavior

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ LED                   ][ Condition                  ][ State               ],                        
[ LED1 (green)          ],[ No WiFi connection         ],[ Off                 ],
[ LED1 (green)          ],[ WiFi connected, no MQTT    ],[ Blinking 1 s period ],
[ LED1 (green)          ],[ WiFi + MQTT connected      ],[ Solid on            ],
[ LED2 (green)          ],[ IR Mode active             ],[ Solid on            ],
[ LED2 (green)          ],[ Manual Mode active         ],[ Off                 ],
[ SCANNING_LED (red)    ],[ RFID inventory in progress ],[ On                  ],
[ SCANNING_LED (red)    ],[ No active inventory        ],[ Off                 ],
[ ACTIVITY_LED (yellow) ],[ Tag detected               ],[ Brief 100 ms flash  ],
  ),
  caption: [Table 3.3.5-4 - LED states during normal operation],
)

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ LED                   ][ Provisioning phase                  ][ State                                       ],
[ LED1 (green)          ],[ AP active, WiFi test not yet passed ],[ Blinking                                    ],
[ LED1 (green)          ],[ WiFi test passed                    ],[ Solid on                                    ],
[ LED2 (green)          ],[ AP active, MQTT test not yet passed ],[ Blinking                                    ],
[ LED2 (green)          ],[ MQTT test passed                    ],[ Solid on                                    ],
  ),
  caption: [Table 3.3.5-5 - LED states during AP provisioning],
)

==== Battery status LED patterns (ACTIVITY_LED, battery power only)

#figure(
  table(
    columns: (auto, auto),
    table.header[ Battery level  ][ LED pattern                      ],
[ USB powered    ],[ Off (tag detection flashes only) ],
[ Battery > 10 % ],[ Brief flash every 5 seconds      ],
[ Battery 5-10 % ],[ Pulsing 500 ms on/off            ],
[ Battery < 5 %  ],[ Rapid pulsing 200 ms on/off      ],
  ),
  caption: [Table 3.3.5-6 - Battery level indication],
)

- The battery LED patterns run in a dedicated FreeRTOS task and do not interfere with the brief 100 ms tag detection
  flashes on the same LED

== Server

=== Infrastructure and Stack

- Server runs as a single BunJS process hosting all subsystems: HTTP API, embedded MQTT broker, WebSocket gateway,
  background pollers
- Hono chosen as HTTP framework - lightweight, TypeScript-native, no runtime overhead
- PostgreSQL as the primary data store; Drizzle ORM for type-safe query building with migration support
- Aedes embedded as the MQTT broker - avoids external broker dependency, allows direct in-process message handling
- SolidJS frontend served as static build from the same process

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Component][Technology][Role],
    [HTTP API],          [Hono],                     [REST endpoints, JWT auth],
    [MQTT Broker],       [Aedes],                    [Receives firmware scan/health messages],
    [Database],          [PostgreSQL + Drizzle ORM], [Persistent event and user storage],
    [WebSocket Gateway], [Bun WebSocket],             [Real-time push to dashboard clients],
    [Navigo3 Poller],    [Custom interval],           [Periodic retry of unsynced events],
    [Event Sweeper],     [Custom interval],           [Cluster detection and direction processing],
  ),
  caption: [Table 3.4.1-1 - Server component responsibilities],
)

#fig-placeholder[Figure 3.4.1-1: Server internal component diagram - showing message flow from MQTT broker through scan handler to DB, and from event sweeper through algorithm layer to processed_events and WebSocket broadcast]

=== Event Ingestion and Raw Scan Storage

- Firmware publishes batched JSON arrays to MQTT topic `lighthouse/{id}/scans`
- Each array element contains: `epc`, `rssiDbm`, `timestampMs`, `timeBasis` (`synced` / `estimated` / `relative`)
- Server-side scan handler validates per-element; invalid elements discarded, valid ones persisted independently
- Raw scans stored in `raw_scans` table with `processedAt` and `orphanedAt` as null - marking pending status
- `timeBasis` stored verbatim; downstream processing rejects non-synced scans at cluster level (not here)
- Health telemetry published separately to `lighthouse/{id}/health`; stored but not part of event pipeline

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

#figure(
  image("./images/3.4.2-1_mqtt_ingestion.svg", width: 80%),
  caption: [Figure 3.4.2-1: MQTT ingestion sequence - firmware batch publish -> broker -> scan handler -> per-element validation -> DB insert -> WebSocket broadcast of raw scan event]
)

=== Direction Detection and Event Processing

==== Cluster detection and event sweeper

- Background poller (`EventSweeper`) runs every *2 s*
- A cluster is defined as all `raw_scans` for a given `(epc, groupId)` pair where the latest scan timestamp is older
  than the group's `activityTimeoutMs` (default *4 s*)
- Cluster detection query groups unprocessed scans by `(epc, groupId)` and filters with
  `MAX(timestamp) < NOW() - activityTimeoutMs`
- Scans for ungrouped lighthouses orphaned after *10 s*

#figure(
  image("./images/3.4.3-1_event_sweeper.svg", width: 80%),
  caption: [Figure 3.4.3-1: Event sweeper cycle flowchart]
)

==== Algorithm 1 - Temporal Centroid (C₁)

- Temporal centroid of each lighthouse's scan group computed as the mean detection
  timestamp

$ overline(t)_"out" = 1/N sum_i t_i^"out", quad overline(t)_"in" = 1/N sum_i t_i^"in" $

- Direction: $overline(t)_"out" < overline(t)_"in"$ → entry (IN); $overline(t)_"in" < overline(t)_"out"$ → exit (OUT)

- Confidence (C₁) - Centroid Separation Factor (CSF):

$ C_1 = "CSF" times "CSzF" times "BCF" $

$ "CSF" = frac(|overline(t)_"out" - overline(t)_"in"|, t_"last" - t_"first") $

#figure(
  image("./images/3.4.3-2_dashboard.png", width: 80%),
  caption: [Figure 3.4.3-2: Cluster timeline diagram - horizontal time axis; two rows (Blue Lighthouse = inside, Orange Lighthouse = outside); scan detections shown as vertical ticks; cluster start/end markers]
)

==== Algorithm 2 - RSSI-Weighted Centroid (C₂)

- RSSI values used as weights when computing the centroid of each lighthouse's scan group - stronger signal pulls the
  centroid toward the scan with highest received power
- Additionally: linear regression of RSSI vs. time computed independently for inside and outside groups; slope sign
  compared against expected direction to produce a *RSSI trend consistency factor* (RTCF)
- Expected slopes for *in* direction: outside slope < 0 (signal weakens as person departs), inside slope > 0 (signal
  strengthens as person approaches)
- RTCF = 1.0 when both trends agree; RTCF = FLOOR when both contradict; RTCF = 0.5 when fewer than 3 scans on either
  side (regression unreliable) or one side inconclusive
- Algorithm 2 can resolve direction even when temporal centroids are equal - RSSI weighting shifts the effective
  centroids apart

$ w_i = f(R S S I_i) quad "(monotonically increasing with signal strength)" $

$ overline(t)_w = frac(sum_i w_i dot t_i, sum_i w_i) $

$ C_2 = "CSF"_w times "CSzF" times "BCF" times "RTCF" $

==== Orphan handling

- `insufficient_data` (single-lighthouse cluster): orphaned only after exceeding group's `orphanTimeoutMs`
- `unsyncable` (all scans have non-synced timeBasis): non-synced scans orphaned immediately; synced scans left for
  reprocessing
- `misconfigured_group` (lighthouse has no group assigned): all scans orphaned immediately

=== User and Tag Management

- Users identified internally by UUID (`id`)
- `syncId` field carries the numeric user ID for integration with the external software
- User can have multiple EPC assignments

=== Navigo3 Integration

- Integration enabled/disabled via environment variable; disabled state has zero overhead on event pipeline
- Eligibility check before every push: event must have `algorithmId` matching config, direction must be `in` or `out`,
  user must have a valid `syncId`

==== Immediate push

- On each new processed event: `pushEvent()` called - maps to `attendance/embedded/start` (in) or
  `attendance/embedded/stop` (out) on the Navigo3 API
- `syncedToIntegration` flag set to `true` on success; left `false` on failure for retry

==== Paired upsert

- If a matching counterpart event exists (same user, opposite direction, same calendar day): `pushPair()` called instead
  - maps to `attendance/embedded/upsert`, creating a closed attendance interval in Navigo3
- Both events marked `syncedToIntegration = true` on success

==== Retry sweep

- Background poller runs every **60 s** (configurable via `NAVIGO3_RETRY_INTERVAL_MS`)
- Fetches up to 100 unsynced eligible events ordered by timestamp
- Attempts paired upsert first; falls back to individual push if no counterpart found
- Non-blocking: skips cycle if previous sweep still running

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[ Endpoint                     ][Direction   ][ Description                              ],
[ `attendance/embedded/start`  ],[ in          ],[ Register arrival                         ],
[ `attendance/embedded/stop`   ],[ out         ],[ Register departure                       ],
[ `attendance/embedded/upsert` ],[ in+out pair ],[ Create/update closed attendance interval ],
  ),
  caption: [Table 3.4.5-1 - Navigo3 API endpoints used],
)

== Dashboard

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

**Overview tab:**

- Direction, confidence percentage, tag EPC, user, group, algorithm name, timestamp, and cluster time span
- Confidence factor breakdown displayed as horizontal progress bars: centroid separation, cluster size, bilateral
  coverage, and (for Algorithm 2) RSSI trend consistency
- Link to the companion event (same cluster, other algorithm) for side-by-side comparison

**Raw Scans tab:**

- Lists all raw scans belonging to the cluster, grouped by lighthouse (inside vs. outside), showing EPC, RSSI,
  timestamp, and time basis

**Timeline tab:**

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
  quality (per Section 3.2.3)

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
- Both algorithms run on every cluster independently; results stored as separate rows per Section 3.4.3; comparison is
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

