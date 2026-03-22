# Phase 2: Event Processing & Direction Detection — Implementation Plan

## Decision Log

All design decisions made during planning. These are binding for implementation.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Algorithm strategy | Dual-algorithm from the start | Thesis requirement: empirical comparison of temporal centroid vs RSSI-weighted centroid |
| Processing model | Cluster-based (not scan-pair) | Physical reality: a traversal produces 5-15+ scans per lighthouse, not one scan per side |
| Traversal segmentation | Gap-based activity timeout | Cluster closes when no new scans arrive for the EPC within the timeout window |
| Activity timeout default | 4000ms per group (configurable) | Fits observed 3-5 second real-world walk-through patterns |
| Orphan timeout default | 2× activity timeout (8000ms) | Grace period for late-arriving partner scans after cluster closes |
| Processing architecture | DB-driven background poller (no in-memory state) | Inherently crash-safe, simpler to implement and reason about |
| Poller interval | 2000ms | Acceptable latency for attendance system; adds 0-2s on top of the 4s activity timeout |
| Non-synced offline events | Store raw scans; skip direction detection for `estimated`/`relative` `timeBasis` | Timestamps are fabricated (`received_at`), making temporal analysis meaningless |
| Synced offline events | Process identically to realtime | `timeBasis: "synced"` preserves original detection time regardless of delivery path |
| Unresolved scans | Surface in dashboard with orphan reason | Admin observability; `misconfigured_group` orphans are re-processable when config is fixed |
| Group validation | Soft — API allows misconfiguration, processor skips invalid groups | Allows incremental setup (claim device, then assign placement later) |
| Confidence model | Multiplicative factors with configurable floor constant | Conservative: any bad factor tanks confidence; floor prevents true zero |
| Confidence factors storage | Dedicated columns (not JSONB) | Easy querying for thesis data analysis |
| Scan-to-event traceability | Junction table `processed_event_scans` | Clean bidirectional lookups; handles dual-algorithm (same scans → two events) |
| `eventType` field | Dropped — `direction` enum is sufficient | Table only stores traversals; no need for a separate event type dimension |
| Fixed-value varchars | Replaced with PostgreSQL enums | Type safety, smaller storage, self-documenting schema |
| Manual events | Factor columns set to 1.0, `algorithmId = 'manual'` | Keeps all factor columns NOT NULL; algorithm filter distinguishes manual from computed |
| Event API filtering | `algorithmId` required on every query, no default | Explicit; dashboard and Navigo3 integration each choose their algorithm |
| WebSocket broadcasts | Emit both algorithms' results per traversal | Dashboard decides what to show; enables live side-by-side comparison |
| Old `processed` column | Drop (clean DB, no data to preserve) | Clean break; forces all references to migrate to new columns |
| Re-processing | `misconfigured_group` orphans can be un-orphaned when group config is fixed | Clearing `orphanedAt`/`orphanReason` makes scans eligible for next poller cycle |

---

## Schema Changes

### New Enums

```
direction_type:       'in' | 'out' | 'unknown'
algorithm_type:       'temporal_centroid' | 'rssi_weighted_centroid' | 'manual'
orphan_reason_type:   'insufficient_data' | 'misconfigured_group' | 'unsyncable'
```

### 1. `lighthouse_groups` — add timing configuration

**File:** `src/server/src/database/schema.ts`

Add two columns to the existing `lighthouseGroups` table:

- `activityTimeoutMs`: `integer().notNull().default(4000)` — gap of silence (ms) before a scan cluster is considered closed for a given EPC.
- `orphanTimeoutMs`: `integer().notNull().default(8000)` — how long after cluster close to wait before orphaning single-lighthouse clusters.

### 2. `raw_scans` — replace `processed` boolean with explicit state columns

Remove:
- `processed` (boolean)

Add:
- `processedAt`: `timestamp({ withTimezone: true })` NULLABLE — set when the scan is successfully included in a processed traversal event.
- `orphanedAt`: `timestamp({ withTimezone: true })` NULLABLE — set when the scan is marked as unresolvable.
- `orphanReason`: `orphanReasonType()` NULLABLE — why the scan was orphaned.

