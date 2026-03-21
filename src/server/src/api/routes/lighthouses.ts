import { Hono } from "hono";
import { jwtAuth } from "../middleware";
import { getConfig } from "../../config";
import { getDatabase, schema } from "../../database/client";
import { and, count, eq, inArray, isNull, sql } from "drizzle-orm";
import { createLogger } from "../../utils/logger";
import { getAllLighthouseStates } from "../../mqtt/state";

const logger = createLogger("Routes");

const router = new Hono();

// Apply JWT authentication to all protected routes
// router.use("*", jwtAuth(getConfig().jwt.secret));

/**
 * List all lighthouses
 * GET /api/v1/lighthouses
 */
router.get("/lighthouses", async (c) => {
  const db = getDatabase();

  const lighthouses = await db.select().from(schema.lighthouses);

  return c.json({
    data: lighthouses,
    count: lighthouses.length,
  });
});

/**
 * Register a new lighthouse
 * POST /api/v1/lighthouses
 */
router.post("/lighthouses", async (c) => {
  const body = await c.req.json<{
    id: number;
    name: string;
    deviceId: string;
    placement?: "STANDALONE" | "INSIDE" | "OUTSIDE";
    comment?: string;
    firmwareVersion?: string;
    config?: Record<string, unknown>;
  }>();

  // Validate required fields
  if (!body.id || !body.name || !body.deviceId) {
    return c.json(
      { error: "Missing required fields: id, name, deviceId", status: 400 },
      400,
    );
  }

  const db = getDatabase();

  // Check for duplicate id or deviceId
  const existing = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.id, body.id))
    .limit(1);

  if (existing.length > 0) {
    return c.json(
      { error: "Lighthouse with this ID already exists", status: 409 },
      409,
    );
  }

  const existingByDevice = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, body.deviceId))
    .limit(1);

  if (existingByDevice.length > 0) {
    return c.json(
      { error: "Lighthouse with this device ID already exists", status: 409 },
      409,
    );
  }

  // Insert new lighthouse
  const now = new Date();
  const result = await db
    .insert(schema.lighthouses)
    .values({
      id: body.id,
      name: body.name,
      deviceId: body.deviceId,
      placement: body.placement || "STANDALONE",
      comment: body.comment,
      firmwareVersion: body.firmwareVersion,
      config: body.config || {},
      isActive: true,
      createdAt: now,
      changedAt: now,
    })
    .returning();

  logger.info(`Lighthouse '${body.name}' (${body.deviceId}) registered`);

  return c.json({ data: result[0] }, 201);
});

/**
 * Get all lighthouses with runtime status and group info
 * GET /api/v1/lighthouses/all
 * (Public endpoint for dashboard)
 */
router.get("/lighthouses/all", async (c) => {
  const db = getDatabase();

  // Get all lighthouses with group info
  const lighthouses = await db
    .select({
      id: schema.lighthouses.id,
      name: schema.lighthouses.name,
      deviceId: schema.lighthouses.deviceId,
      placement: schema.lighthouses.placement,
      comment: schema.lighthouses.comment,
      firmwareVersion: schema.lighthouses.firmwareVersion,
      isActive: schema.lighthouses.isActive,
      groupId: schema.lighthouses.groupId,
      createdAt: schema.lighthouses.createdAt,
      changedAt: schema.lighthouses.cangedAt,
    })
    .from(schema.lighthouses);

  // Get all groups for mapping
  const groups = await db
    .select({
      id: schema.lighthouseGroups.id,
      label: schema.lighthouseGroups.label,
    })
    .from(schema.lighthouseGroups);

  const groupMap = new Map(groups.map((g) => [g.id, g]));
  const allStates = getAllLighthouseStates();

  const data = lighthouses.map((lh) => {
    const runtimeState = allStates.get(lh.deviceId);
    const group = lh.groupId ? groupMap.get(lh.groupId) : null;

    return {
      id: lh.id,
      name: lh.name,
      deviceId: lh.deviceId,
      label: lh.comment,
      placement: lh.placement,
      firmwareVersion: lh.firmwareVersion,
      isActive: lh.isActive,
      createdAt: lh.createdAt.toISOString(),
      group: group ? { id: group.id, label: group.label } : null,
      runtime: runtimeState
        ? {
            isConnected: runtimeState.isConnected,
            lastHealthAt: runtimeState.lastHealthAt?.toISOString() ?? null,
            health: runtimeState.latestHealth
              ? {
                  uptimeSec: runtimeState.latestHealth.uptimeSec,
                  freeHeapBytes: runtimeState.latestHealth.freeHeapBytes,
                  wifiRssiDbm: runtimeState.latestHealth.wifiRssiDbm,
                  rfidState: runtimeState.latestHealth.rfid.state,
                  rfidIsResponsive: runtimeState.latestHealth.rfid.isResponsive,
                }
              : null,
          }
        : null,
    };
  });

  return c.json({
    data,
    count: data.length,
  });
});

/**
 * Get lighthouse by ID
 * GET /api/v1/lighthouses/:id
 */
router.get("/lighthouses/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid lighthouse ID", status: 400 }, 400);
  }

  const db = getDatabase();

  const lighthouses = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.id, id))
    .limit(1);

  if (lighthouses.length === 0) {
    return c.json({ error: "Lighthouse not found", status: 404 }, 404);
  }

  return c.json({ data: lighthouses[0] });
});

/**
 * Update lighthouse configuration
 * PATCH /api/v1/lighthouses/:id
 */
