# Lighthouse Dashboard — Implementation Task

**Project:** Attendance System Thesis  
**Component:** Web Dashboard PoC  
**Stack:** SolidJS + CSS Modules, Bun + Hono, PostgreSQL + Drizzle

---

## Objective

Build a minimal proof-of-concept web dashboard to:
- View registered lighthouse devices with live connection status
- Claim pending (unregistered) devices that appear on the network
- Create lighthouse groups (pairs for direction detection)
- View raw RFID scan events with basic filtering

The dashboard is served from the existing Bun server process. No authentication is required for this PoC.

---

## 1. Database Changes

All migrations should be created using Drizzle Kit (`bunx drizzle-kit generate`).

### 1.1 New Enum: `scan_source`

Create a PostgreSQL enum to track whether a scan event arrived in real-time or was synced from device offline storage.

**Values:** `realtime`, `offline_sync`

**Drizzle definition:**
```
scanSource = pgEnum('scan_source', ['realtime', 'offline_sync'])
```

### 1.2 New Table: `lighthouse_groups`

Stores logical pairings of two lighthouses at a single passage point (e.g., doorway with inside + outside sensors).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `serial` | `PRIMARY KEY` | |
| `label` | `varchar(255)` | `NOT NULL` | User-defined name, e.g., "Main Entrance" |
| `description` | `varchar(500)` | nullable | Optional notes |
| `created_at` | `timestamptz` | `DEFAULT NOW()` | |
| `updated_at` | `timestamptz` | `DEFAULT NOW()` | |

**Index:** `idx_lighthouse_groups_label` on `label`

### 1.3 Alter Table: `lighthouses`

Add a foreign key linking a lighthouse to its group.

| Column | Type | Constraints |
|--------|------|-------------|
| `group_id` | `integer` | `REFERENCES lighthouse_groups(id) ON DELETE SET NULL` |

**Index:** `idx_lighthouses_group_id` on `group_id`

**Constraint:** A group may have at most 2 members. This is enforced at the application layer, not database level.

### 1.4 Alter Table: `raw_scans`

Add source tracking for offline-synced events.

| Column | Type | Constraints |
|--------|------|-------------|
| `source` | `scan_source` | `NOT NULL DEFAULT 'realtime'` |

### 1.5 Migration Verification

After running the migration, verify:
- `SELECT * FROM pg_type WHERE typname = 'scan_source';` returns the enum
- `\d lighthouse_groups` shows the new table
- `\d lighthouses` shows `group_id` column with FK constraint
- `\d raw_scans` shows `source` column with enum type

---

## 2. Backend Changes

### 2.1 Update MQTT Scan Handler

**File:** `src/server/src/mqtt/handlers/scan.ts`

When processing incoming scan messages, set the `source` field based on whether the event is backfilled:

- If the scan message includes a `backfill: true` flag or similar indicator from the firmware → set `source: 'offline_sync'`
- Otherwise → set `source: 'realtime'`

Coordinate with the firmware's MQTT message format to determine how backfilled events are identified.

### 2.2 Update Pending Device Handling

**Current behavior:** Unknown devices are auto-inserted into the database (temporary test code).

**New behavior:** 
- Track them only in the existing runtime state map
- They remain "pending" until explicitly claimed via API

### 2.3 New API Endpoints

Add these routes to the existing Hono app. No authentication middleware required.

#### `GET /api/v1/devices/pending`

Returns devices tracked in runtime memory that are not in the database.

**Response:**
```json
{
  "data": [
    {
      "deviceId": "AA:BB:CC:DD:EE:FF",
      "isConnected": true,
      "firstSeenAt": "2025-01-30T10:00:00Z",
      "lastHealthAt": "2025-01-30T10:05:00Z",
      "health": {
        "uptimeSec": 3600,
        "freeHeapBytes": 180000,
        "wifiRssiDbm": -55,
        "rfidState": "IDLE",
        "rfidIsResponsive": true
      }
    }
  ],
  "count": 1
}
```

#### `POST /api/v1/devices/pending/:deviceId/claim`

Moves a pending device into the database as a registered lighthouse.

**Request:**
```json
{
  "name": "Front Door Inside",
  "label": "Front Door - Inside Sensor",
  "placement": "INSIDE",
  "groupId": 1
}
```

- `name` — required, must be unique
- `label` — optional, display label
- `placement` — required, one of `STANDALONE`, `INSIDE`, `OUTSIDE`
- `groupId` — optional, must reference existing group with <2 members

**Response:** `201 Created` with the created lighthouse record.

**Errors:**
- `404` if deviceId not found in pending devices
- `400` if name already exists or group already has 2 members
- `400` if required fields missing

