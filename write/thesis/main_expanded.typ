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

Automated employee attendance tracking requires a reliable means of identifying a person at a physical boundary - a doorway, turnstile, or office entrance - without manual involvement from staff or administrators. Commercially available systems draw their identification mechanism from one of three categories: knowledge-based (PIN code), biometric (fingerprint, facial recognition), or token-based (a card or tag carried by the employee). The relevant question for this project is which of these can be made fully passive at a distance of two to three metres.

Knowledge-based systems require the employee to stop at a terminal and enter a code. Beyond the queueing this introduces, they are highly susceptible to so-called buddy-punching, where one employee enters another's code on their behalf. Knowledge-based identification is therefore unsuitable for any application aiming at hands-free operation.

Biometric systems can technically eliminate deliberate user action - a face is read while the employee walks past a camera - but introduce a considerably more serious obstacle. Biometric data processed for the purpose of uniquely identifying a person is classified as a special category of personal data under Article 9 of Regulation (EU) 2016/679 (GDPR), and its processing is by default prohibited absent one of the narrow legal bases enumerated in Article 9(2) @gdpr. Combined with a unit cost typically an order of magnitude above token-based readers, both factors disqualify biometrics for this project.

Token-based identification removes any requirement for the employee to stop or act; the employee simply carries a tag. The differentiating parameter between technologies in this category is read range. High-frequency RFID at 13.56 MHz - the technology behind ISO/IEC 14443 @iso-14443 and ISO/IEC 15693 @iso-15693 - operates in the near field and is restricted to roughly 0–10 cm, which forces the user to deliberately present the card; the experience is effectively equivalent to PIN entry. Ultra-high-frequency RFID at 860–960 MHz, governed by EPC Gen2 / ISO/IEC 18000-63 @iso-18000-63, operates in the far field and reaches 1–12 m with passive (battery-less) tags. A tag carried in a bag or pocket is detected at walking pace without any deliberate action by its carrier.

UHF RFID is therefore the only mature passive identification technology meeting the hands-free, 2–3 m range requirement, and is selected as the basis for this system.

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

Distinguishing arrival from departure is a hard requirement for any attendance system; merely confirming that a tag was present at a location is not sufficient. A single reader provides only a presence event and cannot resolve direction, so direction information must be recovered from a second observable.

The standard approach is to mount two readers on opposite sides of the doorway and treat the pair as a portal. The temporal sequence of detections from the two readers carries the direction: detections that begin at the outside reader before the inside reader imply entry, and the reverse implies exit.

The simplest implementation is comparing the timestamps of the very first detection from each reader but is somewhat unreliable in practice. Passive UHF tags respond probabilistically and the radiation field in a real doorway is irregular due to multipath reflections; an early read from an RF null or a reflected wave can invert the apparent detection order. Oikawa demonstrates this failure mode experimentally on an RFID gate and proposes comparing the read-count-weighted temporal centroid of each reader's full detection group instead, which is far more robust to individual outlier reads @oikawa-2009.

A complementary signal is available in the received signal strength indicator (RSSI). As a tag traverses the portal, its RSSI at each reader rises while the tag approaches, peaks at the moment of closest approach, and falls as the tag moves away - a direct consequence of the inverse-square dependence of received power on distance described by the Friis transmission equation. The reader whose RSSI peaks first is therefore the reader the tag passed first; in the portal geometry this carries the same direction information as the temporal centroid by an entirely different physical mechanism. This principle is used as the primary direction cue in the RF-Access barrier-free access control system of Jie et al. @jie-2022-rf-access.

Two algorithmic families therefore emerge from this literature: a temporal centroid algorithm following Oikawa's approach, and an RSSI-weighted centroid algorithm based on the Friis-derived peak-time argument. Both require the full set of raw timestamped RSSI readings from both readers - any per-device deduplication or summarisation discards the very signal the algorithms operate on. Detailed mathematical formulations of both families are given in #ref(<direction_detection_and_event_processing>).

#fig-placeholder[Figure 2.2-1: Dual RSSI curves over time for a single traversal; temporal centroids C_out and C_in marked; RSSI peaks labelled; direction arrow outside to inside]

