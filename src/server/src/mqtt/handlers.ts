import { getDatabase, schema } from "../database/client";
import { createLogger } from "../utils/logger";
import { eq } from "drizzle-orm";

const logger = createLogger("MQTT Handlers");

// Topic pattern: attendance/lighthouse/{device_id}/scans
export const SCAN_TOPIC_PATTERN = /^attendance\/lighthouse\/([^/]+)\/scans$/;

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
}

/**
 * Event emitter interface for WebSocket notifications
 * This will be implemented when WebSocket support is added
 */
export interface ScanEventEmitter {
  emit(event: "newScan", data: { lighthouseId: number; scanId: bigint }): void;
}

// Placeholder for event emitter - will be set when WebSocket is implemented
let eventEmitter: ScanEventEmitter | null = null;

/**
 * Set the event emitter for WebSocket notifications
 */
export function setScanEventEmitter(emitter: ScanEventEmitter): void {
  eventEmitter = emitter;
}

/**
 * Parse device_id from topic
 */
function extractDeviceId(topic: string): string | null {
  const match = topic.match(SCAN_TOPIC_PATTERN);
  return match ? match[1] : null;
}

/**
 * Validate scan payload
 */
function validatePayload(payload: unknown): payload is ScanPayload {
  if (typeof payload !== "object" || payload === null) {
    return false;
  }

  const p = payload as Record<string, unknown>;

  // Required fields
  if (typeof p.epc !== "string" || p.epc.length === 0) {
    return false;
  }

  if (typeof p.timestampMs !== "number") {
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
  payload: Buffer
): Promise<void> {
  const deviceId = extractDeviceId(topic);
  if (!deviceId) {
    logger.warn(`Invalid scan topic format: ${topic}`);
    return;
  }

  // Parse JSON payload
  let scanData: ScanPayload;
  try {
    const payloadStr = payload.toString("utf-8");
    scanData = JSON.parse(payloadStr);
  } catch (error) {
    logger.error(`Failed to parse scan payload from ${deviceId}:`, error);
    return;
  }

  // Validate payload
  if (!validatePayload(scanData)) {
    logger.warn(`Invalid scan payload from ${deviceId}:`, scanData);
    return;
  }

  logger.debug(`Processing scan from device ${deviceId}: EPC=${scanData.epc}`);

  try {
    // Look up lighthouse by device_id
    const db = getDatabase();
    const lighthouses = await db
      .select({ id: schema.lighthouses.id })
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, deviceId))
      .limit(1);

    if (lighthouses.length === 0) {
      logger.warn(`Unknown lighthouse device: ${deviceId}`);
      // Could optionally store in a separate "unknown_scans" table
      return;
    }

    const lighthouseId = lighthouses[0].id;

    // Determine timestamp - prefer ISO string if provided, fall back to timestampMs
    let scanTimestamp: Date;
    if (scanData.timestamp) {
      scanTimestamp = new Date(scanData.timestamp);
    } else {
      scanTimestamp = new Date(Number(scanData.timestampMs));
    }

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
        processed: false,
      })
      .returning({ id: schema.rawScans.id });

    const scanId = insertResult[0].id;
    logger.debug(`Stored scan ${scanId} from lighthouse ${lighthouseId}`);

    // Emit WebSocket event for dashboard (non-blocking)
    if (eventEmitter) {
      setImmediate(() => {
        eventEmitter!.emit("newScan", { lighthouseId, scanId });
      });
    }

    // Add to event processing queue (async, non-blocking)
    // This will be implemented in Task 2.2
    queueScanForProcessing(scanId, lighthouseId, scanData.epc);
  } catch (error) {
    logger.error(`Failed to store scan from ${deviceId}:`, error);
    // Don't rethrow - we don't want to crash the broker for a single failed insert
  }
}

/**
 * Queue a scan for async processing (direction detection)
 * This is a placeholder that will be replaced with actual queue implementation in Task 2.2
 */
function queueScanForProcessing(
  scanId: bigint,
  lighthouseId: number,
  epc: string
): void {
  // TODO: Task 2.2 - Implement actual event processing queue
  // For now, just log that we would queue this scan
  logger.debug(
    `Queued scan ${scanId} (lighthouse=${lighthouseId}, epc=${epc}) for processing`
  );
}

/**
 * Handle batch of scans (for efficiency when lighthouse sends multiple scans)
 */
export async function handleBatchScanMessage(
  topic: string,
  payload: Buffer
): Promise<void> {
  const deviceId = extractDeviceId(topic);
  if (!deviceId) {
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
    logger.error(`Failed to parse batch scan payload from ${deviceId}:`, error);
    return;
  }

  // Process each scan
  for (const scanData of scansData) {
    if (!validatePayload(scanData)) {
      logger.warn(`Invalid scan in batch from ${deviceId}:`, scanData);
      continue;
    }

    // Create individual topic for processing
    const singlePayload = Buffer.from(JSON.stringify(scanData));
    await handleScanMessage(topic, singlePayload);
  }
}
