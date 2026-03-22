# Phase 2: Event Processing & Direction Detection — Agent Task Document

> **Project root:** `src/server/`
> **Runtime:** Bun + TypeScript
> **ORM:** Drizzle ORM with PostgreSQL
> **DB can be wiped:** Yes — no production data. Destructive migrations are acceptable.
> **Test runner:** `bun:test`

---

## TASK 1: Schema Migration

### 1.1 Add enums to `src/server/src/database/schema.ts`

Add these three new pgEnum definitions alongside the existing enums (`lighthousePlacement`, `userType`, `scanSource`, `timeBasis`):

```typescript
export const directionType = pgEnum("direction_type", ["in", "out", "unknown"]);

export const algorithmType = pgEnum("algorithm_type", [
  "temporal_centroid",
  "rssi_weighted_centroid",
  "manual",
]);

export const orphanReasonType = pgEnum("orphan_reason_type", [
  "insufficient_data",
  "misconfigured_group",
  "unsyncable",
]);
```

### 1.2 Modify `lighthouseGroups` table in `src/server/src/database/schema.ts`

Add two columns:

```typescript
activityTimeoutMs: integer().notNull().default(4000),
orphanTimeoutMs: integer().notNull().default(8000),
```

### 1.3 Modify `rawScans` table in `src/server/src/database/schema.ts`

Remove:
- `processed: boolean().default(false)`

Add:
- `processedAt: timestamp({ withTimezone: true })`
- `orphanedAt: timestamp({ withTimezone: true })`
- `orphanReason: orphanReasonType()`

Replace index array. Remove `idx_raw_scans_processed`. Add:

```typescript
index("idx_raw_scans_epc_timestamp").on(table.epc, table.timestamp),
index("idx_raw_scans_lighthouse_timestamp").on(table.lighthouseId, table.timestamp),
index("idx_raw_scans_unprocessed")
  .on(table.epc, table.timestamp)
  .where(sql`processed_at IS NULL AND orphaned_at IS NULL`),
index("idx_raw_scans_orphaned")
  .on(table.orphanedAt)
  .where(sql`orphaned_at IS NOT NULL`),
```

### 1.4 Replace `processedEvents` table in `src/server/src/database/schema.ts`

Drop the existing `processedEvents` definition. Replace with:

```typescript
export const processedEvents = pgTable(
  "processed_events",
  {
    id: uuid().primaryKey().defaultRandom(),
    algorithmId: algorithmType().notNull(),
    direction: directionType().notNull(),
    tagEpc: varchar({ length: 96 }).notNull(),
    userId: uuid(),
    groupId: integer()
      .notNull()
      .references(() => lighthouseGroups.id),
    confidence: real().notNull(),
    centroidSeparationFactor: real().notNull(),
    clusterSizeFactor: real().notNull(),
    bilateralCoverageFactor: real().notNull(),
    rssiTrendConsistencyFactor: real(),
    timestamp: timestamp({ withTimezone: true }).notNull(),
    clusterStartedAt: timestamp({ withTimezone: true }).notNull(),
    clusterEndedAt: timestamp({ withTimezone: true }).notNull(),
    metadata: jsonb(),
    syncedToIntegration: boolean().default(false),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_processed_events_tag_timestamp").on(table.tagEpc, table.timestamp),
    index("idx_processed_events_user_timestamp").on(table.userId, table.timestamp),
    index("idx_processed_events_timestamp").on(table.timestamp),
    index("idx_processed_events_synced").on(table.syncedToIntegration),
    index("idx_processed_events_algorithm").on(table.algorithmId, table.timestamp),
    index("idx_processed_events_group").on(table.groupId, table.timestamp),
  ],
);
```

### 1.5 Add `processedEventScans` junction table in `src/server/src/database/schema.ts`

