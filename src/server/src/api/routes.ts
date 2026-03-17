import { Hono } from "hono";
import { eq, and, gte, lte, ilike, desc, sql, count } from "drizzle-orm";
import { getDatabase, schema, isHealthy } from "../database/client";
import { getMqttBrokerStats } from "../mqtt/broker";
import { getConfig } from "../config";
import { createLogger } from "../utils/logger";
import { requestLogger, errorHandler, jwtAuth, createJWT } from "./middleware";
import {
  getPendingDeviceStates,
  getLighthouseState,
  getAllLighthouseStates,
  isPendingDevice,
  markDeviceAsRegistered,
} from "../mqtt/state";

const logger = createLogger("Routes");

// Create Hono app with middleware
const app = new Hono();

// Apply global middleware
app.use("*", requestLogger);
app.use("*", errorHandler);

// ============================================================================
// Public Routes
// ============================================================================

/**
 * Health check endpoint
 * GET /health
 */
app.get("/health", async (c) => {
  const dbHealthy = await isHealthy();
  const mqttStats = getMqttBrokerStats();

  const status = {
    status: dbHealthy && mqttStats.isRunning ? "healthy" : "degraded",
    timestamp: new Date().toISOString(),
    services: {
      database: dbHealthy ? "connected" : "disconnected",
      mqtt: mqttStats.isRunning ? "running" : "stopped",
    },
    mqtt: {
      port: mqttStats.port,
      connectedClients: mqttStats.connectedClients,
    },
  };

  return c.json(status, dbHealthy && mqttStats.isRunning ? 200 : 503);
});

/**
 * Login endpoint
 * POST /api/v1/auth/login
 */
app.post("/api/v1/auth/login", async (c) => {
  const body = await c.req.json<{ username: string; password: string }>();

  if (!body.username || !body.password) {
    return c.json({ error: "Missing username or password", status: 400 }, 400);
  }

  const db = getDatabase();
  const config = getConfig();

  // Find user by username
  const users = await db
    .select()
    .from(schema.dashboardUsers)
    .where(eq(schema.dashboardUsers.username, body.username))
    .limit(1);

  if (users.length === 0) {
    logger.warn(`Login attempt failed: user '${body.username}' not found`);
    return c.json({ error: "Invalid credentials", status: 401 }, 401);
  }

  const user = users[0];

  if (!user) {
    logger.warn(`Login attempt failed: user '${body.username}' not found`);
    return c.json({ error: "Invalid credentials", status: 401 }, 401);
  }

  // Check if user is active
  if (!user.isActive) {
    logger.warn(`Login attempt failed: user '${body.username}' is inactive`);
    return c.json({ error: "Account is inactive", status: 401 }, 401);
  }

  // Verify password using Bun's native password hashing
  const isValid = await Bun.password.verify(body.password, user.passwordHash);
  if (!isValid) {
    logger.warn(
      `Login attempt failed: invalid password for '${body.username}'`,
    );
    return c.json({ error: "Invalid credentials", status: 401 }, 401);
  }

  // Create JWT token
  const token = await createJWT(
    {
      sub: user.id,
      username: user.username,
      role: user.role,
    },
    config.jwt.secret,
    config.jwt.expiresIn,
  );

  // Update last login timestamp
  await db
    .update(schema.dashboardUsers)
    .set({ lastLogin: new Date() })
    .where(eq(schema.dashboardUsers.id, user.id));

  logger.info(`User '${body.username}' logged in successfully`);

  return c.json({
    token,
    user: {
      id: user.id,
      username: user.username,
      role: user.role,
    },
  });
});

// ============================================================================
// Protected Routes (require authentication)
// ============================================================================

const protectedRoutes = new Hono();

// Apply JWT authentication to all protected routes
protectedRoutes.use("*", jwtAuth(getConfig().jwt.secret));

/**
 * List all lighthouses
 * GET /api/v1/lighthouses
 */
protectedRoutes.get("/lighthouses", async (c) => {
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
protectedRoutes.post("/lighthouses", async (c) => {
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
      cangedAt: now,
    })
    .returning();

  logger.info(`Lighthouse '${body.name}' (${body.deviceId}) registered`);

  return c.json({ data: result[0] }, 201);
});

/**
 * Get lighthouse by ID
 * GET /api/v1/lighthouses/:id
 */
