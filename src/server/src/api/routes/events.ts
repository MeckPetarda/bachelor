import { Hono } from "hono";
import { getDatabase, schema } from "../../database/client";
import { and, desc, eq, gte, isNotNull, isNull, lte, sql } from "drizzle-orm";
import { createLogger } from "../../utils/logger";
import { resolveTagUser } from "../../services/tag-resolver";

const logger = createLogger("Events");

const router = new Hono();

/**
 * List processed traversal events with filtering
 * GET /api/v1/events
 *
 * Required: algorithmId
 * Optional: groupId, userId, tagEpc, direction, from, to, minConfidence,
 *           limit (default 50, max 500), offset (default 0)
 */
router.get("/events", async (c) => {
  const q = c.req.query();

  if (!q.algorithmId) {
    return c.json({ error: "Missing required query parameter: algorithmId" }, 400);
  }

  const validAlgorithms = ["temporal_centroid", "rssi_weighted_centroid", "manual"];
  if (!validAlgorithms.includes(q.algorithmId)) {
    return c.json(
      { error: `Invalid algorithmId. Must be one of: ${validAlgorithms.join(", ")}` },
      400,
    );
  }

  const rawLimit = parseInt(q.limit ?? "50", 10);
  const limit = Math.min(isNaN(rawLimit) ? 50 : rawLimit, 500);
  const rawOffset = parseInt(q.offset ?? "0", 10);
  const offset = isNaN(rawOffset) ? 0 : rawOffset;

  // Build filter conditions
  type AlgorithmId = "temporal_centroid" | "rssi_weighted_centroid" | "manual";
  type Direction = "in" | "out" | "unknown";

  const conditions = [
    eq(
      schema.processedEvents.algorithmId,
      q.algorithmId as AlgorithmId,
    ),
  ];

  if (q.groupId) {
    const gid = parseInt(q.groupId, 10);
    if (!isNaN(gid)) conditions.push(eq(schema.processedEvents.groupId, gid));
  }
  if (q.userId) conditions.push(eq(schema.processedEvents.userId, q.userId));
  if (q.tagEpc) conditions.push(eq(schema.processedEvents.tagEpc, q.tagEpc));
  if (q.direction) {
    conditions.push(eq(schema.processedEvents.direction, q.direction as Direction));
  }
  if (q.from) {
    const from = new Date(q.from);
    if (!isNaN(from.getTime())) {
      conditions.push(gte(schema.processedEvents.timestamp, from));
    }
  }
  if (q.to) {
    const to = new Date(q.to);
    if (!isNaN(to.getTime())) {
      conditions.push(lte(schema.processedEvents.timestamp, to));
    }
  }
  if (q.minConfidence) {
    const mc = parseFloat(q.minConfidence);
    if (!isNaN(mc)) {
      conditions.push(gte(schema.processedEvents.confidence, mc));
    }
  }

  const db = getDatabase();

  const rows = await db
    .select({
      id: schema.processedEvents.id,
      algorithmId: schema.processedEvents.algorithmId,
      direction: schema.processedEvents.direction,
      tagEpc: schema.processedEvents.tagEpc,
      userId: schema.processedEvents.userId,
      groupId: schema.processedEvents.groupId,
      confidence: schema.processedEvents.confidence,
      centroidSeparationFactor: schema.processedEvents.centroidSeparationFactor,
      clusterSizeFactor: schema.processedEvents.clusterSizeFactor,
      bilateralCoverageFactor: schema.processedEvents.bilateralCoverageFactor,
      rssiTrendConsistencyFactor: schema.processedEvents.rssiTrendConsistencyFactor,
      timestamp: schema.processedEvents.timestamp,
      clusterStartedAt: schema.processedEvents.clusterStartedAt,
      clusterEndedAt: schema.processedEvents.clusterEndedAt,
      createdAt: schema.processedEvents.createdAt,
      // Correlated subquery: count linked raw scans for this event
      scanCount: sql<number>`(
        SELECT COUNT(*)
        FROM processed_event_scans pes
        WHERE pes.processed_event_id = ${schema.processedEvents.id}
      )`,
    })
    .from(schema.processedEvents)
    .where(and(...conditions))
    .orderBy(desc(schema.processedEvents.timestamp))
    .limit(limit)
    .offset(offset);

  const data = rows.map((r) => ({
    id: r.id,
    algorithmId: r.algorithmId,
    direction: r.direction,
    tagEpc: r.tagEpc,
    userId: r.userId ?? null,
    groupId: r.groupId,
    confidence: r.confidence,
    centroidSeparationFactor: r.centroidSeparationFactor,
    clusterSizeFactor: r.clusterSizeFactor,
    bilateralCoverageFactor: r.bilateralCoverageFactor,
    rssiTrendConsistencyFactor: r.rssiTrendConsistencyFactor ?? null,
    timestamp: r.timestamp.toISOString(),
    clusterStartedAt: r.clusterStartedAt.toISOString(),
    clusterEndedAt: r.clusterEndedAt.toISOString(),
    scanCount: Number(r.scanCount),
    createdAt: r.createdAt.toISOString(),
  }));

  return c.json({ data, count: data.length, limit, offset });
});

