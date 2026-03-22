# Task: Phase 4 — Navigo3 Integration Service

**Purpose:** Implement outbound synchronisation of processed traversal events from the Lighthouse server to Navigo3. Each eligible event is pushed immediately after being committed, with a periodic background retry timer for any that failed. This is the final server phase required for the thesis.

**Files to create:**
- `src/server/src/services/navigo3/navigo3Service.ts`
- `src/server/src/services/navigo3Poller.ts`

**Files to modify:**
- `src/server/src/database/schema.ts` — add `navigo3RecordId` column to `processedEvents`
- `src/server/src/services/event-processor.ts` — trigger immediate push in the post-commit `setImmediate` block
- `.env.example` — document the four new env vars

**Files NOT to modify:** `src/server/src/services/navigo3/connector.ts` (already implemented), any algorithm files, MQTT handlers, frontend files, or any existing migration files. Do not alter the `syncedToIntegration` index — it already exists.

**Reference:** `docs/navigo3_integration_reference.md` — full design reference including API protocol, data types, push strategy, and session management. Read this file before implementing.

---

## Overview / Context

The Lighthouse server processes raw RFID scans into directional traversal events stored in `processedEvents`. Each row has `syncedToIntegration: boolean` (default `false`) and `algorithmId`. Only events from a single configurable algorithm (`NAVIGO3_ALGORITHM_ID` env var) are eligible for sync.

The Navigo3 DryAPI connector already exists at `src/server/src/services/navigo3/connector.ts`. It exposes a single `execute(method, input)` method that handles session lifecycle including re-authentication on 401. The connector is instantiated once and shared.

Navigo3 uses non-ISO datetime format: `yyyy-MM-dd HH:mm:ss` (no `T`, no timezone offset). All timestamps sent to Navigo3 must be serialised in this format using the server's local time representation of the UTC timestamp stored in the database.

The `attendance/embedded/types` endpoint returns `{ id, name, systemName }` per type (the `systemName` field was added to the Navigo3 API as part of this integration). On startup, the service must call this endpoint and find the entry where `systemName === "atWork"`. If not found, integration is disabled for the lifetime of the process — no events are pushed, no errors thrown, only a warning logged. The `typeId` is cached in memory.

---

## Step 1 — Schema migration

### `src/server/src/database/schema.ts`

In the `processedEvents` table definition, add a new nullable integer column after the existing `syncedToIntegration` column:

```ts
navigo3RecordId: integer(),
```

Generate and apply a new Drizzle migration (`bun drizzle-kit generate` then `bun drizzle-kit migrate`). The migration must be committed alongside the schema change.

---

## Step 2 — Create `navigo3Service.ts`

Create `src/server/src/services/navigo3/navigo3Service.ts`. This file is the attendance-specific layer on top of the connector. It owns all Navigo3 business logic and is the only file that imports from `connector.ts`.

### Initialisation

Export an `initNavigo3Service()` async function that:

1. Reads `NAVIGO3_BASE_URL`, `NAVIGO3_USERNAME`, `NAVIGO3_PASSWORD`, and `NAVIGO3_ALGORITHM_ID` from `process.env`. If any of the first three are absent, log a warning and return without initialising — integration remains disabled.
2. Instantiates `Navigo3Connector` with the three credentials.
3. Calls `attendance/embedded/types` (input: `{}`) via `connector.execute()`.
4. Searches the returned array for an entry where `systemName === "atWork"`. Null or absent `systemName` is treated as non-matching.
5. If not found, logs a warning (`"Navigo3: atWork attendance type not found — integration disabled"`) and returns without further setup.
6. Caches the resolved `typeId` (a number) and the algorithm ID string in module-level state.
7. Marks the service as enabled.

Export a `isNavigo3Enabled(): boolean` function that returns the enabled state.

### Timestamp serialisation

Implement a module-private helper `toNavigo3DateTime(date: Date): string` that formats a JS `Date` as `"yyyy-MM-dd HH:mm:ss"` using the date's UTC values (i.e. `date.getUTCFullYear()`, etc., zero-padded). Do not use any external date library — format manually. Similarly implement `toNavigo3Date(date: Date): string` for date-only fields (`"yyyy-MM-dd"`).