== Hardware Platforms and Embedded Architectures <hardware_platforms_and_embedded_architectures>

The Lighthouse unit's hardware platform must support the full set of identification, network, and local-storage tasks within a single self-contained embedded device. The two principal sub-decisions are the choice of microcontroller and the choice of UHF RFID reader module.

=== Microcontroller Selection <microcontroller_selection>

The Lighthouse runs several concurrent tasks: UART communication with the RFID reader, WiFi connectivity and MQTT publishing, persistent local event storage, and management of GPIO peripherals. The microcontroller therefore needs integrated WiFi, at least one hardware UART, sufficient RAM to run a network stack alongside application logic, enough flash for firmware and an event-cache filesystem, a power profile compatible with battery-backed operation, a mature SDK and toolchain, and a low unit cost.

Single-board computers such as the Raspberry Pi satisfy the connectivity and processing requirements but are unsuitable on several other axes. They run a full Linux distribution with all of its boot, update, and management overhead; their power draw is substantially higher than a microcontroller's; and they typically depend on an SD card for persistent storage, with well-documented reliability problems in continuous embedded deployments. They are also significantly oversized for a single-peripheral embedded task. SBCs are therefore rejected.

Among microcontrollers with integrated WiFi, the ESP32 from Espressif Systems is the strongest match. It pairs a dual-core Xtensa LX6 CPU at up to 240 MHz with 520 KB of internal SRAM, integrated 2.4 GHz WiFi (802.11 b/g/n) and Bluetooth, and a rich peripheral set including multiple UARTs, I²C, SPI, ADC, and hardware AES/SHA cryptographic accelerators @esp32-trm. The dual-core architecture is particularly relevant for this application: the WiFi/network stack can be pinned to Core 0 while the application logic runs on Core 1, eliminating cross-task interference between time-critical RFID handling and the inherently non-deterministic behaviour of a wireless network stack @maly-2024.

The ESP-IDF framework, Espressif's official SDK, integrates every component this project requires - a FreeRTOS kernel, the WiFi stack, an MQTT client, NVS, LittleFS, SNTP, and mbedTLS - all maintained by the silicon vendor @esp-idf. Combined with extensive documentation, an active community, and a module unit cost of approximately 3–5 USD, the ESP32-WROOM-32 module is selected as the platform for the Lighthouse unit.

=== UHF RFID Reader Modules <uhf_rfid_reader_modules>

