import { and, asc, eq, inArray, isNull, lt, sql, ne } from "drizzle-orm";
import { getDatabase, schema } from "../database/client";
import { createLogger } from "../utils/logger";
import { processCluster } from "./event-processor";
import type { ScanData } from "./algorithms/types";
import { broadcastOrphanedScan } from "../api/websocket";
import { hasActiveSyncInGroup } from "./sync-state";

const logger = createLogger("EventSweeper");

const POLLER_INTERVAL_MS = 2000;
const MAX_CLUSTERS_PER_CYCLE = 50;
const UNGROUPED_ORPHAN_TIMEOUT_MS = 10_000;

let intervalHandle: ReturnType<typeof setInterval> | null = null;
let shuttingDown = false;
let sweepInProgress: Promise<void> | null = null;

export function startEventSweeper(): void {
  if (intervalHandle !== null) {
    logger.warn("Event sweeper already running");
    return;
  }
  shuttingDown = false;
  intervalHandle = setInterval(() => {
    if (sweepInProgress !== null) return; // skip tick if previous cycle still running
    sweepInProgress = sweep().finally(() => {
      sweepInProgress = null;
    });
  }, POLLER_INTERVAL_MS);
  logger.info("Event sweeper started");
}

export async function stopEventSweeper(): Promise<void> {
  if (intervalHandle === null) return;
  clearInterval(intervalHandle);
  intervalHandle = null;
  shuttingDown = true;
  if (sweepInProgress !== null) {
    logger.info("Waiting for in-progress sweep cycle to complete...");
    await sweepInProgress;
  }
  logger.info("Event sweeper stopped");
}

// --- Sweep cycle --------------------------------------------------------------

async function sweep(): Promise<void> {
  if (shuttingDown) return;

  const db = getDatabase();
  const started = Date.now();
  let clustersFound = 0;
  let processed = 0;
  let orphaned = 0;
  let skipped = 0;

  try {
    // Step 1: Find closed clusters - those whose latest scan is older than
    // the group's activityTimeoutMs threshold.
    const closedClusters = await db
      .select({
        epc: schema.rawScans.epc,
        groupId: schema.lighthouses.groupId,
        activityTimeoutMs: schema.lighthouseGroups.activityTimeoutMs,
        orphanTimeoutMs: schema.lighthouseGroups.orphanTimeoutMs,
        latestScan: sql<Date>`MAX(${schema.rawScans.timestamp})`.as(
          "latest_scan",
        ),
        scanCount: sql<number>`COUNT(*)`.as("scan_count"),
      })
      .from(schema.rawScans)
      .innerJoin(
        schema.lighthouses,
        eq(schema.rawScans.lighthouseId, schema.lighthouses.id),
      )
      .innerJoin(
        schema.lighthouseGroups,
        eq(schema.lighthouses.groupId, schema.lighthouseGroups.id),
      )
      .where(
        and(
          isNull(schema.rawScans.processedAt),
          isNull(schema.rawScans.orphanedAt),
          ne(schema.rawScans.offlineSyncPending, true),
        ),
      )
      .groupBy(
        schema.rawScans.epc,
        schema.lighthouses.groupId,
        schema.lighthouseGroups.activityTimeoutMs,
        schema.lighthouseGroups.orphanTimeoutMs,
      )
      .having(
        sql`MAX(${schema.rawScans.timestamp}) < NOW() - (${schema.lighthouseGroups.activityTimeoutMs}::text || ' milliseconds')::interval`,
      )
      .limit(MAX_CLUSTERS_PER_CYCLE);

    clustersFound = closedClusters.length;

    // Step 2: Orphan scans for lighthouses that have no group assigned.
    await handleUngroupedScans();

    // Step 3: Process each closed cluster.
    for (const clusterMeta of closedClusters) {
      if (shuttingDown) break;

      const { epc } = clusterMeta;
      const groupId = clusterMeta.groupId;
      if (groupId === null) continue; // guarded by INNER JOIN, but satisfies TS

      // Fetch all constituent scans for this (epc, group) pair.
      const rawRows = await db
        .select()
        .from(schema.rawScans)
        .where(
          and(
            eq(schema.rawScans.epc, epc),
            inArray(
              schema.rawScans.lighthouseId,
              db
                .select({ id: schema.lighthouses.id })
                .from(schema.lighthouses)
                .where(eq(schema.lighthouses.groupId, groupId)),
            ),
            isNull(schema.rawScans.processedAt),
            isNull(schema.rawScans.orphanedAt),
            ne(schema.rawScans.offlineSyncPending, true),
          ),
        )
        .orderBy(asc(schema.rawScans.timestamp));

      if (rawRows.length === 0) continue; // already handled by a concurrent cycle

      // Split on internal gaps exceeding activityTimeoutMs. During live
      // operation the sweeper would never accumulate two bursts separated by
      // more than activityTimeoutMs — the first burst would already be closed
      // and processed. But offline replay delivers all scans at once, so we
      // must re-apply the same timeout logic post-hoc to avoid merging
      // separate traversal events into one artificially long cluster.
      const subClusters = splitByActivityGap(
        rawRows,
        clusterMeta.activityTimeoutMs,
      );

      // Fetch lighthouse IDs once — same for every sub-cluster in this group.
      const groupLhIds = await db
        .select({ id: schema.lighthouses.id })
        .from(schema.lighthouses)
        .where(eq(schema.lighthouses.groupId, groupId));

      for (const subRows of subClusters) {
        const scans: ScanData[] = subRows.map((s) => ({
          id: s.id,
          lighthouseId: s.lighthouseId,
          epc: s.epc,
          rssiDbm: s.rssiDbm ?? null,
          timestamp: s.timestamp,
          timeBasis: s.timeBasis,
        }));

        const result = await processCluster(scans, groupId, epc);

        if (result.processed) {
          processed++;
          continue;
        }

        if (result.reason === "misconfigured_group") {
          await orphanScans(subRows, "misconfigured_group");
          orphaned += subRows.length;
        } else if (result.reason === "unsyncable") {
          const nonSynced = subRows.filter((s) => s.timeBasis !== "synced");
          if (nonSynced.length > 0) {
            await orphanScans(nonSynced, "unsyncable");
            orphaned += nonSynced.length;
          }
        } else if (result.reason === "insufficient_data") {
          // Hold off if any lighthouse in this group is currently replaying
          // offline events, or recently completed a replay (partner may not
          // have connected yet).
          if (hasActiveSyncInGroup(groupLhIds.map((l) => l.id))) {
            skipped++;
            continue;
          }

          // For offline-replayed scans the scan timestamp is old (from before
          // the outage), so age measured against it would always exceed the
          // orphan timeout. Use receivedAt (server insert time) instead so
          // the timeout reflects how long the server has been waiting, not
          // how old the physical scan is.
          const hasOfflineScan = subRows.some(
            (s) => s.source === "offline_sync",
          );
          const subLatest = hasOfflineScan
            ? new Date(
                Math.max(...subRows.map((s) => (s.receivedAt ?? s.timestamp).getTime())),
              )
            : subRows[subRows.length - 1]!.timestamp;

          const ageMs = Date.now() - subLatest.getTime();
          if (ageMs > clusterMeta.orphanTimeoutMs) {
            await orphanScans(subRows, "insufficient_data");
            orphaned += subRows.length;
          } else {
            skipped++;
          }
        }
      }
    }

    const durationMs = Date.now() - started;
    if (
      clustersFound !== 0 ||
      processed !== 0 ||
      orphaned !== 0 ||
      skipped !== 0
    ) {
      logger.info(
        `Sweep done in ${durationMs}ms - found: ${clustersFound}, processed: ${processed}, orphaned: ${orphaned}, skipped: ${skipped}`,
      );
    }
  } catch (error) {
    logger.error("Sweep error:", error);
  }
}