**State semantics:**
- `processedAt IS NULL AND orphanedAt IS NULL` → unprocessed, eligible for poller pickup
- `processedAt IS NOT NULL` → successfully processed into a traversal event (terminal)
- `orphanedAt IS NOT NULL AND orphanReason = 'misconfigured_group'` → re-processable (clear both fields when group config is fixed)
- `orphanedAt IS NOT NULL AND orphanReason IN ('insufficient_data', 'unsyncable')` → terminal orphan

**Index changes:**
- Drop: `idx_raw_scans_processed`
- Add: `idx_raw_scans_unprocessed` — partial index on `(epc, timestamp) WHERE processed_at IS NULL AND orphaned_at IS NULL` — the poller's hot query path.
- Add: `idx_raw_scans_orphaned` — partial index on `(orphaned_at) WHERE orphaned_at IS NOT NULL` — for the unresolved events dashboard query.

### 3. `processed_events` — full restructure

Drop the existing table and recreate:

```
processed_events
├── id: uuid PK defaultRandom
├── algorithmId: algorithm_type NOT NULL
├── direction: direction_type NOT NULL
├── tagEpc: varchar(96) NOT NULL
├── userId: uuid NULLABLE
├── groupId: integer NOT NULL → lighthouse_groups(id)
├── confidence: real NOT NULL
├── centroidSeparationFactor: real NOT NULL
├── clusterSizeFactor: real NOT NULL
├── bilateralCoverageFactor: real NOT NULL
├── rssiTrendConsistencyFactor: real NULLABLE    — NULL only for temporal_centroid algorithm
├── timestamp: timestamptz NOT NULL              — entry-side centroid time
├── clusterStartedAt: timestamptz NOT NULL       — earliest scan in cluster
├── clusterEndedAt: timestamptz NOT NULL         — latest scan in cluster
├── metadata: jsonb                              — algorithm-specific debug data
├── syncedToIntegration: boolean DEFAULT false
├── createdAt: timestamptz DEFAULT now()
```

**Indexes:**
- `idx_processed_events_tag_timestamp` on `(tagEpc, timestamp)`
- `idx_processed_events_user_timestamp` on `(userId, timestamp)`
- `idx_processed_events_timestamp` on `(timestamp)`
- `idx_processed_events_synced` on `(syncedToIntegration)`
- `idx_processed_events_algorithm` on `(algorithmId, timestamp)`
- `idx_processed_events_group` on `(groupId, timestamp)`

### 4. `processed_event_scans` — new junction table

```
processed_event_scans
├── processedEventId: uuid NOT NULL → processed_events(id) ON DELETE CASCADE
├── rawScanId: bigint NOT NULL → raw_scans(id)
├── PRIMARY KEY (processedEventId, rawScanId)
```

**Index:**
- `idx_processed_event_scans_raw_scan` on `(rawScanId)` — for reverse lookup ("which events did this scan contribute to?")

---

## Algorithm Design

### Physical Model

A person walking through a doorway flanked by two lighthouse units (INSIDE and OUTSIDE) generates overlapping streams of UHF tag detections on both readers:

```
Time →
OUTSIDE:  ████████████░░░░░░░░░░    (strong early, fading)
INSIDE:   ░░░░░░░████████████████    (weak early, strengthening)
```

Both readers detect the tag multiple times (typically 5-15 scans each per traversal). The direction signal is in the temporal shift of detection density from one lighthouse to the other.

### Traversal Segmentation

Scans are grouped into traversal clusters by `(epc, groupId)`. A cluster is "open" while scans continue to arrive. A cluster is "closed" when no new scans for that `(epc, groupId)` pair arrive within the group's `activityTimeoutMs`.

The background poller detects closed clusters by checking: `now() - MAX(timestamp) > activityTimeoutMs` for each `(epc, groupId)` group of unprocessed scans.

### Shared Prerequisites (both algorithms)

Before either algorithm runs on a closed cluster, the processor must:

1. **Validate group configuration.** The group must contain exactly one lighthouse with `placement = 'INSIDE'` and one with `placement = 'OUTSIDE'`. If not → orphan all scans in the cluster with reason `misconfigured_group`.

2. **Check time basis.** All scans in the cluster must have `timeBasis = 'synced'`. Any scan with `estimated` or `relative` time basis is excluded from the cluster. If no synced scans remain → orphan with reason `unsyncable`.

3. **Validate bilateral coverage.** Both lighthouses must have contributed at least one scan to the cluster. If all scans come from a single lighthouse → orphan with reason `insufficient_data`.

