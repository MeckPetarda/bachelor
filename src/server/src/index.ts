import {
  initDatabase,
  closeDatabase,
  testConnection,
  schema,
} from "./database/client";
import {
  startMqttBroker,
  closeMqttBroker,
  getMqttBrokerStats,
} from "./mqtt/broker";
import {
  startRetentionScheduler,
  stopRetentionScheduler,
} from "./database/cleanup";
import { startEventSweeper, stopEventSweeper } from "./services/event-sweeper";
import { app } from "./api/routes";
import { getConfig } from "./config";
import { createLogger } from "./utils/logger";
import {
  handleWebSocketOpen,
  handleWebSocketClose,
  handleWebSocketMessage,
  closeAllConnections,
} from "./api/websocket";

const logger = createLogger("Server");

logger.info("Starting attendance system server...");

// Initialize database
const db = initDatabase();

// HTTP server reference for graceful shutdown
let httpServer: ReturnType<typeof Bun.serve> | null = null;

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
    // Stop HTTP server first (stop accepting new requests)
    if (httpServer) {
      logger.info("Stopping HTTP server...");
      httpServer.stop();
      httpServer = null;
    }

    // Close all WebSocket connections
    closeAllConnections();

    // Stop retention cleanup scheduler
    stopRetentionScheduler();

    // Stop event sweeper (wait for any in-progress cycle)
    await stopEventSweeper();

    // Close MQTT broker (stop accepting new messages)
    await closeMqttBroker();

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

// Test database connection and start services
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
        logger.info(
          `  - ${lh.name} (${lh.deviceId}): ${lh.isActive ? "active" : "inactive"}`,
        );
      });
    }

    // Start MQTT broker
    startMqttBroker();

    // Log broker stats after a short delay to ensure it's fully started
    setTimeout(() => {
      const stats = getMqttBrokerStats();
      if (stats.isRunning) {
        logger.info(`MQTT broker running on port ${stats.port}`);
      }
    }, 100);

    // Start retention cleanup scheduler
    startRetentionScheduler();

    // Start event sweeper (background poller for closed RFID clusters)
    startEventSweeper();
    logger.info("Event sweeper started");

    // Start HTTP server with WebSocket support
    const config = getConfig();
    httpServer = Bun.serve({
      port: config.http.port,
      fetch(req, server) {
        // Check for WebSocket upgrade
        const url = new URL(req.url);
        if (url.pathname === "/ws") {
          const upgraded = server.upgrade(req, {
            data: { connectedAt: new Date() },
          });
          if (upgraded) {
            return undefined; // Bun handles the response
          }
          return new Response("WebSocket upgrade failed", { status: 500 });
        }

        // Handle regular HTTP requests via Hono
        return app.fetch(req);
      },
      websocket: {
        open(ws) {
          handleWebSocketOpen(ws as unknown as WebSocket);
        },
        close(ws) {
          handleWebSocketClose(ws as unknown as WebSocket);
        },
        message(ws, message) {
          handleWebSocketMessage(
            ws as unknown as WebSocket,
            typeof message === "string" ? message : Buffer.from(message),
          );
        },
      },
    });

    logger.info(`HTTP server running on port ${config.http.port}`);
    logger.info(
      `WebSocket endpoint available at ws://localhost:${config.http.port}/ws`,
    );
    logger.info("Server startup completed successfully");
  } catch (error) {
    logger.error("Startup failed:", error);
    await gracefulShutdown("startup-failure");
  }
}

// Run startup
startup();