```typescript
export const processedEventScans = pgTable(
  "processed_event_scans",
  {
    processedEventId: uuid()
      .notNull()
      .references(() => processedEvents.id, { onDelete: "cascade" }),
    rawScanId: bigserial({ mode: "bigint" })
      .notNull()
      .references(() => rawScans.id),
  },
  (table) => [
    // Composite primary key
    index("pk_processed_event_scans").on(table.processedEventId, table.rawScanId),
    index("idx_processed_event_scans_raw_scan").on(table.rawScanId),
  ],
);
```

Note: Drizzle may require `primaryKey({ columns: [table.processedEventId, table.rawScanId] })` syntax instead of an index for the composite PK. Check Drizzle docs for `pgTable` composite key syntax and use the correct approach.

### 1.6 Generate and apply migration

```bash
cd src/server
bunx drizzle-kit generate
bunx drizzle-kit push
```

Since the DB can be wiped, if the migration is complex, drop all tables and re-push:

```bash
bunx drizzle-kit push --force
```

### 1.7 Fix all references to removed `processed` column

Search for `processed` across the codebase. Files that reference it:

- `src/server/src/mqtt/handlers/scan.ts` — remove `processed: false` from the insert `.values()` call.
- `src/server/tests/` — any test asserting on `processed` field. Update or remove.
- `src/server/src/database/schema.ts` — already handled above.

**Acceptance criteria:**
- `bunx drizzle-kit push` succeeds without errors.
- All existing tests pass (update any that reference the removed `processed` column).
- The new tables and columns exist in the database.

---

## TASK 2: Tag Resolver

### Create `src/server/src/services/tag-resolver.ts`

Single exported function. Looks up active tag assignment for an EPC and returns the userId if found.

```typescript
import { getDatabase, schema } from "../database/client";
import { and, eq, isNull } from "drizzle-orm";

/**
 * Resolve an EPC to a userId via active tag assignments.
 * Returns the userId if the tag is actively assigned, null otherwise.
 */
export async function resolveTagUser(epc: string): Promise<string | null> {
  const db = getDatabase();

  const assignments = await db
    .select({ userId: schema.tagAssignments.userId })
    .from(schema.tagAssignments)
    .where(
      and(
        eq(schema.tagAssignments.tagEpc, epc),
        isNull(schema.tagAssignments.deactivatedAt),
      ),
    )
    .limit(1);

  return assignments[0]?.userId ?? null;
}
```

**Acceptance criteria:**
- Returns a userId string for an EPC with an active assignment.
- Returns null for an EPC with no active assignment.
- Returns null for an EPC whose assignment has been deactivated.

---

## TASK 3: Algorithm Types

### Create `src/server/src/services/algorithms/types.ts`

Shared interfaces used by both algorithm implementations and the processor.

```typescript
export interface ScanData {
  id: bigint;
  lighthouseId: number;
  epc: string;
  rssiDbm: number | null;
  timestamp: Date;
  timeBasis: "synced" | "estimated" | "relative";
}

export interface PartitionedCluster {
  epc: string;
  groupId: number;
  insideScans: ScanData[];
  outsideScans: ScanData[];
  allScans: ScanData[];
  clusterStartedAt: Date;
  clusterEndedAt: Date;
}

export type Direction = "in" | "out" | "unknown";

export interface AlgorithmResult {
  algorithmId: "temporal_centroid" | "rssi_weighted_centroid";
  direction: Direction;
  confidence: number;
  centroidSeparationFactor: number;
  clusterSizeFactor: number;
  bilateralCoverageFactor: number;
  rssiTrendConsistencyFactor: number | null;
  timestamp: Date;           // canonical event timestamp (entry-side centroid)
  metadata: Record<string, unknown>;
}

/**
 * Minimum value for any confidence factor.
 * Prevents any single factor from zeroing out the product.
 * TUNABLE — adjust after collecting real traversal data.
 */
export const CONFIDENCE_FACTOR_FLOOR = 0.1;
```

**Acceptance criteria:**
- File compiles without errors.
- Types are importable from other service files.

---

## TASK 4: Algorithm 1 — Temporal Centroid

### Create `src/server/src/services/algorithms/temporal-centroid.ts`