#### `GET /api/v1/groups`

List all groups with their member lighthouses.

**Response:**
```json
{
  "data": [
    {
      "id": 1,
      "label": "Main Entrance",
      "description": "Building A front door",
      "members": [
        { "id": 1, "name": "Front Inside", "deviceId": "AA:...", "placement": "INSIDE" },
        { "id": 2, "name": "Front Outside", "deviceId": "BB:...", "placement": "OUTSIDE" }
      ],
      "createdAt": "2025-01-30T10:00:00Z",
      "updatedAt": "2025-01-30T10:00:00Z"
    }
  ],
  "count": 1
}
```

#### `POST /api/v1/groups`

Create a new group.

**Request:**
```json
{
  "label": "Main Entrance",
  "description": "Building A front door"
}
```

**Response:** `201 Created` with the created group (members array will be empty).

#### `GET /api/v1/groups/:id`

Get a single group by ID with its members.

**Response:** Same structure as single item in list response.

**Errors:** `404` if not found.

#### `PATCH /api/v1/groups/:id`

Update group label or description.

**Request:**
```json
{
  "label": "New Label",
  "description": "Updated description"
}
```

**Response:** Updated group object.

#### `DELETE /api/v1/groups/:id`

Delete a group. Member lighthouses have their `group_id` set to `NULL`.

**Response:** `204 No Content`

#### `GET /api/v1/lighthouses` (Modify Existing)

Augment the existing response to include:
- Runtime connection status from in-memory state
- Group information if assigned

**Response per lighthouse:**
```json
{
  "id": 1,
  "name": "Front Door Inside",
  "deviceId": "AA:BB:CC:DD:EE:FF",
  "label": "Front Door - Inside Sensor",
  "placement": "INSIDE",
  "firmwareVersion": "1.0.0",
  "isActive": true,
  "createdAt": "...",
  "group": {
    "id": 1,
    "label": "Main Entrance"
  },
  "runtime": {
    "isConnected": true,
    "lastHealthAt": "2025-01-30T10:05:00Z",
    "health": {
      "uptimeSec": 3600,
      "freeHeapBytes": 180000,
      "wifiRssiDbm": -55,
      "rfidState": "IDLE",
      "rfidIsResponsive": true
    }
  }
}
```

If device is not in runtime state, `runtime` should be `null`.

#### `PATCH /api/v1/lighthouses/:id` (Modify Existing)

Add support for `groupId` field to assign/unassign from groups.

**Request:**
```json
{
  "groupId": 1
}
```

To remove from group: `{ "groupId": null }`

**Validation:** If groupId is provided and not null, verify the target group has fewer than 2 members.

#### `GET /api/v1/scans`

Query raw scan events with filtering and pagination.

**Query Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `lighthouseId` | integer | — | Filter by lighthouse ID |
| `epc` | string | — | Filter by tag EPC (partial match, case-insensitive) |
| `source` | string | — | Filter by `realtime` or `offline_sync` |
| `from` | ISO datetime | — | Start of time range (inclusive) |
| `to` | ISO datetime | — | End of time range (inclusive) |
| `limit` | integer | 50 | Max results (cap at 500) |
| `offset` | integer | 0 | Pagination offset |

**Response:**
```json
{
  "data": [
    {
      "id": "12345",
      "lighthouseId": 1,
      "lighthouseName": "Front Door Inside",
      "epc": "E200001234567890",
      "rssiDbm": -45,
      "timestamp": "2025-01-30T10:05:00Z",
      "source": "realtime",
      "receivedAt": "2025-01-30T10:05:00.123Z"
    }
  ],
  "total": 1500,
  "limit": 50,
  "offset": 0
}
```

Results ordered by `timestamp` descending (newest first).

### 2.4 WebSocket Endpoint

Create a WebSocket endpoint for real-time updates to the dashboard.

**Endpoint:** `GET /ws` (upgrades to WebSocket)

No authentication required. Multiple clients may connect simultaneously.

#### Server → Client Messages

All messages are JSON with this structure:
```json
{
  "type": "<message_type>",
  "payload": { ... },
  "timestamp": "2025-01-30T10:05:00Z"
}
```

**Message Types:**

| Type | Trigger | Payload |
|------|---------|---------|
| `scan` | New scan event stored | `{ id, lighthouseId, lighthouseName, epc, rssiDbm, timestamp, source }` |
| `device:online` | Device connects | `{ deviceId, lighthouseId }` (lighthouseId null if pending) |
| `device:offline` | Device disconnects | `{ deviceId, lighthouseId, isGraceful }` |
| `device:health` | Health update received | `{ deviceId, lighthouseId, health: {...} }` |
| `device:pending` | New unregistered device seen | `{ deviceId }` |

