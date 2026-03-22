# Processed Events Page — Agent Task Document

> **Project root:** `src/server/`
> **Frontend framework:** SolidJS with `@solidjs/router`
> **Styling:** CSS Modules (`.module.css`)
> **API client:** `src/web/api/client.ts` (exports `get`, `post`, `patch`, `del`)
> **State pattern:** SolidJS `createStore` + exported functions (see `src/web/stores/users.ts` for pattern)
> **Existing pages for reference:** `src/web/pages/Events.tsx` (raw scans table), `src/web/pages/Users.tsx`
> **No external charting libraries.** Histograms must be pure CSS/SVG.

---

## TASK 1: Backend — Event Detail Endpoint

### Create or extend `src/server/src/api/routes/events.ts`

Add a new endpoint. If the events router was created during Phase 2, add to it. If it doesn't exist yet, create it and mount it.

**`GET /api/v1/events/:id`**

Returns a single processed event with full detail including all linked raw scans grouped by lighthouse.

**Query logic:**

1. Fetch the `processed_events` row by `id` (UUID).
2. Join to get group label from `lighthouse_groups`.
3. Join to get user info (name, syncId) from `users` if `userId` is not null.
4. Fetch all linked raw scans via `processed_event_scans` junction → `raw_scans`. For each scan, join `lighthouses` to get `lighthouse.name` and `lighthouse.placement`.
5. Group the scans into `insideScans[]` and `outsideScans[]` based on `lighthouse.placement`.

**Response body:**

```json
{
  "event": {
    "id": "uuid",
    "algorithmId": "temporal_centroid",
    "direction": "in",
    "tagEpc": "E280...",
    "userId": "uuid or null",
    "userName": "John Doe or null",
    "userSyncId": "EMP001 or null",
    "groupId": 1,
    "groupLabel": "Main Entrance",
    "confidence": 0.82,
    "centroidSeparationFactor": 0.91,
    "clusterSizeFactor": 0.88,
    "bilateralCoverageFactor": 0.95,
    "rssiTrendConsistencyFactor": null,
    "timestamp": "ISO8601",
    "clusterStartedAt": "ISO8601",
    "clusterEndedAt": "ISO8601",
    "metadata": { ... },
    "syncedToIntegration": false,
    "createdAt": "ISO8601"
  },
  "scans": {
    "inside": {
      "lighthouseId": 2,
      "lighthouseName": "Main Entrance Inside",
      "scans": [
        {
          "id": "bigint as string",
          "epc": "E280...",
          "rssiDbm": -65,
          "timestamp": "ISO8601",
          "timestampMs": "bigint as string",
          "antennaId": 0,
          "frequency": 47,
          "source": "realtime",
          "timeBasis": "synced"
        }
      ]
    },
    "outside": {
      "lighthouseId": 1,
      "lighthouseName": "Main Entrance Outside",
      "scans": [
        { ... }
      ]
    }
  }
}
```

Return 404 if event not found.

**Also fetch the companion event.** Since each traversal produces two events (one per algorithm), include the companion event's ID and confidence so the frontend can offer a quick link/comparison:

Add to the response:

```json
{
  "event": { ... },
  "scans": { ... },
  "companionEvent": {
    "id": "uuid",
    "algorithmId": "rssi_weighted_centroid",
    "direction": "in",
    "confidence": 0.78
  }
}
```

To find the companion: query `processed_events` where `tagEpc` matches, `groupId` matches, `clusterStartedAt` matches, `algorithmId` differs, and `id` differs. Should return exactly one row.

**Acceptance criteria:**
- Returns full event detail with scans grouped by lighthouse placement.
- Scans are ordered by `timestamp ASC` within each group.
- Returns 404 for unknown event ID.
- Companion event is included when it exists.

---

## TASK 2: Backend — List Endpoint Enhancements

### Modify `GET /api/v1/events` in `src/server/src/api/routes/events.ts`

The list endpoint needs to return enough data for the table view. Ensure the response includes per-lighthouse scan counts (not just total `scanCount`). Modify the query to compute:

- `insideScanCount`: count of linked scans from the INSIDE lighthouse
- `outsideScanCount`: count of linked scans from the OUTSIDE lighthouse