Pure function. Takes a `PartitionedCluster`, returns an `AlgorithmResult`. No DB access, no side effects.

**Algorithm logic:**

1. Compute `outsideCentroid = mean(outsideScans[].timestamp)` (arithmetic mean of Unix ms values).
2. Compute `insideCentroid = mean(insideScans[].timestamp)`.
3. Direction:
   - `outsideCentroid < insideCentroid` → `"in"`
   - `insideCentroid < outsideCentroid` → `"out"`
   - Within 1ms → `"unknown"`
4. Canonical timestamp:
   - `"in"` → `outsideCentroid`
   - `"out"` → `insideCentroid`
   - `"unknown"` → midpoint

**Confidence factors** (all clamped to `[CONFIDENCE_FACTOR_FLOOR, 1.0]`):

1. `centroidSeparationFactor`:
   - `centroidDelta = abs(outsideCentroid - insideCentroid)` ms
   - `clusterDuration = clusterEndedAt - clusterStartedAt` ms
   - If `clusterDuration == 0` → `CONFIDENCE_FACTOR_FLOOR`
   - Else → `max(CONFIDENCE_FACTOR_FLOOR, centroidDelta / clusterDuration)`

2. `clusterSizeFactor`:
   - `totalScans = insideScans.length + outsideScans.length`
   - `rawFactor = min(1.0, (totalScans - 2) / 8)`
   - `max(CONFIDENCE_FACTOR_FLOOR, rawFactor)`

3. `bilateralCoverageFactor`:
   - `ratio = min(insideCount, outsideCount) / max(insideCount, outsideCount)`
   - `max(CONFIDENCE_FACTOR_FLOOR, ratio)`

4. `rssiTrendConsistencyFactor` → `null` (not used by this algorithm).

5. `confidence = centroidSeparationFactor × clusterSizeFactor × bilateralCoverageFactor`

**Metadata:**

```json
{
  "outsideCentroidMs": <number>,
  "insideCentroidMs": <number>,
  "centroidDeltaMs": <number>,
  "clusterDurationMs": <number>,
  "outsideScanCount": <number>,
  "insideScanCount": <number>
}
```

**Exported function signature:**

```typescript
export function analyzeTemporalCentroid(cluster: PartitionedCluster): AlgorithmResult
```

**Acceptance criteria:**
- Given a cluster where outside scans are earlier → returns `direction: "in"`.
- Given a cluster where inside scans are earlier → returns `direction: "out"`.
- Confidence increases with larger centroid separation, more scans, and balanced bilateral coverage.
- All factors are ≥ `CONFIDENCE_FACTOR_FLOOR`.
- `rssiTrendConsistencyFactor` is `null`.

---

## TASK 5: Algorithm 2 — RSSI-Weighted Centroid + Trend

### Create `src/server/src/services/algorithms/rssi-weighted-centroid.ts`

Pure function. Same interface as Algorithm 1.

**Differences from Algorithm 1:**

1. **RSSI-weighted centroids.** Each scan's weight:
   - If `rssiDbm` is null → `weight = 1.0`
   - Else → `weight = clamp(1.0 - ((abs(rssiDbm) - 40) / 50), 0.1, 1.0)`
   - Maps: -40 dBm → 1.0, -90 dBm → 0.1
   - Centroid = `sum(timestamp_ms * weight) / sum(weight)` per lighthouse

2. **RSSI trend analysis.** For each lighthouse's scan set (≥ 3 scans):
   - Simple linear regression: x = timestamp (cluster-relative ms), y = rssiDbm
   - Output: `slope` (dBm/s), `r2` (coefficient of determination)
   - Expected for entry (`"in"`): outside slope < 0 (weakening), inside slope > 0 (strengthening)
   - Expected for exit (`"out"`): inside slope < 0, outside slope > 0

