import { eq, inArray } from "drizzle-orm";
import { getDatabase, schema, withTransaction } from "../database/client";
import { createLogger } from "../utils/logger";
import { resolveTagUser } from "./tag-resolver";
import { analyzeTemporalCentroid } from "./algorithms/temporal-centroid";
import { analyzeRssiWeightedCentroid } from "./algorithms/rssi-weighted-centroid";
import type {
  ScanData,
  PartitionedCluster,
  AlgorithmResult,
} from "./algorithms/types";
import {
  broadcastTraversalEvent,
  type TraversalEventPayload,
} from "../api/websocket";

const logger = createLogger("EventProcessor");

export type ProcessResult =
  | { processed: true }
  | {
      processed: false;
      reason: "misconfigured_group" | "unsyncable" | "insufficient_data";
    };

/**
 * Process a closed cluster of raw scans for one EPC in one group.
 *
 * Validates prerequisites, runs both direction-detection algorithms, writes
 * all results atomically, and broadcasts WebSocket events.
 *
 * Returns { processed: true } on success or { processed: false, reason } when
 * the cluster cannot be processed (caller decides how to handle the scans).
 */
export async function processCluster(
  scans: ScanData[],
  groupId: number,
  epc: string,
): Promise<ProcessResult> {
  const db = getDatabase();

  // -- Step 1: Validate group config -----------------------------------------
  // The group must contain exactly one INSIDE and one OUTSIDE lighthouse.

  const groupLighthouses = await db
    .select({
      id: schema.lighthouses.id,
      placement: schema.lighthouses.placement,
    })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.groupId, groupId));

  const insideLighthouses = groupLighthouses.filter(
    (l) => l.placement === "INSIDE",
  );
  const outsideLighthouses = groupLighthouses.filter(
    (l) => l.placement === "OUTSIDE",
  );

  if (insideLighthouses.length !== 1 || outsideLighthouses.length !== 1) {
    logger.warn(
      `Group ${groupId}: misconfigured - found ${insideLighthouses.length} INSIDE, ${outsideLighthouses.length} OUTSIDE lighthouses`,
    );
    return { processed: false, reason: "misconfigured_group" };
  }

  const insideLighthouseId = insideLighthouses[0]!.id;
  const outsideLighthouseId = outsideLighthouses[0]!.id;

  // -- Step 2: Filter to synced scans only -----------------------------------

  const syncedScans = scans.filter((s) => s.timeBasis === "synced");
  if (syncedScans.length === 0) {
    logger.warn(
      `EPC ${epc} group ${groupId}: all ${scans.length} scans are non-synced`,
    );
    return { processed: false, reason: "unsyncable" };
  }

  // -- Step 3: Partition by lighthouse ---------------------------------------

  const insideScans = syncedScans.filter(
    (s) => s.lighthouseId === insideLighthouseId,
  );
  const outsideScans = syncedScans.filter(
    (s) => s.lighthouseId === outsideLighthouseId,
  );

  // -- Step 4: Validate bilateral coverage -----------------------------------

  if (insideScans.length === 0 || outsideScans.length === 0) {
    logger.debug(
      `EPC ${epc} group ${groupId}: insufficient bilateral data ` +
        `(inside=${insideScans.length}, outside=${outsideScans.length})`,
    );
    return { processed: false, reason: "insufficient_data" };
  }

  // -- Step 5: Build PartitionedCluster --------------------------------------

  const allScans = [...outsideScans, ...insideScans];
  const times = allScans.map((s) => s.timestamp.getTime());
  const cluster: PartitionedCluster = {
    epc,
    groupId,
    outsideScans,
    insideScans,
    allScans,
    clusterStartedAt: new Date(Math.min(...times)),
    clusterEndedAt: new Date(Math.max(...times)),
  };

  // -- Step 6: Resolve user --------------------------------------------------

  const userId = await resolveTagUser(epc);

  // -- Steps 7 & 8: Run both algorithms --------------------------------------

  const result1 = analyzeTemporalCentroid(cluster);
  const result2 = analyzeRssiWeightedCentroid(cluster);

  // -- Step 9: Atomic write --------------------------------------------------

  const scanIds = allScans.map((s) => s.id);

  const { eventId1, eventId2 } = await withTransaction(async (tx) => {
    // Insert both processed_events rows
    const [ev1, ev2] = await Promise.all([
      insertEvent(tx, result1, epc, userId, groupId, cluster),
      insertEvent(tx, result2, epc, userId, groupId, cluster),
    ]);

    // Insert junction rows: each scan linked to both events
    const junctionRows = scanIds.flatMap((rawScanId) => [
      { processedEventId: ev1.id, rawScanId },
      { processedEventId: ev2.id, rawScanId },
    ]);
    await tx.insert(schema.processedEventScans).values(junctionRows);

    // Mark all scans as processed
    await tx
      .update(schema.rawScans)
      .set({ processedAt: new Date() })
      .where(inArray(schema.rawScans.id, scanIds));

    return { eventId1: ev1.id, eventId2: ev2.id };
  });

  logger.info(
    `Processed EPC ${epc} group ${groupId}: ` +
      `algo1=${result1.direction}(${result1.confidence.toFixed(3)}) ` +
      `algo2=${result2.direction}(${result2.confidence.toFixed(3)})`,
  );

  // -- Step 10: Broadcast (after commit, non-blocking) -----------------------

  setImmediate(() => {
    broadcastEvent(
      eventId1,
      result1,
      epc,
      userId,
      groupId,
      cluster,
      scanIds.length,
    );
    broadcastEvent(
      eventId2,
      result2,
      epc,
      userId,
      groupId,
      cluster,
      scanIds.length,
    );
  });

  return { processed: true };
}

