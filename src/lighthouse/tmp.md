Core Functionality Questions:

1. Authentication scope — You have JWT auth in place. For the MVP, is this single-user (just you/admin), or do you need multi-user with roles (admin vs. viewer)?
Lighthouse pairing flow — How do you envision the pairing process?

2. Does the device announce itself via MQTT when it comes online, and then you "claim" it in the UI?
Or do you manually enter device IDs?
Should there be any security handshake (e.g., device shows a code on serial/LED, you enter it in webapp)?


3. Lighthouse groups/pairs — For direction detection, I assume a "group" is two lighthouses at one doorway (entry sensor + exit sensor). Questions:

Can a lighthouse belong to multiple groups, or strictly one?
Does group configuration need to be pushed to the devices themselves, or is direction logic computed server-side from raw events?


4. Events display — What's the MVP need here?

Simple chronological list with filtering (by device, tag, time range)?
Real-time updates via WebSocket, or polling/refresh is acceptable for MVP?
Any aggregation (e.g., "Tag X entered at 9:00, exited at 17:30")?


5. Device management — Beyond pairing and grouping, what device controls do you need in MVP?

View status (online/offline, last seen, health metrics)?
Restart/reboot command?
Configuration changes (detection sensitivity, reporting interval)?


6. Locations/Zones — Do groups need to be associated with physical locations (e.g., "Building A, Main Entrance"), or is that a post-MVP concern?

Technical Constraints:

7. Offline sync visibility — When a device comes back online and flushes cached events, should the UI indicate these are "backfilled" vs. real-time?
8. Current database schema — Do you have any tables defined yet, or is this greenfield for the core entities (devices, groups, events, tags)?

1. Not the focus at the moment
2. Currently the device sends a status message to the broker and the server logs even unknown device in memory (no in database):

```js
const db = getDatabase();
const lighthouses = await db
  .select({ id: schema.lighthouses.id })
  .from(schema.lighthouses)
  .where(eq(schema.lighthouses.deviceId, macAddress))
  .limit(1);

if (lighthouses.length === 0 || lighthouses[0] === undefined) {
  logger.warn(`Unknown lighthouse device: ${macAddress}`);
  // Still update runtime state for unknown devices
  if (isOnline) {
    setLighthouseConnected(macAddress);
  } else {
    setLighthouseDisconnected(macAddress, false);
  }

  // This should not really be automatic and there should be a more defined process
  await db.insert(schema.lighthouses).values({
    name: macAddress, 
    placement: "STANDALONE",
    isActive: true,
    deviceId: macAddress
  })
  return;
}
```

a security handshake may be added later

3. You assume correctly. I'd say they can belong to strictly one. The configuration is only relevant to the server.
4. 
Simple chronological list with filtering (by device, tag, time range)? - Yes
Real-time updates via WebSocket, or polling/refresh is acceptable for MVP? - Yes
Any aggregation (e.g., "Tag X entered at 9:00, exited at 17:30")? - Yet to be implemented so not relevant right now

5. For now only status. Configuration will be added later
6. The groups should at least have a user modifiable label. The lighthouses table have a new column `group_id` reffering to the relevant group
7. There should be an indication yes.
8. Yes there is, check `/src/server/src/database/schema.ts`



1. Unknown device handling — Your current code auto-inserts unknown devices. For MVP, should we instead keep them in a "pending" list in the UI where you explicitly "claim" them, or is auto-registration acceptable for now with the ability to rename/group them later?
2. Real-time updates — For the WebSocket, do you want:

Just new scan events streamed live?
Also device status changes (online/offline)?
Also health metric updates?

3. Events backfill indicator — You mentioned marking events that came from offline cache sync. Is there already a field for this in raw_scans, or do we need to add something like is_backfilled: boolean or source: 'realtime' | 'offline_sync'?
4. Frontend tech preferences — The devlog mentions React + MobX + SCSS. Is that still the plan, or are you open to alternatives (e.g., Zustand is lighter than MobX, TailwindCSS is popular)?

1. No, the code that adds them was indeed temporary for testing. The webpage should work with the logged devices in memory and prompt to add them to the database.
2. All three of possible
3. There is no field in the database currently, but the scan handler is handling the offline sync, it's only a matter of saving it to a new field
4. I have an aversion to Tailwind to be honest XD, I'd like to definitely stick with scss, I am open to exploring zustand and I am also considering going with solidjs or svelte for a change.
