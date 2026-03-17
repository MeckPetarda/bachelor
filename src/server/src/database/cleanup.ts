/**
 * Retention cleanup for old health snapshots and connection events
 */

import { lt, sql } from "drizzle-orm";
import { getDatabase, schema } from "./client";
import { getConfig } from "../config";
import { createLogger } from "../utils/logger";

const logger = createLogger("Retention Cleanup");

// 24 hours in milliseconds
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Delete health snapshots older than the configured retention period
 * @returns The number of deleted rows
 */
export async function cleanupOldHealthSnapshots(): Promise<number> {
  const config = getConfig();
  const retentionDays = config.retention.healthRetentionDays;
  const cutoffDate = new Date(Date.now() - retentionDays * DAY_MS);

  const db = getDatabase();

  const result = await db
    .delete(schema.lighthouseHealthSnapshots)
    .where(lt(schema.lighthouseHealthSnapshots.recordedAt, cutoffDate))
    .returning({ id: schema.lighthouseHealthSnapshots.id });

  const deletedCount = result.length;

  if (deletedCount > 0) {
    logger.info(
      `Deleted ${deletedCount} health snapshots older than ${retentionDays} days`,
    );
  }

  return deletedCount;
}

/**
 * Delete connection events older than the configured retention period
 * @returns The number of deleted rows
 */
export async function cleanupOldConnectionEvents(): Promise<number> {
  const config = getConfig();
  const retentionDays = config.retention.connectionRetentionDays;
  const cutoffDate = new Date(Date.now() - retentionDays * DAY_MS);

  const db = getDatabase();

  const result = await db
    .delete(schema.lighthouseConnectionEvents)
    .where(lt(schema.lighthouseConnectionEvents.recordedAt, cutoffDate))
    .returning({ id: schema.lighthouseConnectionEvents.id });

  const deletedCount = result.length;

  if (deletedCount > 0) {
    logger.info(
      `Deleted ${deletedCount} connection events older than ${retentionDays} days`,
    );
  }

  return deletedCount;
}

/**
 * Run all retention cleanup tasks
 */
export async function runRetentionCleanup(): Promise<void> {
  logger.info("Starting retention cleanup...");

  try {
    const healthDeleted = await cleanupOldHealthSnapshots();
    const connectionDeleted = await cleanupOldConnectionEvents();

    logger.info(
      `Retention cleanup complete: ${healthDeleted} health snapshots, ${connectionDeleted} connection events deleted`,
    );
  } catch (error) {
    logger.error("Error during retention cleanup:", error);
    throw error;
  }
}

// Store interval ID for cleanup
let cleanupIntervalId: ReturnType<typeof setInterval> | null = null;

/**
 * Start the daily retention cleanup scheduler
 */
export function startRetentionScheduler(): void {
  // Run cleanup immediately on startup
  runRetentionCleanup().catch((error) => {
    logger.error("Initial retention cleanup failed:", error);
  });

  // Schedule daily cleanup (24 hours)
  cleanupIntervalId = setInterval(() => {
    runRetentionCleanup().catch((error) => {
      logger.error("Scheduled retention cleanup failed:", error);
    });
  }, DAY_MS);

  logger.info("Retention cleanup scheduler started (runs daily)");
}

/**
 * Stop the retention cleanup scheduler
 */
export function stopRetentionScheduler(): void {
  if (cleanupIntervalId) {
    clearInterval(cleanupIntervalId);
    cleanupIntervalId = null;
    logger.info("Retention cleanup scheduler stopped");
  }
}