4. **Partition scans by lighthouse.** Split the cluster into `insideScans[]` and `outsideScans[]` based on each scan's `lighthouseId` → `lighthouse.placement`.

5. **Resolve user.** Query `tag_assignments` for an active assignment matching the EPC. Set `userId` if found; leave NULL if unassigned. The event is still created either way.

If all prerequisites pass, run both algorithms on the same cluster and write two `processed_events` rows. Link all scans in the cluster to both rows via the junction table. Mark all scans with `processedAt = now()`.

### Algorithm 1: Temporal Centroid (`temporal_centroid`)

**Concept:** Compute the temporal center-of-mass of each lighthouse's scan set. Direction is determined by which centroid is earlier. All scans are weighted equally — RSSI is ignored entirely.

**Direction determination:**

- Compute `outsideCentroid = mean(outsideScans[].timestamp)`
- Compute `insideCentroid = mean(insideScans[].timestamp)`
- If `outsideCentroid < insideCentroid` → tag presence shifted from outside to inside → **direction = "in"** (entry)
- If `insideCentroid < outsideCentroid` → tag presence shifted from inside to outside → **direction = "out"** (exit)
- If centroids are within 1ms → **direction = "unknown"**

**Canonical timestamp:** The centroid of whichever lighthouse corresponds to the entry side:
- If direction is `"in"` → `timestamp = outsideCentroid` (person arrived at the outside boundary first)
- If direction is `"out"` → `timestamp = insideCentroid` (person arrived at the inside boundary first)
- If `"unknown"` → midpoint of both centroids

**Confidence factors:**

All factors return a value in `[CONFIDENCE_FACTOR_FLOOR, 1.0]`.

1. **Centroid separation factor** — how far apart are the two centroids relative to the cluster duration?
   - `centroidDelta = abs(outsideCentroid - insideCentroid)` in ms
   - `clusterDuration = clusterEndedAt - clusterStartedAt` in ms
   - If `clusterDuration == 0`: factor = `CONFIDENCE_FACTOR_FLOOR`
   - Otherwise: `rawFactor = centroidDelta / clusterDuration` (0.0 when centroids overlap, approaching 1.0 when centroids are at opposite ends of the cluster)
   - `centroidSeparationFactor = max(CONFIDENCE_FACTOR_FLOOR, rawFactor)`

2. **Cluster size factor** — how many total scans support this determination?
   - `totalScans = insideScans.length + outsideScans.length`
   - Scale: 2 scans (minimum) → floor. 10+ scans → 1.0. Linear interpolation between.
   - `rawFactor = min(1.0, (totalScans - 2) / 8)`
   - `clusterSizeFactor = max(CONFIDENCE_FACTOR_FLOOR, rawFactor)`

3. **Bilateral coverage factor** — how balanced is the scan distribution across the two lighthouses?
   - `ratio = min(insideScans.length, outsideScans.length) / max(insideScans.length, outsideScans.length)`
   - Perfectly balanced (1:1 ratio) → 1.0. Heavily skewed (1:15 ratio) → near floor.
   - `bilateralCoverageFactor = max(CONFIDENCE_FACTOR_FLOOR, ratio)`

4. **RSSI trend consistency factor** — `NULL` for this algorithm (not used).

**Final confidence:**

```
confidence = centroidSeparationFactor × clusterSizeFactor × bilateralCoverageFactor
```

**Metadata:**

```json
{
  "outsideCentroidMs": 1742169601200,
  "insideCentroidMs": 1742169603800,
  "centroidDeltaMs": 2600,
  "clusterDurationMs": 5200,
  "outsideScanCount": 8,
  "insideScanCount": 6
}
```

### Algorithm 2: RSSI-Weighted Temporal Centroid + RSSI Trend (`rssi_weighted_centroid`)

**Concept:** Same centroid approach as Algorithm 1, but scans are weighted by RSSI signal strength — scans with stronger signal (tag closer to reader) contribute more to that lighthouse's centroid position. Additionally, RSSI trend per lighthouse is analyzed as a confirming or contradicting signal.

**RSSI weighting rationale:** A scan with high RSSI (e.g., -55 dBm) means the tag was physically close to the reader at that moment. That timestamp is more spatially meaningful than a scan at -82 dBm (tag at the edge of range). Weighting by RSSI anchors each centroid to the moments when the tag was most definitively near that reader.

**Direction determination:**

