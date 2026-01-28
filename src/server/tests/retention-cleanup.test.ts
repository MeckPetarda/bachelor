import { describe, it, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { initDatabase, closeDatabase, getDatabase, schema } from "../src/database/client";
import { eq } from "drizzle-orm";
import {
  cleanupOldHealthSnapshots,
  cleanupOldConnectionEvents,
} from "../src/database/cleanup";

// Test configuration
const TEST_LIGHTHOUSE_ID = 998;
const TEST_DEVICE_ID = "AA:BB:CC:DD:EE:02";

// Helper to create a date in the past
function daysAgo(days: number): Date {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return date;
}

describe("Retention Cleanup", () => {
  beforeAll(async () => {
    // Initialize database
    initDatabase();
    const db = getDatabase();

    // Create test lighthouse if it doesn't exist
    const existing = await db
      .select()
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, TEST_DEVICE_ID))
      .limit(1);

    if (existing.length === 0) {
      await db.insert(schema.lighthouses).values({
        id: TEST_LIGHTHOUSE_ID,
        name: "Retention Test Lighthouse",
        deviceId: TEST_DEVICE_ID,
        placement: "STANDALONE",
        isActive: true,
      });
    }
  });

  afterAll(async () => {
    // Clean up test data
    const db = getDatabase();
    await db
      .delete(schema.lighthouseHealthSnapshots)
      .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID));
    await db
      .delete(schema.lighthouseConnectionEvents)
      .where(eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID));

    // Close database
    await closeDatabase();
  });

  beforeEach(async () => {
    // Clean up any data from previous tests
    const db = getDatabase();
    await db
      .delete(schema.lighthouseHealthSnapshots)
      .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID));
    await db
      .delete(schema.lighthouseConnectionEvents)
      .where(eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID));
  });

  it("should delete health snapshots older than retention period", async () => {
    const db = getDatabase();

    // Insert old health snapshot (10 days old, default retention is 7 days)
    await db.insert(schema.lighthouseHealthSnapshots).values({
      lighthouseId: TEST_LIGHTHOUSE_ID,
      uptimeSec: 1000,
      freeHeapBytes: 50000,
      minFreeHeapBytes: 45000,
      wifiRssiDbm: -50,
      rfidState: "READY",
      rfidIsResponsive: true,
      rfidPowerRailPresent: true,
      rfidFwVersion: "1.0",
      rfidLastError: 0,
      recordedAt: daysAgo(10),
    });

    // Verify it was inserted
    const beforeCleanup = await db
      .select()
      .from(schema.lighthouseHealthSnapshots)
      .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(beforeCleanup.length).toBe(1);

    // Run cleanup
    const deletedCount = await cleanupOldHealthSnapshots();
    expect(deletedCount).toBe(1);

    // Verify it was deleted
    const afterCleanup = await db
      .select()
      .from(schema.lighthouseHealthSnapshots)
      .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(afterCleanup.length).toBe(0);
  });

  it("should preserve health snapshots within retention period", async () => {
    const db = getDatabase();

    // Insert recent health snapshot (2 days old, within default 7 day retention)
    await db.insert(schema.lighthouseHealthSnapshots).values({
      lighthouseId: TEST_LIGHTHOUSE_ID,
      uptimeSec: 2000,
      freeHeapBytes: 48000,
      minFreeHeapBytes: 43000,
      wifiRssiDbm: -55,
      rfidState: "IDLE",
      rfidIsResponsive: true,
      rfidPowerRailPresent: true,
      rfidFwVersion: "1.1",
      rfidLastError: 0,
      recordedAt: daysAgo(2),
    });

    // Run cleanup
    const deletedCount = await cleanupOldHealthSnapshots();
    expect(deletedCount).toBe(0);

    // Verify it was preserved
    const afterCleanup = await db
      .select()
      .from(schema.lighthouseHealthSnapshots)
      .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(afterCleanup.length).toBe(1);
  });

  it("should delete connection events older than retention period", async () => {
    const db = getDatabase();

    // Insert old connection event (35 days old, default retention is 30 days)
    await db.insert(schema.lighthouseConnectionEvents).values({
      lighthouseId: TEST_LIGHTHOUSE_ID,
      eventType: "connected",
      isGraceful: null,
      recordedAt: daysAgo(35),
    });

    // Verify it was inserted
    const beforeCleanup = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(beforeCleanup.length).toBe(1);

    // Run cleanup
    const deletedCount = await cleanupOldConnectionEvents();
    expect(deletedCount).toBe(1);

    // Verify it was deleted
    const afterCleanup = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(afterCleanup.length).toBe(0);
  });

  it("should preserve connection events within retention period", async () => {
    const db = getDatabase();

    // Insert recent connection event (10 days old, within default 30 day retention)
    await db.insert(schema.lighthouseConnectionEvents).values({
      lighthouseId: TEST_LIGHTHOUSE_ID,
      eventType: "disconnected",
      isGraceful: true,
      recordedAt: daysAgo(10),
    });

    // Run cleanup
    const deletedCount = await cleanupOldConnectionEvents();
    expect(deletedCount).toBe(0);

    // Verify it was preserved
    const afterCleanup = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID));
    expect(afterCleanup.length).toBe(1);
  });

  it("should handle empty tables gracefully", async () => {
    // Run cleanup on empty tables
    const healthDeleted = await cleanupOldHealthSnapshots();
    const connectionDeleted = await cleanupOldConnectionEvents();

    expect(healthDeleted).toBe(0);
    expect(connectionDeleted).toBe(0);
  });
});
