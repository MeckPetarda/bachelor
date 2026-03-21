/**
 * Integration tests for the event processing pipeline.
 *
 * Covers all 10 test cases from the task spec:
 *   1  Basic IN detection
 *   2  Basic OUT detection
 *   3  Misconfigured group
 *   4  Single-lighthouse cluster (insufficient_data)
 *   5  Unsyncable scans
 *   6  Algorithm 2 confidence >= Algorithm 1 when RSSI agrees
 *   7  Algorithm 2 confidence < Algorithm 1 when RSSI contradicts
 *   8  POST /api/v1/events/manual
 *   9  GET /api/v1/events - algorithmId filter
 *  10  GET /api/v1/events/unresolved - orphaned scans
 *
 * Requires a running PostgreSQL instance (uses the standard DATABASE_URL env var).
 * No MQTT broker needed - processCluster and the events API do not use MQTT.
 */

import {
  describe,
  it,
  expect,
  beforeAll,
  afterAll,
  beforeEach,
} from "bun:test";
import { app } from "../src/api/routes";
import {
  initDatabase,
  closeDatabase,
  getDatabase,
  schema,
} from "../src/database/client";
import { eq, inArray } from "drizzle-orm";
import { processCluster } from "../src/services/event-processor";
import type { ScanData } from "../src/services/algorithms/types";

// --- Test fixture constants ---------------------------------------------------
// IDs chosen to avoid collisions with other test files (997, 998, 999, 1).

const TEST_OUTSIDE_LH_ID = 991;
const TEST_INSIDE_LH_ID = 992;
const TEST_MISC_LH_ID_A = 993; // both INSIDE for misconfigured-group tests
const TEST_MISC_LH_ID_B = 994;

const TEST_EPC = "EPROC_TEST_EP000001";

// Arbitrary fixed base time; offsets are added per-scan.
const BASE_MS = new Date("2025-01-15T10:00:00Z").getTime();

// Populated in beforeAll after the DB insert returns the generated IDs.
let testGroupId: number;
let miscGroupId: number;

// --- Helpers ------------------------------------------------------------------

type Database = ReturnType<typeof getDatabase>;

/**
 * Insert raw_scans rows and return them as ScanData so they can be passed
 * directly to processCluster.
 */
async function insertScans(
  db: Database,
  specs: Array<{
    lighthouseId: number;
    epc?: string;
    timestampOffsetMs: number;
    timeBasis?: "synced" | "estimated" | "relative";
    rssiDbm?: number;
  }>,
): Promise<ScanData[]> {
  const rows = await db
    .insert(schema.rawScans)
    .values(
      specs.map((s) => {
        const ts = new Date(BASE_MS + s.timestampOffsetMs);
        return {
          lighthouseId: s.lighthouseId,
          epc: s.epc ?? TEST_EPC,
          timestamp: ts,
          timeBasis: (s.timeBasis ?? "synced") as
            | "synced"
            | "estimated"
            | "relative",
          timestampMs: BigInt(ts.getTime()),
          source: "realtime" as const,
          rssiDbm: s.rssiDbm ?? null,
        };
      }),
    )
    .returning();

  return rows.map((r) => ({
    id: r.id,
    lighthouseId: r.lighthouseId,
    epc: r.epc,
    rssiDbm: r.rssiDbm ?? null,
    timestamp: r.timestamp,
    timeBasis: r.timeBasis,
  }));
}

/** IDs of all four test lighthouses. */
const ALL_TEST_LH_IDS = [
  TEST_OUTSIDE_LH_ID,
  TEST_INSIDE_LH_ID,
  TEST_MISC_LH_ID_A,
  TEST_MISC_LH_ID_B,
];

// --- Suite lifecycle ----------------------------------------------------------

