# Lighthouse — UHF RFID Attendance System

Bachelor's thesis project: **Embedded Implementation of an Attendance System for Integration into an Enterprise Application**

**Author:** Jakub Hloušek
**Supervisor:** Ing. Michal Bastl, Ph.D.
**Institution:** Brno University of Technology, Faculty of Mechanical Engineering
**Academic year:** 2025/26

## Overview

Lighthouse is a passive, hands-free attendance tracking system using UHF RFID technology (860–960 MHz) to detect employees at 2–3 meter range without any user interaction. Tags are detected through bags, purses, and pockets. Two paired Lighthouse units at an entrance determine traversal direction (entry vs. exit) and report events to a central server, which integrates with Navigo3 — a Czech HR/enterprise application by Navigo Solutions s.r.o.

The system is designed to be cost-effective, low-maintenance, and self-contained with its own REST API, while also supporting external integration.

## Architecture

```
[UHF RFID Tag] ──► [Lighthouse Unit A] ──► MQTT ──► [Server] ──► [Navigo3 API]
                   [Lighthouse Unit B] ──►          │
                                                    ├── PostgreSQL
                                                    ├── REST API
                                                    └── SolidJS Dashboard
```

The project consists of three major components:

### Firmware (`src/lighthouse/`)

ESP32-based firmware written in C using ESP-IDF and FreeRTOS. Runs on custom PCBs with YPD-R300 UHF RFID reader modules.

Key features:
- UHF RFID tag reading via UART (command 0x89 real-time inventory)
- IR sensor-triggered scan windows
- WiFi provisioning via captive portal (AP mode with DNS redirect)
- MQTT communication with QoS 2 and Last Will & Testament
- NTP time synchronization with explicit quality tracking (`synced`, `estimated`, `relative`)
- Offline event caching on LittleFS (2 MB partition, ~43k events)
- Battery monitoring via ADC
- Health telemetry reporting
- AES-encrypted credential storage in dedicated NVS partition

Firmware source modules: `lighthouse.c`, `rfid_reader.c`, `my_mqtt_client.c`, `io_controller.c`, `battery_monitor.c`, `time_sync.c`, `wifi_manager.c`, `offline_event_logger.c`, and the `wifi_provisioning` component.

### Server (`src/server/`)

BunJS/TypeScript backend with an embedded MQTT broker.

| Layer      | Technology | Purpose                          |
|------------|------------|----------------------------------|
| Runtime    | Bun        | TypeScript execution, test runner|
| HTTP       | Hono       | REST API framework               |
| Database   | PostgreSQL | Persistent storage               |
| ORM        | Drizzle    | Type-safe queries, migrations    |
| MQTT       | Aedes      | Embedded broker (no external dep)|
| Frontend   | SolidJS    | Dashboard SPA                    |
| Build      | Vite       | Frontend bundling                |

REST API provides endpoints for lighthouses, groups, events, scans, and users. WebSocket support for real-time dashboard updates. Retention cleanup scheduler for old data. Event sweeper for processing closed RFID scan clusters.

### Hardware (`circuits/lighthouse/`)

Custom PCB designed in KiCad. Board v2 has been sent to fabrication (PCBWay).

Key components: ESP32-WROOM-32, YPD-R300 UHF RFID module, TP4056 charging module (USB-C), SX1308 DC-DC boost converter, CP2102 USB-UART bridge, 18650 battery holder, IR sensor for scan triggering.

### Dashboard (`src/server/src/web/`)

SolidJS single-page application served by the backend. Pages for lighthouse management, groups, raw events, processed events, and users.

## Repository Structure

```
.
├── src/
│   ├── lighthouse/          # ESP32 firmware (ESP-IDF/FreeRTOS, C)
│   │   ├── main/            # Core firmware modules
│   │   ├── components/      # WiFi provisioning component (captive portal, settings)
│   │   ├── partitions.csv   # Flash partition layout
│   │   └── sdkconfig        # ESP-IDF configuration
│   └── server/              # Backend + frontend (BunJS, TypeScript, SolidJS)
│       ├── src/
│       │   ├── api/         # Hono REST routes and middleware
│       │   ├── database/    # Drizzle ORM schema and client
│       │   ├── mqtt/        # Aedes broker, topic handlers
│       │   ├── services/    # Event processing, algorithms, Navigo3 integration
│       │   └── web/         # SolidJS dashboard (pages, components, stores)
│       └── tests/           # Bun test suite
├── circuits/lighthouse/     # KiCad PCB project (schematic, board, components)
├── docs/                    # Datasheets, API docs, design documents
├── tasks/                   # Agent task documents (implementation specs)
├── logbook/                 # Development logs
├── write/                   # Thesis LaTeX/Typst sources
├── scripts/                 # Utility scripts (NTP setup)
└── presentation/            # Presentation materials
```

## Prerequisites

### Firmware

- [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/) (v5.x)
- ESP32 development board or Lighthouse custom PCB
- USB-UART connection (CP2102 or external adapter)

### Server

