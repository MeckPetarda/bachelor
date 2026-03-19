import { Hono } from "hono";
import { getDatabase, schema } from "../../database/client";
import { and, eq, inArray, isNull } from "drizzle-orm";
import { createLogger } from "../../utils/logger";
import { errorHandler, requestLogger } from "../middleware";

const logger = createLogger("Routes");

const router = new Hono();

router.use("*", requestLogger);
router.use("*", errorHandler);

/**
 * List all users with their assigned tags
 * GET /api/v1/users
 */
router.get("/users", async (c) => {
  const db = getDatabase();

  const users = await db.select().from(schema.users);

  const activeAssignments = await db
    .select({
      userId: schema.tagAssignments.userId,
      tagEpc: schema.tagAssignments.tagEpc,
    })
    .from(schema.tagAssignments)
    .where(isNull(schema.tagAssignments.deactivatedAt));

  const data = users.map((user) => ({
    id: user.id,
    sync_id: user.syncId,
    name: user.name,
    email: user.email,
    isActive: user.isActive,
    tags: activeAssignments
      .filter((ta) => ta.userId === user.id)
      .map((ta) => ta.tagEpc),
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  }));

  return c.json({
    data,
    count: data.length,
  });
});

/**
 * Create a new user and assign tags
 * POST /api/v1/users
 */
router.post("/users", async (c) => {
  const body = await c.req.json<{
    id?: number;
    name?: string;
    tags: string[];
    sync_id: string;
    email?: string;
    isActive: boolean;
  }>();

  const db = getDatabase();
  const now = new Date();

  const result = await db
    .insert(schema.users)
    .values({
      syncId: body.sync_id?.trim() ?? null,
      name: body.name?.trim() ?? null,
      email: body.email?.trim() ?? null,
      isActive: body.isActive,
      createdAt: now,
      updatedAt: now,
    })
    .returning();

  const createdUser = result[0];
  if (!createdUser) {
    return c.json({ error: "Failed to create user", status: 500 }, 500);
  }

  // Handle tag assignments
  const tags = (body.tags ?? []).map((t) => t.trim()).filter((t) => t !== "");

  if (tags.length > 0) {
    // Deactivate any existing active assignments for these tags
    await db
      .update(schema.tagAssignments)
      .set({ deactivatedAt: now })
      .where(
        and(
          inArray(schema.tagAssignments.tagEpc, tags),
          isNull(schema.tagAssignments.deactivatedAt),
        ),
      );

    // Create new assignments
    await db.insert(schema.tagAssignments).values(
      tags.map((tagEpc) => ({
        userId: createdUser.id,
        tagEpc,
        assignedAt: now,
        createdAt: now,
      })),
    );
  }

  logger.info(`User '${createdUser.id}' created with ${tags.length} tags`);

  return c.json(
    {
      id: createdUser.id,
      sync_id: createdUser.syncId,
      name: createdUser.name,
      email: createdUser.email,
      isActive: createdUser.isActive,
      tags,
      createdAt: createdUser.createdAt.toISOString(),
      updatedAt: createdUser.updatedAt.toISOString(),
    },
    201,
  );
});

/**
 * Get a single user by ID
 * GET /api/v1/users/:id
 */
router.get("/users/:id", async (c) => {
  const id = c.req.param("id");

  const db = getDatabase();

  const users = await db
    .select()
    .from(schema.users)
    .where(eq(schema.users.id, id))
    .limit(1);

  const user = users[0];
  if (!user) {
    return c.json({ error: "User not found", status: 404 }, 404);
  }

  return c.json({
    id: user.id,
    sync_id: user.syncId,
    name: user.name,
    email: user.email,
    isActive: user.isActive,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  });
});

/**
 * Update a user
 * PATCH /api/v1/users/:id
 */
router.patch("/users/:id", async (c) => {
  const id = c.req.param("id");

  const body = await c.req.json<{
    sync_id?: string | null;
    name?: string | null;
    email?: string | null;
    isActive?: boolean;
    tags?: string[];
  }>();

  const db = getDatabase();
  const now = new Date();

  const existing = await db
    .select()
    .from(schema.users)
    .where(eq(schema.users.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "User not found", status: 404 }, 404);
  }

  const updateData: Record<string, unknown> = {
    updatedAt: now,
  };

  if (body.sync_id !== undefined) {
    updateData.syncId = body.sync_id?.trim() ?? null;
  }
  if (body.name !== undefined) {
    updateData.name = body.name?.trim() ?? null;
  }
  if (body.email !== undefined) {
    updateData.email = body.email?.trim() ?? null;
  }
  if (body.isActive !== undefined) {
    updateData.isActive = body.isActive;
  }

  const result = await db
    .update(schema.users)
    .set(updateData)
    .where(eq(schema.users.id, id))
    .returning();

  const updatedUser = result[0];
  if (!updatedUser) {
    return c.json({ error: "Failed to update user", status: 500 }, 500);
  }

  // Reconcile tag assignments if tags were provided
  let tags: string[] | undefined;

  if (body.tags !== undefined) {
    tags = (body.tags ?? []).map((t) => t.trim()).filter((t) => t !== "");

    // Get current active assignments for this user
    const currentAssignments = await db
      .select({ tagEpc: schema.tagAssignments.tagEpc })
      .from(schema.tagAssignments)
      .where(
        and(
          eq(schema.tagAssignments.userId, id),
          isNull(schema.tagAssignments.deactivatedAt),
        ),
      );

    const currentTags = new Set(currentAssignments.map((a) => a.tagEpc));
    const desiredTags = new Set(tags);

    // Deactivate tags that are no longer assigned to this user
    const toRemove = [...currentTags].filter((t) => !desiredTags.has(t));
    if (toRemove.length > 0) {
      await db
        .update(schema.tagAssignments)
        .set({ deactivatedAt: now })
        .where(
          and(
            eq(schema.tagAssignments.userId, id),
            inArray(schema.tagAssignments.tagEpc, toRemove),
            isNull(schema.tagAssignments.deactivatedAt),
          ),
        );
    }

    // Insert new tags (ones not already active for this user)
    const toAdd = [...desiredTags].filter((t) => !currentTags.has(t));
    if (toAdd.length > 0) {
      // Deactivate any active assignments of these tags on other users
      await db
        .update(schema.tagAssignments)
        .set({ deactivatedAt: now })
        .where(
          and(
            inArray(schema.tagAssignments.tagEpc, toAdd),
            isNull(schema.tagAssignments.deactivatedAt),
          ),
        );

      await db.insert(schema.tagAssignments).values(
        toAdd.map((tagEpc) => ({
          userId: id,
          tagEpc,
          assignedAt: now,
          createdAt: now,
        })),
      );
    }
  }

  logger.info(`User ${id} updated`);

  return c.json({
    id: updatedUser.id,
    sync_id: updatedUser.syncId,
    name: updatedUser.name,
    email: updatedUser.email,
    isActive: updatedUser.isActive,
    ...(tags !== undefined && { tags }),
    createdAt: updatedUser.createdAt.toISOString(),
    updatedAt: updatedUser.updatedAt.toISOString(),
  });
});

/**
 * Delete a user
 * DELETE /api/v1/users/:id
 */
router.delete("/users/:id", async (c) => {
  const id = c.req.param("id");

  const db = getDatabase();

  const existing = await db
    .select()
    .from(schema.users)
    .where(eq(schema.users.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "User not found", status: 404 }, 404);
  }

  await db.delete(schema.users).where(eq(schema.users.id, id));

  logger.info(`User ${id} deleted`);

  return c.body(null, 204);
});

export default router;