- Compute RSSI weight for each scan: `weight = rssiToWeight(scan.rssiDbm)`
  - If `rssiDbm` is null → `weight = 1.0` (equal weight, degrades to Algorithm 1 behavior)
  - Otherwise: `weight = 1.0 - ((abs(rssiDbm) - 40) / 50)` clamped to `[0.1, 1.0]`
  - This maps -40 dBm (very strong) → weight 1.0, -90 dBm (very weak) → weight 0.1
- Compute `outsideCentroid = weightedMean(outsideScans[].timestamp, outsideScans[].weight)`
- Compute `insideCentroid = weightedMean(insideScans[].timestamp, insideScans[].weight)`
- Direction logic identical to Algorithm 1

**Canonical timestamp:** Same rules as Algorithm 1, using the RSSI-weighted centroids.

**RSSI trend analysis (per lighthouse):**

For each lighthouse's scan set, compute a simple linear regression of RSSI over time:
- x-axis: scan timestamp (normalized to cluster-relative ms)
- y-axis: `rssiDbm` value
- Output: `slope` (dBm per second) and `R²` (coefficient of determination)

Expected trends for an **entry** (outside → inside):
- OUTSIDE lighthouse: RSSI should decrease over time (tag moving away) → negative slope
- INSIDE lighthouse: RSSI should increase over time (tag approaching) → positive slope (note: RSSI is negative, so "increase" means becoming less negative, i.e., slope > 0 when using raw dBm values)

**Confidence factors:**

Factors 1–3 are computed identically to Algorithm 1 but using the RSSI-weighted centroids.

4. **RSSI trend consistency factor** — does the RSSI trend on each lighthouse agree with the determined direction?
   - For each lighthouse, check if the regression slope direction matches the expected pattern for the determined traversal direction.
   - If both slopes agree with expected direction: `trendAgreement = 1.0`
   - If one agrees, one is flat or inconclusive (R² < 0.1): `trendAgreement = 0.7`
   - If one contradicts: `trendAgreement = 0.4`
   - If both contradict: `trendAgreement = CONFIDENCE_FACTOR_FLOOR`
   - If either lighthouse has fewer than 3 scans (regression unreliable): `trendAgreement = 0.5` (neutral)
   - `rssiTrendConsistencyFactor = max(CONFIDENCE_FACTOR_FLOOR, trendAgreement)`

**Final confidence:**

```
confidence = centroidSeparationFactor × clusterSizeFactor × bilateralCoverageFactor × rssiTrendConsistencyFactor
```

**Metadata:**

```json
{
  "outsideCentroidMs": 1742169601150,
  "insideCentroidMs": 1742169603950,
  "centroidDeltaMs": 2800,
  "clusterDurationMs": 5200,
  "outsideScanCount": 8,
  "insideScanCount": 6,
  "rssiWeights": {
    "outside": [0.82, 0.76, 0.71, 0.65, 0.58, 0.50, 0.42, 0.35],
    "inside": [0.30, 0.38, 0.45, 0.55, 0.68, 0.75]
  },
  "rssiTrend": {
    "outside": { "slope": -3.2, "r2": 0.87 },
    "inside": { "slope": 4.1, "r2": 0.82 }
  }
}
```

### Thesis Comparison Value

The two algorithms differ in a single, well-defined way: how they weight scans when computing centroids, plus Algorithm 2's RSSI trend signal.

In a clean traversal (person walks through at normal speed), both algorithms will likely agree on direction and produce similar confidence. The interesting cases are:

- **Lingering in overlap zone:** temporal centroids converge → both algorithms lose centroid separation. But RSSI weighting may anchor the centroid more firmly if signal strength has a clear spatial gradient despite temporal ambiguity.
- **Noisy RSSI environment** (multipath, reflections): Algorithm 2's RSSI weighting could pull centroids in the wrong direction, producing lower confidence or incorrect direction where Algorithm 1 (treating all scans equally) gets it right.
- **Sparse clusters** (2-3 scans per lighthouse): RSSI weighting has outsized influence with few data points. Algorithm 1 is more stable with small samples.

These scenarios map directly to thesis analysis sections comparing algorithm accuracy under varying conditions.

### Direction Convention

- **"in" (entry):** person moves from OUTSIDE → INSIDE (entering the building/room). OUTSIDE lighthouse centroid is earlier.
- **"out" (exit):** person moves from INSIDE → OUTSIDE (leaving). INSIDE lighthouse centroid is earlier.
- Maps directly to lighthouse `placement` enum values already in the schema.

