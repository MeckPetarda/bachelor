import {
  initDatabase,
  closeDatabase,
  testConnection,
  schema
} from "./database/client";
import { createLogger } from "./utils/logger";

const logger = createLogger("Server")

logger.info("Starting attendance system server...");

// Initialize database
const db = initDatabase();

// Set up graceful shutdown handlers
let isShuttingDown = false;

async function gracefulShutdown(signal: string) {
  if (isShuttingDown) {
    logger.info(`Shutdown already in progress, ignoring ${signal}`);
    return;
  }

  isShuttingDown = true;
  logger.info(`\nReceived ${signal}, starting graceful shutdown...`);

  try {
    // Close database connections
    await closeDatabase();
    logger.info("Graceful shutdown completed");
    process.exit(0);
  } catch (error) {
    logger.error("Error during shutdown:", error);
    process.exit(1);
  }
}

// Register shutdown handlers for common signals
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));

// Handle uncaught errors
process.on("uncaughtException", async (error) => {
  logger.error("Uncaught exception:", error);
  await gracefulShutdown("uncaughtException");
});

process.on("unhandledRejection", async (reason, promise) => {
  logger.error("Unhandled rejection at:", promise, "reason:", reason);
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
    logger.info("Querying lighthouses table...");
    const lighthouses = await db.select().from(schema.lighthouses);
    logger.info(`Found ${lighthouses.length} lighthouse(s) in database`);

    if (lighthouses.length > 0) {
      logger.info("Lighthouses:");
      lighthouses.forEach((lh) => {
        logger.info(`  - ${lh.name} (${lh.deviceId}): ${lh.isActive ? 'active' : 'inactive'}`);
      });
    }

    logger.info("Server startup completed successfully");
  } catch (error) {
    logger.error("Startup failed:", error);
    await gracefulShutdown("startup-failure");
  }
}

// Run startup
startup();