UHF RFID readers are available across a wide cost and integration spectrum, from rack-mountable enterprise readers (Impinj R420 and similar) at hundreds of dollars to bare R-series chips intended for OEM integration. The relevant tier for this project is the embedded-integration tier: compact carrier modules that expose a UART command interface and can be controlled directly by a microcontroller. Within this tier, the selection criteria were a documented UART command protocol, 5 V supply compatibility (matching the board's primary rail), and a unit cost suitable for small-scope prototyping.

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

The YPD-R300 was selected. Its higher RF output rating relative to the R200 line supports the 2–3 m range requirement; its 5 V supply matches the board's main power rail directly; and its external SMA connector permits the antenna to be substituted during range testing, which is not possible with the integrated-antenna variant. The bare R-series chip option was rejected as it would require a custom RF front-end design, an unjustifiable scope expansion at the prototype stage. The Impinj R420 and the ThingMagic and SparkFun modules, while well-supported, were excluded on cost grounds; their per-unit price would consume a disproportionate share of the prototype budget for three units.

The 25 dBm RF output value cited in Table 2.3.2-1 reflects the module's actual hardware ceiling rather than the higher 33 dBm nominal value given on the manufacturer's datasheet; the relevant firmware-side handling of this discrepancy is discussed in #ref(<uhf_rfid_scan_control>).

=== Power Supply and Battery Considerations <power_supply_and_battery_considerations>

The Lighthouse must operate from USB-C mains power while a lithium-ion cell provides backup autonomy. Both sources must be capable of powering the device simultaneously, with automatic and electrically safe arbitration between them so that connecting or disconnecting either source does not interrupt operation.

A single lithium-ion cell at 3.7 V nominal cannot directly supply either of the two regulated rails the device requires: the ESP32 needs a 3.3 V regulated supply, and the YPD-R300 RFID reader requires 5 V. A boost converter is therefore required to step the cell voltage up to 5 V, from which a low-dropout regulator derives the 3.3 V rail.

The constituent sub-problems - battery charging, cell protection (against overcurrent, overvoltage, and undervoltage), and arbitration between the USB and battery-derived 5 V rails via a Schottky-diode OR are well-established in embedded design practice, and dedicated single-function ICs exist for each role. The specific selections and the assembled topology are described on #ref(<power_delivery_architecture>, form: "page").

One characteristic of this particular load deserves mention here, as it constrains the entire power chain: the UHF reader draws significant peak current during active scan windows. The supply must sustain these transients without rail collapse - an undersized converter or insufficient bulk decoupling will cause the ESP32 to brown out and reset. Sizing of converters, bulk capacitance, and the connections between them must therefore be dimensioned for peak rather than average current.

=== Timekeeping Without a Hardware RTC <timekeeping_without_a_hardware_rtc>

The ESP32-WROOM-32 module does not include a battery-backed real-time clock. The internal RTC counter on the SoC continues to run during deep sleep but loses its value on a cold boot @esp32-trm[§9.3.6]. For an attendance system, every event must carry a timestamp traceable to real calendar time, so a boot-relative counter is not by itself sufficient.

The standard approach for ESP32 timekeeping is synchronisation over the network using the Simple Network Time Protocol (SNTPv4) @rfc4330. ESP-IDF includes a built-in SNTP client that synchronises the SoC's RTC counter against one or more configured time servers; the residual error after synchronisation is well below one second, which is more than adequate for attendance event timestamping.

The limitation of an SNTP-only design is that calendar time is lost whenever the device powers off or loses network access. The mitigation applied at the data-model level is a `timeBasis` field carried on every event payload, with three values - `synced`, `estimated`, or `relative` - communicating the provenance of the timestamp to the server, which then applies appropriate handling. A hardware RTC IC with coin-cell backup would eliminate the underlying limitation entirely and is identified as the primary hardware improvement for a future board revision.

== Communication Protocols and Enterprise Integration <communication_protocols_and_enterprise_integration>

Two distinct communication paths exist in this system, with different requirements. The firmware-to-server path carries frequent small messages from a constrained embedded device over an unreliable wireless network. The server-to-enterprise path carries low-frequency, high-importance attendance records pushed from the server to an external HR system. The two paths are evaluated separately.

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

For the firmware-to-server path, MQTT is selected. It was designed specifically for constrained devices communicating over unreliable networks and provides the three features this project relies on directly: tunable Quality-of-Service levels, automatic reconnection in the client library, and a Last Will and Testament (LWT) message published by the broker when a client disconnects unexpectedly @mqtt. QoS 1 (at-least-once) is used for live scan publishes during high-frequency scan windows, where occasional duplicate delivery is tolerable and the lower handshake overhead is essential. QoS 2 (exactly-once) is used for offline replay of cached events, where duplicate attendance records would be incorrect and the lower throughput is irrelevant. The LWT mechanism gives the server immediate notification of an unexpected device disconnection without polling.

The transport is offline-first: every event is written to a LittleFS-backed cache before any attempt to transmit it, and is replayed on reconnection. No event is discarded as a result of transient network unavailability.

For the server-to-enterprise path, REST over HTTP is appropriate. Attendance records are created once per traversal event - a low-frequency, high-importance flow that is well served by stateless idempotent HTTP endpoints, which are also universally supported by enterprise software. The integration target is Navigo3, the HR and project-management platform developed by Navigo Solutions s.r.o.; its REST API is built on the open-source `dry-api` framework, a typed JSON-over-HTTP transport @dry-api @navigo3-api. The platform's attendance-recording endpoints were extended in release 2026.03 with parametrised `start`/`stop` overloads, developed in conjunction with this thesis; the connector implementation is described in #ref(<navigo3_integration>).

== Embedded Software Frameworks <embedded_software_frameworks>

The ESP32 platform is supported by ESP-IDF (Espressif IoT Development Framework), the official vendor SDK. It bundles all of the components this project requires and avoids the fragmentation of assembling a firmware stack from independent libraries @esp-idf @maly-2024.

FreeRTOS, integrated into ESP-IDF, is a preemptive real-time kernel that provides tasks, queues, semaphores, and event groups @freertos. It pairs with the dual-core architecture naturally: the WiFi stack runs on Core 0 (managed by ESP-IDF) while application tasks - RFID control, MQTT publishing, the offline event cache, and the LED state machine - run on Core 1 without contending for the network stack's CPU time. This is the standard arrangement for ESP32 application firmware.

NVS (Non-Volatile Storage), an ESP-IDF component, exposes a key-value store backed by an internal flash partition with transparent wear-levelling. It is used for WiFi credentials, MQTT broker configuration, device identity, the last-known-good timestamp, and offline buffer pointers; for configuration data of this kind it is simpler and more robust than maintaining a hand-rolled flash partition.

LittleFS, a wear-levelling filesystem designed for NOR flash, is used for the offline event cache. It is included as an ESP-IDF component and was chosen over SPIFFS - the older alternative bundled with earlier ESP-IDF versions - for its crash resilience and its support for directories @littlefs.

mbedTLS, also part of ESP-IDF, provides the cryptographic primitives needed to encrypt WiFi credentials stored in NVS using AES-128-ECB. The ESP32 includes a hardware AES accelerator, which mbedTLS uses transparently when configured for the platform @esp32-trm[§14], keeping the encryption overhead negligible.

For initial WiFi credential entry, the ESP-IDF `wifi_provisioning` component (BLE-based) was evaluated and rejected because it requires a companion mobile application, undermining the goal of a self-contained device with no auxiliary tooling on the employee or installer side. A custom captive-portal solution was implemented instead - SoftAP mode combined with DNS hijacking and an HTTP credential form served from SPIFFS - so that any device with a browser can provision the unit regardless of operating system.

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

=== Architecture and Stack <dashboard-arch>

The dashboard is a single-page application built with SolidJS, chosen for its fine-grained reactivity model: component state updates propagate directly to the DOM without a virtual-DOM diffing pass, keeping the runtime footprint small. Client-side routing is handled by `@solidjs/router` with five declared routes; the compiled static build is served directly from the BunJS process that hosts the REST API and MQTT broker, eliminating the need for a separate static file server. Per-component CSS modules provide style encapsulation. 

Real-time updates are delivered over a single WebSocket connection opened on application mount in `App.tsx`. A central WebSocket store receives incoming messages and dispatches them to page-specific reactive stores, so only the relevant page re-renders on each incoming event; no polling is required. Table~@tbl-ws-messages lists the seven message types produced by the server and their consumer pages. Authentication is outside the scope of this prototype; the dashboard and REST API are accessible without credentials on the local network, with session management and role-based access control identified as future work. 

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
  caption: [WebSocket message types and their consumer pages],
) <tbl-ws-messages>

