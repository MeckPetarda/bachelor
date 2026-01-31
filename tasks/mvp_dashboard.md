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
