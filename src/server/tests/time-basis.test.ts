import {
  describe,
  it,
  expect,
  beforeAll,
  afterAll,
  beforeEach,
} from "bun:test";
import mqtt from "mqtt";
import { startMqttBroker, closeMqttBroker } from "../src/mqtt/broker";
import {
  initDatabase,
  closeDatabase,
  getDatabase,
  schema,
} from "../src/database/client";
import { eq } from "drizzle-orm";
import { buildScanTopic } from "../src/mqtt/topics";
import { clearAllStates } from "../src/mqtt/state";

// --- Test configuration -------------------------------------------------------

const MQTT_PORT = 1883;
const MQTT_URL = `mqtt://localhost:${MQTT_PORT}`;

// Use distinct IDs to avoid collisions with mqtt-broker.test.ts (uses 999 / EE:01)
const TEST_LIGHTHOUSE_ID = 997;
const TEST_DEVICE_ID = "AA:BB:CC:DD:EE:03";

// A known Unix timestamp used in "synced" tests: 2025-03-17T00:00:00Z
const KNOWN_UNIX_MS = 1742169600000;

// --- Helper: wait for a condition with timeout ---------------------------------

async function waitFor(
  condition: () => Promise<boolean>,
  timeout = 5000,
  interval = 100,
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (await condition()) return;
    await new Promise((r) => setTimeout(r, interval));
  }
  throw new Error(`Timeout waiting for condition after ${timeout}ms`);
}

// --- Helper: connect an MQTT test client --------------------------------------

async function connectClient(clientId: string): Promise<mqtt.MqttClient> {
  const client = mqtt.connect(MQTT_URL, { clientId, connectTimeout: 5000 });
  await new Promise<void>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("Connection timeout")), 5000);
    client.on("connect", () => {
      clearTimeout(t);
      resolve();
    });
    client.on("error", (err) => {
      clearTimeout(t);
      reject(err);
    });
  });
  return client;
}

async function disconnectClient(client: mqtt.MqttClient): Promise<void> {
  if (client.connected) {
    await new Promise<void>((resolve) =>
      client.end(false, {}, () => resolve()),
    );
  }
}

// --- Helper: publish a scan and wait for it to appear in raw_scans ------------