=== Pages <dashboard-pages>

==== Lighthouses (`/`) <page-lighthouses>

The root page lists all registered Lighthouse devices with their current status: online/offline indicator and the most recent health telemetry payload - uptime, WiFi RSSI, and RFID reader state. Health data arrives via `device:health` WebSocket messages and updates the display without a page refresh. Devices that connect to the MQTT broker but are not yet registered appear in a separate _pending_ section; the operator assigns a name and a placement (inside/outside) to claim the device. The ESP32 eFuse MAC address serves as the stable device identifier throughout registration. 

==== Groups (`/groups`) <page-groups>

A group pairs two Lighthouses - one designated outside, one inside - into a detection portal. The page manages the group label and description; the two per-group timing parameters (`activityTimeoutMs`, default 4 000 ms; `orphanTimeoutMs`, default 8 000 ms) are stored in the database and configurable via the REST API, but UI controls for these values are out of scope for this prototype. A Lighthouse may belong to at most one group; scans from ungrouped units are orphaned by the event sweeper and never produce processed events. 

==== Events (`/events`) <page-events>

The Events page is a live feed of raw scan records as they arrive from Lighthouse units. New scans are prepended to the table via the `scan` WebSocket message. The table is filterable by Lighthouse, EPC (partial match), scan source (`realtime` / `offline_sync`), and date range. The page serves as a diagnostic tool, allowing the operator to confirm that both units in a portal are detecting tags before trusting the direction detection output. 