3. **rssiTrendConsistencyFactor:**
   - Both slopes agree with expected direction → `1.0`
   - One agrees, one inconclusive (R² < 0.1) → `0.7`
   - One contradicts → `0.4`
   - Both contradict → `CONFIDENCE_FACTOR_FLOOR`
   - Either lighthouse < 3 scans → `0.5` (neutral)
   - Clamped to `[CONFIDENCE_FACTOR_FLOOR, 1.0]`

4. **Confidence:**
   `confidence = centroidSeparationFactor × clusterSizeFactor × bilateralCoverageFactor × rssiTrendConsistencyFactor`

**Metadata:**

```json
{
  "outsideCentroidMs": <number>,
  "insideCentroidMs": <number>,
  "centroidDeltaMs": <number>,
  "clusterDurationMs": <number>,
  "outsideScanCount": <number>,
  "insideScanCount": <number>,
  "rssiWeights": {
    "outside": [<number>, ...],
    "inside": [<number>, ...]
  },
  "rssiTrend": {
    "outside": { "slope": <number>, "r2": <number> },
    "inside": { "slope": <number>, "r2": <number> }
  }
}
```

**Exported function signature:**

```typescript
export function analyzeRssiWeightedCentroid(cluster: PartitionedCluster): AlgorithmResult
```

**Implementation note:** Linear regression can be implemented inline — no external library needed. Standard least-squares formula for slope and R².

**Acceptance criteria:**
- Produces different centroid positions than Algorithm 1 when RSSI values vary across scans.
- `rssiTrendConsistencyFactor` is non-null and reflects RSSI trend agreement.
- Degrades gracefully to Algorithm 1 behavior when all `rssiDbm` values are null (all weights = 1.0, trend factor = 0.5).
- All factors are ≥ `CONFIDENCE_FACTOR_FLOOR`.

---

## TASK 6: Event Processor

### Create `src/server/src/services/event-processor.ts`

Orchestration module. Called by the sweeper with a closed cluster's raw scans. Validates prerequisites, runs both algorithms, writes results to DB.

**Exported function:**

```typescript
export async function processCluster(
  scans: ScanData[],
  groupId: number,
  epc: string,
): Promise<{ processed: boolean; reason?: string }>
```

**Logic:**

1. **Validate group config.** Query `lighthouses` WHERE `groupId = groupId`. Must find exactly one with `placement = 'INSIDE'` and exactly one with `placement = 'OUTSIDE'`. If not → return `{ processed: false, reason: 'misconfigured_group' }`.

2. **Filter synced scans.** Remove any scan with `timeBasis !== 'synced'`. If no scans remain → return `{ processed: false, reason: 'unsyncable' }`.

3. **Partition by lighthouse.** Split into `insideScans[]` and `outsideScans[]` using each scan's `lighthouseId` matched against the resolved INSIDE/OUTSIDE lighthouse IDs.

4. **Validate bilateral coverage.** If either `insideScans` or `outsideScans` is empty → return `{ processed: false, reason: 'insufficient_data' }`.

5. **Build `PartitionedCluster` object.** Compute `clusterStartedAt` (min timestamp), `clusterEndedAt` (max timestamp).

6. **Resolve user.** Call `resolveTagUser(epc)` from Task 2.

7. **Run Algorithm 1.** Call `analyzeTemporalCentroid(cluster)`.

8. **Run Algorithm 2.** Call `analyzeRssiWeightedCentroid(cluster)`.

9. **Write results.** In a single transaction:
   - Insert two rows into `processed_events` (one per algorithm result), setting `userId`, `groupId`, `tagEpc`, and all factor/confidence/metadata/timestamp fields.
   - Insert junction rows into `processed_event_scans` linking both event IDs to all scan IDs in the cluster.
   - UPDATE all scans in the cluster: set `processedAt = now()`.

10. **Broadcast WebSocket events.** After commit, call broadcast functions for both algorithm results (see Task 11).

11. Return `{ processed: true }`.

**Important:** All DB writes in step 9 must be in a single transaction. If any part fails, roll back entirely.

