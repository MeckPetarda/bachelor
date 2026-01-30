import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from "bun:test";
import { app } from "../src/api/routes";
import { initDatabase, closeDatabase, getDatabase, schema } from "../src/database/client";
import { startMqttBroker, closeMqttBroker } from "../src/mqtt/broker";
import { createJWT } from "../src/api/middleware";
import { getConfig } from "../src/config";
import { eq, and } from "drizzle-orm";
import {
  setLighthouseConnected,
  updateLighthouseHealth,
  clearAllStates,
  type HealthPayload,
} from "../src/mqtt/state";

// Test configuration
const TEST_GROUP_LABEL = "Test Group";
const TEST_LIGHTHOUSE_NAME = "Test Dashboard Lighthouse";
const TEST_DEVICE_ID = "AA:BB:CC:DD:EE:FF";
const TEST_PENDING_DEVICE_ID = "11:22:33:44:55:66";
const TEST_USERNAME = "testdashboardadmin";
const TEST_PASSWORD = "testpassword123";

let authToken: string;
let testGroupId: number;
let testLighthouseId: number;

describe("Dashboard API Endpoints", () => {
  beforeAll(async () => {
    // Initialize database and MQTT broker
    initDatabase();
    startMqttBroker();

    // Wait for broker to be ready
    await new Promise((resolve) => setTimeout(resolve, 500));

    const db = getDatabase();
    const config = getConfig();

    // Create test admin user if it doesn't exist
    const existingUser = await db
      .select()
      .from(schema.dashboardUsers)
      .where(eq(schema.dashboardUsers.username, TEST_USERNAME))
      .limit(1);

    if (existingUser.length === 0) {
      const hashedPassword = await Bun.password.hash(TEST_PASSWORD);
      await db.insert(schema.dashboardUsers).values({
        username: TEST_USERNAME,
        passwordHash: hashedPassword,
        role: "STANDALONE",
        isActive: true,
      });
    }

    // Create auth token for protected route tests
    authToken = await createJWT(
      { sub: "test-user-id", username: TEST_USERNAME, role: "STANDALONE" },
      config.jwt.secret,
      "1h"
    );
  });

  afterAll(async () => {
    const db = getDatabase();

    // Clean up test data (including all test lighthouses)
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, TEST_LIGHTHOUSE_NAME));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, "Group Member 1"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, "Group Member 2"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "XX:XX:XX:XX:XX:XX"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "G1:G1:G1:G1:G1:G1"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "G2:G2:G2:G2:G2:G2"));

    await db
      .delete(schema.lighthouseGroups)
      .where(eq(schema.lighthouseGroups.label, TEST_GROUP_LABEL));

    await db
      .delete(schema.dashboardUsers)
      .where(eq(schema.dashboardUsers.username, TEST_USERNAME));

    // Clear runtime state
    clearAllStates();

    // Close services
    await closeMqttBroker();
    await closeDatabase();
  });

  beforeEach(async () => {
    // Clean up test data before each test
    const db = getDatabase();

    // Delete test lighthouses (including group members created in some tests)
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, TEST_LIGHTHOUSE_NAME));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, "Group Member 1"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.name, "Group Member 2"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "XX:XX:XX:XX:XX:XX"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "G1:G1:G1:G1:G1:G1"));
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, "G2:G2:G2:G2:G2:G2"));

    // Delete test groups
    await db
      .delete(schema.lighthouseGroups)
      .where(eq(schema.lighthouseGroups.label, TEST_GROUP_LABEL));

    // Clear runtime state
    clearAllStates();
  });

  // ============================================================================
  // Pending Devices Tests
  // ============================================================================

  describe("GET /api/v1/devices/pending", () => {
    it("should return empty list when no pending devices", async () => {
      const res = await app.request("/api/v1/devices/pending");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data).toEqual([]);
      expect(body.count).toBe(0);
    });

    it("should return pending devices from runtime state", async () => {
      // Add a pending device to runtime state
      setLighthouseConnected(TEST_PENDING_DEVICE_ID, false);

      const res = await app.request("/api/v1/devices/pending");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.count).toBe(1);
      expect(body.data[0].deviceId).toBe(TEST_PENDING_DEVICE_ID.toUpperCase());
      expect(body.data[0].isConnected).toBe(true);
      expect(body.data[0].firstSeenAt).toBeDefined();
    });

    it("should include health data for pending devices", async () => {
      // Add a pending device with health data
      const healthPayload: HealthPayload = {
        uptimeSec: 3600,
        freeHeapBytes: 180000,
        minFreeHeapBytes: 150000,
        wifiRssiDbm: -55,
        rfid: {
          state: "IDLE",
          isResponsive: true,
          powerRailPresent: true,
          fwVersion: "1.0.0",
          lastError: 0,
        },
      };
      updateLighthouseHealth(TEST_PENDING_DEVICE_ID, healthPayload, false);

      const res = await app.request("/api/v1/devices/pending");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data[0].health).toBeDefined();
      expect(body.data[0].health.uptimeSec).toBe(3600);
      expect(body.data[0].health.wifiRssiDbm).toBe(-55);
      expect(body.data[0].health.rfidState).toBe("IDLE");
    });
  });

  describe("POST /api/v1/devices/pending/:deviceId/claim", () => {
    it("should return 404 for non-existent pending device", async () => {
      const res = await app.request("/api/v1/devices/pending/XX:XX:XX:XX:XX:XX/claim", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: TEST_LIGHTHOUSE_NAME,
          placement: "STANDALONE",
        }),
      });

      expect(res.status).toBe(404);
      const body = await res.json();
      expect(body.error).toContain("not found");
    });

    it("should return 400 for missing required fields", async () => {
      // Add a pending device
      setLighthouseConnected(TEST_PENDING_DEVICE_ID, false);

      const res = await app.request(`/api/v1/devices/pending/${TEST_PENDING_DEVICE_ID}/claim`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });

      expect(res.status).toBe(400);
    });

    it("should claim a pending device successfully", async () => {
      // Add a pending device
      setLighthouseConnected(TEST_PENDING_DEVICE_ID, false);

      const res = await app.request(`/api/v1/devices/pending/${TEST_PENDING_DEVICE_ID}/claim`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: TEST_LIGHTHOUSE_NAME,
          label: "Test Label",
          placement: "INSIDE",
        }),
      });

      expect(res.status).toBe(201);

      const body = await res.json();
      expect(body.data.name).toBe(TEST_LIGHTHOUSE_NAME);
      expect(body.data.deviceId).toBe(TEST_PENDING_DEVICE_ID.toUpperCase());
      expect(body.data.placement).toBe("INSIDE");

      // Verify device is no longer in pending state
      const pendingRes = await app.request("/api/v1/devices/pending");
      const pendingBody = await pendingRes.json();
      expect(pendingBody.count).toBe(0);
    });

    it("should reject duplicate name", async () => {
      const db = getDatabase();

      // Create existing lighthouse
      await db.insert(schema.lighthouses).values({
        name: TEST_LIGHTHOUSE_NAME,
        deviceId: "XX:XX:XX:XX:XX:XX",
        placement: "STANDALONE",
      });

      // Add a pending device
      setLighthouseConnected(TEST_PENDING_DEVICE_ID, false);

      const res = await app.request(`/api/v1/devices/pending/${TEST_PENDING_DEVICE_ID}/claim`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: TEST_LIGHTHOUSE_NAME,
          placement: "STANDALONE",
        }),
      });

      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error).toContain("name already exists");
    });

    it("should reject if group has 2 members", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      // Add 2 lighthouses to the group
      await db.insert(schema.lighthouses).values([
        { name: "Group Member 1", deviceId: "G1:G1:G1:G1:G1:G1", placement: "INSIDE", groupId },
        { name: "Group Member 2", deviceId: "G2:G2:G2:G2:G2:G2", placement: "OUTSIDE", groupId },
      ]);

      // Add a pending device
      setLighthouseConnected(TEST_PENDING_DEVICE_ID, false);

      const res = await app.request(`/api/v1/devices/pending/${TEST_PENDING_DEVICE_ID}/claim`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: TEST_LIGHTHOUSE_NAME,
          placement: "STANDALONE",
          groupId,
        }),
      });

      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error).toContain("2 members");
    });
  });

  // ============================================================================
  // Groups Tests
  // ============================================================================

  describe("GET /api/v1/groups", () => {
    it("should return empty list when no groups", async () => {
      const res = await app.request("/api/v1/groups");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(Array.isArray(body.data)).toBe(true);
    });

    it("should return groups with members", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL, description: "Test Description" })
        .returning();
      const groupId = groupResult[0].id;

      // Add a lighthouse to the group
      await db.insert(schema.lighthouses).values({
        name: TEST_LIGHTHOUSE_NAME,
        deviceId: TEST_DEVICE_ID,
        placement: "INSIDE",
        groupId,
      });

      const res = await app.request("/api/v1/groups");
      expect(res.status).toBe(200);

      const body = await res.json();
      const testGroup = body.data.find((g: { label: string }) => g.label === TEST_GROUP_LABEL);
      expect(testGroup).toBeDefined();
      expect(testGroup.description).toBe("Test Description");
      expect(testGroup.members.length).toBe(1);
      expect(testGroup.members[0].name).toBe(TEST_LIGHTHOUSE_NAME);
    });
  });

  describe("POST /api/v1/groups", () => {
    it("should create a new group", async () => {
      const res = await app.request("/api/v1/groups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: TEST_GROUP_LABEL,
          description: "Test Description",
        }),
      });

      expect(res.status).toBe(201);

      const body = await res.json();
      expect(body.data.label).toBe(TEST_GROUP_LABEL);
      expect(body.data.description).toBe("Test Description");
      expect(body.data.members).toEqual([]);
    });

    it("should reject missing label", async () => {
      const res = await app.request("/api/v1/groups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });

      expect(res.status).toBe(400);
    });
  });

  describe("GET /api/v1/groups/:id", () => {
    it("should return 404 for non-existent group", async () => {
      const res = await app.request("/api/v1/groups/99999");
      expect(res.status).toBe(404);
    });

    it("should return group by ID", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      const res = await app.request(`/api/v1/groups/${groupId}`);
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.id).toBe(groupId);
      expect(body.data.label).toBe(TEST_GROUP_LABEL);
    });
  });

  describe("PATCH /api/v1/groups/:id", () => {
    it("should update group", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      const res = await app.request(`/api/v1/groups/${groupId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: "Updated Label",
          description: "New Description",
        }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.label).toBe("Updated Label");
      expect(body.data.description).toBe("New Description");
    });

    it("should reject empty label", async () => {
      const db = getDatabase();

      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();

      const res = await app.request(`/api/v1/groups/${groupResult[0].id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ label: "" }),
      });

      expect(res.status).toBe(400);
    });
  });

  describe("DELETE /api/v1/groups/:id", () => {
    it("should delete group", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      const res = await app.request(`/api/v1/groups/${groupId}`, {
        method: "DELETE",
      });

      expect(res.status).toBe(204);

      // Verify group is deleted
      const checkRes = await app.request(`/api/v1/groups/${groupId}`);
      expect(checkRes.status).toBe(404);
    });

    it("should set lighthouse groupId to null on delete", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      // Add a lighthouse to the group
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
          groupId,
        })
        .returning();

      // Delete the group
      await app.request(`/api/v1/groups/${groupId}`, { method: "DELETE" });

      // Check lighthouse groupId is null
      const lighthouse = await db
        .select()
        .from(schema.lighthouses)
        .where(eq(schema.lighthouses.id, lhResult[0].id))
        .limit(1);

      expect(lighthouse[0].groupId).toBeNull();
    });
  });

  // ============================================================================
  // Lighthouses with Runtime Status Tests
  // ============================================================================

  describe("GET /api/v1/lighthouses/all", () => {
    it("should return lighthouses with runtime status", async () => {
      const db = getDatabase();

      // Create a lighthouse
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
        })
        .returning();

      // Set runtime state
      setLighthouseConnected(TEST_DEVICE_ID, true);

      const healthPayload: HealthPayload = {
        uptimeSec: 7200,
        freeHeapBytes: 200000,
        minFreeHeapBytes: 180000,
        wifiRssiDbm: -45,
        rfid: {
          state: "READING",
          isResponsive: true,
          powerRailPresent: true,
          fwVersion: "1.0.0",
          lastError: 0,
        },
      };
      updateLighthouseHealth(TEST_DEVICE_ID, healthPayload, true);

      const res = await app.request("/api/v1/lighthouses/all");
      expect(res.status).toBe(200);

      const body = await res.json();
      const testLighthouse = body.data.find((lh: { name: string }) => lh.name === TEST_LIGHTHOUSE_NAME);
      expect(testLighthouse).toBeDefined();
      expect(testLighthouse.runtime).toBeDefined();
      expect(testLighthouse.runtime.isConnected).toBe(true);
      expect(testLighthouse.runtime.health.uptimeSec).toBe(7200);
    });

    it("should include group info", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();

      // Create a lighthouse in the group
      await db.insert(schema.lighthouses).values({
        name: TEST_LIGHTHOUSE_NAME,
        deviceId: TEST_DEVICE_ID,
        placement: "INSIDE",
        groupId: groupResult[0].id,
      });

      const res = await app.request("/api/v1/lighthouses/all");
      expect(res.status).toBe(200);

      const body = await res.json();
      const testLighthouse = body.data.find((lh: { name: string }) => lh.name === TEST_LIGHTHOUSE_NAME);
      expect(testLighthouse.group).toBeDefined();
      expect(testLighthouse.group.label).toBe(TEST_GROUP_LABEL);
    });
  });

  describe("PATCH /api/v1/lighthouses/:id/update", () => {
    it("should update lighthouse with groupId", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();

      // Create a lighthouse
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
        })
        .returning();

      const res = await app.request(`/api/v1/lighthouses/${lhResult[0].id}/update`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          groupId: groupResult[0].id,
          placement: "INSIDE",
        }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.groupId).toBe(groupResult[0].id);
      expect(body.data.placement).toBe("INSIDE");
    });

    it("should remove from group with null groupId", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();

      // Create a lighthouse in the group
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "INSIDE",
          groupId: groupResult[0].id,
        })
        .returning();

      const res = await app.request(`/api/v1/lighthouses/${lhResult[0].id}/update`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ groupId: null }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.groupId).toBeNull();
    });

    it("should reject if group has 2 members", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();
      const groupId = groupResult[0].id;

      // Add 2 lighthouses to the group
      await db.insert(schema.lighthouses).values([
        { name: "Group Member 1", deviceId: "G1:G1:G1:G1:G1:G1", placement: "INSIDE", groupId },
        { name: "Group Member 2", deviceId: "G2:G2:G2:G2:G2:G2", placement: "OUTSIDE", groupId },
      ]);

      // Create a lighthouse not in the group
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
        })
        .returning();

      const res = await app.request(`/api/v1/lighthouses/${lhResult[0].id}/update`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ groupId }),
      });

      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error).toContain("2 members");
    });
  });

  // ============================================================================
  // Scans Tests
  // ============================================================================

  describe("GET /api/v1/scans", () => {
    beforeEach(async () => {
      const db = getDatabase();

      // Create a lighthouse
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
        })
        .returning();
      testLighthouseId = lhResult[0].id;

      // Insert some test scans
      const now = new Date();
      await db.insert(schema.rawScans).values([
        {
          lighthouseId: testLighthouseId,
          epc: "E200001234567890",
          rssiDbm: -45,
          timestampMs: BigInt(now.getTime()),
          timestamp: now,
          source: "realtime",
        },
        {
          lighthouseId: testLighthouseId,
          epc: "E200009876543210",
          rssiDbm: -50,
          timestampMs: BigInt(now.getTime() - 1000),
          timestamp: new Date(now.getTime() - 1000),
          source: "offline_sync",
        },
        {
          lighthouseId: testLighthouseId,
          epc: "E200001111111111",
          rssiDbm: -55,
          timestampMs: BigInt(now.getTime() - 2000),
          timestamp: new Date(now.getTime() - 2000),
          source: "realtime",
        },
      ]);
    });

    afterEach(async () => {
      const db = getDatabase();
      // Clean up scans
      await db
        .delete(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, testLighthouseId));
    });

    it("should return scans with default pagination", async () => {
      const res = await app.request("/api/v1/scans");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.length).toBeGreaterThanOrEqual(3);
      expect(body.limit).toBe(50);
      expect(body.offset).toBe(0);
    });

    it("should filter by lighthouseId", async () => {
      const res = await app.request(`/api/v1/scans?lighthouseId=${testLighthouseId}`);
      expect(res.status).toBe(200);

      const body = await res.json();
      body.data.forEach((scan: { lighthouseId: number }) => {
        expect(scan.lighthouseId).toBe(testLighthouseId);
      });
    });

    it("should filter by EPC (partial match)", async () => {
      const res = await app.request("/api/v1/scans?epc=1234");
      expect(res.status).toBe(200);

      const body = await res.json();
      body.data.forEach((scan: { epc: string }) => {
        expect(scan.epc.toLowerCase()).toContain("1234");
      });
    });

    it("should filter by source", async () => {
      const res = await app.request("/api/v1/scans?source=offline_sync");
      expect(res.status).toBe(200);

      const body = await res.json();
      body.data.forEach((scan: { source: string }) => {
        expect(scan.source).toBe("offline_sync");
      });
    });

    it("should respect limit parameter", async () => {
      const res = await app.request("/api/v1/scans?limit=2");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.length).toBeLessThanOrEqual(2);
      expect(body.limit).toBe(2);
    });

    it("should cap limit at 500", async () => {
      const res = await app.request("/api/v1/scans?limit=1000");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.limit).toBe(500);
    });

    it("should return scans in descending timestamp order", async () => {
      const res = await app.request(`/api/v1/scans?lighthouseId=${testLighthouseId}`);
      expect(res.status).toBe(200);

      const body = await res.json();
      for (let i = 1; i < body.data.length; i++) {
        const prev = new Date(body.data[i - 1].timestamp);
        const curr = new Date(body.data[i].timestamp);
        expect(prev.getTime()).toBeGreaterThanOrEqual(curr.getTime());
      }
    });
  });

  // ============================================================================
  // Protected Lighthouses PATCH with groupId Tests
  // ============================================================================

  describe("PATCH /api/v1/lighthouses/:id (protected)", () => {
    it("should update lighthouse with groupId", async () => {
      const db = getDatabase();

      // Create a group
      const groupResult = await db
        .insert(schema.lighthouseGroups)
        .values({ label: TEST_GROUP_LABEL })
        .returning();

      // Create a lighthouse
      const lhResult = await db
        .insert(schema.lighthouses)
        .values({
          name: TEST_LIGHTHOUSE_NAME,
          deviceId: TEST_DEVICE_ID,
          placement: "STANDALONE",
        })
        .returning();

      const res = await app.request(`/api/v1/lighthouses/${lhResult[0].id}`, {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          groupId: groupResult[0].id,
        }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.groupId).toBe(groupResult[0].id);
    });
  });
});
