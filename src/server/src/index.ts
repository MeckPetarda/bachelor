import {
  initDatabase,
  closeDatabase,
  testConnection,
  getDatabase,
  schema
} from "./database/client";

console.log("[Server] Starting attendance system server...");

// Initialize database
const db = initDatabase();

// Set up graceful shutdown handlers
let isShuttingDown = false;

async function gracefulShutdown(signal: string) {
  if (isShuttingDown) {
    console.log(`[Server] Shutdown already in progress, ignoring ${signal}`);
    return;
  }

  isShuttingDown = true;
  console.log(`\n[Server] Received ${signal}, starting graceful shutdown...`);

  try {
    // Close database connections
    await closeDatabase();
    console.log("[Server] Graceful shutdown completed");
    process.exit(0);
  } catch (error) {
    console.error("[Server] Error during shutdown:", error);
    process.exit(1);
  }
}

// Register shutdown handlers for common signals
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));

// Handle uncaught errors
process.on("uncaughtException", async (error) => {
  console.error("[Server] Uncaught exception:", error);
  await gracefulShutdown("uncaughtException");
});

process.on("unhandledRejection", async (reason, promise) => {
  console.error("[Server] Unhandled rejection at:", promise, "reason:", reason);
  await gracefulShutdown("unhandledRejection");
});

// Test database connection and query lighthouses table
async function startup() {
  try {
    // Test basic connectivity
    const connected = await testConnection();
    if (!connected) {
      throw new Error("Failed to connect to database");
    }

    // Query lighthouses table to verify schema
    console.log("[Server] Querying lighthouses table...");
    const lighthouses = await db.select().from(schema.lighthouses);
    console.log(`[Server] Found ${lighthouses.length} lighthouse(s) in database`);

    if (lighthouses.length > 0) {
      console.log("[Server] Lighthouses:");
      lighthouses.forEach((lh) => {
        console.log(`  - ${lh.name} (${lh.deviceId}): ${lh.isActive ? 'active' : 'inactive'}`);
      });
    }

    console.log("[Server] Server startup completed successfully");
  } catch (error) {
    console.error("[Server] Startup failed:", error);
    await gracefulShutdown("startup-failure");
  }
}

// Run startup
startup();