### Constants

```
CONFIDENCE_FACTOR_FLOOR    — minimum value for any confidence factor (tunable, start with a placeholder)
POLLER_INTERVAL_MS = 2000  — how often the background poller runs
```

`CONFIDENCE_FACTOR_FLOOR` is deliberately left as a named constant without a fixed value. Set an initial value for development, tune after collecting real traversal data.

---

## Processing Architecture

### Background Poller

**File:** `src/server/src/services/event-sweeper.ts`

The sole processing component. Runs on a fixed interval (`POLLER_INTERVAL_MS`). No in-memory state — fully DB-driven and crash-recoverable.

**Each polling cycle:**

1. **Query closed clusters.** Join `raw_scans` → `lighthouses` → `lighthouse_groups` to get `groupId` and `activityTimeoutMs`. Filter to scans where `processedAt IS NULL AND orphanedAt IS NULL`. Group by `(epc, groupId)`. For each group, compute `MAX(timestamp)` as `latestScan`. A cluster is closed when `now() - latestScan > activityTimeoutMs`.

2. **For each closed cluster, validate prerequisites:**
   - Check group configuration (exactly one INSIDE + one OUTSIDE lighthouse). If invalid → set `orphanedAt = now()` and `orphanReason = 'misconfigured_group'` on all scans in the cluster.
   - Filter out scans with `timeBasis != 'synced'`. Orphan those scans individually with `orphanReason = 'unsyncable'`.
   - Check bilateral coverage (scans from both lighthouses). If single-lighthouse only and `now() - latestScan > orphanTimeoutMs` → orphan with `orphanReason = 'insufficient_data'`. If within orphan timeout → skip, try again next cycle.

3. **Process valid clusters:**
   - Partition scans into `insideScans[]` and `outsideScans[]` by lighthouse placement.
   - Run Algorithm 1 (`temporal_centroid`). Write `processed_events` row.
   - Run Algorithm 2 (`rssi_weighted_centroid`). Write `processed_events` row.
   - Insert junction table rows linking both events to all scans in the cluster.
   - Set `processedAt = now()` on all scans in the cluster.
   - Resolve user from `tag_assignments` and set `userId` on both event rows.
   - Broadcast both results via WebSocket.

4. **Batch size limit.** Process at most N clusters per cycle (e.g., 50) to prevent a single poller cycle from running too long. Remaining clusters are picked up next cycle.

**Concurrency safety:** The poller is the only writer to `processedAt`/`orphanedAt`. Since there's a single poller instance (single server process), there's no race condition. If multi-instance deployment ever becomes relevant, add `SELECT ... FOR UPDATE SKIP LOCKED` on the raw scans being processed.

**Graceful shutdown:** On `SIGTERM`/`SIGINT`, clear the poll interval and let any in-progress cycle complete before exiting. Register in the existing shutdown handler chain in `index.ts`.

### Re-processing on Group Config Fix

When a group's configuration changes via the API (lighthouse placement updated, second lighthouse added/removed), the API handler should:

1. Clear `orphanedAt` and `orphanReason` on all `raw_scans` from lighthouses in that group where `orphanReason = 'misconfigured_group'` and `processedAt IS NULL`.
2. These scans become eligible for the poller's next cycle.

This is a targeted UPDATE scoped to the affected group — not a full table scan.

### Removal of Inline Processing

The `queueScanForProcessing()` function in `src/mqtt/handlers/scan.ts` is removed. The MQTT scan handler's sole responsibilities are: validate, store in `raw_scans`, broadcast to WebSocket. All processing logic lives in the poller.

---

## File Structure

### New files

```
src/server/src/services/
├── event-sweeper.ts               — background poller loop and cluster detection
├── event-processor.ts             — cluster validation, algorithm orchestration, result writing
├── algorithms/
│   ├── types.ts                   — shared types (ClusterData, AlgorithmResult, etc.)
│   ├── temporal-centroid.ts       — Algorithm 1 implementation
│   └── rssi-weighted-centroid.ts  — Algorithm 2 implementation
└── tag-resolver.ts                — EPC → userId lookup via tag_assignments
```

### Modified files

