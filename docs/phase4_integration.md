# Navigo3 Integration - Design Reference

**Project:** Lighthouse Attendance System  
**Component:** Server Phase 4 - External Integration  
**Author:** Jakub Hloušek  
**Status:** Design complete, implementation pending

---

## Overview

Phase 4 implements outbound synchronisation of processed traversal events from the Lighthouse server to Navigo3, a Czech HR/project management application developed by Navigo Solutions s.r.o. (Brno). The integration is implemented entirely within the Lighthouse TypeScript server - no external runtime, no Python, no dependency on Navigo-hosted infrastructure.

The integration is intentionally one-directional: Lighthouse pushes attendance records to Navigo3. Navigo3 does not push back. User identity resolution (mapping RFID tag → Navigo3 user ID) is handled via the `syncId` field on the Lighthouse `users` table, which stores the Navigo3 internal numeric user ID.

---

## Navigo3 API Protocol

### Transport

All API calls go to a single endpoint:

```
POST https://<instance>.navigo3.com/API/execute
```

The request body is a JSON object containing a `requests` array. Each element represents one API method call. In practice, Lighthouse will always send single-request batches.

```json
{
  "requests": [
    {
      "qualifiedName": "attendance/embedded/start",
      "requestType": "EXECUTE",
      "inputMappings": null,
      "requestUuid": "<uuid-v4>",
      "input": { ... }
    }
  ]
}
```

Required headers on every call:
- `Content-Type: application/json;charset=utf-8`
- `X-API-Session: <sessionId>` (obtained at login)

### Authentication

Authentication is session-based. Before any API calls can be made, the connector must obtain a session ID:

```
POST https://<instance>.navigo3.com/API/login
Content-Type: application/json;charset=utf-8

{ "login": "<username>", "password": "<password>" }
```

On success (HTTP 200):
```json
{ "succeeded": true, "sessionId": "ec2b4f90e7f4451e..." }
```

On failure (HTTP 400/401/500):
```json
{ "succeeded": false, "problem": "Authorization failed" }
```

The `sessionId` is then passed as the `X-API-Session` header on all subsequent requests. Session lifetime is not documented; the connector must handle `401` responses by re-authenticating once and retrying the failed request before propagating an error.

Logout (recommended on clean shutdown):
```
POST https://<instance>.navigo3.com/API/logout

{ "sessionId": "<sessionId>" }
```

### Response Structure

All responses return a JSON object with the following shape:

```json
{
  "overallSuccess": true,
  "responses": [
    {
      "status": "SUCCESS",
      "output": { ... }
    }
  ]
}
```

Possible `status` values: `SUCCESS`, `INVALID_INPUT`, `NOT_AUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR_ON_EXECUTION`, `MALFORMED_INPUT`, `METHOD_NOT_ALLOWED`, `NOT_PROCESSED_DUE_TO_PREVIOUS_ERRORS`.

HTTP return codes: 200 (full success), 400 (batch partially/fully failed), 401 (not authenticated), 403 (IP not whitelisted), 500 (server error).

### Special Data Types

| Type | Format |
|---|---|
| `DATE` | `yyyy-MM-dd` |
| `DATETIME` | `yyyy-MM-dd HH:mm:ss` |
| `TIME` | `HH:mm:ss` |

> ⚠️ Navigo3 does **not** use ISO 8601. The `T` separator and timezone offsets are not valid. All timestamps must be serialized without them.

---

## Navigo3 API Methods Used

### `attendance/embedded/start`

Marks the start of a work period for a specific user at a specific time.

**Input:**
```
comment       STRING
time          DATETIME  (optional - defaults to now if omitted)
typeId        NUMBER
userId        NUMBER    (optional - defaults to logged-in user if omitted)
```

Maps to a Lighthouse `direction: "in"` event.

### `attendance/embedded/stop`

Marks the end of a work period for a specific user at a specific time.

**Input:**
```
comment   STRING
time      DATETIME  (optional - defaults to now if omitted)
userId    NUMBER    (optional - defaults to logged-in user if omitted)
```

Maps to a Lighthouse `direction: "out"` event.

### `attendance/embedded/upsert`

Creates or updates a complete attendance record, including both start and end times. Used for backfill when a full `in`/`out` pair is available and the connection was previously unavailable.

**Input:**
```
changedBy    NUMBER
comment      STRING
createdFrom  DATETIME
createdTo    DATETIME
day          DATE
id           NUMBER      (omitted for insert; Navigo3-assigned ID for update)
timeFrom     TIME
timeTo       TIME
typeId       NUMBER
userId       NUMBER
```

**Output:**
```
id   NUMBER   (Navigo3-assigned record ID)
```

The returned `id` must be stored on the `processedEvents` row (`navigo3RecordId` column - see Schema Changes) to enable future updates to that record.

### `attendance/embedded/types`