describe("Event Processing Pipeline", () => {
  beforeAll(async () => {
    initDatabase();
    const db = getDatabase();

    // Insert the two test groups and capture their generated IDs.
    const [good] = await db
      .insert(schema.lighthouseGroups)
      .values({
        label: "EP Test Group - Good",
        activityTimeoutMs: 4000,
        orphanTimeoutMs: 8000,
      })
      .returning({ id: schema.lighthouseGroups.id });
    testGroupId = good!.id;

    const [bad] = await db
      .insert(schema.lighthouseGroups)
      .values({
        label: "EP Test Group - Misconfigured",
        activityTimeoutMs: 4000,
        orphanTimeoutMs: 8000,
      })
      .returning({ id: schema.lighthouseGroups.id });
    miscGroupId = bad!.id;

    // Insert test lighthouses.
    await db.insert(schema.lighthouses).values([
      {
        id: TEST_OUTSIDE_LH_ID,
        name: "EP Test LH Outside",
        deviceId: "EP:00:00:00:00:01",
        placement: "OUTSIDE",
        groupId: testGroupId,
        isActive: true,
      },
      {
        id: TEST_INSIDE_LH_ID,
        name: "EP Test LH Inside",
        deviceId: "EP:00:00:00:00:02",
        placement: "INSIDE",
        groupId: testGroupId,
        isActive: true,
      },
      {
        id: TEST_MISC_LH_ID_A,
        name: "EP Test LH Misc A",
        deviceId: "EP:00:00:00:00:03",
        placement: "INSIDE",
        groupId: miscGroupId,
        isActive: true,
      },
      {
        id: TEST_MISC_LH_ID_B,
        name: "EP Test LH Misc B",
        deviceId: "EP:00:00:00:00:04",
        placement: "INSIDE",
        groupId: miscGroupId,
        isActive: true,
      },
    ]);
  });

  afterAll(async () => {
    const db = getDatabase();

    // processedEventScans CASCADE-deleted when processedEvents rows are removed.
    await db
      .delete(schema.processedEvents)
      .where(
        inArray(schema.processedEvents.groupId, [testGroupId, miscGroupId]),
      );

    await db
      .delete(schema.rawScans)
      .where(inArray(schema.rawScans.lighthouseId, ALL_TEST_LH_IDS));

    // Lighthouses must be deleted before groups (FK: lighthouse.groupId -> groups.id).
    await db
      .delete(schema.lighthouses)
      .where(inArray(schema.lighthouses.id, ALL_TEST_LH_IDS));

    await db
      .delete(schema.lighthouseGroups)
      .where(inArray(schema.lighthouseGroups.id, [testGroupId, miscGroupId]));

    await closeDatabase();
  });

  beforeEach(async () => {
    const db = getDatabase();

    // processedEventScans are cascade-deleted with their parent processedEvents.
    await db
      .delete(schema.processedEvents)
      .where(
        inArray(schema.processedEvents.groupId, [testGroupId, miscGroupId]),
      );

    await db
      .delete(schema.rawScans)
      .where(inArray(schema.rawScans.lighthouseId, ALL_TEST_LH_IDS));
  });

  // --- Test 1: Basic IN detection ---------------------------------------------

  it("1. detects IN direction when outside scans precede inside scans", async () => {
    const db = getDatabase();

    // 5 outside scans (1000-3000 ms) then 5 inside scans (3000-5000 ms).
    const scans = await insertScans(db, [
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 1000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 1500 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 2000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 2500 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 3500 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 4000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 4500 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 5000 },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(true);

    // Both algorithm rows should be direction "in" with positive confidence.
    const events = await db
      .select()
      .from(schema.processedEvents)
      .where(eq(schema.processedEvents.tagEpc, TEST_EPC));

    expect(events.length).toBe(2);
    for (const ev of events) {
      expect(ev.direction).toBe("in");
      expect(ev.confidence).toBeGreaterThan(0);
      expect(ev.centroidSeparationFactor).toBeGreaterThan(0);
      expect(ev.clusterSizeFactor).toBeGreaterThan(0);
      expect(ev.bilateralCoverageFactor).toBeGreaterThan(0);
    }

    // Junction table: 10 scans * 2 events = 20 rows.
    const scanIds = scans.map((s) => s.id);
    const junction = await db
      .select()
      .from(schema.processedEventScans)
      .where(inArray(schema.processedEventScans.rawScanId, scanIds));
    expect(junction.length).toBe(20);

    // Every scan should now have processedAt set.
    const updated = await db
      .select({ processedAt: schema.rawScans.processedAt })
      .from(schema.rawScans)
      .where(inArray(schema.rawScans.id, scanIds));
    for (const row of updated) {
      expect(row.processedAt).not.toBeNull();
    }
  });

  // --- Test 2: Basic OUT detection --------------------------------------------

  it("2. detects OUT direction when inside scans precede outside scans", async () => {
    const db = getDatabase();

    // Inside earlier -> OUT direction.
    const scans = await insertScans(db, [
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 1000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 1500 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 2000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 2500 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 3500 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 4000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 4500 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 5000 },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(true);

    const events = await db
      .select()
      .from(schema.processedEvents)
      .where(eq(schema.processedEvents.tagEpc, TEST_EPC));

    expect(events.length).toBe(2);
    for (const ev of events) {
      expect(ev.direction).toBe("out");
    }
  });

  // --- Test 3: Misconfigured group ---------------------------------------------

  it("3. returns misconfigured_group when group has no OUTSIDE lighthouse", async () => {
    const db = getDatabase();

    const scans = await insertScans(db, [
      { lighthouseId: TEST_MISC_LH_ID_A, timestampOffsetMs: 1000 },
      { lighthouseId: TEST_MISC_LH_ID_A, timestampOffsetMs: 2000 },
      { lighthouseId: TEST_MISC_LH_ID_B, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_MISC_LH_ID_B, timestampOffsetMs: 4000 },
    ]);

    const result = await processCluster(scans, miscGroupId, TEST_EPC);
    expect(result.processed).toBe(false);
    if (!result.processed) {
      expect(result.reason).toBe("misconfigured_group");
    }
  });

  // --- Test 4: Single-lighthouse cluster -> insufficient_data ------------------

  it("4. returns insufficient_data when only one side has scans", async () => {
    const db = getDatabase();

    // Only OUTSIDE scans; no INSIDE scans in this cluster.
    const scans = await insertScans(db, [
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 1000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 2000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 3000 },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(false);
    if (!result.processed) {
      expect(result.reason).toBe("insufficient_data");
    }
  });

  // --- Test 5: Unsyncable scans ------------------------------------------------

  it("5. returns unsyncable when all scans have non-synced timeBasis", async () => {
    const db = getDatabase();

    const scans = await insertScans(db, [
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 1000,
        timeBasis: "estimated",
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 2000,
        timeBasis: "estimated",
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 3000,
        timeBasis: "estimated",
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 4000,
        timeBasis: "estimated",
      },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(false);
    if (!result.processed) {
      expect(result.reason).toBe("unsyncable");
    }
  });

  // --- Test 6: RSSI agreement boosts Algorithm 2 confidence ------------------

  it("6. Algorithm 2 confidence >= Algorithm 1 when RSSI trend agrees with direction", async () => {
    const db = getDatabase();

    // Outside scans: early timestamps + falling RSSI (-50 -> -80).
    //   High-weight scans are early -> weighted outside centroid pulled earlier.
    //   Slope < 0 = expected for "in" direction (weakening as person leaves).
    //
    // Inside scans: late timestamps + rising RSSI (-80 -> -50).
    //   High-weight scans are late -> weighted inside centroid pulled later.
    //   Slope > 0 = expected for "in" direction (strengthening as person enters).
    //
    // Both trends agree -> rssiTrendConsistencyFactor = 1.0.
    // Weighted centroid separation > unweighted -> algo2 CSF > algo1 CSF.
    const scans = await insertScans(db, [
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 1000,
        rssiDbm: -50,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 1500,
        rssiDbm: -57,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 2000,
        rssiDbm: -65,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 2500,
        rssiDbm: -72,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 3000,
        rssiDbm: -80,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 3000,
        rssiDbm: -80,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 3500,
        rssiDbm: -72,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 4000,
        rssiDbm: -65,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 4500,
        rssiDbm: -57,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 5000,
        rssiDbm: -50,
      },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(true);

    const events = await db
      .select()
      .from(schema.processedEvents)
      .where(eq(schema.processedEvents.tagEpc, TEST_EPC));

    const algo1 = events.find((e) => e.algorithmId === "temporal_centroid")!;
    const algo2 = events.find(
      (e) => e.algorithmId === "rssi_weighted_centroid",
    )!;

    expect(algo1).toBeDefined();
    expect(algo2).toBeDefined();
    expect(algo2.rssiTrendConsistencyFactor).not.toBeNull();
    // Trend agreement should not hurt confidence.
    expect(algo2.confidence).toBeGreaterThanOrEqual(algo1.confidence);
  });

  // --- Test 7: RSSI contradiction degrades Algorithm 2 confidence -------------

  it("7. Algorithm 2 confidence < Algorithm 1 when RSSI trend contradicts direction", async () => {
    const db = getDatabase();

    // Outside scans: early timestamps + RISING RSSI (-80 -> -50).
    //   Slope > 0 = expects exit (weakening), but temporal says "in". CONTRADICTS.
    //
    // Inside scans: late timestamps + FALLING RSSI (-50 -> -80).
    //   Slope < 0 = expects entry (strengthening), but temporal says "in". CONTRADICTS.
    //
    // Both contradict -> rssiTrendConsistencyFactor = CONFIDENCE_FACTOR_FLOOR.
    // Weighted centroid separation < unweighted -> algo2 CSF < algo1 CSF.
    const scans = await insertScans(db, [
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 1000,
        rssiDbm: -80,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 1500,
        rssiDbm: -72,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 2000,
        rssiDbm: -65,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 2500,
        rssiDbm: -57,
      },
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        timestampOffsetMs: 3000,
        rssiDbm: -50,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 3000,
        rssiDbm: -50,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 3500,
        rssiDbm: -57,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 4000,
        rssiDbm: -65,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 4500,
        rssiDbm: -72,
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        timestampOffsetMs: 5000,
        rssiDbm: -80,
      },
    ]);

    const result = await processCluster(scans, testGroupId, TEST_EPC);
    expect(result.processed).toBe(true);

    const events = await db
      .select()
      .from(schema.processedEvents)
      .where(eq(schema.processedEvents.tagEpc, TEST_EPC));

    const algo1 = events.find((e) => e.algorithmId === "temporal_centroid")!;
    const algo2 = events.find(
      (e) => e.algorithmId === "rssi_weighted_centroid",
    )!;

    expect(algo1).toBeDefined();
    expect(algo2).toBeDefined();
    // RSSI contradiction must reduce algo2's confidence below algo1's.
    expect(algo2.confidence).toBeLessThan(algo1.confidence);
  });

  // --- Test 8: Manual event creation ------------------------------------------

  it("8. POST /api/v1/events/manual creates event with all confidence factors = 1.0", async () => {
    const res = await app.request("/api/v1/events/manual", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tagEpc: TEST_EPC,
        direction: "in",
        timestamp: new Date(BASE_MS).toISOString(),
        groupId: testGroupId,
        notes: "test manual entry",
      }),
    });

    expect(res.status).toBe(201);

    const body = (await res.json()) as Record<string, unknown>;
    expect(body.algorithmId).toBe("manual");
    expect(body.direction).toBe("in");
    expect(body.confidence).toBe(1.0);
    expect(body.centroidSeparationFactor).toBe(1.0);
    expect(body.clusterSizeFactor).toBe(1.0);
    expect(body.bilateralCoverageFactor).toBe(1.0);
    expect(body.rssiTrendConsistencyFactor).toBeNull();
    expect(body.id).toBeDefined();
    expect(typeof body.id).toBe("string");
  });

  // --- Test 9: Events API filtering by algorithmId ----------------------------

  it("9. GET /api/v1/events filters correctly by algorithmId", async () => {
    const db = getDatabase();

    // processCluster inserts one row per algorithm (temporal + rssi_weighted).
    const scans = await insertScans(db, [
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 1000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 2000 },
      { lighthouseId: TEST_OUTSIDE_LH_ID, timestampOffsetMs: 3000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 4000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 5000 },
      { lighthouseId: TEST_INSIDE_LH_ID, timestampOffsetMs: 6000 },
    ]);
    await processCluster(scans, testGroupId, TEST_EPC);

    // - Filter: temporal_centroid only ---------------------------------------
    const res1 = await app.request(
      `/api/v1/events?algorithmId=temporal_centroid&groupId=${testGroupId}`,
    );
    expect(res1.status).toBe(200);
    const body1 = (await res1.json()) as {
      data: Array<{ algorithmId: string }>;
      count: number;
    };
    expect(body1.data.length).toBeGreaterThan(0);
    for (const ev of body1.data) {
      expect(ev.algorithmId).toBe("temporal_centroid");
    }

    // - Filter: rssi_weighted_centroid only ----------------------------------
    const res2 = await app.request(
      `/api/v1/events?algorithmId=rssi_weighted_centroid&groupId=${testGroupId}`,
    );
    expect(res2.status).toBe(200);
    const body2 = (await res2.json()) as {
      data: Array<{ algorithmId: string }>;
    };
    expect(body2.data.length).toBeGreaterThan(0);
    for (const ev of body2.data) {
      expect(ev.algorithmId).toBe("rssi_weighted_centroid");
    }

    // - Missing algorithmId -> 400 --------------------------------------------
    const res3 = await app.request("/api/v1/events");
    expect(res3.status).toBe(400);
  });

  // --- Test 10: Unresolved events API -----------------------------------------

  it("10. GET /api/v1/events/unresolved returns orphaned scans with correct reasons", async () => {
    const db = getDatabase();
    const now = new Date();

    // Insert two orphaned raw scans with different reasons.
    await db.insert(schema.rawScans).values([
      {
        lighthouseId: TEST_OUTSIDE_LH_ID,
        epc: TEST_EPC,
        timestamp: new Date(BASE_MS + 1000),
        timeBasis: "synced",
        timestampMs: BigInt(BASE_MS + 1000),
        source: "realtime",
        orphanedAt: now,
        orphanReason: "insufficient_data",
      },
      {
        lighthouseId: TEST_INSIDE_LH_ID,
        epc: TEST_EPC,
        timestamp: new Date(BASE_MS + 2000),
        timeBasis: "synced",
        timestampMs: BigInt(BASE_MS + 2000),
        source: "realtime",
        orphanedAt: now,
        orphanReason: "misconfigured_group",
      },
    ]);

    const res = await app.request(
      `/api/v1/events/unresolved?groupId=${testGroupId}`,
    );
    expect(res.status).toBe(200);

    const body = (await res.json()) as {
      data: Array<{
        scanId: string;
        epc: string;
        lighthouseId: number;
        lighthouseName: string;
        orphanReason: string;
        orphanedAt: string;
      }>;
      count: number;
    };

    expect(body.data.length).toBe(2);

    const reasons = body.data.map((d) => d.orphanReason).sort();
    expect(reasons).toContain("insufficient_data");
    expect(reasons).toContain("misconfigured_group");

    for (const item of body.data) {
      expect(item.epc).toBe(TEST_EPC);
      expect(item.lighthouseName).toBeDefined();
      expect(typeof item.scanId).toBe("string"); // bigint serialised as string
      expect(item.orphanedAt).toBeDefined();
    }
  });
});