```
src/server/src/database/schema.ts              — new enums, table restructure, new junction table
src/server/src/mqtt/handlers/scan.ts           — remove queueScanForProcessing, remove processed field usage
src/server/src/index.ts                        — start poller on boot, register shutdown handler
src/server/src/api/routes/groups.ts            — expose activityTimeoutMs/orphanTimeoutMs, trigger re-processing on config change
src/server/src/api/websocket.ts                — add event:new and event:orphaned broadcast types
```

### New migration

```
src/server/drizzle/XXXX_phase2_event_processing.sql
```

Since the DB can be cleaned entirely, this migration can use destructive operations (DROP/CREATE) rather than incremental ALTER.

---

## REST API Changes

### Modified endpoints

**`GET /api/v1/groups`** — response includes `activityTimeoutMs` and `orphanTimeoutMs` per group.

**`POST /api/v1/groups`** — request body accepts optional `activityTimeoutMs` and `orphanTimeoutMs` (defaults apply if omitted).

**`PATCH /api/v1/groups/:id`** — accepts `activityTimeoutMs` and `orphanTimeoutMs`. When lighthouse membership or placement changes, triggers re-processing of `misconfigured_group` orphans.

### New endpoints

**`GET /api/v1/events`** — query processed traversal events.

Required parameters:
- `algorithmId` — which algorithm's results to return (`temporal_centroid` | `rssi_weighted_centroid` | `manual`)

Optional filters:
- `groupId` — filter by group
- `userId` — filter by user
- `tagEpc` — filter by tag
- `direction` — filter by `in` | `out` | `unknown`
- `from` / `to` — timestamp range (ISO 8601)
- `minConfidence` — minimum confidence threshold (0.0–1.0)
- `limit` / `offset` — pagination (default limit 50, max 500)

Response includes all columns from `processed_events` plus resolved user info and scan count from the junction table.

**`GET /api/v1/events/unresolved`** — query orphaned scans for admin review.

Optional filters:
- `groupId` — filter by group
- `orphanReason` — filter by reason
- `tagEpc` — filter by tag
- `from` / `to` — timestamp range
- `limit` / `offset` — pagination

Response includes scan details, orphan reason, resolved user (if tag is assigned), lighthouse info.

**`POST /api/v1/events/manual`** — admin creates a manual traversal event.

Request body:
```json
{
  "tagEpc": "E28011704000021D53D80D0A",
  "direction": "in",
  "timestamp": "2026-03-20T14:30:00Z",
  "groupId": 1,
  "notes": "Manual correction — badge reader confirmed entry"
}
```

Creates a `processed_events` row with:
- `algorithmId = 'manual'`
- `confidence = 1.0`
- All factor columns = `1.0`
- `clusterStartedAt` = `clusterEndedAt` = provided timestamp
- `metadata = { "notes": "..." }`
- No junction table entries (no linked raw scans)

---

## WebSocket Events

New broadcast types alongside existing `scan:new`:

```typescript
// Traversal detected — emitted twice per traversal (once per algorithm)
{
  type: "event:new",
  data: {
    id: string,
    algorithmId: "temporal_centroid" | "rssi_weighted_centroid",
    direction: "in" | "out" | "unknown",
    tagEpc: string,
    userId: string | null,
    groupId: number,
    confidence: number,
    timestamp: string,
    clusterStartedAt: string,
    clusterEndedAt: string,
    scanCount: number
  }
}

// Scan orphaned — emitted once per orphaned scan
{
  type: "event:orphaned",
  data: {
    scanId: string,
    epc: string,
    lighthouseId: number,
    timestamp: string,
    orphanReason: "insufficient_data" | "misconfigured_group" | "unsyncable"
  }
}
```

---

## Processing Rules Summary

