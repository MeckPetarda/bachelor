import { and, asc, eq, inArray, isNotNull, or } from "drizzle-orm";
import { getDatabase, schema } from "../../database/client";
import { createLogger } from "../../utils/logger";
import { Navigo3Connector } from "./connector";

const logger = createLogger("Navigo3Service");

// ---------------------------------------------------------------------------
// Module-level state
// ---------------------------------------------------------------------------

let connector: Navigo3Connector | null = null;
let enabled = false;
let typeId: number | null = null;
let algorithmId: string | null = null;

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

export async function initNavigo3Service(): Promise<void> {
  const baseUrl = process.env.NAVIGO3_BASE_URL;
  const username = process.env.NAVIGO3_USERNAME;
  const password = process.env.NAVIGO3_PASSWORD;

  if (!baseUrl || !username || !password) {
    logger.warn(
      "Navigo3: NAVIGO3_BASE_URL, NAVIGO3_USERNAME, or NAVIGO3_PASSWORD not set — integration disabled",
    );
    return;
  }

  connector = new Navigo3Connector(baseUrl, username, password);

  let types: Array<{ id: number; name: string; systemName?: string | null }>;
  try {
    types = (await connector.execute(
      "attendance/embedded/types",
      {},
    )) as typeof types;
  } catch (err) {
    logger.warn(
      "Navigo3: could not connect to Navigo3 instance — integration disabled",
      { err },
    );
    connector = null;
    return;
  }

  const atWorkType = types.find((t) => t.systemName === "atWork");
  if (!atWorkType) {
    logger.warn(
      "Navigo3: atWork attendance type not found — integration disabled",
    );
    return;
  }

  typeId = atWorkType.id;
  algorithmId = process.env.NAVIGO3_ALGORITHM_ID ?? null;
  enabled = true;
  logger.info(
    `Navigo3: service enabled, atWork typeId=${typeId}, algorithmId=${algorithmId}`,
  );
}

export function isNavigo3Enabled(): boolean {
  return enabled;
}

// ---------------------------------------------------------------------------
// Timestamp helpers
// ---------------------------------------------------------------------------

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function toNavigo3DateTime(date: Date): string {
  return (
    `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ` +
    `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`
  );
}