protectedRoutes.get("/lighthouses/:id", async (c) => {
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
protectedRoutes.patch("/lighthouses/:id", async (c) => {
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
    cangedAt: new Date(),
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

  logger.info(`Lighthouse ${id} updated`);

  return c.json({ data: result[0] });
});

// ============================================================================
// Public Dashboard Routes (No authentication required for PoC)
// These must be defined BEFORE mounting protected routes
// ============================================================================

/**
 * Get pending (unregistered) devices
 * GET /api/v1/devices/pending
 */
app.get("/api/v1/devices/pending", async (c) => {
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
app.post("/api/v1/devices/pending/:deviceId/claim", async (c) => {
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
      cangedAt: now,
    })
    .returning();

  // Mark device as registered in runtime state
  markDeviceAsRegistered(deviceId);

  logger.info(`Device ${deviceId} claimed as lighthouse '${body.name}'`);

  return c.json(result[0], 201);
});

/**
 * List all groups with their member lighthouses
 * GET /api/v1/groups
 */
app.get("/api/v1/groups", async (c) => {
  const db = getDatabase();

  // Get all groups
  const groups = await db.select().from(schema.lighthouseGroups);

  // Get all lighthouses with group assignments
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

  // Build response with members
  const data = groups.map((group) => ({
    id: group.id,
    label: group.label,
    description: group.description,
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

  return c.json({
    data,
    count: data.length,
  });
});

/**
 * Create a new group
 * POST /api/v1/groups
 */
app.post("/api/v1/groups", async (c) => {
  const body = await c.req.json<{
    label: string;
    description?: string;
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
app.get("/api/v1/groups/:id", async (c) => {
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

  // Get members
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
app.patch("/api/v1/groups/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid group ID", status: 400 }, 400);
  }

  const body = await c.req.json<{
    label?: string;
    description?: string | null;
  }>();

  const db = getDatabase();

  // Check if group exists
  const existing = await db
    .select()
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Group not found", status: 404 }, 404);
  }

  // Build update object
  const updateData: Record<string, unknown> = {
    updatedAt: new Date(),
  };

  if (body.label !== undefined) {
    if (typeof body.label !== "string" || body.label.trim() === "") {
      return c.json({ error: "Label cannot be empty", status: 400 }, 400);
    }
    updateData.label = body.label.trim();
  }
  if (body.description !== undefined) {
    updateData.description = body.description?.trim() ?? null;
  }

  const result = await db
    .update(schema.lighthouseGroups)
    .set(updateData)
    .where(eq(schema.lighthouseGroups.id, id))
    .returning();

  // Get members
  const members = await db
    .select({
      id: schema.lighthouses.id,
      name: schema.lighthouses.name,
      deviceId: schema.lighthouses.deviceId,
      placement: schema.lighthouses.placement,
    })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.groupId, id));

  const updatedGroup = result[0];
  if (!updatedGroup) {
    return c.json({ error: "Failed to update group", status: 500 }, 500);
  }

  logger.info(`Group ${id} updated`);

  return c.json({
    data: {
      id: updatedGroup.id,
      label: updatedGroup.label,
      description: updatedGroup.description,
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
app.delete("/api/v1/groups/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid group ID", status: 400 }, 400);
  }

  const db = getDatabase();

  // Check if group exists
  const existing = await db
    .select()
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id))
    .limit(1);

  if (existing.length === 0) {
    return c.json({ error: "Group not found", status: 404 }, 404);
  }

  // Delete the group (ON DELETE SET NULL will handle lighthouses)
  await db
    .delete(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, id));

  logger.info(`Group ${id} deleted`);

  return c.body(null, 204);
});

/**
 * Get all lighthouses with runtime status and group info
 * GET /api/v1/lighthouses/all
 * (Public endpoint for dashboard)
 */
app.get("/api/v1/lighthouses/all", async (c) => {
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
      cangedAt: schema.lighthouses.cangedAt,
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
 * Update lighthouse (public version with groupId support)
 * PATCH /api/v1/lighthouses/:id/update
 */
app.patch("/api/v1/lighthouses/:id/update", async (c) => {
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
    cangedAt: new Date(),
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

  logger.info(`Lighthouse ${id} updated`);

  return c.json({ data: result[0] });
});

/**
 * Query raw scan events with filtering and pagination
 * GET /api/v1/scans
 */
app.get("/api/v1/scans", async (c) => {
  const db = getDatabase();

  // Parse query parameters
  const lighthouseIdParam = c.req.query("lighthouseId");
  const epcParam = c.req.query("epc");
  const sourceParam = c.req.query("source");
  const fromParam = c.req.query("from");
  const toParam = c.req.query("to");
  const limitParam = c.req.query("limit");
  const offsetParam = c.req.query("offset");

  // Parse and validate numeric params
  let limit = 50;
  if (limitParam) {
    const parsed = parseInt(limitParam, 10);
    if (!isNaN(parsed) && parsed > 0) {
      limit = Math.min(parsed, 500); // Cap at 500
    }
  }

  let offset = 0;
  if (offsetParam) {
    const parsed = parseInt(offsetParam, 10);
    if (!isNaN(parsed) && parsed >= 0) {
      offset = parsed;
    }
  }

  // Build conditions array
  const conditions: ReturnType<typeof eq>[] = [];

  if (lighthouseIdParam) {
    const lighthouseId = parseInt(lighthouseIdParam, 10);
    if (!isNaN(lighthouseId)) {
      conditions.push(eq(schema.rawScans.lighthouseId, lighthouseId));
    }
  }

  if (epcParam) {
    conditions.push(ilike(schema.rawScans.epc, `%${epcParam}%`));
  }

  if (
    sourceParam &&
    (sourceParam === "realtime" || sourceParam === "offline_sync")
  ) {
    conditions.push(eq(schema.rawScans.source, sourceParam));
  }

  if (fromParam) {
    const fromDate = new Date(fromParam);
    if (!isNaN(fromDate.getTime())) {
      conditions.push(gte(schema.rawScans.timestamp, fromDate));
    }
  }

  if (toParam) {
    const toDate = new Date(toParam);
    if (!isNaN(toDate.getTime())) {
      conditions.push(lte(schema.rawScans.timestamp, toDate));
    }
  }

  // Get total count
  const totalResult = await db
    .select({ count: count() })
    .from(schema.rawScans)
    .where(conditions.length > 0 ? and(...conditions) : undefined);

  const total = totalResult[0]?.count ?? 0;

  // Get scans with lighthouse info
  const scans = await db
    .select({
      id: schema.rawScans.id,
      lighthouseId: schema.rawScans.lighthouseId,
      lighthouseName: schema.lighthouses.name,
      epc: schema.rawScans.epc,
      rssiDbm: schema.rawScans.rssiDbm,
      timestamp: schema.rawScans.timestamp,
      source: schema.rawScans.source,
      receivedAt: schema.rawScans.receivedAt,
    })
    .from(schema.rawScans)
    .leftJoin(
      schema.lighthouses,
      eq(schema.rawScans.lighthouseId, schema.lighthouses.id),
    )
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(schema.rawScans.timestamp))
    .limit(limit)
    .offset(offset);

  const data = scans.map((scan) => ({
    id: scan.id.toString(),
    lighthouseId: scan.lighthouseId,
    lighthouseName: scan.lighthouseName,
    epc: scan.epc,
    rssiDbm: scan.rssiDbm,
    timestamp: scan.timestamp.toISOString(),
    source: scan.source,
    receivedAt: scan.receivedAt?.toISOString() ?? null,
  }));

  return c.json({
    data,
    total,
    limit,
    offset,
  });
});

// Mount protected routes under /api/v1 AFTER public routes
app.route("/api/v1", protectedRoutes);

// ============================================================================
// Static File Serving (Frontend SPA)
// ============================================================================

const STATIC_DIR = "./dist/web";
const INDEX_HTML = `${STATIC_DIR}/index.html`;

// Helper to determine MIME type
function getMimeType(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase();
  const mimeTypes: Record<string, string> = {
    html: "text/html",
    css: "text/css",
    js: "application/javascript",
    mjs: "application/javascript",
    json: "application/json",
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    svg: "image/svg+xml",
    ico: "image/x-icon",
    woff: "font/woff",
    woff2: "font/woff2",
    ttf: "font/ttf",
  };
  return mimeTypes[ext || ""] || "application/octet-stream";
}

// Catch-all route for static files and SPA fallback
app.get("*", async (c) => {
  const url = new URL(c.req.url);
  let filePath = `${STATIC_DIR}${url.pathname}`;

  // Try to serve the requested file
  let file = Bun.file(filePath);
  if (await file.exists()) {
    const content = await file.arrayBuffer();
    return new Response(content, {
      headers: {
        "Content-Type": getMimeType(filePath),
        "Cache-Control": "public, max-age=31536000",
      },
    });
  }

  // For paths that look like file requests (have extension), return 404
  if (url.pathname.includes(".")) {
    return c.notFound();
  }

  // SPA fallback: serve index.html for all other routes
  file = Bun.file(INDEX_HTML);
  if (await file.exists()) {
    const content = await file.text();
    return new Response(content, {
      headers: {
        "Content-Type": "text/html",
        "Cache-Control": "no-cache",
      },
    });
  }

  // No frontend built yet - show helpful message
  return c.html(`
    <!DOCTYPE html>
    <html>
      <head><title>Lighthouse Dashboard</title></head>
      <body style="font-family: system-ui; padding: 2rem; text-align: center;">
        <h1>Frontend not built</h1>
        <p>Run <code>bun run build:web</code> to build the frontend.</p>
        <p>For development, run <code>bun run dev:web</code> to start the Vite dev server.</p>
      </body>
    </html>
  `);
});

export { app };