| Scan condition | Poller action | Result |
|---------------|--------------|--------|
| Cluster closed, both lighthouses contributed, group valid, all scans synced | Run both algorithms, write 2 events, mark `processedAt` | Traversal event |
| Cluster closed, single lighthouse only, within orphan timeout | Skip — try again next cycle | Pending |
| Cluster closed, single lighthouse only, past orphan timeout | Mark `orphanedAt`, reason `insufficient_data` | Unresolved |
| Any scan with `timeBasis != 'synced'` | Mark `orphanedAt`, reason `unsyncable` | Unresolved |
| Cluster from misconfigured group | Mark `orphanedAt` immediately, reason `misconfigured_group` | Unresolved (re-processable) |
| Group config fixed (API PATCH) | Clear `orphanedAt`/`orphanReason` on affected `misconfigured_group` scans | Re-enters processing pipeline |

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Person lingers in overlap zone | Produces one long cluster with converging centroids → low confidence, possibly `unknown` direction. Correct behavior. |
| Multiple people simultaneously (different tags) | Clusters segmented by EPC — completely independent, no interference. |
| Same tag, multiple groups | Each group processes independently. |
| Server restart mid-cycle | No in-memory state. Poller resumes from DB on next startup. Clusters that were open during shutdown are either still open (scans resume) or close naturally (activity timeout passes during downtime). |
| Clock skew between lighthouses | Both sync via SNTP to same server. Sub-100ms drift on LAN is negligible for centroid analysis. `timeBasis: "synced"` gatekeeper ensures only SNTP-synced scans are processed. |
| Back-to-back traversals (same person, in then out) | Activity timeout (4s) segments them into two separate clusters if gap between traversals exceeds the timeout. |
| Offline replay burst | Scans land with `timeBasis: "synced"` and original detection timestamps — processed normally by the next poller cycle after the cluster's activity timeout expires. |

---

## Execution Order

1. **Schema migration** — new enums, `lighthouse_groups` new columns, `raw_scans` column changes, `processed_events` restructure, `processed_event_scans` junction table. Destructive migration (clean DB).
2. **Tag resolver** — `tag-resolver.ts`. Pure query function, no dependencies.
3. **Algorithm types** — `algorithms/types.ts`. Shared interfaces for cluster data and algorithm results.
4. **Algorithm 1** — `algorithms/temporal-centroid.ts`. Pure function: takes cluster data, returns direction + confidence factors + metadata.
5. **Algorithm 2** — `algorithms/rssi-weighted-centroid.ts`. Pure function: same interface, adds RSSI weighting and trend analysis.
6. **Event processor** — `event-processor.ts`. Orchestrates prerequisites, runs both algorithms, writes results, resolves users.
7. **Event sweeper** — `event-sweeper.ts`. Poller loop, cluster detection, orphan management. Wire into `index.ts`.
8. **Scan handler cleanup** — remove `queueScanForProcessing` and `processed` field usage from `scan.ts`.
9. **Group API update** — expose timing columns, add re-processing trigger on config change.
10. **Events API** — new endpoints for traversal events and unresolved scans.
11. **Manual events API** — `POST /api/v1/events/manual`.
12. **WebSocket events** — `event:new` and `event:orphaned` broadcasts.

---

## Acceptance Criteria

### Core processing
- Both algorithms run on every qualifying cluster and produce independent `processed_events` rows.
- Direction detection correctly identifies entry (outside→inside) vs exit (inside→outside) based on lighthouse placement and temporal centroid comparison.
- The poller correctly segments traversals using gap-based activity timeout.
- Clusters with scans from both lighthouses are processed; single-lighthouse clusters are orphaned after the orphan timeout.

### Confidence scoring
- Confidence factors are computed per the specified formulas and stored in dedicated columns.
- `CONFIDENCE_FACTOR_FLOOR` is applied to all factors, preventing any factor from reaching true zero.
- Multiplicative combination produces a final confidence that reflects the overall evidence quality.
- Algorithm 2's RSSI trend consistency factor modulates confidence based on whether RSSI trends agree with the determined direction.

### Offline and degraded handling
- Scans with `timeBasis = 'estimated'` or `'relative'` are orphaned with reason `unsyncable`.
- Scans with `timeBasis = 'synced'` and `source = 'offline_sync'` are processed identically to realtime scans.
- Misconfigured-group scans are orphaned immediately and re-processed when the group configuration is corrected.

### API and dashboard
- `GET /api/v1/events` requires `algorithmId` and returns filtered traversal events.
- `GET /api/v1/events/unresolved` returns orphaned scans with reasons.
- `POST /api/v1/events/manual` creates manual traversal events with all factor columns set to 1.0.
- WebSocket emits both algorithms' results for each traversal and orphan notifications.

### Infrastructure
- The poller shuts down gracefully without losing in-progress work.
- Group timing parameters (`activityTimeoutMs`, `orphanTimeoutMs`) are configurable per group via the API.
- Junction table correctly links processed events to their source raw scans bidirectionally.
- Existing tests continue to pass; new tests cover both algorithms, the poller, cluster segmentation, orphan detection, re-processing, and the non-synced skip behavior.