==== Processed Events (`/processed`) <page-processed>

This page displays the output of the direction detection pipeline. Each row represents one processed event and shows direction, confidence, algorithm, tag EPC, assigned user, group, and timestamp. Rows are filterable by algorithm, direction, user, group, and date range; both algorithms can be viewed simultaneously in a merged, time-sorted view. A notification banner appears when new `event:new` WebSocket messages arrive while the page is open, allowing the operator to refresh without leaving the page. 

Each row opens a detail modal with three tabs:

- *Overview* - direction, confidence percentage, tag EPC, user, group, algorithm,
  timestamp, and cluster time span; confidence factor breakdown rendered as horizontal
  progress bars (centroid separation, cluster size, bilateral coverage, and - for
  Algorithm~2 - RSSI trend consistency); a link to the companion event produced by the
  other algorithm for direct comparison.
- *Raw Scans* - all raw scans belonging to the cluster, grouped by Lighthouse
  (inside vs. outside), with EPC, RSSI, timestamp, and time basis.
- *Timeline* - a scan-timing histogram with a horizontal time axis, bars coloured by
  Lighthouse (blue = outside, orange = inside), and dashed centroid markers. For
  Algorithm~2, an RSSI-over-time scatter plot with per-Lighthouse linear regression lines
  is rendered below the histogram, illustrating the signal trend used in the RSSI Trend
  Consistency Factor calculation.

#figure(
  image("images/3.5.2-1_modal.png", width: 100%),
  caption: [Processed event detail modal - Overview tab showing direction, confidence,
            confidence factor bars, and companion algorithm link.],
) <fig-modal-overview>

#figure(
  image("images/3.5.2-2_modal.png", width: 100%),
  caption: [Processed event detail modal - Timeline tab showing scan timing histogram
            with centroid markers and RSSI scatter plot with regression lines.],
) <fig-modal-timeline>

==== Users (`/users`) <page-users>

The Users page manages user records comprising a display name, email address, and a Navigo3 sync ID used by the integration layer. Each user may have multiple EPC tag assignments active simultaneously; deactivated assignments are retained with a `deactivatedAt` timestamp for audit purposes rather than being deleted. 

== System verification

All validation was conducted using three Board v2 Lighthouse units running production firmware, each assembled in its final 3D-printed enclosure. The detection portal for all multi-unit tests was formed by the Red unit (designated OUTSIDE) and the Yellow unit (designated INSIDE); both portal units are equipped with IPEX/U.FL receptacle antenna connections. The Blue unit participated only in the standalone detection range measurement. The server ran on a local area network with an embedded Aedes MQTT broker, PostgreSQL storage, and a Navigo3 test instance connected via the integration layer described in #ref(<navigo3_integration>). The event sweeper was configured with `activityTimeoutMs = 4000 ms` and a polling interval of 2 seconds throughout all sessions. 

=== Detection range

Per-unit detection range was measured with each unit in isolation. A passive UHF tag was held up oriented directly toward the antenna. Maximum reliable range was defined as the furthest distance at which the tag was detected in every one of three consecutive scan windows; distance was stepped in 0.5 m increments. Red was measured at two points in the test campaign due to a mechanical event discussed below. 

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Unit][Antenna connection][Max reliable range \[m\]][Condition],
    [Red],    [IPEX/U.FL],    [2.5], [Pre-drop],
    [Red],    [IPEX/U.FL],    [1.5], [Post-repair],
    [Yellow],  [IPEX/U.FL],    [3.0], [N/A],
    [Blue],           [Direct-solder],   [3.0], [N/A],
  ),
  caption: [Table 3.6.1-1 - Detection range per unit],
)

Yellow and Blue produce identical 3.0 m maximum reliable ranges despite using different antenna connection methods, demonstrating that an IPEX/U.FL receptacle carries no measurable range penalty relative to a direct-solder pigtail when joint quality is consistent. Detection range at this power level is bounded by the YPD-R300 module's transmit power ceiling and antenna gain, not by the connection type itself. Red's pre-drop range of 2.5 m was already 0.5 m below the other two units, attributable to assembly-level variance in the IPEX cable and connector as discussed in #ref(<antenna_and_rf_considerations>). 