/**
 * List orphaned (unresolved) raw scans
 * GET /api/v1/events/unresolved
 *
 * Optional: groupId, orphanReason, tagEpc, from, to, limit, offset
 */
router.get("/events/unresolved", async (c) => {
  const q = c.req.query();

  const rawLimit = parseInt(q.limit ?? "50", 10);
  const limit = Math.min(isNaN(rawLimit) ? 50 : rawLimit, 500);
  const rawOffset = parseInt(q.offset ?? "0", 10);
  const offset = isNaN(rawOffset) ? 0 : rawOffset;

  type OrphanReason = "insufficient_data" | "misconfigured_group" | "unsyncable";

  const conditions = [
    isNotNull(schema.rawScans.orphanedAt),
    isNull(schema.rawScans.processedAt),
  ];

  if (q.groupId) {
    const gid = parseInt(q.groupId, 10);
    if (!isNaN(gid)) conditions.push(eq(schema.lighthouses.groupId, gid));
  }
  if (q.orphanReason) {
    conditions.push(eq(schema.rawScans.orphanReason, q.orphanReason as OrphanReason));
  }
  if (q.tagEpc) conditions.push(eq(schema.rawScans.epc, q.tagEpc));
  if (q.from) {
    const from = new Date(q.from);
    if (!isNaN(from.getTime())) {
      conditions.push(gte(schema.rawScans.timestamp, from));
    }
  }
  if (q.to) {
    const to = new Date(q.to);
    if (!isNaN(to.getTime())) {
      conditions.push(lte(schema.rawScans.timestamp, to));
    }
  }

  const db = getDatabase();

  const rows = await db
    .select({
      id: schema.rawScans.id,
      epc: schema.rawScans.epc,
      lighthouseId: schema.rawScans.lighthouseId,
      lighthouseName: schema.lighthouses.name,
      rssiDbm: schema.rawScans.rssiDbm,
      timestamp: schema.rawScans.timestamp,
      orphanedAt: schema.rawScans.orphanedAt,
      orphanReason: schema.rawScans.orphanReason,
    })
    .from(schema.rawScans)
    .innerJoin(
      schema.lighthouses,
      eq(schema.rawScans.lighthouseId, schema.lighthouses.id),
    )
    .where(and(...conditions))
    .orderBy(desc(schema.rawScans.orphanedAt))
    .limit(limit)
    .offset(offset);

  // Resolve userId for each unique EPC in the result set
  const uniqueEpcs = [...new Set(rows.map((r) => r.epc))];
  const resolutions = await Promise.all(
    uniqueEpcs.map((epc) =>
      resolveTagUser(epc).then((userId) => ({ epc, userId })),
    ),
  );
  const epcToUser = new Map(resolutions.map((r) => [r.epc, r.userId]));

  const data = rows.map((r) => ({
    scanId: r.id.toString(),
    epc: r.epc,
    lighthouseId: r.lighthouseId,
    lighthouseName: r.lighthouseName,
    rssiDbm: r.rssiDbm ?? null,
    timestamp: r.timestamp.toISOString(),
    orphanedAt: r.orphanedAt!.toISOString(),
    orphanReason: r.orphanReason,
    userId: epcToUser.get(r.epc) ?? null,
  }));

  return c.json({ data, count: data.length, limit, offset });
});

