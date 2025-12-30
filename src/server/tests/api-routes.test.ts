import { describe, it, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { app } from "../src/api/routes";
import { initDatabase, closeDatabase, getDatabase, schema } from "../src/database/client";
import { startMqttBroker, closeMqttBroker } from "../src/mqtt/broker";
import { createJWT } from "../src/api/middleware";
import { getConfig } from "../src/config";
import { eq } from "drizzle-orm";

// Test configuration
const TEST_LIGHTHOUSE_ID = 998;
const TEST_DEVICE_ID = "test-api-lighthouse-001";
const TEST_USERNAME = "testadmin";
const TEST_PASSWORD = "testpassword123";

let authToken: string;

describe("REST API Endpoints", () => {
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

    // Clean up test data
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.id, TEST_LIGHTHOUSE_ID));

    await db
      .delete(schema.dashboardUsers)
      .where(eq(schema.dashboardUsers.username, TEST_USERNAME));

    // Close services
    await closeMqttBroker();
    await closeDatabase();
  });

  beforeEach(async () => {
    // Clean up test lighthouse before each test
    const db = getDatabase();
    await db
      .delete(schema.lighthouses)
      .where(eq(schema.lighthouses.id, TEST_LIGHTHOUSE_ID));
  });

  // ============================================================================
  // Health Endpoint Tests
  // ============================================================================

  describe("GET /health", () => {
    it("should return health status", async () => {
      const res = await app.request("/health");
      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.status).toBe("healthy");
      expect(body.services.database).toBe("connected");
      expect(body.services.mqtt).toBe("running");
      expect(body.timestamp).toBeDefined();
    });
  });

  // ============================================================================
  // Auth Endpoint Tests
  // ============================================================================

  describe("POST /api/v1/auth/login", () => {
    it("should return JWT token with valid credentials", async () => {
      const res = await app.request("/api/v1/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: TEST_USERNAME,
          password: TEST_PASSWORD,
        }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.token).toBeDefined();
      expect(body.user.username).toBe(TEST_USERNAME);
      expect(body.user.role).toBeDefined();
    });

    it("should reject invalid credentials", async () => {
      const res = await app.request("/api/v1/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: TEST_USERNAME,
          password: "wrongpassword",
        }),
      });

      expect(res.status).toBe(401);

      const body = await res.json();
      expect(body.error).toBe("Invalid credentials");
    });

    it("should reject non-existent user", async () => {
      const res = await app.request("/api/v1/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: "nonexistent",
          password: "password",
        }),
      });

      expect(res.status).toBe(401);
    });

    it("should reject missing credentials", async () => {
      const res = await app.request("/api/v1/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });

      expect(res.status).toBe(400);

      const body = await res.json();
      expect(body.error).toContain("Missing");
    });
  });

  // ============================================================================
  // JWT Authentication Tests
  // ============================================================================

  describe("JWT Authentication", () => {
    it("should reject requests without Authorization header", async () => {
      const res = await app.request("/api/v1/lighthouses");
      expect(res.status).toBe(401);

      const body = await res.json();
      expect(body.error).toContain("Unauthorized");
    });

    it("should reject requests with invalid token", async () => {
      const res = await app.request("/api/v1/lighthouses", {
        headers: { Authorization: "Bearer invalid.token.here" },
      });
      expect(res.status).toBe(401);
    });

    it("should accept requests with valid token", async () => {
      const res = await app.request("/api/v1/lighthouses", {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      expect(res.status).toBe(200);
    });
  });

  // ============================================================================
  // Lighthouse CRUD Tests
  // ============================================================================

  describe("GET /api/v1/lighthouses", () => {
    it("should return list of lighthouses", async () => {
      const res = await app.request("/api/v1/lighthouses", {
        headers: { Authorization: `Bearer ${authToken}` },
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(Array.isArray(body.data)).toBe(true);
      expect(typeof body.count).toBe("number");
    });
  });

  describe("POST /api/v1/lighthouses", () => {
    it("should create a new lighthouse", async () => {
      const res = await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "Test API Lighthouse",
          deviceId: TEST_DEVICE_ID,
          placement: "INSIDE",
          comment: "Created via API test",
        }),
      });

      expect(res.status).toBe(201);

      const body = await res.json();
      expect(body.data.id).toBe(TEST_LIGHTHOUSE_ID);
      expect(body.data.name).toBe("Test API Lighthouse");
      expect(body.data.deviceId).toBe(TEST_DEVICE_ID);
      expect(body.data.placement).toBe("INSIDE");
    });

    it("should reject duplicate lighthouse ID", async () => {
      // Create first lighthouse
      await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "First Lighthouse",
          deviceId: TEST_DEVICE_ID,
        }),
      });

      // Try to create duplicate
      const res = await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "Duplicate Lighthouse",
          deviceId: "different-device",
        }),
      });

      expect(res.status).toBe(409);

      const body = await res.json();
      expect(body.error).toContain("already exists");
    });

    it("should reject missing required fields", async () => {
      const res = await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "Missing ID",
        }),
      });

      expect(res.status).toBe(400);

      const body = await res.json();
      expect(body.error).toContain("Missing required fields");
    });
  });

  describe("GET /api/v1/lighthouses/:id", () => {
    it("should return lighthouse by ID", async () => {
      // Create a lighthouse first
      await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "Get Test Lighthouse",
          deviceId: TEST_DEVICE_ID,
        }),
      });

      const res = await app.request(`/api/v1/lighthouses/${TEST_LIGHTHOUSE_ID}`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.id).toBe(TEST_LIGHTHOUSE_ID);
      expect(body.data.name).toBe("Get Test Lighthouse");
    });

    it("should return 404 for non-existent lighthouse", async () => {
      const res = await app.request("/api/v1/lighthouses/99999", {
        headers: { Authorization: `Bearer ${authToken}` },
      });

      expect(res.status).toBe(404);

      const body = await res.json();
      expect(body.error).toContain("not found");
    });

    it("should return 400 for invalid ID format", async () => {
      const res = await app.request("/api/v1/lighthouses/invalid", {
        headers: { Authorization: `Bearer ${authToken}` },
      });

      expect(res.status).toBe(400);

      const body = await res.json();
      expect(body.error).toContain("Invalid");
    });
  });

  describe("PATCH /api/v1/lighthouses/:id", () => {
    it("should update lighthouse configuration", async () => {
      // Create a lighthouse first
      await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "Update Test Lighthouse",
          deviceId: TEST_DEVICE_ID,
        }),
      });

      const res = await app.request(`/api/v1/lighthouses/${TEST_LIGHTHOUSE_ID}`, {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "Updated Lighthouse Name",
          placement: "OUTSIDE",
          comment: "Updated via PATCH",
        }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.name).toBe("Updated Lighthouse Name");
      expect(body.data.placement).toBe("OUTSIDE");
      expect(body.data.comment).toBe("Updated via PATCH");
    });

    it("should return 404 for non-existent lighthouse", async () => {
      const res = await app.request("/api/v1/lighthouses/99999", {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ name: "New Name" }),
      });

      expect(res.status).toBe(404);
    });

    it("should update isActive flag", async () => {
      // Create a lighthouse first
      await app.request("/api/v1/lighthouses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: TEST_LIGHTHOUSE_ID,
          name: "Active Test Lighthouse",
          deviceId: TEST_DEVICE_ID,
        }),
      });

      const res = await app.request(`/api/v1/lighthouses/${TEST_LIGHTHOUSE_ID}`, {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ isActive: false }),
      });

      expect(res.status).toBe(200);

      const body = await res.json();
      expect(body.data.isActive).toBe(false);
    });
  });
});
