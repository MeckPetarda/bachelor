import { getDatabase, schema } from "../../database/client";
import { createLogger, LogLevel } from "../../utils/logger";
import { eq } from "drizzle-orm";
import { extractMacAddress } from "../topics";
import { broadcastScan } from "../../api/websocket";

const logger = createLogger("Scan Handler");

/**
 * Scan message payload structure from lighthouse
 */
export interface ScanPayload {
  epc: string;
  epcLength?: number;
  rssiDbm?: number;
  antennaId?: number;
  frequency?: number;
  sequenceNumber?: number;
  detectionConfidence?: number;
  timestampMs: number;
  timestamp?: string; // ISO 8601 format
  offline?: boolean; // Indicates if this scan was synced from offline storage
  replayTime?: number; // Unix ms when the offline event was replayed
  timeBasis?: "synced" | "estimated" | "relative"; // Time quality from firmware
}

/**
 * Scan event data for WebSocket notifications
 */
export interface ScanEventData {
  lighthouseId: number;
  scanId: bigint;
  epc: string;
  rssiDbm: number | null;
  timestamp: Date;
  source: "realtime" | "offline_sync";
}

/**
 * Event emitter interface for WebSocket notifications
 * This will be implemented when WebSocket support is added
 */
export interface ScanEventEmitter {
  emit(event: "newScan", data: ScanEventData): void;
}

// Placeholder for event emitter - will be set when WebSocket is implemented
export let eventEmitter: ScanEventEmitter | null = null;

/**
 * Set the event emitter for WebSocket notifications
 */
export function setScanEventEmitter(emitter: ScanEventEmitter): void {
  eventEmitter = emitter;
}

/**
 * Validate scan payload
 */
function validatePayload(payload: unknown): payload is ScanPayload {
  if (typeof payload !== "object" || payload === null) {
    logger.error("Invalid payload", payload);
    return false;
  }

  const p = payload as Record<string, unknown>;

  // Required fields
  if (typeof p.epc !== "string" || p.epc.length === 0) {
    logger.error("Invalid epc", p.epc);
    return false;
  }

  if (typeof p.timestampMs !== "number") {
    logger.error("Invalid timestamp", p.timestampMs);
    return false;
  }

  return true;
}

/**
 * Handle incoming scan message from lighthouse
 * @param topic - MQTT topic
 * @param payload - Message payload (Buffer)
 */
export async function handleScanMessage(
  topic: string,
  payload: string | Buffer,
): Promise<void> {
  const macAddress = extractMacAddress(topic);
  if (!macAddress) {
    logger.warn(`Invalid scan topic format: ${topic}`);
    return;
  }

  // Parse JSON payload
  let scanData: ScanPayload;
  try {
    const payloadStr = payload.toString("utf-8");
    scanData = JSON.parse(payloadStr);
  } catch (error) {
    logger.error(`Failed to parse scan payload from ${macAddress}:`, error);
    return;
  }

  logger.debug("scanData", scanData);

  // Validate payload
  if (!validatePayload(scanData)) {
    logger.warn(`Invalid scan payload from ${macAddress}:`, scanData);
    return;
  }

  logger.debug(
    `Processing scan from device ${macAddress}: EPC=${scanData.epc}`,
  );

  try {
    // Look up lighthouse by deviceId (MAC address)
    const db = getDatabase();
    const lighthouses = await db
      .select({ id: schema.lighthouses.id, name: schema.lighthouses.name })
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, macAddress))
      .limit(1);

    if (lighthouses.length === 0 || lighthouses[0] === undefined) {
      logger.warn(`Unknown lighthouse device: ${macAddress}`);
      // Could optionally store in a separate "unknown_scans" table
      return;
    }

    const lighthouseId = lighthouses[0].id;
    const lighthouseName = lighthouses[0].name;

    // Determine timestamp based on timeBasis field.
    // - "synced": timestampMs is a real Unix timestamp -> use it directly.
    // - "estimated" / "relative": timestampMs is boot-relative -> fall back to
    //   server receipt time so the database never stores epoch-relative junk.
    // - undefined (legacy firmware, no timeBasis field): treat as "synced" for
    //   backward compatibility during the rollout period.
    const basis = scanData.timeBasis ?? "synced";
    let scanTimestamp: Date;
    if (basis === "synced") {
      // Prefer explicit ISO string when provided, otherwise use Unix ms value.
      if (scanData.timestamp) {
        scanTimestamp = new Date(scanData.timestamp);
      } else {
        scanTimestamp = new Date(Number(scanData.timestampMs));
      }
    } else {
      // Boot-relative timestamp - use server receipt time as the best estimate.
      scanTimestamp = new Date();
    }

    // Determine source based on backfill flag
    const source = scanData.offline === true ? "offline_sync" : "realtime";

    // Insert into raw_scans table
    const insertResult = await db
      .insert(schema.rawScans)
      .values({
        lighthouseId,
        epc: scanData.epc,
        epcLength: scanData.epcLength ?? null,
        rssiDbm: scanData.rssiDbm ?? null,
        antennaId: scanData.antennaId ?? null,
        frequency: scanData.frequency ?? null,
        sequenceNumber: scanData.sequenceNumber ?? null,
        detectionConfidence: scanData.detectionConfidence ?? null,
        timestampMs: BigInt(scanData.timestampMs),
        timestamp: scanTimestamp,
        source,
        timeBasis: basis,
      })
      .returning({ id: schema.rawScans.id });

    const insertedScan = insertResult[0];
    if (!insertedScan) {
      logger.error(`Failed to insert scan from ${macAddress}`);
      return;
    }
    const scanId = insertedScan.id;
    logger.debug(`Stored scan ${scanId} from lighthouse ${lighthouseId}`);

    // Broadcast WebSocket event for dashboard (non-blocking)
    const eventData: ScanEventData = {
      lighthouseId,
      scanId,
      epc: scanData.epc,
      rssiDbm: scanData.rssiDbm ?? null,
      timestamp: scanTimestamp,
      source,
    };
    setImmediate(() => {
      broadcastScan(eventData, lighthouseName);
    });

    // Legacy event emitter support
    if (eventEmitter) {
      setImmediate(() => {
        eventEmitter!.emit("newScan", eventData);
      });
    }
  } catch (error) {
    logger.error(`Failed to store scan from ${macAddress}:`, error);
    // Don't rethrow - we don't want to crash the broker for a single failed insert
  }
}

/**
 * Handle batch of scans (for efficiency when lighthouse sends multiple scans)
 */
export async function handleBatchScanMessage(
  topic: string,
  payload: Buffer,
): Promise<void> {
  const macAddress = extractMacAddress(topic);
  if (!macAddress) {
    logger.warn(`Invalid scan topic format: ${topic}`);
    return;
  }

  // Parse JSON payload - expect array of scans
  let scansData: ScanPayload[];
  try {
    const payloadStr = payload.toString("utf-8");
    const parsed = JSON.parse(payloadStr);
    scansData = Array.isArray(parsed) ? parsed : [parsed];
  } catch (error) {
    logger.error(
      `Failed to parse batch scan payload from ${macAddress}:`,
      error,
    );
    return;
  }

  // Process each scan
  for (const scanData of scansData) {
    if (!validatePayload(scanData)) {
      logger.warn(`Invalid scan in batch from ${macAddress}:`, scanData);
      continue;
    }

    // Create individual topic for processing
    const singlePayload = Buffer.from(JSON.stringify(scanData));
    await handleScanMessage(topic, singlePayload);
  }
}