async function publishScan(
  client: mqtt.MqttClient,
  payload: Record<string, unknown>,
): Promise<void> {
  const topic = buildScanTopic(TEST_DEVICE_ID);
  await new Promise<void>((resolve, reject) => {
    client.publish(topic, JSON.stringify(payload), { qos: 0 }, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

// --- Suite lifecycle ----------------------------------------------------------

describe("Time Basis Scan Handling", () => {
  let client: mqtt.MqttClient | null = null;

  beforeAll(async () => {
    initDatabase();
    const db = getDatabase();

    // Insert test lighthouse if not present
    const existing = await db
      .select()
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, TEST_DEVICE_ID))
      .limit(1);

    if (existing.length === 0) {
      await db.insert(schema.lighthouses).values({
        id: TEST_LIGHTHOUSE_ID,
        name: "Time Basis Test Lighthouse",
        deviceId: TEST_DEVICE_ID,
        placement: "STANDALONE",
        isActive: true,
      });
    }

    startMqttBroker();
    await new Promise((r) => setTimeout(r, 500));
  });

  afterAll(async () => {
    if (client) await disconnectClient(client);
    client = null;

    const db = getDatabase();
    await db
      .delete(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.id, TEST_LIGHTHOUSE_ID));

    await closeMqttBroker();
    await closeDatabase();
  });

  beforeEach(async () => {
    const db = getDatabase();
    await db
      .delete(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
    clearAllStates();
  });

  // --- Test 1: timeBasis "synced" - timestamp used directly ------------------

  it('should use timestampMs directly when timeBasis is "synced"', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-synced");

    await publishScan(client, {
      epc: "E200SYNCED0000000001",
      timestampMs: KNOWN_UNIX_MS,
      rssiDbm: -60,
      timeBasis: "synced",
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    expect(rows.length).toBe(1);
    const row = rows[0]!;

    // timestamp should match KNOWN_UNIX_MS (within 1 second)
    const storedMs = row.timestamp.getTime();
    expect(Math.abs(storedMs - KNOWN_UNIX_MS)).toBeLessThan(1000);

    // Raw value preserved
    expect(row.timestampMs).toBe(BigInt(KNOWN_UNIX_MS));

    // time_basis column
    expect(row.timeBasis).toBe("synced");

    await disconnectClient(client);
    client = null;
  });

  // --- Test 2: timeBasis "estimated" - falls back to received_at -------------

  it('should use received_at when timeBasis is "estimated"', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-estimated");

    const bootRelativeMs = 45000; // 45 seconds after boot - not a real Unix ts
    const beforePublish = Date.now();

    await publishScan(client, {
      epc: "E200ESTIMATED0000001",
      timestampMs: bootRelativeMs,
      rssiDbm: -55,
      timeBasis: "estimated",
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const afterPublish = Date.now();

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    const row = rows[0]!;

    // timestamp should be approximately "now", not 1970
    const storedMs = row.timestamp.getTime();
    expect(storedMs).toBeGreaterThan(beforePublish - 2000);
    expect(storedMs).toBeLessThan(afterPublish + 2000);

    // Raw boot-relative value is preserved unchanged
    expect(row.timestampMs).toBe(BigInt(bootRelativeMs));

    expect(row.timeBasis).toBe("estimated");

    await disconnectClient(client);
    client = null;
  });

  // --- Test 3: timeBasis "relative" - falls back to received_at --------------

  it('should use received_at when timeBasis is "relative"', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-relative");

    const bootRelativeMs = 12345;
    const beforePublish = Date.now();

    await publishScan(client, {
      epc: "E200RELATIVE00000001",
      timestampMs: bootRelativeMs,
      rssiDbm: -70,
      timeBasis: "relative",
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const afterPublish = Date.now();

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    const row = rows[0]!;

    const storedMs = row.timestamp.getTime();
    expect(storedMs).toBeGreaterThan(beforePublish - 2000);
    expect(storedMs).toBeLessThan(afterPublish + 2000);

    expect(row.timestampMs).toBe(BigInt(bootRelativeMs));
    expect(row.timeBasis).toBe("relative");

    await disconnectClient(client);
    client = null;
  });

  // --- Test 4: Missing timeBasis - backward compatibility --------------------

  it('should default to "synced" behavior when timeBasis is absent', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-compat");

    await publishScan(client, {
      epc: "E200COMPAT000000001",
      timestampMs: KNOWN_UNIX_MS,
      rssiDbm: -50,
      // timeBasis intentionally omitted - simulates pre-update firmware
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    const row = rows[0]!;

    // Should be stored without error and treated as synced
    expect(row).toBeDefined();
    expect(row.timeBasis).toBe("synced");

    // Timestamp should match the provided Unix ms value
    const storedMs = row.timestamp.getTime();
    expect(Math.abs(storedMs - KNOWN_UNIX_MS)).toBeLessThan(1000);

    await disconnectClient(client);
    client = null;
  });

  // --- Test 5: Offline replay with timeBasis "synced" ------------------------

  it('should use timestampMs for offline "synced" replay', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-offline-synced");

    const replayTime = Date.now();
    const originalDetectionMs = KNOWN_UNIX_MS; // earlier than replay

    await publishScan(client, {
      epc: "E200OFFLINE_SYNC001",
      timestampMs: originalDetectionMs,
      rssiDbm: -65,
      offline: true,
      replayTime,
      timeBasis: "synced",
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    const row = rows[0]!;

    // timestamp should be the original detection time, not replay time
    const storedMs = row.timestamp.getTime();
    expect(Math.abs(storedMs - originalDetectionMs)).toBeLessThan(1000);

    expect(row.source).toBe("offline_sync");
    expect(row.timeBasis).toBe("synced");

    await disconnectClient(client);
    client = null;
  });

  // --- Test 6: Offline replay with timeBasis "relative" ----------------------

  it('should use received_at for offline "relative" replay', async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-offline-relative");

    const bootRelativeMs = 9999;
    const beforePublish = Date.now();

    await publishScan(client, {
      epc: "E200OFFLINE_REL001",
      timestampMs: bootRelativeMs,
      rssiDbm: -72,
      offline: true,
      replayTime: Date.now(),
      timeBasis: "relative",
    });

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length > 0;
    });

    const afterPublish = Date.now();

    const rows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    const row = rows[0]!;

    const storedMs = row.timestamp.getTime();
    expect(storedMs).toBeGreaterThan(beforePublish - 2000);
    expect(storedMs).toBeLessThan(afterPublish + 2000);

    expect(row.source).toBe("offline_sync");
    expect(row.timeBasis).toBe("relative");

    await disconnectClient(client);
    client = null;
  });

  // --- Test 7: Mixed timeBasis values - no state leakage ---------------------

  it("should handle a batch of mixed timeBasis values independently", async () => {
    const db = getDatabase();
    client = await connectClient("tb-test-mixed");

    const topic = buildScanTopic(TEST_DEVICE_ID);

    const scans = [
      {
        epc: "E200MIX_SYNCED00001",
        timestampMs: KNOWN_UNIX_MS,
        timeBasis: "synced",
      },
      { epc: "E200MIX_ESTIM00001", timestampMs: 55000, timeBasis: "estimated" },
      { epc: "E200MIX_RELAT00001", timestampMs: 77000, timeBasis: "relative" },
    ];

    const beforePublish = Date.now();

    for (const scan of scans) {
      await new Promise<void>((resolve, reject) => {
        client!.publish(topic, JSON.stringify(scan), { qos: 0 }, (err) => {
          if (err) reject(err);
          else resolve();
        });
      });
    }

    await waitFor(async () => {
      const rows = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return rows.length >= scans.length;
    });

    const afterPublish = Date.now();

    const storedRows = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));

    expect(storedRows.length).toBe(scans.length);

    const byEpc = Object.fromEntries(storedRows.map((r) => [r.epc, r]));

    // Synced scan: timestamp should match KNOWN_UNIX_MS
    const syncedRow = byEpc["E200MIX_SYNCED00001"]!;
    expect(syncedRow.timeBasis).toBe("synced");
    expect(
      Math.abs(syncedRow.timestamp.getTime() - KNOWN_UNIX_MS),
    ).toBeLessThan(1000);

    // Estimated scan: timestamp should be approximately now
    const estimatedRow = byEpc["E200MIX_ESTIM00001"]!;
    expect(estimatedRow.timeBasis).toBe("estimated");
    expect(estimatedRow.timestamp.getTime()).toBeGreaterThan(
      beforePublish - 2000,
    );
    expect(estimatedRow.timestamp.getTime()).toBeLessThan(afterPublish + 2000);
    expect(estimatedRow.timestampMs).toBe(BigInt(55000));

    // Relative scan: timestamp should be approximately now
    const relativeRow = byEpc["E200MIX_RELAT00001"]!;
    expect(relativeRow.timeBasis).toBe("relative");
    expect(relativeRow.timestamp.getTime()).toBeGreaterThan(
      beforePublish - 2000,
    );
    expect(relativeRow.timestamp.getTime()).toBeLessThan(afterPublish + 2000);
    expect(relativeRow.timestampMs).toBe(BigInt(77000));

    await disconnectClient(client);
    client = null;
  });
});
