import { Hono } from "hono";
import { getDatabase, schema } from "../../database/client";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { createLogger } from "../../utils/logger";
import { errorHandler, requestLogger } from "../middleware";

const logger = createLogger("Routes");

const router = new Hono();

router.use("*", requestLogger);
router.use("*", errorHandler);

/**
 * List all groups with their member lighthouses
 * GET /api/v1/groups
 */
router.get("/groups", async (c) => {
  const db = getDatabase();

  const groups = await db.select().from(schema.lighthouseGroups);

  const lighthouses = await db
    .select({
      id: schema.lighthouses.id,
      name: schema.lighthouses.name,
      deviceId: schema.lighthouses.deviceId,
      placement: schema.lighthouses.placement,
      groupId: schema.lighthouses.groupId,
    })
    .from(schema.lighthouses)
    .where(sql`${schema.lighthouses.groupId} IS NOT NULL`);

  const data = groups.map((group) => ({
    id: group.id,
    label: group.label,
    description: group.description,
    activityTimeoutMs: group.activityTimeoutMs,
    orphanTimeoutMs: group.orphanTimeoutMs,
    members: lighthouses
      .filter((lh) => lh.groupId === group.id)
      .map((lh) => ({
        id: lh.id,
        name: lh.name,
        deviceId: lh.deviceId,
        placement: lh.placement,
      })),
    createdAt: group.createdAt.toISOString(),
    updatedAt: group.updatedAt.toISOString(),
  }));

  return c.json({ data, count: data.length });
});

/**
 * Create a new group
 * POST /api/v1/groups
 */
router.post("/groups", async (c) => {
  const body = await c.req.json<{
    label: string;
    description?: string;
    activityTimeoutMs?: number;
    orphanTimeoutMs?: number;
  }>();

  if (
    !body.label ||
    typeof body.label !== "string" ||
    body.label.trim() === ""
  ) {
    return c.json({ error: "Missing required field: label", status: 400 }, 400);
  }

  const db = getDatabase();
  const now = new Date();

  const result = await db
    .insert(schema.lighthouseGroups)
    .values({
      label: body.label.trim(),
      description: body.description?.trim() ?? null,
      ...(body.activityTimeoutMs !== undefined && {
        activityTimeoutMs: body.activityTimeoutMs,
      }),
      ...(body.orphanTimeoutMs !== undefined && {
        orphanTimeoutMs: body.orphanTimeoutMs,
      }),
      createdAt: now,
      updatedAt: now,
    })
    .returning();

  const createdGroup = result[0];
  if (!createdGroup) {
    return c.json({ error: "Failed to create group", status: 500 }, 500);
  }

  logger.info(`Group '${body.label}' created`);

  return c.json(
    {
      id: createdGroup.id,
      label: createdGroup.label,
      description: createdGroup.description,
      activityTimeoutMs: createdGroup.activityTimeoutMs,
      orphanTimeoutMs: createdGroup.orphanTimeoutMs,
      members: [],
      createdAt: createdGroup.createdAt.toISOString(),
      updatedAt: createdGroup.updatedAt.toISOString(),
    },
    201,
  );
});

/**
 * Get a single group by ID
 * GET /api/v1/groups/:id
 */
router.get("/groups/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid group ID", status: 400 }, 400);
  }

  const db = getDatabase();

  const groups = await db
    .select()
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id))
    .limit(1);

  const group = groups[0];
  if (!group) {
    return c.json({ error: "Group not found", status: 404 }, 404);
  }

  const members = await db
    .select({
      id: schema.lighthouses.id,
      name: schema.lighthouses.name,
      deviceId: schema.lighthouses.deviceId,
      placement: schema.lighthouses.placement,
    })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.groupId, id));

  return c.json({
    data: {
      id: group.id,
      label: group.label,
      description: group.description,
      activityTimeoutMs: group.activityTimeoutMs,
      orphanTimeoutMs: group.orphanTimeoutMs,
      members,
      createdAt: group.createdAt.toISOString(),
      updatedAt: group.updatedAt.toISOString(),
    },
  });
});

/**
 * Update a group
 * PATCH /api/v1/groups/:id
 */
router.patch("/groups/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid group ID", status: 400 }, 400);
  }

  const body = await c.req.json<{
    label?: string;
    description?: string | null;
    activityTimeoutMs?: number;
    orphanTimeoutMs?: number;
  }>();

  const db = getDatabase();

  const existing = await db
    .select()
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Group not found", status: 404 }, 404);
  }

  const updateData: Record<string, unknown> = { updatedAt: new Date() };

  if (body.label !== undefined) {
    if (typeof body.label !== "string" || body.label.trim() === "") {
      return c.json({ error: "Label cannot be empty", status: 400 }, 400);
    }
    updateData.label = body.label.trim();
  }
  if (body.description !== undefined) {
    updateData.description = body.description?.trim() ?? null;
  }
  if (body.activityTimeoutMs !== undefined) {
    updateData.activityTimeoutMs = body.activityTimeoutMs;
  }
  if (body.orphanTimeoutMs !== undefined) {
    updateData.orphanTimeoutMs = body.orphanTimeoutMs;
  }

  const result = await db
    .update(schema.lighthouseGroups)
    .set(updateData)
    .where(eq(schema.lighthouseGroups.id, id))
    .returning();

  const updatedGroup = result[0];
  if (!updatedGroup) {
    return c.json({ error: "Failed to update group", status: 500 }, 500);
  }

  // Re-enable misconfigured_group orphans so the sweeper can retry them now
  // that the group configuration may have changed.
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
            .where(eq(schema.lighthouses.groupId, id)),
        ),
        eq(schema.rawScans.orphanReason, "misconfigured_group"),
        isNull(schema.rawScans.processedAt),
      ),
    );

  const members = await db
    .select({
      id: schema.lighthouses.id,
      name: schema.lighthouses.name,
      deviceId: schema.lighthouses.deviceId,
      placement: schema.lighthouses.placement,
    })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.groupId, id));

  logger.info(`Group ${id} updated`);

  return c.json({
    data: {
      id: updatedGroup.id,
      label: updatedGroup.label,
      description: updatedGroup.description,
      activityTimeoutMs: updatedGroup.activityTimeoutMs,
      orphanTimeoutMs: updatedGroup.orphanTimeoutMs,
      members,
      createdAt: updatedGroup.createdAt.toISOString(),
      updatedAt: updatedGroup.updatedAt.toISOString(),
    },
  });
});

/**
 * Delete a group
 * DELETE /api/v1/groups/:id
 */
router.delete("/groups/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid group ID", status: 400 }, 400);
  }

  const db = getDatabase();

  const existing = await db
    .select()
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Group not found", status: 404 }, 404);
  }

  await db
    .delete(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id));

  logger.info(`Group ${id} deleted`);

  return c.body(null, 204);
});

export default router;
