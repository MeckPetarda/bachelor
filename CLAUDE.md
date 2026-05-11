# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An RFID-based attendance tracking system (bachelor thesis). ESP32 devices ("lighthouses") scan UHF RFID tags and report scans to a central server over MQTT. The server processes scans, stores them in PostgreSQL, and exposes a REST API plus a SolidJS dashboard.

Two independent sub-projects live under `src/`:
- `src/server/` — Bun/TypeScript backend with embedded MQTT broker + SolidJS frontend
- `src/lighthouse/` — ESP32 firmware (ESP-IDF, C)

---

## Server (`src/server/`)

### Commands

```bash
# Install dependencies
bun install

# Run server with hot reload
bun run dev

# Run Vite dev server for frontend (proxies /api/v1, /ws, /health to :3000)
bun run dev:web

# Build frontend (outputs to dist/web/)
bun run build:web

# Run all tests
bun test

# Run a specific test file
bun test tests/mqtt-broker.test.ts

# Database migrations
bunx drizzle-kit generate   # generate migration from schema changes
bunx drizzle-kit migrate    # apply pending migrations
bunx drizzle-kit studio     # open Drizzle Studio
```

### Environment Variables

All have defaults suitable for local development:

| Variable | Default |
|---|---|
| `DATABASE_URL` | `postgresql://postgres:postgres@localhost:5432/attendance` |
| `JWT_SECRET` | `dev-secret-change-in-production` |
| `JWT_EXPIRES_IN` | `24h` |
| `MQTT_PORT` | `1883` |
| `HTTP_PORT` | `3000` |
| `HEALTH_RETENTION_DAYS` | `7` |
| `CONNECTION_RETENTION_DAYS` | `30` |
| `NODE_ENV` | `development` |

### Architecture

The server is a single Bun process (`src/index.ts`) that starts four services:
1. **PostgreSQL** via Drizzle ORM (`src/database/`)
2. **Aedes MQTT broker** (`src/mqtt/broker.ts`) on port 1883 — receives messages from lighthouses
3. **Hono HTTP API** (`src/api/routes/`) on port 3000 — REST endpoints under `/api/v1/`
4. **WebSocket** at `/ws` — pushes real-time events to the frontend dashboard

**MQTT message flow:** Lighthouses publish to `attendance/lighthouse/{MAC}/[scans|status|health|config/{key}]`. The broker routes each topic to a handler in `src/mqtt/handlers/`. Scan messages insert into `raw_scans`; health/status messages update `lighthouse_health_snapshots` and `lighthouse_connection_events`. Real-time events are broadcast to all connected WebSocket clients.

**Device lifecycle:** Any device that connects via MQTT is tracked in in-memory state (`src/mqtt/state.ts`) keyed by MAC address. Devices not yet in the `lighthouses` DB table appear as "pending devices" in the dashboard. Claiming a device creates a `lighthouses` row and marks it registered in the runtime state.

**Frontend:** SolidJS SPA (`src/web/`). In production it is served as static files from `dist/web/` by the Hono catch-all. In development, run `bun run dev:web` (Vite on port 5173) while the backend runs on port 3000. Stores under `src/web/stores/` are plain SolidJS signals. `websocket.ts` reconnects automatically every 3 seconds on disconnect.

**Database schema key tables:**
- `lighthouses` — registered devices, identified by `device_id` (MAC address)
- `lighthouse_groups` — logical groupings of lighthouses (e.g. entrance pairs)
- `raw_scans` — every RFID scan event received from a lighthouse
- `processed_events` — attendance entry/exit events derived from raw scans
- `users` / `tag_assignments` — personnel linked to RFID tag EPCs
- `dashboard_users` — login credentials for the web dashboard

**Auth:** `POST /api/v1/auth/login` returns a JWT. All protected routes require `Authorization: Bearer <token>`. Passwords are hashed with `Bun.password` (bcrypt).

**Drizzle config:** Schema is in `src/database/schema.ts`; migrations output to `drizzle/`; column names use `snake_case` (Drizzle `casing: "snake_case"` option).

---

## Lighthouse Firmware (`src/lighthouse/`)

### Commands

Requires ESP-IDF toolchain (`idf.py`) to be sourced.

```bash
# Build
idf.py build

# Flash to connected device
idf.py flash

# Open serial monitor
idf.py monitor

# Flash and monitor in one step
idf.py flash monitor
```

### Architecture

The firmware (`main/lighthouse.c`) initialises subsystems in sequence:

1. **`io_controller`** — GPIO setup (LEDs, buttons, IR sensor, RFID power rail)
2. **`battery_monitor`** — ADC-based voltage reading; triggers deep sleep at ≤3.2 V
3. **`wifi_provisioning`** / **`wifi_manager`** — WiFi connection; AP provisioning mode triggered by holding BUTTON2 for 5 seconds
4. **`time_sync`** — SNTP using the MQTT broker's IP as the NTP server
5. **`my_mqtt_client`** — Connects to broker, publishes scans/health/status, subscribes to `config/#`
6. **`offline_event_logger`** — Stores scan events to flash (LittleFS) when MQTT is unavailable; replays on reconnect
7. **`rfid_reader`** — UART driver for the R300/Y300 UHF RFID module; fires `on_tag_detected` callback

**Scan modes (toggled by holding BUTTON1 for 3 s):**
- *IR mode* (default): an IR sensor drives RFID power on/off automatically
- *Manual mode*: BUTTON1 short-press toggles scanning

**Offline resilience:** Every tag event is first stored to flash, then optionally published to MQTT if connected. On MQTT reconnect the pending events are relayed to the server with `source: "offline_sync"` and `time_basis` set to `synced`, `estimated`, or `relative`.

**Config updates:** The server can push config changes to a lighthouse via retained MQTT messages on `attendance/lighthouse/{MAC}/config/{key}`. Supported keys: `rfid/power` (20–33 dBm), `rfid/beeper` (0–2), `rfid/frequency` ("FCC"/"EU"/"CN").