router.patch("/lighthouses/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid lighthouse ID", status: 400 }, 400);
  }

  const body = await c.req.json<{
    name?: string;
    placement?: "STANDALONE" | "INSIDE" | "OUTSIDE";
    comment?: string;
    firmwareVersion?: string;
    isActive?: boolean;
    groupId?: number | null;
    config?: Record<string, unknown>;
  }>();

  const db = getDatabase();

  // Check if lighthouse exists
  const existing = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Lighthouse not found", status: 404 }, 404);
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

    // Check if group already has 2 members (excluding current lighthouse)
    const memberCount = await db
      .select({ count: count() })
      .from(schema.lighthouses)
      .where(
        and(
          eq(schema.lighthouses.groupId, body.groupId),
          sql`${schema.lighthouses.id} != ${id}`,
        ),
      );

    if (memberCount[0] && memberCount[0].count >= 2) {
      return c.json({ error: "Group already has 2 members", status: 400 }, 400);
    }
  }

  // Build update object with only provided fields
  const updateData: Record<string, unknown> = {
    changedAt: new Date(),
  };

  if (body.name !== undefined) updateData.name = body.name;
  if (body.placement !== undefined) updateData.placement = body.placement;
  if (body.comment !== undefined) updateData.comment = body.comment;
  if (body.firmwareVersion !== undefined)
    updateData.firmwareVersion = body.firmwareVersion;
  if (body.isActive !== undefined) updateData.isActive = body.isActive;
  if (body.config !== undefined) updateData.config = body.config;
  if (body.groupId !== undefined) updateData.groupId = body.groupId;

  const result = await db
    .update(schema.lighthouses)
    .set(updateData)
    .where(eq(schema.lighthouses.id, id))
    .returning();

  // When groupId or placement changes, re-enable misconfigured_group orphans
  // for the affected group(s) so the sweeper can retry them.
  if (body.groupId !== undefined || body.placement !== undefined) {
    const oldGroupId = existing[0]!.groupId;
    const newGroupId = result[0]?.groupId ?? null;
    const groupIds = [
      ...new Set(
        [oldGroupId, newGroupId].filter((g): g is number => g !== null),
      ),
    ];
    for (const gId of groupIds) {
      await db
        .update(schema.rawScans)
        .set({ orphanedAt: null, orphanReason: null })
        .where(
          and(
            inArray(
              schema.rawScans.lighthouseId,
              db
                .select({ id: schema.lighthouses.id })
                .from(schema.lighthouses)
                .where(eq(schema.lighthouses.groupId, gId)),
            ),
            eq(schema.rawScans.orphanReason, "misconfigured_group"),
            isNull(schema.rawScans.processedAt),
          ),
        );
    }
  }

  logger.info(`Lighthouse ${id} updated`);

  return c.json({ data: result[0] });
});

/**
 * Update lighthouse (public version with groupId support)
 * PATCH /api/v1/lighthouses/:id/update
 */
router.patch("/lighthouses/:id/update", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid lighthouse ID", status: 400 }, 400);
  }

  const body = await c.req.json<{
    name?: string;
    placement?: "STANDALONE" | "INSIDE" | "OUTSIDE";
    comment?: string;
    firmwareVersion?: string;
    isActive?: boolean;
    groupId?: number | null;
    config?: Record<string, unknown>;
  }>();

  const db = getDatabase();

  // Check if lighthouse exists
  const existing = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Lighthouse not found", status: 404 }, 404);
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

    // Check if group already has 2 members (excluding current lighthouse)
    const memberCount = await db
      .select({ count: count() })
      .from(schema.lighthouses)
      .where(
        and(
          eq(schema.lighthouses.groupId, body.groupId),
          sql`${schema.lighthouses.id} != ${id}`,
        ),
      );

    if (memberCount[0] && memberCount[0].count >= 2) {
      return c.json({ error: "Group already has 2 members", status: 400 }, 400);
    }
  }

  // Build update object with only provided fields
  const updateData: Record<string, unknown> = {
    changedAt: new Date(),
  };

  if (body.name !== undefined) updateData.name = body.name;
  if (body.placement !== undefined) updateData.placement = body.placement;
  if (body.comment !== undefined) updateData.comment = body.comment;
  if (body.firmwareVersion !== undefined)
    updateData.firmwareVersion = body.firmwareVersion;
  if (body.isActive !== undefined) updateData.isActive = body.isActive;
  if (body.config !== undefined) updateData.config = body.config;
  if (body.groupId !== undefined) updateData.groupId = body.groupId;

  const result = await db
    .update(schema.lighthouses)
    .set(updateData)
    .where(eq(schema.lighthouses.id, id))
    .returning();

  // When groupId or placement changes, re-enable misconfigured_group orphans
  // for the affected group(s) so the sweeper can retry them.
  if (body.groupId !== undefined || body.placement !== undefined) {
    const oldGroupId = existing[0]!.groupId;
    const newGroupId = result[0]?.groupId ?? null;
    const groupIds = [
      ...new Set(
        [oldGroupId, newGroupId].filter((g): g is number => g !== null),
      ),
    ];
    for (const gId of groupIds) {
      await db
        .update(schema.rawScans)
        .set({ orphanedAt: null, orphanReason: null })
        .where(
          and(
            inArray(
              schema.rawScans.lighthouseId,
              db
                .select({ id: schema.lighthouses.id })
                .from(schema.lighthouses)
                .where(eq(schema.lighthouses.groupId, gId)),
            ),
            eq(schema.rawScans.orphanReason, "misconfigured_group"),
            isNull(schema.rawScans.processedAt),
          ),
        );
    }
  }

  logger.info(`Lighthouse ${id} updated`);

  return c.json({ data: result[0] });
});

export default router;