/**
 * Create a manual traversal event
 * POST /api/v1/events/manual
 */
router.post("/events/manual", async (c) => {
  const body = await c.req.json<{
    tagEpc: string;
    direction: string;
    timestamp: string;
    groupId: number;
    notes?: string;
  }>();

  if (!body.tagEpc || typeof body.tagEpc !== "string") {
    return c.json({ error: "Missing required field: tagEpc" }, 400);
  }
  if (body.direction !== "in" && body.direction !== "out") {
    return c.json({ error: "direction must be 'in' or 'out'" }, 400);
  }
  if (!body.timestamp) {
    return c.json({ error: "Missing required field: timestamp" }, 400);
  }
  const eventTime = new Date(body.timestamp);
  if (isNaN(eventTime.getTime())) {
    return c.json({ error: "timestamp must be a valid ISO 8601 date" }, 400);
  }
  if (!body.groupId || typeof body.groupId !== "number") {
    return c.json({ error: "Missing required field: groupId" }, 400);
  }

  const db = getDatabase();

  // Verify the group exists
  const group = await db
    .select({ id: schema.lighthouseGroups.id })
    .from(schema.lighthouseGroups)
    .where(eq(schema.lighthouseGroups.id, body.groupId))
    .limit(1);

  if (group.length === 0) {
    return c.json({ error: "Group not found" }, 400);
  }

  const userId = await resolveTagUser(body.tagEpc);

  const result = await db
    .insert(schema.processedEvents)
    .values({
      algorithmId: "manual",
      direction: body.direction as "in" | "out",
      tagEpc: body.tagEpc,
      userId: userId ?? undefined,
      groupId: body.groupId,
      confidence: 1.0,
      centroidSeparationFactor: 1.0,
      clusterSizeFactor: 1.0,
      bilateralCoverageFactor: 1.0,
      rssiTrendConsistencyFactor: undefined,
      timestamp: eventTime,
      clusterStartedAt: eventTime,
      clusterEndedAt: eventTime,
      metadata: body.notes ? { notes: body.notes } : {},
      syncedToIntegration: false,
    })
    .returning();

  const created = result[0];
  if (!created) {
    return c.json({ error: "Failed to create event" }, 500);
  }

  logger.info(`Manual event created for EPC ${body.tagEpc} (${body.direction})`);

  return c.json(
    {
      id: created.id,
      algorithmId: created.algorithmId,
      direction: created.direction,
      tagEpc: created.tagEpc,
      userId: created.userId ?? null,
      groupId: created.groupId,
      confidence: created.confidence,
      centroidSeparationFactor: created.centroidSeparationFactor,
      clusterSizeFactor: created.clusterSizeFactor,
      bilateralCoverageFactor: created.bilateralCoverageFactor,
      rssiTrendConsistencyFactor: created.rssiTrendConsistencyFactor ?? null,
      timestamp: created.timestamp.toISOString(),
      clusterStartedAt: created.clusterStartedAt.toISOString(),
      clusterEndedAt: created.clusterEndedAt.toISOString(),
      metadata: created.metadata,
      createdAt: created.createdAt.toISOString(),
    },
    201,
  );
});

export default router;