- [Bun](https://bun.sh/) runtime
- PostgreSQL (with a database named `attendance`)
- [chrony](https://chrony-project.org/) NTP server (optional, for ESP32 time sync on LAN — config in `src/server/config/chrony.conf`)

## Building & Flashing the Firmware

### 1. Set up ESP-IDF environment

```bash
. /home/kuba/code/esp-idf/export.sh
```

### 2. Build

```bash
cd src/lighthouse
idf.py build
```

### 3. Flash

The firmware uses a custom partition table. All four binaries must be flashed to their correct offsets:

```bash
esptool --chip esp32 -p /dev/ttyUSB0 -b 921600 \
  --before=no-reset --after=no-reset --no-stub \
  write-flash --flash-mode dio --flash-freq 40m --flash-size detect \
  0x1000 ./build/bootloader/bootloader.bin \
  0x8000 ./build/partition_table/partition-table.bin \
  0x360000 ./build/spiffs.bin \
  0x10000 ./build/lighthouse.bin
```

**Flash layout** (from `partitions.csv`):

| Offset     | Size   | Partition        | Purpose                              |
|------------|--------|------------------|--------------------------------------|
| 0x1000     | —      | Bootloader       | ESP-IDF managed                      |
| 0x8000     | 4 KB   | Partition table  | Partition metadata                   |
| 0x9000     | 24 KB  | `nvs`            | System NVS (WiFi calibration, etc.)  |
| 0xF000     | 4 KB   | `phy_init`       | RF calibration data                  |
| 0x10000    | 1280 KB| `factory`        | Application firmware                 |
| 0x150000   | 2 MB   | `offline_events` | LittleFS — offline RFID event cache  |
| 0x350000   | 16 KB  | `nvs_settings`   | Encrypted WiFi/MQTT credentials      |
| 0x360000   | 64 KB  | `spiffs`         | Setup page HTML (captive portal)     |

### 4. Monitor serial output

```bash
idf.py -p /dev/ttyUSB0 monitor
```

Or with custom baud rate:

```bash
idf.py -p /dev/ttyUSB0 -b 115200 monitor
```

Exit monitor with `Ctrl+]`.

## Running the Server

### 1. Install dependencies

```bash
cd src/server
bun install
```

### 2. Configure database

The server expects PostgreSQL at `postgresql://postgres:postgres@localhost:5432/attendance` by default. Override with the `DATABASE_URL` environment variable.

Run Drizzle migrations:

```bash
bunx drizzle-kit push
```

### 3. Start the server

Development mode (with file watching):

```bash
bun run dev
```

This starts the HTTP server (with embedded MQTT broker) and serves the API.

### 4. Build and serve the dashboard

Development (Vite dev server with HMR):

```bash
bun run dev:web
```

Production build:

```bash
bun run build:web
```

The production build is served automatically by the backend at the root path.

### 5. Run tests

```bash
bun test
```

Individual test suites:

```bash
bun test tests/mqtt-broker.test.ts
bun test tests/event-processing.test.ts
bun test tests/api-routes.test.ts
```

## Device Setup (First Boot)

1. Power on the Lighthouse unit. If no WiFi credentials are stored, it enters setup mode automatically.
2. Long-press BUTTON1 (5 seconds) to force entry into setup mode at any time.
3. Connect to the `Lighthouse-Setup` WiFi network from a phone or computer.
4. A captive portal opens automatically on iOS, Android, Windows, and macOS. On Linux, navigate to `http://192.168.4.1` manually.
5. Enter WiFi SSID, password, and MQTT broker IP/port on the setup page.
6. The device tests connectivity, saves encrypted credentials to NVS, and reboots into normal operation.

## Debugging

### Firmware debug tips

- **Serial log levels**: Controlled via `sdkconfig`. Default is `DEBUG`. Use `idf.py menuconfig` under `Component config → Log output` to change.
- **RF debug mode**: Compile with `#define RF_DEBUG_MODE` in `lighthouse.c` to enable power sweep, parameter queries, and continuous RSSI inventory. This replaces normal operation entirely.
- **Button controls in normal mode**: BUTTON1 starts/stops scanning; BUTTON2 prints statistics to serial.
- **LED indicators**: WiFi status LED, MQTT status LED, and RFID scanning status LED provide visual feedback on GPIO pins.
- **Offline event log**: Events are cached in LittleFS at the `offline_events` partition. The log uses a ring buffer with CRC32 integrity checks per record.
- **Time quality**: Check serial output for `TIME_QUALITY_SYNCED`, `TIME_QUALITY_ESTIMATED`, or `TIME_QUALITY_NONE` — events are tagged with this quality in MQTT payloads as the `timeBasis` field.

### Server debug tips

- **Server logs**: Structured logging via the internal logger. Increase verbosity by editing `src/utils/logger.ts`.
- **MQTT debugging**: The embedded Aedes broker runs alongside the HTTP server. Use any MQTT client (e.g., `mosquitto_sub`) to subscribe to `lighthouse/#` topics for raw traffic inspection.
- **Database inspection**: Connect directly to PostgreSQL. Key tables: `raw_scans` (immutable audit log), `processed_events` (derived entry/exit), `lighthouses`, `tag_assignments`, `users`.
- **Integration test**: `bun run scripts/integration-test.ts` exercises the MQTT → database pipeline.

### NTP setup

The server machine doubles as the NTP server for Lighthouse devices on the LAN. Install and configure chrony using the provided config:

```bash
sudo cp src/server/config/chrony.conf /etc/chrony/chrony.conf
sudo systemctl restart chrony
```

Alternatively, use the setup script:

```bash
sudo bash scripts/setup-ntp.sh
```

## Documentation

- `docs/` — Component datasheets (ESP32, R300 RFID module, TP4056, CP2102, etc.)
- `docs/navigo_api.md` — Navigo3 REST API documentation
- `docs/phase2_event_processing_plan.md` — Direction detection algorithm design
- `docs/phase4_integration.md` — Navigo3 integration plan
- `logbook/` — Chronological development logs
- `tasks/` — Structured implementation task documents

## License

See [LICENSE](LICENSE).
