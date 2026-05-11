import { eq, and } from "drizzle-orm";
import { getDatabase, schema } from "../../database/client";
import { createLogger } from "../../utils/logger";
import { extractMacAddress } from "../topics";
import { markSyncStart, markSyncComplete } from "../../services/sync-state";

const logger = createLogger("Sync Handler");

export async function handleSyncStart(
  topic: string,
  payload: string | Buffer,
): Promise<void> {
  const mac = extractMacAddress(topic);
  if (!mac) return;

  let count = 0;
  try {
    const parsed = JSON.parse(payload.toString("utf-8")) as { count?: number };
    count = parsed.count ?? 0;
  } catch {
    // payload optional — log what we have
  }

  const db = getDatabase();
  const lighthouses = await db
    .select({ id: schema.lighthouses.id })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, mac))
    .limit(1);

  if (lighthouses[0]) {
    markSyncStart(lighthouses[0].id);
  }

  logger.info(`Offline sync starting for ${mac}: ${count} event(s) expected`);
}

export async function handleSyncComplete(
  topic: string,
  _payload: string | Buffer,
): Promise<void> {
  const mac = extractMacAddress(topic);
  if (!mac) return;

  const db = getDatabase();

  const lighthouses = await db
    .select({ id: schema.lighthouses.id })
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, mac))
    .limit(1);

  if (!lighthouses[0]) {
    logger.warn(`sync/complete from unknown lighthouse ${mac}`);
    return;
  }

  const lighthouseId = lighthouses[0].id;

  markSyncComplete(lighthouseId);

  const result = await db
    .update(schema.rawScans)
    .set({ offlineSyncPending: false })
    .where(
      and(
        eq(schema.rawScans.lighthouseId, lighthouseId),
        eq(schema.rawScans.offlineSyncPending, true),
      ),
    );

  logger.info(`Offline sync complete for ${mac}: scans released to sweeper`);
}