**Acceptance criteria:**
- Returns correct reason strings for each failure mode.
- Creates exactly 2 `processed_events` rows per successful cluster.
- Junction table links all scans to both events.
- All scans marked `processedAt` after success.
- Transaction rolls back on partial failure.

---

## TASK 7: Event Sweeper (Background Poller)

### Create `src/server/src/services/event-sweeper.ts`

Background poller that runs on a fixed interval. No in-memory state.

**Constants:**

```typescript
const POLLER_INTERVAL_MS = 2000;
const MAX_CLUSTERS_PER_CYCLE = 50;
```

**Exported functions:**

```typescript
export function startEventSweeper(): void    // starts the interval
export function stopEventSweeper(): void     // clears the interval, waits for in-progress cycle
```

**Each polling cycle (`sweep()`):**

1. **Find closed clusters.** Single query:

```sql
SELECT rs.epc, l.group_id, lg.activity_timeout_ms, lg.orphan_timeout_ms,
       MAX(rs.timestamp) as latest_scan, COUNT(*) as scan_count
FROM raw_scans rs
JOIN lighthouses l ON rs.lighthouse_id = l.id
JOIN lighthouse_groups lg ON l.group_id = lg.id
WHERE rs.processed_at IS NULL
  AND rs.orphaned_at IS NULL
GROUP BY rs.epc, l.group_id, lg.activity_timeout_ms, lg.orphan_timeout_ms
HAVING MAX(rs.timestamp) < NOW() - (lg.activity_timeout_ms || ' milliseconds')::interval
LIMIT $MAX_CLUSTERS_PER_CYCLE
```

Translate to Drizzle ORM equivalent. This is the core query — get it right.

2. **Handle ungrouped scans.** Separately, find scans where the lighthouse has `groupId IS NULL`, `processedAt IS NULL`, `orphanedAt IS NULL`, and the scan is older than a fixed timeout (e.g., 10 seconds). Orphan with reason `misconfigured_group`.

3. **For each closed cluster**, fetch all constituent scans:

```sql
SELECT * FROM raw_scans
WHERE epc = $epc
  AND lighthouse_id IN (SELECT id FROM lighthouses WHERE group_id = $groupId)
  AND processed_at IS NULL
  AND orphaned_at IS NULL
ORDER BY timestamp ASC
```

