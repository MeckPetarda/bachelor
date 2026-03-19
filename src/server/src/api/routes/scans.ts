import { Hono } from "hono";
import { getDatabase, schema } from "../../database/client";
import { and, count, desc, eq, gte, ilike, lte, sql } from "drizzle-orm";
import { createLogger } from "../../utils/logger";
import { errorHandler, requestLogger } from "../middleware";

const logger = createLogger("Routes");

// Create Hono router with middleware
const router = new Hono();

// Apply global middleware
router.use("*", requestLogger);
router.use("*", errorHandler);

/**
 * Query raw scan events with filtering and pagination
 * GET /api/v1/scans
 */
router.get("/scans", async (c) => {
  const db = getDatabase();

  // Parse query parameters
  const lighthouseIdParam = c.req.query("lighthouseId");
  const epcParam = c.req.query("epc");
  const sourceParam = c.req.query("source");
  const fromParam = c.req.query("from");
  const toParam = c.req.query("to");
  const limitParam = c.req.query("limit");
  const offsetParam = c.req.query("offset");

  // Parse and validate numeric params
  let limit = 50;
  if (limitParam) {
    const parsed = parseInt(limitParam, 10);
    if (!isNaN(parsed) && parsed > 0) {
      limit = Math.min(parsed, 500); // Cap at 500
    }
  }

  let offset = 0;
  if (offsetParam) {
    const parsed = parseInt(offsetParam, 10);
    if (!isNaN(parsed) && parsed >= 0) {
      offset = parsed;
    }
  }

  // Build conditions array
  const conditions: ReturnType<typeof eq>[] = [];

  if (lighthouseIdParam) {
    const lighthouseId = parseInt(lighthouseIdParam, 10);
    if (!isNaN(lighthouseId)) {
      conditions.push(eq(schema.rawScans.lighthouseId, lighthouseId));
    }
  }

  if (epcParam) {
    conditions.push(ilike(schema.rawScans.epc, `%${epcParam}%`));
  }

  if (
    sourceParam &&
    (sourceParam === "realtime" || sourceParam === "offline_sync")
  ) {
    conditions.push(eq(schema.rawScans.source, sourceParam));
  }

  if (fromParam) {
    const fromDate = new Date(fromParam);
    if (!isNaN(fromDate.getTime())) {
      conditions.push(gte(schema.rawScans.timestamp, fromDate));
    }
  }

  if (toParam) {
    const toDate = new Date(toParam);
    if (!isNaN(toDate.getTime())) {
      conditions.push(lte(schema.rawScans.timestamp, toDate));
    }
  }

  // Get total count
  const totalResult = await db
    .select({ count: count() })
    .from(schema.rawScans)
    .where(conditions.length > 0 ? and(...conditions) : undefined);

  const total = totalResult[0]?.count ?? 0;

  // Get scans with lighthouse info
  const scans = await db
    .select({
      id: schema.rawScans.id,
      lighthouseId: schema.rawScans.lighthouseId,
      lighthouseName: schema.lighthouses.name,
      epc: schema.rawScans.epc,
      rssiDbm: schema.rawScans.rssiDbm,
      timestamp: schema.rawScans.timestamp,
      source: schema.rawScans.source,
      receivedAt: schema.rawScans.receivedAt,
    })
    .from(schema.rawScans)
    .leftJoin(
      schema.lighthouses,
      eq(schema.rawScans.lighthouseId, schema.lighthouses.id),
    )
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(schema.rawScans.timestamp))
    .limit(limit)
    .offset(offset);

  const data = scans.map((scan) => ({
    id: scan.id.toString(),
    lighthouseId: scan.lighthouseId,
    lighthouseName: scan.lighthouseName,
    epc: scan.epc,
    rssiDbm: scan.rssiDbm,
    timestamp: scan.timestamp.toISOString(),
    source: scan.source,
    receivedAt: scan.receivedAt?.toISOString() ?? null,
  }));

  return c.json({
    data,
    total,
    limit,
    offset,
  });
});

export default router;