This requires joining through `processed_event_scans` → `raw_scans` → `lighthouses` and grouping. If this is too expensive for the list query, an alternative is to store these counts on the `processed_events` row at processing time (would require a small schema addition). Use whichever approach is more practical.

Additionally, ensure the list endpoint also returns:
- `userName` (joined from `users.name` where `userId` matches)
- `userSyncId` (joined from `users.syncId`)
- `groupLabel` (joined from `lighthouse_groups.label`)

**Updated list response item:**

```json
{
  "id": "uuid",
  "algorithmId": "temporal_centroid",
  "direction": "in",
  "tagEpc": "E280...",
  "userId": "uuid or null",
  "userName": "John Doe or null",
  "userSyncId": "EMP001 or null",
  "groupId": 1,
  "groupLabel": "Main Entrance",
  "confidence": 0.82,
  "centroidSeparationFactor": 0.91,
  "clusterSizeFactor": 0.88,
  "bilateralCoverageFactor": 0.95,
  "rssiTrendConsistencyFactor": null,
  "timestamp": "ISO8601",
  "clusterStartedAt": "ISO8601",
  "clusterEndedAt": "ISO8601",
  "insideScanCount": 6,
  "outsideScanCount": 8,
  "createdAt": "ISO8601"
}
```

**Acceptance criteria:**
- List response includes per-lighthouse scan counts.
- List response includes resolved user name/syncId and group label.

---

## TASK 3: Frontend — Types

### Add to `src/server/src/web/types.ts`

```typescript
// Processed events
export interface ProcessedEvent {
  id: string;
  algorithmId: "temporal_centroid" | "rssi_weighted_centroid" | "manual";
  direction: "in" | "out" | "unknown";
  tagEpc: string;
  userId: string | null;
  userName: string | null;
  userSyncId: string | null;
  groupId: number;
  groupLabel: string;
  confidence: number;
  centroidSeparationFactor: number;
  clusterSizeFactor: number;
  bilateralCoverageFactor: number;
  rssiTrendConsistencyFactor: number | null;
  timestamp: string;
  clusterStartedAt: string;
  clusterEndedAt: string;
  insideScanCount: number;
  outsideScanCount: number;
  createdAt: string;
}

export interface ProcessedEventScan {
  id: string;
  epc: string;
  rssiDbm: number | null;
  timestamp: string;
  timestampMs: string;
  antennaId: number | null;
  frequency: number | null;
  source: "realtime" | "offline_sync";
  timeBasis: "synced" | "estimated" | "relative";
}

export interface LighthouseScans {
  lighthouseId: number;
  lighthouseName: string;
  scans: ProcessedEventScan[];
}

export interface CompanionEvent {
  id: string;
  algorithmId: string;
  direction: string;
  confidence: number;
}

export interface ProcessedEventDetail {
  event: ProcessedEvent & {
    metadata: Record<string, unknown>;
    syncedToIntegration: boolean;
  };
  scans: {
    inside: LighthouseScans;
    outside: LighthouseScans;
  };
  companionEvent: CompanionEvent | null;
}

export interface ProcessedEventsFilter {
  algorithmId: string;
  groupId?: number;
  userId?: string;
  tagEpc?: string;
  direction?: "in" | "out" | "unknown";
  from?: string;
  to?: string;
  minConfidence?: number;
  limit?: number;
  offset?: number;
}
```

**Acceptance criteria:**
- Types compile without errors.
- Types match the backend response shapes from Tasks 1 and 2.

---

## TASK 4: Frontend — API Functions

### Add to `src/server/src/web/api/index.ts`

```typescript
// Processed events
export function getProcessedEvents(
  filters: ProcessedEventsFilter,
): Promise<PaginatedResponse<ProcessedEvent>> {
  const params = new URLSearchParams();
  params.set("algorithmId", filters.algorithmId);
  if (filters.groupId !== undefined) params.set("groupId", String(filters.groupId));
  if (filters.userId) params.set("userId", filters.userId);
  if (filters.tagEpc) params.set("tagEpc", filters.tagEpc);
  if (filters.direction) params.set("direction", filters.direction);
  if (filters.from) params.set("from", filters.from);
  if (filters.to) params.set("to", filters.to);
  if (filters.minConfidence !== undefined) params.set("minConfidence", String(filters.minConfidence));
  if (filters.limit !== undefined) params.set("limit", String(filters.limit));
  if (filters.offset !== undefined) params.set("offset", String(filters.offset));
  return get<PaginatedResponse<ProcessedEvent>>(`/events?${params.toString()}`);
}

export function getProcessedEventDetail(id: string): Promise<ProcessedEventDetail> {
  return get<ProcessedEventDetail>(`/events/${id}`);
}
```