### Event eligibility check

Implement a module-private helper `isEligible(event: { algorithmId: string; direction: string; userId: string | null; userSyncId: string | null }): boolean` that returns true only when:
- `algorithmId === NAVIGO3_ALGORITHM_ID` (the cached value)
- `direction === "in"` or `direction === "out"`
- `userId` is not null
- `userSyncId` is not null and not empty

### Immediate push

Export `pushEvent(eventId: string): Promise<void>`. This function:

1. Returns immediately (no-op) if the service is not enabled.
2. Queries the database for the `processedEvents` row by `eventId`, joining `users` to get `syncId`. Select: `id`, `algorithmId`, `direction`, `userId`, `timestamp`, `syncedToIntegration`, and the joined `users.syncId` as `userSyncId`.
3. If the row is not found, or `syncedToIntegration` is already `true`, returns.
4. Runs eligibility check. If not eligible, returns silently.
5. Calls either `attendance/embedded/start` (for `direction === "in"`) or `attendance/embedded/stop` (for `direction === "out"`) via `connector.execute()`.

   For `start`, the input object is:
   ```json
   {
     "userId": <number — parseInt(userSyncId)>,
     "time": "<toNavigo3DateTime(event.timestamp)>",
     "typeId": <cached atWork typeId>,
     "comment": ""
   }
   ```

   For `stop`, the input object is:
   ```json
   {
     "userId": <number — parseInt(userSyncId)>,
     "time": "<toNavigo3DateTime(event.timestamp)>",
     "comment": ""
   }
   ```

6. On success, updates `processedEvents` row: `syncedToIntegration = true`. `navigo3RecordId` is NOT set here — `start`/`stop` do not return a record ID.
7. On any thrown error, logs the error with the `eventId` and rethrows. Do not swallow errors here — the caller (`event-processor.ts`) wraps this in a fire-and-forget `setImmediate` so a throw there is harmless.

### Backfill upsert

Export `pushPair(inEventId: string, outEventId: string): Promise<void>`. This function handles the case where both sides of an interval are available and neither has been synced. It:

1. Returns immediately if service is not enabled.
2. Fetches both events (with `userSyncId` via join). Both must have the same `userId` and `userSyncId`, both must be eligible, and neither must be `syncedToIntegration = true`. If any condition fails, returns silently.
3. Identifies which event is `"in"` and which is `"out"`.
4. Calls `attendance/embedded/upsert` with input:
   ```json
   {
     "userId": <parseInt(userSyncId)>,
     "day": "<toNavigo3Date(inEvent.timestamp)>",
     "timeFrom": "<HH:mm:ss of inEvent.timestamp>",
     "timeTo": "<HH:mm:ss of outEvent.timestamp>",
     "createdFrom": "<toNavigo3DateTime(inEvent.timestamp)>",
     "createdTo": "<toNavigo3DateTime(outEvent.timestamp)>",
     "typeId": <cached atWork typeId>,
     "comment": "",
     "changedBy": 0
   }
   ```
   > Note: `changedBy` is set to `0` here — Navigo3 overwrites it server-side with the API session user's ID, so the value sent is irrelevant. Do not omit the field as the schema requires it.

5. The response output is `{ id: number }`. Store this value as `navigo3RecordId` on **both** event rows.
6. Sets `syncedToIntegration = true` on both rows in a single `UPDATE ... WHERE id IN (...)`.
7. On error, logs and rethrows.

### Retry sweep

Export `runRetrySweep(): Promise<void>`. This is called by the poller. It:

1. Returns immediately if service is not enabled.
2. Queries all `processedEvents` where `syncedToIntegration = false`, joining `users` for `syncId`. Filter to only rows where `algorithmId = NAVIGO3_ALGORITHM_ID`, `direction IN ('in', 'out')`, `userId IS NOT NULL`. Fetch up to 100 rows per sweep ordered by `timestamp ASC`.
3. For each unsynchronised event, check if a counterpart event exists for the same `userId`, same calendar day (`DATE(timestamp)`), and opposite direction, also with `syncedToIntegration = false`.
4. If both sides are present: call `pushPair(inEventId, outEventId)`. Mark both as handled so they are not processed again in this sweep iteration.
5. If only one side is present: call `pushEvent(eventId)`.
6. Errors from individual push calls are caught and logged per-event — a single failure must not abort the rest of the sweep.

