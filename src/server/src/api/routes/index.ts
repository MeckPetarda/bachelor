import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getDatabase, schema, isHealthy } from "../../database/client";
import { getMqttBrokerStats } from "../../mqtt/broker";
import { getConfig } from "../../config";
import { createLogger } from "../../utils/logger";
import { requestLogger, errorHandler, jwtAuth, createJWT } from "../middleware";

import devicesRoutes from "./devices";
import groupsRoutes from "./groups";
import lighthousesRoutes from "./lighthouses";
import scansRoutes from "./scans";
import usersRoutes from "./users";

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

// Mount protected routes under /api/v1 AFTER public routes
app.route("/api/v1", devicesRoutes);
app.route("/api/v1", groupsRoutes);
app.route("/api/v1", lighthousesRoutes);
app.route("/api/v1", scansRoutes);
app.route("/api/v1", usersRoutes);
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
