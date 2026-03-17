import postgres from "postgres";
import { drizzle } from "drizzle-orm/postgres-js";
import { getConfig } from "../config/index.ts";
import * as schema from "./schema";
import { createLogger } from "../utils/logger.ts";

let sql: ReturnType<typeof postgres> | null = null;
let db: ReturnType<typeof drizzle<typeof schema>> | null = null;
let isShuttingDown = false;

// Logger helper for consistent output
const logger = createLogger("Database");

/**
 * Initialize the PostgreSQL connection pool
 * @throws Error if connection fails
 */
export function initDatabase(): ReturnType<typeof drizzle<typeof schema>> {
  if (db) {
    logger.debug("Database already initialized, returning existing instance");
    return db;
  }

  const config = getConfig();

  try {
    logger.info("Initializing PostgreSQL connection pool...");
    logger.debug(
      `Connecting to: ${config.database.url.replace(/\/\/[^:]+:[^@]+@/, "//***:***@")}`,
    );

    sql = postgres(config.database.url, {
      max: 20, // Maximum number of connections in pool
      idle_timeout: 20, // Close idle connections after 20 seconds
      connect_timeout: 10, // Connection timeout in seconds
      prepare: false, // Disable prepared statements for better compatibility
      onnotice: (notice) => logger.debug("PostgreSQL notice:", notice.message),
      debug:
        config.nodeEnv === "development"
          ? (_connection, query, _params) => {
              logger.debug(
                `Query: ${query.substring(0, 100)}${query.length > 100 ? "..." : ""}`,
              );
            }
          : undefined,
    });

    db = drizzle(sql, { schema, casing: "snake_case" });

    logger.info("Connection pool initialized successfully");

    return db;
  } catch (error) {
    logger.error("Failed to initialize database connection pool:", error);
    throw error;
  }
}

/**
 * Get the database instance (initializes if not already done)
 * @throws Error if database is shutting down or initialization fails
 */
export function getDatabase(): ReturnType<typeof drizzle<typeof schema>> {
  if (isShuttingDown) {
    throw new Error("Database is shutting down, cannot get connection");
  }

  if (!db) {
    return initDatabase();
  }
  return db;
}

/**
 * Get the raw postgres client for advanced queries
 * @throws Error if database is shutting down
 */
export function getSql(): ReturnType<typeof postgres> {
  if (isShuttingDown) {
    throw new Error("Database is shutting down, cannot get connection");
  }

  if (!sql) {
    initDatabase();
  }
  return sql!;
}

/**
 * Close the database connection pool gracefully
 * @param timeout - Maximum time to wait for connections to close (ms)
 */
export async function closeDatabase(timeout = 5000): Promise<void> {
  if (!sql) {
    logger.debug("No database connection to close");
    return;
  }

  if (isShuttingDown) {
    logger.warn("Database shutdown already in progress");
    return;
  }

  isShuttingDown = true;
  logger.info("Closing database connection pool...");

  try {
    // Create a timeout promise
    const timeoutPromise = new Promise<void>((_, reject) => {
      setTimeout(
        () => reject(new Error("Database shutdown timed out")),
        timeout,
      );
    });

    // Race between graceful close and timeout
    await Promise.race([sql.end({ timeout: timeout / 1000 }), timeoutPromise]);

    sql = null;
    db = null;
    logger.info("Connection pool closed successfully");
  } catch (error) {
    logger.error("Error closing database connection pool:", error);
    // Force cleanup even on error
    sql = null;
    db = null;
    throw error;
  } finally {
    isShuttingDown = false;
  }
}

/**
 * Test the database connection
 * @returns true if connection is successful, false otherwise
 */
export async function testConnection(): Promise<boolean> {
  try {
    logger.debug("Testing database connection...");
    const result = await getSql()`SELECT 1 as test`;
    const success = result.length > 0 && result[0]?.test === 1;
    if (success) {
      logger.info("Database connection test successful");
    }
    return success;
  } catch (error) {
    logger.error("Connection test failed:", error);
    return false;
  }
}

/**
 * Check if the database is connected and healthy
 */
export async function isHealthy(): Promise<boolean> {
  if (isShuttingDown || !sql) {
    return false;
  }
  return testConnection();
}

/**
 * Get connection pool statistics (for monitoring)
 */
export function getPoolStats(): {
  isInitialized: boolean;
  isShuttingDown: boolean;
} {
  return {
    isInitialized: sql !== null,
    isShuttingDown,
  };
}

// ============================================================================
// Query Helper Functions
// ============================================================================

/**
 * Execute a query with automatic error handling and logging
 * @param queryFn - Function that executes the query
 * @returns The query result
 */
export async function executeQuery<T>(queryFn: () => Promise<T>): Promise<T> {
  const startTime = performance.now();

  try {
    const result = await queryFn();
    const duration = performance.now() - startTime;
    logger.debug(`Query executed in ${duration.toFixed(2)}ms`);
    return result;
  } catch (error) {
    const duration = performance.now() - startTime;
    logger.error(`Query failed after ${duration.toFixed(2)}ms:`, error);
    throw error;
  }
}

type TransactionCallback<T> = Parameters<
  ReturnType<typeof drizzle<typeof schema>>["transaction"]
>[0] extends (tx: infer Tx) => unknown
  ? (tx: Tx) => Promise<T>
  : never;

/**
 * Execute a query within a transaction
 * @param txFn - Function that receives the transaction and executes queries
 * @returns The transaction result
 */
export async function withTransaction<T>(
  txFn: TransactionCallback<T>,
): Promise<T> {
  const database = getDatabase();
  const startTime = performance.now();

  try {
    logger.debug("Starting transaction...");
    const result = await database.transaction(txFn);
    const duration = performance.now() - startTime;
    logger.debug(`Transaction completed in ${duration.toFixed(2)}ms`);
    return result;
  } catch (error) {
    const duration = performance.now() - startTime;
    logger.error(`Transaction failed after ${duration.toFixed(2)}ms:`, error);
    throw error;
  }
}

/**
 * Execute a raw SQL query with parameters
 * @param query - SQL template literal
 * @returns The query result
 */
export async function rawQuery<T extends postgres.Row[]>(
  queryFn: (sql: ReturnType<typeof postgres>) => Promise<T>,
): Promise<T> {
  return executeQuery(() => queryFn(getSql()));
}

export { schema };