---

## Step 3 — Create `navigo3Poller.ts`

Create `src/server/src/services/navigo3Poller.ts`. Follow the exact same pattern as the existing background pollers in `src/server/src/services/` (read one to confirm the pattern — interval-based with a `startNavigo3Poller()` / `stopNavigo3Poller()` export pair).

The poller calls `runRetrySweep()` on a fixed interval. The interval is read from `process.env.NAVIGO3_RETRY_INTERVAL_MS`, defaulting to `60000` (60 seconds) if absent or non-numeric. The poller must not start a new sweep if the previous one is still running (use a boolean guard).

---

## Step 4 — Hook into `event-processor.ts`

### `src/server/src/services/event-processor.ts`

Locate the `setImmediate` block after the transaction commit (Step 10 in the existing comments). It currently calls `broadcastEvent` for both algorithm results. Extend it to also fire `pushEvent` for whichever event matches the configured algorithm ID.

The addition must be inside the existing `setImmediate` callback, after the two `broadcastEvent` calls. It should call `pushEvent` only for the event whose `algorithmId` matches — this means checking both `result1.algorithmId` and `result2.algorithmId` against `NAVIGO3_ALGORITHM_ID` (via `isNavigo3Enabled()` first as a short-circuit guard).

Import `pushEvent` and `isNavigo3Enabled` from `navigo3Service.ts`. Wrap the `pushEvent` call in a `.catch(err => logger.warn(...))` — errors must not propagate out of `setImmediate`.

---

## Step 5 — Wire up server startup and shutdown

Locate the server entry point (the file that starts the existing background pollers). Add:
- `await initNavigo3Service()` during startup, after the database is initialised.
- `startNavigo3Poller()` after `initNavigo3Service()` returns.
- `stopNavigo3Poller()` in the graceful shutdown handler alongside the other poller stops.

---

## Step 6 — `.env.example`

Add the following four entries with comments:

```
# Navigo3 integration
# Algorithm whose events are pushed (temporal_centroid or rssi_weighted_centroid)
NAVIGO3_ALGORITHM_ID=temporal_centroid
NAVIGO3_BASE_URL=https://<instance>.navigo3.com
NAVIGO3_USERNAME=
NAVIGO3_PASSWORD=
# Retry sweep interval in milliseconds (default: 60000)
NAVIGO3_RETRY_INTERVAL_MS=60000
```

---

## Acceptance Criteria

- [ ] `bun run build` (or equivalent typecheck) completes without errors.
- [ ] A new Drizzle migration file exists and `navigo3RecordId` column is present in `processedEvents` after migration.
- [ ] On server start with valid `NAVIGO3_*` env vars and a reachable Navigo3 instance, the log shows either `"Navigo3 session established"` followed by a `typeId` cache message, or `"Navigo3: atWork attendance type not found — integration disabled"`.
- [ ] On server start with `NAVIGO3_BASE_URL` absent from env, no Navigo3 connection is attempted and no error is thrown.
- [ ] A processed event with matching `algorithmId`, `direction: "in"` or `"out"`, and a user with a non-null `syncId` results in a `pushEvent` call being fired from the `setImmediate` block in `event-processor.ts`.
- [ ] A processed event with `direction: "unknown"` does not trigger a push attempt.
- [ ] A processed event whose `algorithmId` does not match `NAVIGO3_ALGORITHM_ID` does not trigger a push attempt.
- [ ] After a successful `pushEvent`, the corresponding `processedEvents` row has `syncedToIntegration = true`.
- [ ] After a successful `pushPair`, both rows have `syncedToIntegration = true` and both have `navigo3RecordId` set to the value returned by `upsert`.
- [ ] `runRetrySweep` processes a mix of paired and unpaired events without throwing, and logs per-event errors without aborting the sweep.
- [ ] The Navigo3 poller does not start a concurrent sweep if the previous call to `runRetrySweep` has not yet resolved.
- [ ] No changes to algorithm logic, MQTT handlers, frontend files, or existing migration files.