Lists all configured attendance types. Called once on startup to resolve the `atWork` type ID.

**Input:** `{}` (VoidParam)

**Output:** Array of `{ id: NUMBER, name: STRING, systemName: STRING }`

---

## Navigo3 API Modifications

The standard Navigo3 `AttendanceMethods.java` was augmented to support programmatic push on behalf of arbitrary users. The original `start` and `stop` methods only operated on the currently authenticated session user. Two overloaded versions were added:

### `start` - redefined interface (single usage was in the method being modified)

```java
public static void start(
    NavigoAppContext appContext,
    Optional<Integer> userId,
    Optional<LocalDateTime> timestamp,
    int typeId,
    String comment
)
```

- `userId`: if empty, falls back to `appContext.getUser().getId()`
- `timestamp`: if empty, falls back to `LocalDateTime.now()`
- `changedBy` is always set from `appContext.getUser().getId()` (the API integration user), regardless of `userId`

### `stop` - redefined interface (single usage was in the method being modified)
 
```java
public static void stop(
    NavigoAppContext appContext,
    Optional<Integer> userId,
    Optional<LocalDateTime> timestamp,
    String comment
)
```

Same conventions as `start`. `changedBy` is always the API session user.

---

## Lighthouse Server Integration Design

### Configuration (`.env`)

```
NAVIGO3_BASE_URL=https://<instance>.navigo3.com
NAVIGO3_USERNAME=<api-user-login>
NAVIGO3_PASSWORD=<api-user-password>
NAVIGO3_ALGORITHM_ID=temporal_centroid   # or rssi_weighted_centroid
```

The algorithm whose events are pushed is configurable per deployment. Only events matching `NAVIGO3_ALGORITHM_ID` are eligible for sync.

### Startup Behaviour

On server start, the Navigo3 connector:

1. Calls `attendance/embedded/types` to fetch all attendance types.
2. Searches for an entry where `systemName === "atWork"`.
3. If the `atWork` type is **not found**, integration is **disabled** for the lifetime of the process. No events are pushed, no errors are thrown. A warning is logged.
4. If found, caches the `typeId` and proceeds.

This avoids hardcoding a type ID that may differ between Navigo3 instances.

### Event Eligibility

A processed event is eligible for Navigo3 sync if and only if:
- `algorithmId === NAVIGO3_ALGORITHM_ID`
- `direction` is `"in"` or `"out"` (never `"unknown"`)
- `userId` is not null (tag must be assigned to a user)
- The resolved user has a non-null `syncId` (maps to a Navigo3 user ID)
- `syncedToIntegration === false`

### Push Strategy

**Immediate push (normal path):**  
When the event processor commits a new `processedEvents` row, it triggers a non-blocking post-commit push attempt for the configured algorithm's event. The push calls either `attendance/embedded/start` (for `"in"`) or `attendance/embedded/stop` (for `"out"`), supplying `userId` (from `users.syncId`), `time` (from `processedEvents.timestamp`, formatted as `yyyy-MM-dd HH:mm:ss`), `typeId` (cached `atWork` ID), and an empty `comment`.

On success, `syncedToIntegration` is set to `true` on the row.

**Backfill path (retry of failed events):**  
A periodic background timer (interval configurable, default 60 seconds) queries `processedEvents` where `syncedToIntegration = false` and the event is otherwise eligible. For each unsynchronised event:

- If both the `"in"` and `"out"` events for the same user on the same day are present and unsynchronised, push them together as a single `attendance/embedded/upsert` call. This reconstructs the closed interval.
- If only one side is available (e.g. only `"in"` with no corresponding `"out"`), push it individually using `start` or `stop` as appropriate.

The Navigo3 record ID returned by `upsert` is stored in `processedEvents.navigo3RecordId` for future reference.

### Session Management

The connector maintains a single session. On any `401` response, it:
1. Attempts re-login with the configured credentials.
2. Retries the failed request once with the new session ID.
3. If re-login fails or the retry also returns `401`, marks the event as failed and logs an error. The retry timer will attempt it again on the next cycle.

### Schema Changes Required

One new column on `processedEvents`:

```sql
navigo3RecordId   INTEGER   NULL
```

Stores the Navigo3-assigned record ID after a successful `upsert`. Null for records pushed via `start`/`stop` (Navigo3 does not return an ID for those). Used to correlate Lighthouse events with Navigo3 records.

---

## What Is Not Implemented

- No inbound sync from Navigo3 (attendance records created manually in Navigo3 are not reflected in Lighthouse).
- No user sync - Navigo3 user IDs must be manually entered into the `syncId` field on Lighthouse users.
- No deletion propagation - deleting an event in Lighthouse does not call `attendance/embedded/delete` in Navigo3.
- No multi-instance support - the integration targets a single Navigo3 instance configured in `.env`.