=== Direction detection accuracy

Controlled traversals were performed through the portal at normal walking pace. Each traversal was logged as a processed event by the server; the algorithm's direction output was compared against the intended direction. Detection rate is reported as $(n_"detected" / n_"attempted") times 100%$ with 95% Wilson score confidence intervals; missed detections were identified post-hoc from raw scan data as one-sided clusters orphaned by the sweeper as `insufficient_data` (per #ref(<orphan_handling>)). 

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Algorithm][Correct \[n\]][Incorrect \[n\]][Unknown \[n\]][Accuracy \[%\]],
    [Temporal Centroid ($C_1$)], [78], [0], [0], [100.0],
    [RSSI-Weighted ($C_2$)],     [78], [0], [0], [100.0],
  ),
  caption: [Table 3.6.1-2 - Direction detection accuracy per algorithm (combined dataset, n = 78 detected traversals)],
)

Direction accuracy across the full test campaign was 100% on both algorithms over 78 detected traversals. The detection rate, however, varied substantially with tag carry method. Under unobstructed hand-held conditions, 41 of 42 attempted traversals were detected (97.6%; 95% CI: 87.7--99.6%). With the tag carried in a near-side front trouser pocket at close range, 20 of 23 traversals were detected (87.0%; 95% CI: 67.9--95.5%). At longer range in the same pocket position, detection rate fell further (5 of 7; 71.4%; small sample). Tag carry on a lanyard presenting the tag edge-on to the antennas, and carry in a cross-body trouser pocket, produced effectively zero detection in both cases; these failure modes are a consequence of UHF tag polarisation physics interacting with the chosen portal geometry rather than a system limitation. The system's failure mode is exclusively non-detection: the `insufficient_data` orphan logic in the event sweeper guarantees that no direction call is produced from a one-sided cluster, so any event that reaches the database reflects bilateral evidence of traversal. 

The bilateral coverage factor (BCF, defined in #ref(<direction_detection_and_event_processing>)) quantifies the balance of scan counts between the two units per cluster. Its mean shifted from 0.59 under unobstructed hand-held conditions to 0.42 in the close-range pocket session and 0.32 at longer range, reflecting the signal attenuation introduced by body absorption. Despite this degradation, every detected cluster produced a correct direction call, confirming that the temporal centroid approach is robust to scan asymmetry provided at least one scan is received from each unit.

Mean $C_1$ confidence across all sessions was 0.327 ± 0.155; mean $C_2$ confidence was 0.176 ± 0.099, a ratio of approximately 1.86:1. The $C_2$ deficit is driven by the RSSI Trend Consistency Factor, which rarely achieves high values during a normal walking traversal because the RSSI signal over a four-second window is noisy rather than monotonic. This does not affect directional accuracy; both algorithms produced identical directional outputs on every detected traversal. 

=== End-to-end processing time

End-to-end latency was measured as the interval between `cluster_started_at` - the timestamp of the first RFID scan in a cluster - and the Navigo3 audit log database commit time for the resulting attendance record. This interval captures the full server-side pipeline: scan accumulation, `activityTimeoutMs` expiry, sweeper polling delay, direction detection, HTTP POST to Navigo3, and database write. The `cluster_started_at` timestamp lags the physical IR trigger by approximately 400 ms (200 ms YPD-R300 power-on delay plus 200 ms stabilisation period); true end-to-end latency from IR trigger is therefore approximately 400 ms greater than the values in Table 3.6.1-3. The dataset covers 15 events from 8 attendance records (8 IN and 7 OUT events). 

#figure(
  table(
    columns: (auto, auto),
    table.header[Metric][Value \[s\]],
    [Theoretical minimum], [\~11],
    [Mean measured (cluster start → Navigo3)], [9.54 ± 1.16],
    [Mean measured (IR trigger → Navigo3, adjusted)], [\~9.94],
    [Min measured],        [7.46],
    [Max measured],        [11.69],
  ),
  caption: [Table 3.6.1-3 - End-to-end processing time (IR trigger → Navigo3 record)],
)