**Implementation notes:**
- Maintain a Set of connected WebSocket clients
- In MQTT handlers, after processing messages, broadcast to all WS clients
- Handle client disconnection gracefully (remove from Set)

---

### 2.5 Tests

All new or modified api endpoints should have their functionality fully covered by tests that need to be altered or newly created.

## 3. Frontend Implementation

### 3.1 Project Setup

Create the frontend inside the existing server project:

```
src/server/
  src/
    web/                    # New frontend directory
      index.html
      index.tsx
      ...
  vite.config.ts            # New Vite config
```

**Dependencies to add:**
```
bun add solid-js @solidjs/router
bun add -d vite vite-plugin-solid
```

**Vite config** should:
- Use `vite-plugin-solid`
- Output build to `dist/web/`
- Proxy `/api` and `/ws` to the backend during development (if running separately)

### 3.2 Static File Serving

Add a catch-all route to Hono to serve the built frontend:

- Serve files from `dist/web/` for non-API routes
- Return `index.html` for any path that doesn't match a static file (SPA fallback)

During development, either use Vite's dev server with proxy, or integrate Vite middleware into Hono.

### 3.3 Folder Structure

Keep it flat and simple for PoC:

```
src/web/
  index.html
  index.tsx               # Mount App
  App.tsx                 # Router setup
  styles/
    variables.css         # CSS custom properties
    global.css            # Reset, base styles
  pages/
    Lighthouses.tsx       # Main page: registered + pending devices
    Lighthouses.module.css
    Groups.tsx            # Group management
    Groups.module.css
    Events.tsx            # Scan events viewer
    Events.module.css
  components/
    LighthouseCard.tsx
    LighthouseCard.module.css
    PendingDeviceCard.tsx
    GroupCard.tsx
    GroupCard.module.css
    ClaimModal.tsx        # Modal for claiming pending device
    GroupModal.tsx        # Modal for create/edit group
    EventsTable.tsx
    Toast.tsx             # Simple toast notifications
  stores/
    lighthouses.ts        # Registered + pending + runtime state
    groups.ts
    events.ts
    websocket.ts          # WS connection, dispatches to other stores
  api/
    client.ts             # Fetch wrapper
    index.ts              # All API functions
  types.ts                # Shared interfaces
```

### 3.4 Routing

Three pages, simple top navigation:

| Path | Page | Description |
|------|------|-------------|
| `/` | Lighthouses | Default landing page |
| `/groups` | Groups | Group management |
| `/events` | Events | Scan event log |

Use `@solidjs/router` with a simple `<A>` nav component.

### 3.5 Pages Specification

#### Lighthouses Page (`/`)

**Layout:**
- Navigation bar at top (links to all 3 pages)
- Two sections stacked vertically:
  1. "Pending Devices" — only shown if there are pending devices
  2. "Registered Lighthouses"

**Pending Devices Section:**
- Header: "Pending Devices" with count badge
- Grid/list of `PendingDeviceCard` components
- Each card shows:
  - Device ID (MAC address)
  - Connection status indicator (green dot if connected)
  - "Claim" button → opens `ClaimModal`

**Registered Lighthouses Section:**
- Header: "Lighthouses" with count
- Grid/list of `LighthouseCard` components
- Each card shows:
  - Name (label if set, else name)
  - Device ID
  - Connection status indicator
  - Group badge (if assigned)
  - Placement badge (INSIDE/OUTSIDE/STANDALONE)
  - Click to expand: health metrics (uptime, heap, RSSI, RFID state)

**ClaimModal:**
- Form fields:
  - Name (required, text input)
  - Label (optional, text input)
  - Placement (required, select: STANDALONE/INSIDE/OUTSIDE)
  - Group (optional, select from existing groups that have <2 members)
- Submit button: "Claim Device"
- On success: close modal, refresh lighthouse list, show toast
- On error: show error message in modal

#### Groups Page (`/groups`)

**Layout:**
- Navigation bar
- Header: "Lighthouse Groups" with "Create Group" button
- List of `GroupCard` components

**GroupCard:**
- Group label
- Description (if set)
- Member lighthouses (show name and placement for each, max 2)
- "Edit" button → opens `GroupModal` in edit mode
- "Delete" button → deletes group (no confirmation needed for PoC)

**GroupModal:**
- Form fields:
  - Label (required)
  - Description (optional)
- For edit mode: show current values
- Submit: "Create" or "Save"

**Note:** Assigning lighthouses to groups is done from the Lighthouses page via the claim modal or by editing a lighthouse. The Groups page just manages group metadata.

#### Events Page (`/events`)