// --- Helpers ------------------------------------------------------------------

type Tx = Parameters<
  Parameters<ReturnType<typeof getDatabase>["transaction"]>[0]
>[0];

async function insertEvent(
  tx: Tx,
  result: AlgorithmResult,
  epc: string,
  userId: string | null,
  groupId: number,
  cluster: PartitionedCluster,
): Promise<{ id: string }> {
  const rows = await tx
    .insert(schema.processedEvents)
    .values({
      algorithmId: result.algorithmId,
      direction: result.direction,
      tagEpc: epc,
      userId: userId ?? undefined,
      groupId,
      confidence: result.confidence,
      centroidSeparationFactor: result.centroidSeparationFactor,
      clusterSizeFactor: result.clusterSizeFactor,
      bilateralCoverageFactor: result.bilateralCoverageFactor,
      rssiTrendConsistencyFactor:
        result.rssiTrendConsistencyFactor ?? undefined,
      timestamp: result.timestamp,
      clusterStartedAt: cluster.clusterStartedAt,
      clusterEndedAt: cluster.clusterEndedAt,
      metadata: result.metadata,
      syncedToIntegration: false,
    })
    .returning({ id: schema.processedEvents.id });

  const row = rows[0];
  if (!row) throw new Error("Failed to insert processed_event");
  return row;
}

function broadcastEvent(
  eventId: string,
  result: AlgorithmResult,
  epc: string,
  userId: string | null,
  groupId: number,
  cluster: PartitionedCluster,
  scanCount: number,
): void {
  const payload: TraversalEventPayload = {
    id: eventId,
    algorithmId: result.algorithmId,
    direction: result.direction,
    tagEpc: epc,
    userId,
    groupId,
    confidence: result.confidence,
    timestamp: result.timestamp.toISOString(),
    clusterStartedAt: cluster.clusterStartedAt.toISOString(),
    clusterEndedAt: cluster.clusterEndedAt.toISOString(),
    scanCount,
  };
  broadcastTraversalEvent(payload);
}