// --- Helpers ------------------------------------------------------------------

/**
 * Mark scans for lighthouses with no group as misconfigured, once they exceed
 * the fixed ungrouped orphan timeout.
 */
async function handleUngroupedScans(): Promise<void> {
  const db = getDatabase();
  const cutoff = new Date(Date.now() - UNGROUPED_ORPHAN_TIMEOUT_MS);

  const ungroupedRows = await db
    .select({
      id: schema.rawScans.id,
      epc: schema.rawScans.epc,
      lighthouseId: schema.rawScans.lighthouseId,
      timestamp: schema.rawScans.timestamp,
    })
    .from(schema.rawScans)
    .innerJoin(
      schema.lighthouses,
      eq(schema.rawScans.lighthouseId, schema.lighthouses.id),
    )
    .where(
      and(
        isNull(schema.lighthouses.groupId),
        isNull(schema.rawScans.processedAt),
        isNull(schema.rawScans.orphanedAt),
        ne(schema.rawScans.offlineSyncPending, true),
        lt(schema.rawScans.timestamp, cutoff),
      ),
    );

  if (ungroupedRows.length > 0) {
    logger.debug(`Orphaning ${ungroupedRows.length} ungrouped scan(s)`);
    await orphanScans(ungroupedRows, "misconfigured_group");
  }
}

type OrphanableRow = {
  id: bigint;
  epc: string;
  lighthouseId: number;
  timestamp: Date;
};

/**
 * Bulk-update scans to orphaned state and broadcast an `event:orphaned` WS
 * message for each one.
 */
async function orphanScans(
  scans: OrphanableRow[],
  reason: "misconfigured_group" | "unsyncable" | "insufficient_data",
): Promise<void> {
  const db = getDatabase();
  const scanIds = scans.map((s) => s.id);
  const now = new Date();

  await db
    .update(schema.rawScans)
    .set({ orphanedAt: now, orphanReason: reason })
    .where(inArray(schema.rawScans.id, scanIds));

  for (const scan of scans) {
    broadcastOrphanedScan({
      scanId: scan.id.toString(),
      epc: scan.epc,
      lighthouseId: scan.lighthouseId,
      timestamp: scan.timestamp.toISOString(),
      orphanReason: reason,
    });
  }
}

function splitByActivityGap<T extends { timestamp: Date }>(
  rows: T[],
  gapMs: number,
): T[][] {
  if (rows.length === 0) return [];
  const result: T[][] = [];
  let current: T[] = [rows[0]!];
  for (let i = 1; i < rows.length; i++) {
    const gap =
      rows[i]!.timestamp.getTime() - rows[i - 1]!.timestamp.getTime();
    if (gap > gapMs) {
      result.push(current);
      current = [rows[i]!];
    } else {
      current.push(rows[i]!);
    }
  }
  result.push(current);
  return result;
}