Import the new types at the top of the file.

**Acceptance criteria:**
- Both functions are callable and return typed responses.

---

## TASK 5: Frontend — Store

### Create `src/server/src/web/stores/processedEvents.ts`

Follow the pattern from `src/web/stores/users.ts`.

```typescript
import { createStore } from "solid-js/store";
import * as api from "../api";
import type { ProcessedEvent, ProcessedEventDetail, ProcessedEventsFilter } from "../types";
import { showToast } from "./toast";

interface ProcessedEventsState {
  events: ProcessedEvent[];
  total: number;
  loading: boolean;
  error: string | null;
  filters: ProcessedEventsFilter;
  // Detail modal
  selectedEventDetail: ProcessedEventDetail | null;
  detailLoading: boolean;
}

const [state, setState] = createStore<ProcessedEventsState>({
  events: [],
  total: 0,
  loading: false,
  error: null,
  filters: {
    algorithmId: "temporal_centroid",
    limit: 50,
    offset: 0,
  },
  selectedEventDetail: null,
  detailLoading: false,
});

export async function fetchEvents(filters?: Partial<ProcessedEventsFilter>) {
  if (filters) {
    setState("filters", (prev) => ({ ...prev, ...filters }));
  }
  setState({ loading: true, error: null });
  try {
    const res = await api.getProcessedEvents(state.filters);
    setState({ events: res.data, total: res.total, loading: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to fetch events";
    setState({ error: message, loading: false });
    showToast(message, "error");
  }
}

export async function fetchEventDetail(id: string) {
  setState({ detailLoading: true, selectedEventDetail: null });
  try {
    const detail = await api.getProcessedEventDetail(id);
    setState({ selectedEventDetail: detail, detailLoading: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to fetch event detail";
    setState({ detailLoading: false });
    showToast(message, "error");
  }
}

export function clearEventDetail() {
  setState({ selectedEventDetail: null });
}

export function updateFilters(filters: Partial<ProcessedEventsFilter>) {
  setState("filters", (prev) => ({ ...prev, ...filters, offset: 0 }));
  fetchEvents();
}

export { state as processedEventsState };
```

**Acceptance criteria:**
- Store manages list and detail state.
- Filter updates reset offset to 0 and re-fetch.

---

## TASK 6: Frontend — Processed Events Page

### Create `src/server/src/web/pages/ProcessedEvents.tsx` and `ProcessedEvents.module.css`

**Page layout — top to bottom:**

1. **Filter bar** — horizontal row of controls:
   - **Algorithm selector**: three buttons/tabs — "Temporal Centroid", "RSSI Weighted", "Both". "Both" shows rows from both algorithms side by side (may show duplicate traversals). Default: "Temporal Centroid".
   - **User/tag filter**: text input that searches by user name, syncId, or tag EPC (partial match). Debounced (300ms).
   - **Direction filter**: dropdown — "All", "In", "Out", "Unknown".
   - **Group filter**: dropdown populated from `GET /api/v1/groups`. "All groups" default.
   - **Date range**: two date inputs (from/to). Optional.

2. **Results table** — columns:
   - **Direction**: arrow icon or text ("→ In" / "← Out" / "? Unknown")
   - **Tag / User**: show user name if resolved, otherwise last 5 chars of EPC in monospace. Show full EPC as tooltip.
   - **Group**: group label
   - **Confidence**: percentage (e.g., "82%"). Color-coded: green ≥ 0.7, yellow 0.4–0.7, red < 0.4.
   - **Algorithm**: short label ("Temporal" / "RSSI" / "Manual")
   - **Inside scans**: count
   - **Outside scans**: count
   - **Time**: formatted `timestamp` (relative if recent, absolute if older)
   - **Duration**: `clusterEndedAt - clusterStartedAt` formatted as "Xs" or "X.Xs"

   Rows are clickable — clicking opens the detail modal.