All 15 events fell within the theoretical pipeline budget of approximately 11 seconds. The single event that marginally exceeded the budget (11.69 s) is attributable to a worst-case combination of cluster scan distribution and sweeper polling alignment. OUT events completed approximately 1.3 s faster than IN events on average. The standard deviation of 1.16 s across all events is consistent with the 0–2 s uniform jitter introduced by the sweeper's fixed polling interval, which is the dominant source of latency variance in this pipeline.

=== Offline replay verification

Between the testing sessions the Red unit was dropped and subsequently repaired; a post-repair range measurement confirmed the reduction from 2.5 m to 1.5 m recorded in Table 3.6.1-1, which resulted in a scan count asymmetry favouring the Yellow unit during the offline replay session that follows. 

Twelve alternating traversals were performed during a deliberate offline window of approximately four minutes and twenty-five seconds. The server was then restarted and replay was observed to completion. 

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Scans buffered][Scans replayed][Scans lost][Processed events][Navigo3 records],
    [606], [606], [0], [12 / 12], [12],
  ),
  caption: [Table 3.6.1-4 - Offline replay verification results],
)

All 606 replayed scans carried `timeBasis = synced`, confirming that SNTP wall-clock timestamps were preserved correctly through the LittleFS ring buffer. The sweeper successfully clustered every traversal's scans bilaterally despite the replay rate of approximately ten entries per second, producing 12 processed events in perfect alternating OUT/IN sequence. No stale entries from prior sessions were re-delivered. Confidence and BCF distributions were consistent with the hand-held benchmark session, confirming that no degradation in clustering quality results from the replay path relative to live operation. 

=== Algorithm comparison

The combined dataset of 78 detected traversals, spanning the hand-held benchmark, near- and far-side pocket sessions, and the offline replay session, was used for a head-to-head comparison of Algorithm 1 (Temporal Centroid, $C_1$) and Algorithm 2 (RSSI-Weighted Centroid, $C_2$). Both algorithms are run on every cluster independently by the event sweeper per #ref(<direction_detection_and_event_processing>); the comparison is therefore a post-hoc analysis of stored outputs requiring no reprocessing. 

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Metric][$C_1$ - Temporal Centroid][$C_2$ - RSSI-Weighted Centroid],
    [Overall accuracy \[%\]],            [100.0],          [100.0],
    [Correct directions \[n\]],          [78 / 78],        [78 / 78],
    [Incorrect directions \[n\]],        [0],              [0],
    [Unknown directions \[n\]],          [0],              [0],
    [Mean confidence (all calls)],       [0.327 ± 0.155],  [0.176 ± 0.099],
    [Confidence ratio ($C_1 : C_2$)],   [1.86 : 1],       [-],
    [Inter-algorithm agreement \[%\]],   [100.0],          [-],
  ),
  caption: [Table 3.6.3-1 - Algorithm comparison summary (combined dataset, n = 78)],
)

Both algorithms classified direction correctly in every detected case under all tested conditions. The directional outputs of the two algorithms are perfectly correlated across the entire campaign. $C_2$'s lower confidence reflects the additional gating effect of the RSSI Trend Consistency Factor: when RSSI is noisy over the cluster window - which is the common case during a normal walking traversal - the composite $C_2$ confidence is penalised even though the directional inference is correct. $C_1$'s score, computed from centroid separation, cluster size, and bilateral coverage alone, is less susceptible to this penalty and produces confidence values that more directly reflect the geometric quality of the cluster. 

$C_1$ is the recommended algorithm for production deployment. It produces identical directional outputs to $C_2$ with consistently higher and more interpretable confidence scores, and its factors map directly to measurable cluster properties that operators can reason about. $C_2$ remains valuable as an independent confirmation channel - agreement between the two algorithms on every processed event strengthens the evidence behind each attendance record - but does not provide additional discriminating power beyond $C_1$ under the conditions tested. Future work involving tag carrier identification or multi-tag clutter rejection may benefit from $C_2$'s RSSI weighting in scenarios where $C_1$'s temporal information alone is insufficient. 

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
  - (4) system verification - lab validation performed
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

#bibliography("references.bib", style: "ieee")