function toNavigo3Date(date: Date): string {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function toNavigo3Time(date: Date): string {
  return `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

// ---------------------------------------------------------------------------
// Eligibility
// ---------------------------------------------------------------------------

function isEligible(event: {
  algorithmId: string;
  direction: string;
  userId: string | null;
  userSyncId: string | null;
}): boolean {
  return (
    event.algorithmId === algorithmId &&
    (event.direction === "in" || event.direction === "out") &&
    event.userId !== null &&
    event.userSyncId !== null &&
    event.userSyncId !== ""
  );
}

// ---------------------------------------------------------------------------
// DB helpers
// ---------------------------------------------------------------------------

type EventRow = {
  id: string;
  algorithmId: string;
  direction: string;
  userId: string | null;
  timestamp: Date;
  syncedToIntegration: boolean | null;
  userSyncId: string | null;
};

async function fetchEvent(eventId: string): Promise<EventRow | null> {
  const db = getDatabase();
  const rows = await db
    .select({
      id: schema.processedEvents.id,
      algorithmId: schema.processedEvents.algorithmId,
      direction: schema.processedEvents.direction,
      userId: schema.processedEvents.userId,
      timestamp: schema.processedEvents.timestamp,
      syncedToIntegration: schema.processedEvents.syncedToIntegration,
      userSyncId: schema.users.syncId,
    })
    .from(schema.processedEvents)
    .leftJoin(schema.users, eq(schema.processedEvents.userId, schema.users.id))
    .where(eq(schema.processedEvents.id, eventId));
  return rows[0] ?? null;
}

// ---------------------------------------------------------------------------
// Immediate push
// ---------------------------------------------------------------------------

export async function pushEvent(eventId: string): Promise<void> {
  if (!enabled) return;

  const event = await fetchEvent(eventId);
  if (!event || event.syncedToIntegration === true) return;
  if (!isEligible(event)) return;

  const db = getDatabase();

  try {
    if (event.direction === "in") {
      await connector!.execute("attendance/embedded/start", {
        userId: parseInt(event.userSyncId!),
        time: toNavigo3DateTime(event.timestamp),
        typeId: typeId!,
        comment: "",
      });
    } else {
      await connector!.execute("attendance/embedded/stop", {
        userId: parseInt(event.userSyncId!),
        time: toNavigo3DateTime(event.timestamp),
        comment: "",
      });
    }

    await db
      .update(schema.processedEvents)
      .set({ syncedToIntegration: true })
      .where(eq(schema.processedEvents.id, eventId));
  } catch (err) {
    logger.error(`pushEvent: error pushing event ${eventId}:`, err);
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Backfill upsert
// ---------------------------------------------------------------------------

export async function pushPair(
  inEventId: string,
  outEventId: string,
): Promise<void> {
  if (!enabled) return;

  const [inEvent, outEvent] = await Promise.all([
    fetchEvent(inEventId),
    fetchEvent(outEventId),
  ]);

  if (
    !inEvent ||
    !outEvent ||
    inEvent.userId !== outEvent.userId ||
    inEvent.userSyncId !== outEvent.userSyncId ||
    !isEligible(inEvent) ||
    !isEligible(outEvent) ||
    inEvent.syncedToIntegration === true ||
    outEvent.syncedToIntegration === true
  ) {
    return;
  }

  try {
    const result = (await connector!.execute("attendance/embedded/upsert", {
      userId: parseInt(inEvent.userSyncId!),
      day: toNavigo3Date(inEvent.timestamp),
      timeFrom: toNavigo3Time(inEvent.timestamp),
      timeTo: toNavigo3Time(outEvent.timestamp),
      createdFrom: toNavigo3DateTime(inEvent.timestamp),
      createdTo: toNavigo3DateTime(outEvent.timestamp),
      typeId: typeId!,
      comment: "",
      changedBy: 0,
    })) as { id: number };

    const db = getDatabase();
    await db
      .update(schema.processedEvents)
      .set({ syncedToIntegration: true, navigo3RecordId: result.id })
      .where(inArray(schema.processedEvents.id, [inEventId, outEventId]));
  } catch (err) {
    logger.error(
      `pushPair: error pushing pair ${inEventId}/${outEventId}:`,
      err,
    );
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Retry sweep
// ---------------------------------------------------------------------------

export async function runRetrySweep(): Promise<void> {
  if (!enabled || !algorithmId) return;

  const db = getDatabase();

  const rows = await db
    .select({
      id: schema.processedEvents.id,
      algorithmId: schema.processedEvents.algorithmId,
      direction: schema.processedEvents.direction,
      userId: schema.processedEvents.userId,
      timestamp: schema.processedEvents.timestamp,
      syncedToIntegration: schema.processedEvents.syncedToIntegration,
      userSyncId: schema.users.syncId,
    })
    .from(schema.processedEvents)
    .leftJoin(schema.users, eq(schema.processedEvents.userId, schema.users.id))
    .where(
      and(
        eq(schema.processedEvents.syncedToIntegration, false),
        eq(
          schema.processedEvents.algorithmId,
          algorithmId as "temporal_centroid",
        ),
        or(
          eq(schema.processedEvents.direction, "in"),
          eq(schema.processedEvents.direction, "out"),
        ),
        isNotNull(schema.processedEvents.userId),
      ),
    )
    .orderBy(asc(schema.processedEvents.timestamp))
    .limit(100);

  const handled = new Set<string>();

  for (const event of rows) {
    if (handled.has(event.id)) continue;

    const oppDirection = event.direction === "in" ? "out" : "in";
    const eventDay = toNavigo3Date(event.timestamp);

    const counterpart = rows.find(
      (r) =>
        !handled.has(r.id) &&
        r.id !== event.id &&
        r.userId === event.userId &&
        r.direction === oppDirection &&
        toNavigo3Date(r.timestamp) === eventDay,
    );

    if (counterpart) {
      const inEvent = event.direction === "in" ? event : counterpart;
      const outEvent = event.direction === "out" ? event : counterpart;
      try {
        await pushPair(inEvent.id, outEvent.id);
      } catch (err) {
        logger.warn(
          `runRetrySweep: pushPair failed for ${inEvent.id}/${outEvent.id}:`,
          err,
        );
      }
      handled.add(event.id);
      handled.add(counterpart.id);
    } else {
      try {
        await pushEvent(event.id);
      } catch (err) {
        logger.warn(`runRetrySweep: pushEvent failed for ${event.id}:`, err);
      }
      handled.add(event.id);
    }
  }
}