3. **Pagination** — same pattern as existing Events page.

### Register the route

**Modify `src/server/src/web/index.tsx`:**

```typescript
import { ProcessedEvents } from "./pages/ProcessedEvents";

// Add route:
<Route path="/processed" component={ProcessedEvents} />
```

**Modify `src/server/src/web/App.tsx`:**

Add nav link:

```tsx
<A href="/processed" class={styles.navLink} activeClass={styles.active}>
  Processed Events
</A>
```

**Acceptance criteria:**
- Page loads at `/processed`.
- Filter controls work and trigger re-fetch.
- Table displays processed events with all columns.
- Clicking a row triggers detail fetch and opens modal.
- Pagination works.

---

## TASK 7: Frontend — Event Detail Modal

### Create `src/server/src/web/components/EventDetailModal.tsx` and `EventDetailModal.module.css`

Modal overlay that opens when a table row is clicked. Closes on backdrop click, Escape key, or close button.

**Modal structure — tabs/sections:**

The modal should have a tab bar with three tabs. Use SolidJS signals for active tab state.

### Tab 1: "Overview"

Formatted summary of the event. Layout as a two-column key-value grid:

| Left column | Right column |
|---|---|
| Direction | "→ Entry" or "← Exit" (large, colored) |
| Tag EPC | Full EPC in monospace |
| User | Name + syncId, or "Unassigned" |
| Group | Group label |
| Algorithm | Full name |
| Timestamp | Formatted canonical timestamp |
| Cluster span | "clusterStartedAt → clusterEndedAt (Xs duration)" |
| Confidence | Large percentage + color indicator |

Below the grid, show confidence factor breakdown as a horizontal bar chart (pure CSS):

```
Centroid separation  ████████████████░░░░  0.91
Cluster size         █████████████████░░░  0.88
Bilateral coverage   ██████████████████░░  0.95
RSSI trend           (not applicable)
```

Each bar is a `<div>` with `width: ${factor * 100}%` and a colored background. Show "N/A" for null factors.

If a companion event exists, show a small card: "Also analyzed by [algorithm name] → confidence X%" with a clickable link that loads the companion event into the same modal.

### Tab 2: "Raw Scans"

Two sub-sections: "Inside Lighthouse (name)" and "Outside Lighthouse (name)".

Each section is a table:

| Timestamp | RSSI (dBm) | Antenna | Frequency | Source |
|---|---|---|---|---|
| Relative to cluster start (e.g., "+0ms", "+340ms") | -65 | 0 | 47 | realtime |

Order by timestamp ASC.

Show total count per lighthouse as section header: "Inside — Main Entrance Inside (6 scans)".

### Tab 3: "Timeline"

This is the visualization tab. It contains histogram(s) built with pure SVG.

**For `temporal_centroid` events:**

Single combined histogram. X-axis is time (relative to `clusterStartedAt`, in ms). Y-axis is scan count per time bin.

Implementation:
- Bin all scans into time buckets (bin width = cluster duration / 15, minimum 50ms per bin).
- For each bin, count inside scans and outside scans separately.
- Render as a grouped bar chart or stacked bar chart with two colors:
  - Outside lighthouse: one color (e.g., blue)
  - Inside lighthouse: another color (e.g., orange)
- Draw vertical dashed lines at each lighthouse's centroid position (from `metadata.outsideCentroidMs` and `metadata.insideCentroidMs`). Label them.
- Show a legend: color → lighthouse name.

**For `rssi_weighted_centroid` events:**

Two charts stacked vertically:

1. **Scan timing histogram** — same as above, but also show the RSSI-weighted centroid positions (from metadata) as additional vertical lines, visually distinct from the unweighted ones.

2. **RSSI over time scatter plot** — X-axis is time (same scale as histogram above). Y-axis is RSSI (dBm). Plot each scan as a dot, colored by lighthouse. Draw the linear regression trend lines (slope and intercept from `metadata.rssiTrend.inside` and `metadata.rssiTrend.outside`).

**SVG implementation notes:**

