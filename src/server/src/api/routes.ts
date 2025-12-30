import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getDatabase, schema, isHealthy } from "../database/client";
import { getMqttBrokerStats } from "../mqtt/broker";
import { getConfig } from "../config";
import { createLogger } from "../utils/logger";
import {
  requestLogger,
  errorHandler,
  jwtAuth,
  createJWT,
} from "./middleware";

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
    return c.json(
      { error: "Missing username or password", status: 400 },
      400
    );
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
    logger.warn(`Login attempt failed: invalid password for '${body.username}'`);
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
    config.jwt.expiresIn
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
      400
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
      409
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
      409
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

  // Build update object with only provided fields
  const updateData: Record<string, unknown> = {
    cangedAt: new Date(),
  };

  if (body.name !== undefined) updateData.name = body.name;
  if (body.placement !== undefined) updateData.placement = body.placement;
  if (body.comment !== undefined) updateData.comment = body.comment;
  if (body.firmwareVersion !== undefined) updateData.firmwareVersion = body.firmwareVersion;
  if (body.isActive !== undefined) updateData.isActive = body.isActive;
  if (body.config !== undefined) updateData.config = body.config;

  const result = await db
    .update(schema.lighthouses)
    .set(updateData)
    .where(eq(schema.lighthouses.id, id))
    .returning();

  logger.info(`Lighthouse ${id} updated`);

  return c.json({ data: result[0] });
});

// Mount protected routes under /api/v1
app.route("/api/v1", protectedRoutes);

export { app };