**Layout:**
- Navigation bar
- Filters row:
  - Lighthouse dropdown (optional filter)
  - EPC text input (partial search)
  - Source toggle: All / Realtime / Offline Sync
- Events table
- Pagination controls (Previous / Next, or Load More)

**EventsTable:**
- Columns: Time, Lighthouse, EPC, RSSI, Source
- Time: formatted as `HH:MM:SS` with date on hover/title
- Source: show "Offline" badge for `offline_sync`, nothing for realtime
- Newest events at top
- New events from WebSocket appear at top with brief highlight animation

### 3.6 Stores

Use SolidJS `createStore` for state management.

#### `lighthouses.ts`
```
State:
  - registered: Lighthouse[]
  - pending: PendingDevice[]
  - loading: boolean

Actions:
  - fetchAll() — GET /api/v1/lighthouses + GET /api/v1/devices/pending
  - claimDevice(deviceId, data) — POST /api/v1/devices/pending/:id/claim
  - updateLighthouse(id, data) — PATCH /api/v1/lighthouses/:id
  - handleWsMessage(msg) — update runtime status from WS events
```

#### `groups.ts`
```
State:
  - groups: Group[]
  - loading: boolean

Actions:
  - fetchAll() — GET /api/v1/groups
  - create(data) — POST /api/v1/groups
  - update(id, data) — PATCH /api/v1/groups/:id
  - remove(id) — DELETE /api/v1/groups/:id
```

#### `events.ts`
```
State:
  - events: Scan[]
  - filters: { lighthouseId?, epc?, source? }
  - pagination: { limit, offset, total }
  - loading: boolean

Actions:
  - fetch() — GET /api/v1/scans with current filters
  - setFilter(key, value) — update filter, reset offset, refetch
  - nextPage() / prevPage()
  - prependEvent(event) — add new event from WS to top of list
```

#### `websocket.ts`
```
State:
  - connected: boolean

Actions:
  - connect() — open WS to /ws
  - disconnect()

On message:
  - Parse JSON
  - Switch on type:
    - scan → events store prependEvent
    - device:online/offline/health → lighthouses store handleWsMessage
    - device:pending → lighthouses store refresh pending
```

### 3.7 Toast Notifications

Simple toast component for:
- "Device claimed successfully"
- "Group created"
- "Device went offline: {name}"
- "New device detected"

Show in bottom-right corner, auto-dismiss after 4 seconds.

---

## 4. Development Workflow

### Option A: Integrated Dev Server (Recommended)

Use Vite middleware in Hono for development:
- Single `bun run dev` command
- Vite handles HMR for frontend
- API routes work directly

### Option B: Separate Processes

- Terminal 1: `bun run dev:server` (API on :3000)
- Terminal 2: `bun run dev:web` (Vite on :5173, proxy API/WS to :3000)

### Production Build

1. `bun run build:web` — Vite builds to `dist/web/`
2. `bun run start` — Hono serves API + static files

---

## 5. Verification Checklist

### Database
- [ ] Migration runs without errors
- [ ] `scan_source` enum exists with correct values
- [ ] `lighthouse_groups` table created
- [ ] `lighthouses.group_id` FK works (can assign, SET NULL on delete)
- [ ] `raw_scans.source` defaults to `realtime`

### API
- [ ] `GET /api/v1/devices/pending` returns in-memory pending devices
- [ ] `POST /api/v1/devices/pending/:id/claim` creates lighthouse, removes from pending
- [ ] Claiming with invalid group (≥2 members) returns 400
- [ ] `GET /api/v1/groups` includes member lighthouses
- [ ] `POST /api/v1/groups` creates group
- [ ] `DELETE /api/v1/groups/:id` sets member `group_id` to NULL
- [ ] `GET /api/v1/lighthouses` includes runtime status and group info
- [ ] `PATCH /api/v1/lighthouses/:id` can set/unset groupId
- [ ] `GET /api/v1/scans` filtering works (lighthouse, epc partial, source, date range)
- [ ] `GET /api/v1/scans` pagination works

### WebSocket
- [ ] Client can connect to `/ws`
- [ ] `scan` messages broadcast on new scan
- [ ] `device:online`/`device:offline` broadcast on status change
- [ ] `device:pending` broadcast when new unknown device connects

### Frontend
- [ ] App loads at `/`
- [ ] Navigation between pages works
- [ ] Pending devices shown and can be claimed
- [ ] Registered lighthouses show with status indicators
- [ ] Groups can be created, edited, deleted
- [ ] Events table shows scans with filtering
- [ ] WebSocket updates appear in real-time
- [ ] Toast notifications appear for key events

---

*Document Version: 1.0*