- Use a fixed SVG viewBox (e.g., `0 0 700 300` per chart).
- Compute scales: map time domain `[0, clusterDuration]` to x range `[padding, width - padding]`. Map RSSI domain `[minRssi - 5, maxRssi + 5]` to y range.
- Bars: `<rect>` elements positioned per bin.
- Dots: `<circle>` elements for scatter plot.
- Lines: `<line>` for centroids and regression trends.
- Labels: `<text>` elements for axis labels, centroid markers.
- Colors: use CSS custom properties from the existing `variables.css` if available, otherwise define two lighthouse colors as constants.
- The charts must be responsive — use `width="100%" viewBox="..."` on the SVG.

**For `manual` events:**

Show a simple message: "Manual event — no scan data to visualize."

**Acceptance criteria:**
- Modal opens with event detail.
- Three tabs work and display correct content.
- Overview tab shows all event fields and confidence factor bars.
- Raw Scans tab shows scans grouped by lighthouse with relative timestamps.
- Timeline tab renders SVG histogram for temporal_centroid events.
- Timeline tab renders histogram + RSSI scatter for rssi_weighted_centroid events.
- Centroid lines are drawn at correct positions.
- RSSI trend regression lines are drawn for Algorithm 2.
- Companion event link works (loads different event into same modal).
- Modal closes on backdrop click and Escape key.

---

## TASK 8: Frontend — WebSocket Integration

### Modify `src/server/src/web/stores/websocket.ts`

Add handler for `event:new` WebSocket messages. When received, if the processed events page is active and the event matches current filters, prepend it to the events list (or show a "new events available" indicator).

This is low priority — the page works fine with manual refresh. Implement as a simple "New events detected — click to refresh" banner at the top of the table when new `event:new` WebSocket messages arrive that match the current algorithm filter.

**Acceptance criteria:**
- Banner appears when new events arrive via WebSocket.
- Clicking the banner refreshes the table.

---

## FILE SUMMARY

### New backend files:
- None (endpoint added to existing `events.ts` route file)

### Modified backend files:
- `src/server/src/api/routes/events.ts` — add `GET /api/v1/events/:id`, enhance list response

### New frontend files:
- `src/web/pages/ProcessedEvents.tsx`
- `src/web/pages/ProcessedEvents.module.css`
- `src/web/components/EventDetailModal.tsx`
- `src/web/components/EventDetailModal.module.css`
- `src/web/stores/processedEvents.ts`

### Modified frontend files:
- `src/web/types.ts` — add processed event types
- `src/web/api/index.ts` — add API functions
- `src/web/index.tsx` — add route
- `src/web/App.tsx` — add nav link
- `src/web/stores/websocket.ts` — add `event:new` handler

---

## EXECUTION ORDER

```
TASK 1  → Backend detail endpoint (no frontend dependencies)
TASK 2  → Backend list enhancements (no frontend dependencies)
TASK 3  → Frontend types (depends on Tasks 1, 2 response shapes)
TASK 4  → Frontend API functions (depends on Task 3)
TASK 5  → Frontend store (depends on Task 4)
TASK 6  → Page + table + filters + routing (depends on Task 5)
TASK 7  → Detail modal with all three tabs (depends on Tasks 5, 6)
TASK 8  → WebSocket integration (depends on Task 6)
```

Tasks 1 and 2 can run in parallel.
Tasks 3 and 4 are quick and can be done together.
Task 7 is the largest task — the SVG histogram implementation.

---

## CONSTRAINTS

- **No external charting libraries.** All histograms and scatter plots are pure SVG rendered inline in SolidJS components.
- **Follow existing patterns.** CSS modules, store pattern, API client pattern — match what exists in the codebase.
- **Scans in timeline must use relative timestamps.** X-axis shows milliseconds from cluster start, not absolute time.
- **Centroid lines must use values from `metadata`.** Do not recompute centroids client-side — the metadata contains the exact values the algorithm used.
- **Modal must handle both algorithms.** Tab 3 content differs based on `algorithmId`. Check and render accordingly.
- **Companion event navigation must not cause full page reload.** Replace the modal content by fetching the new event detail.
- **Confidence factor bars must have consistent scale** — all bars go from 0 to 1.0 (100% width), so factors are visually comparable.