4. **Call `processCluster()`.** Handle the result:
   - `{ processed: true }` → done, scans are marked in the processor.
   - `{ processed: false, reason: 'misconfigured_group' }` → UPDATE scans: `orphanedAt = now(), orphanReason = 'misconfigured_group'`. Broadcast `event:orphaned` for each.
   - `{ processed: false, reason: 'unsyncable' }` → UPDATE only the non-synced scans: `orphanedAt = now(), orphanReason = 'unsyncable'`. Leave synced scans alone (they may pair with future scans — but in practice this shouldn't happen since the cluster is closed).
   - `{ processed: false, reason: 'insufficient_data' }` → Check if `now() - latestScan > orphanTimeoutMs`. If yes → orphan all scans with reason `insufficient_data`. If no → skip this cluster, try next cycle.

5. **Log** each cycle: number of clusters found, processed, orphaned, skipped.

**Graceful shutdown:**

`stopEventSweeper()` should:
- Clear the `setInterval` handle.
- Set a `shuttingDown` flag.
- If a sweep cycle is in progress, wait for it to complete (use a promise/flag).

**Acceptance criteria:**
- Poller runs every 2 seconds when started.
- Correctly identifies closed clusters (activity timeout expired).
- Passes clusters to the processor.
- Handles all processor return reasons correctly.
- Orphans scans with correct reasons.
- Stops cleanly on shutdown without interrupting in-progress work.

---

## TASK 8: Wire Sweeper into Server Lifecycle

### Modify `src/server/src/index.ts`

**In the `startup()` function**, after `startRetentionScheduler()`:

```typescript
import { startEventSweeper, stopEventSweeper } from "./services/event-sweeper";

// ... in startup():
startEventSweeper();
logger.info("Event sweeper started");
```

**In `gracefulShutdown()`**, before `closeMqttBroker()`:

```typescript
// Stop event sweeper
stopEventSweeper();
```

### Modify `src/server/src/mqtt/handlers/scan.ts`

Remove the `queueScanForProcessing()` function entirely. Remove the call to it in `handleScanMessage()`. Remove the `// TODO: Task 2.2` comment block.

The scan handler now only: validates → stores → broadcasts WebSocket scan event.

**Acceptance criteria:**
- Server starts with sweeper running.
- Server shuts down cleanly with sweeper stopped.
- `scan.ts` no longer references `queueScanForProcessing`.

---

## TASK 9: Group API Updates

### Modify `src/server/src/api/routes/groups.ts`

**`POST /api/v1/groups`** — accept optional `activityTimeoutMs` and `orphanTimeoutMs` in the request body. Pass to insert if provided; defaults apply in the schema if omitted.

**`PATCH /api/v1/groups/:id`** — accept `activityTimeoutMs` and `orphanTimeoutMs` in the update body.

**`PATCH /api/v1/groups/:id`** — additionally, when the response succeeds AND the update involved `groupId` membership changes or lighthouse placement changes, trigger re-processing:

```typescript
// After successful update, re-enable orphaned scans for this group
await db
  .update(schema.rawScans)
  .set({ orphanedAt: null, orphanReason: null })
  .where(
    and(
      inArray(
        schema.rawScans.lighthouseId,
        db.select({ id: schema.lighthouses.id })
          .from(schema.lighthouses)
          .where(eq(schema.lighthouses.groupId, groupId))
      ),
      eq(schema.rawScans.orphanReason, "misconfigured_group"),
      isNull(schema.rawScans.processedAt),
    ),
  );
```

Note: also trigger this logic from `PATCH /api/v1/lighthouses/:id` and `PATCH /api/v1/lighthouses/:id/update` when `groupId` or `placement` changes.

**`GET /api/v1/groups`** and **`GET /api/v1/groups/:id`** — include `activityTimeoutMs` and `orphanTimeoutMs` in the response.

**Acceptance criteria:**
- Can create groups with custom timeout values.
- Can update timeout values on existing groups.
- Changing lighthouse placement or group membership clears `misconfigured_group` orphans.
- Timeout values appear in GET responses.

---

## TASK 10: Events API

### Create `src/server/src/api/routes/events.ts`

New router. Mount in the app alongside existing routes.

**`GET /api/v1/events`**

Required query parameter: `algorithmId` (reject with 400 if missing).

Optional query parameters: `groupId`, `userId`, `tagEpc`, `direction`, `from` (ISO 8601), `to` (ISO 8601), `minConfidence` (float), `limit` (default 50, max 500), `offset` (default 0).

Query `processed_events` with filters. Join to get scan count from `processed_event_scans` (use a subquery or `COUNT`). Return results ordered by `timestamp DESC`.

Response body:

```json
{
  "data": [
    {
      "id": "uuid",
      "algorithmId": "temporal_centroid",
      "direction": "in",
      "tagEpc": "E280...",
      "userId": "uuid or null",
      "groupId": 1,
      "confidence": 0.82,
      "centroidSeparationFactor": 0.91,
      "clusterSizeFactor": 0.88,
      "bilateralCoverageFactor": 0.95,
      "rssiTrendConsistencyFactor": null,
      "timestamp": "ISO8601",
      "clusterStartedAt": "ISO8601",
      "clusterEndedAt": "ISO8601",
      "scanCount": 14,
      "createdAt": "ISO8601"
    }
  ],
  "count": 1,
  "limit": 50,
  "offset": 0
}
```

**`GET /api/v1/events/unresolved`**

Optional query parameters: `groupId`, `orphanReason`, `tagEpc`, `from`, `to`, `limit`, `offset`.

Query `raw_scans` WHERE `orphanedAt IS NOT NULL AND processedAt IS NULL`. Join `lighthouses` for lighthouse info. Call `resolveTagUser` for each unique EPC in the result set.

Response body:

```json
{
  "data": [
    {
      "scanId": "bigint as string",
      "epc": "E280...",
      "lighthouseId": 1,
      "lighthouseName": "Front Door Outside",
      "rssiDbm": -65,
      "timestamp": "ISO8601",
      "orphanedAt": "ISO8601",
      "orphanReason": "insufficient_data",
      "userId": "uuid or null"
    }
  ],
  "count": 1,
  "limit": 50,
  "offset": 0
}
```

**`POST /api/v1/events/manual`**

Request body:

```json
{
  "tagEpc": "E280...",
  "direction": "in",
  "timestamp": "ISO8601",
  "groupId": 1,
  "notes": "optional string"
}
```

Validate: `tagEpc` required, `direction` must be `"in"` | `"out"`, `timestamp` required valid ISO, `groupId` must exist.

Insert into `processed_events`:
- `algorithmId`: `"manual"`
- `direction`: from body
- `confidence`: `1.0`
- `centroidSeparationFactor`: `1.0`
- `clusterSizeFactor`: `1.0`
- `bilateralCoverageFactor`: `1.0`
- `rssiTrendConsistencyFactor`: `null`
- `timestamp`, `clusterStartedAt`, `clusterEndedAt`: all set to the provided timestamp
- `metadata`: `{ "notes": body.notes }` or `{}` if no notes
- `userId`: resolved via `resolveTagUser(tagEpc)`

No junction table rows (no linked raw scans).

Return 201 with the created event.

### Mount the router

In `src/server/src/api/routes.ts` (or wherever routes are mounted), add:

```typescript
import eventsRouter from "./routes/events";
app.route("/api/v1", eventsRouter);
```

**Acceptance criteria:**
- `GET /api/v1/events` returns 400 without `algorithmId`.
- Filtering by all supported parameters works.
- `GET /api/v1/events/unresolved` returns orphaned scans with reasons.
- `POST /api/v1/events/manual` creates a valid manual event with all factors = 1.0.

---

## TASK 11: WebSocket Event Broadcasting

### Modify `src/server/src/api/websocket.ts`

Add to `WebSocketMessageType`:

```typescript
export type WebSocketMessageType =
  | "scan"
  | "device:online"
  | "device:offline"
  | "device:health"
  | "device:pending"
  | "event:new"        // ADD
  | "event:orphaned";  // ADD
```

Add payload types:

```typescript
export interface TraversalEventPayload {
  id: string;
  algorithmId: string;
  direction: string;
  tagEpc: string;
  userId: string | null;
  groupId: number;
  confidence: number;
  timestamp: string;
  clusterStartedAt: string;
  clusterEndedAt: string;
  scanCount: number;
}

export interface OrphanedScanPayload {
  scanId: string;
  epc: string;
  lighthouseId: number;
  timestamp: string;
  orphanReason: string;
}
```

Add broadcast functions:

```typescript
export function broadcastTraversalEvent(data: TraversalEventPayload): void {
  broadcast("event:new", data);
}

export function broadcastOrphanedScan(data: OrphanedScanPayload): void {
  broadcast("event:orphaned", data);
}
```

Call `broadcastTraversalEvent` from `event-processor.ts` (Task 6) after writing each algorithm result.
Call `broadcastOrphanedScan` from `event-sweeper.ts` (Task 7) when orphaning scans.

**Acceptance criteria:**
- WebSocket clients receive `event:new` messages when traversals are detected.
- WebSocket clients receive `event:orphaned` messages when scans are orphaned.
- Two `event:new` messages are emitted per traversal (one per algorithm).

---

## TASK 12: Tests

### Create `src/server/tests/event-processing.test.ts`

Test framework: `bun:test`. Follow existing test patterns in `tests/mqtt-broker.test.ts` and `tests/time-basis.test.ts`.

**Setup:**
- `beforeAll`: `initDatabase()`, insert test lighthouses (one INSIDE, one OUTSIDE) in a test group with known `activityTimeoutMs` and `orphanTimeoutMs`. Start MQTT broker if needed.
- `afterAll`: clean up test data, close DB.
- `beforeEach`: clean `raw_scans`, `processed_events`, `processed_event_scans` for test lighthouse IDs.

**Test cases:**

1. **Basic entry detection.** Insert 10 raw scans: 5 from OUTSIDE lighthouse (timestamps 1000-3000ms range), 5 from INSIDE (timestamps 3000-5000ms range). All `timeBasis: 'synced'`. Call `processCluster()` directly. Assert: both algorithm results have `direction: "in"`, confidence > 0, all factors populated. Junction table has 20 rows (10 scans × 2 events).

2. **Basic exit detection.** Same as above but INSIDE timestamps are earlier. Assert `direction: "out"`.

3. **Misconfigured group.** Insert scans for a group with two INSIDE lighthouses (no OUTSIDE). Assert `processCluster` returns `{ processed: false, reason: 'misconfigured_group' }`.

4. **Single lighthouse cluster.** Insert scans from only the OUTSIDE lighthouse. Assert returns `{ processed: false, reason: 'insufficient_data' }`.

5. **Unsyncable scans.** Insert scans with `timeBasis: 'estimated'`. Assert returns `{ processed: false, reason: 'unsyncable' }`.

6. **Algorithm comparison.** Insert a cluster where RSSI values strongly support the temporal direction. Assert Algorithm 2's confidence ≥ Algorithm 1's confidence (trend agreement should boost it).

7. **RSSI degradation.** Insert a cluster where RSSI values contradict the temporal direction. Assert Algorithm 2's confidence < Algorithm 1's confidence.

8. **Manual event creation.** POST to `/api/v1/events/manual`. Assert response 201, all factors = 1.0, `algorithmId: "manual"`.

9. **Events API filtering.** Create multiple events, query with `algorithmId` filter. Assert only matching algorithm's results returned.

10. **Unresolved events API.** Orphan some scans, query `GET /api/v1/events/unresolved`. Assert correct results with orphan reasons.

**Acceptance criteria:**
- All 10 tests pass.
- No interference with existing test suites.

---

## EXECUTION ORDER

Execute tasks in this exact order. Each task depends on prior tasks being complete.

```
TASK 1  → Schema migration (everything else depends on this)
TASK 2  → Tag resolver (no dependencies beyond Task 1)
TASK 3  → Algorithm types (no dependencies beyond Task 1)
TASK 4  → Algorithm 1 (depends on Task 3)
TASK 5  → Algorithm 2 (depends on Task 3)
TASK 6  → Event processor (depends on Tasks 2, 4, 5)
TASK 7  → Event sweeper (depends on Task 6)
TASK 8  → Wire into server lifecycle (depends on Task 7)
TASK 9  → Group API updates (depends on Task 1)
TASK 10 → Events API (depends on Tasks 1, 2)
TASK 11 → WebSocket events (depends on Tasks 6, 7)
TASK 12 → Tests (depends on all above)
```

Tasks 2, 3, 9 can run in parallel after Task 1.
Tasks 4 and 5 can run in parallel after Task 3.
Task 10 can start after Task 1 (doesn't need algorithms).

---

## CONSTRAINTS

- **No in-memory processing state.** The sweeper is purely DB-driven.
- **Single transaction for cluster processing.** All writes in `processCluster()` must be atomic.
- **Both algorithms run on every cluster.** Never skip one.
- **Never process scans with `timeBasis !== 'synced'`.** Orphan them instead.
- **`algorithmId` is required on `GET /api/v1/events`.** No default algorithm.
- **`CONFIDENCE_FACTOR_FLOOR` is a named constant.** Do not inline magic numbers.
- **Do not modify firmware code.** This is server-only work.
- **Preserve all existing functionality.** Scan ingestion, WebSocket scan broadcasts, health monitoring, device management, user/tag management — all must continue working.
