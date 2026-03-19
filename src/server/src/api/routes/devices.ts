import { Hono } from "hono";
import { createLogger } from "../../utils/logger";
import {
  getPendingDeviceStates,
  isPendingDevice,
  markDeviceAsRegistered,
} from "../../mqtt/state";
import { getDatabase, schema } from "../../database/client";
import { count, eq } from "drizzle-orm";
import { errorHandler, requestLogger } from "../middleware";

const logger = createLogger("Routes");

// Create Hono router with middleware
const router = new Hono();

// Apply global middleware
router.use("*", requestLogger);
router.use("*", errorHandler);

/**
 * Get pending (unregistered) devices
 * GET /api/v1/devices/pending
 */
router.get("/devices/pending", async (c) => {
  const pendingStates = getPendingDeviceStates();

  const data = Array.from(pendingStates.entries()).map(([deviceId, state]) => ({
    deviceId,
    isConnected: state.isConnected,
    firstSeenAt: state.firstSeenAt.toISOString(),
    lastHealthAt: state.lastHealthAt?.toISOString() ?? null,
    health: state.latestHealth
      ? {
          uptimeSec: state.latestHealth.uptimeSec,
          freeHeapBytes: state.latestHealth.freeHeapBytes,
          wifiRssiDbm: state.latestHealth.wifiRssiDbm,
          rfidState: state.latestHealth.rfid.state,
          rfidIsResponsive: state.latestHealth.rfid.isResponsive,
        }
      : null,
  }));

  return c.json({
    data,
    count: data.length,
  });
});

/**
 * Claim a pending device
 * POST /api/v1/devices/pending/:deviceId/claim
 */
router.post("/devices/pending/:deviceId/claim", async (c) => {
  const deviceId = c.req.param("deviceId").toUpperCase();

  // Check if device is in pending state
  if (!isPendingDevice(deviceId)) {
    return c.json(
      { error: "Device not found in pending devices", status: 404 },
      404,
    );
  }

  const body = await c.req.json<{
    name: string;
    label?: string;
    placement: "STANDALONE" | "INSIDE" | "OUTSIDE";
    groupId?: number | null;
  }>();

  // Validate required fields
  if (!body.name || typeof body.name !== "string" || body.name.trim() === "") {
    return c.json({ error: "Missing required field: name", status: 400 }, 400);
  }

  if (
    !body.placement ||
    !["STANDALONE", "INSIDE", "OUTSIDE"].includes(body.placement)
  ) {
    return c.json(
      { error: "Missing or invalid required field: placement", status: 400 },
      400,
    );
  }

  const db = getDatabase();

  // Check if name already exists
  const existingByName = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.name, body.name.trim()))
    .limit(1);

  if (existingByName.length > 0) {
    return c.json(
      { error: "A lighthouse with this name already exists", status: 400 },
      400,
    );
  }

  // Check if device ID already exists in database
  const existingByDevice = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, deviceId))
    .limit(1);

  if (existingByDevice.length > 0) {
    return c.json({ error: "Device is already registered", status: 400 }, 400);
  }

  // Validate groupId if provided
  if (body.groupId !== undefined && body.groupId !== null) {
    const group = await db
      .select()
      .from(schema.lighthouseGroups)
      .where(eq(schema.lighthouseGroups.id, body.groupId))
      .limit(1);

    if (group.length === 0) {
      return c.json({ error: "Group not found", status: 400 }, 400);
    }

    // Check if group already has 2 members
    const memberCount = await db
      .select({ count: count() })
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.groupId, body.groupId));

    if (memberCount[0] && memberCount[0].count >= 2) {
      return c.json({ error: "Group already has 2 members", status: 400 }, 400);
    }
  }

  // Create the lighthouse
  const now = new Date();
  const result = await db
    .insert(schema.lighthouses)
    .values({
      name: body.name.trim(),
      deviceId,
      placement: body.placement,
      comment: body.label ?? null,
      groupId: body.groupId ?? null,
      isActive: true,
      createdAt: now,
      changedAt: now,
    })
    .returning();

  // Mark device as registered in runtime state
  markDeviceAsRegistered(deviceId);

  logger.info(`Device ${deviceId} claimed as lighthouse '${body.name}'`);

  return c.json(result[0], 201);
});

export default router;
