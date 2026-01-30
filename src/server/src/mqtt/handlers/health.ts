/**
 * Health message handler for lighthouse health metrics tracking
 */

import { eq } from "drizzle-orm";
import { getDatabase, schema } from "../../database/client";
import { createLogger } from "../../utils/logger";
import { extractMacAddress } from "../topics";
import { updateLighthouseHealth, type HealthPayload } from "../state";
import { broadcastDeviceHealth } from "../../api/websocket";

const logger = createLogger("Health Handler");

/**
 * Expected JSON payload structure from lighthouse
 */
interface HealthMessagePayload {
  uptime_sec: number;
  free_heap_bytes: number;
  min_free_heap_bytes: number;
  wifi_rssi_dbm: number;
  rfid: {
    state: string;
    is_responsive: boolean;
    power_rail_present: boolean;
    fw_version: string;
    last_error: number;
  };
}

/**
 * Validate that the payload has all required fields with correct types
 */
function validateHealthPayload(payload: unknown): payload is HealthMessagePayload {
  if (typeof payload !== "object" || payload === null) {
    return false;
  }

  const p = payload as Record<string, unknown>;

  // Check top-level fields
  if (typeof p.uptime_sec !== "number") return false;
  if (typeof p.free_heap_bytes !== "number") return false;
  if (typeof p.min_free_heap_bytes !== "number") return false;
  if (typeof p.wifi_rssi_dbm !== "number") return false;

  // Check rfid object
  if (typeof p.rfid !== "object" || p.rfid === null) return false;

  const rfid = p.rfid as Record<string, unknown>;
  if (typeof rfid.state !== "string") return false;
  if (typeof rfid.is_responsive !== "boolean") return false;
  if (typeof rfid.power_rail_present !== "boolean") return false;
  if (typeof rfid.fw_version !== "string") return false;
  if (typeof rfid.last_error !== "number") return false;

  return true;
}

/**
 * Convert wire format (snake_case) to internal format (camelCase)
 */
function convertToHealthPayload(payload: HealthMessagePayload): HealthPayload {
  return {
    uptimeSec: payload.uptime_sec,
    freeHeapBytes: payload.free_heap_bytes,
    minFreeHeapBytes: payload.min_free_heap_bytes,
    wifiRssiDbm: payload.wifi_rssi_dbm,
    rfid: {
      state: payload.rfid.state,
      isResponsive: payload.rfid.is_responsive,
      powerRailPresent: payload.rfid.power_rail_present,
      fwVersion: payload.rfid.fw_version,
      lastError: payload.rfid.last_error,
    },
  };
}

/**
 * Handle incoming health message from lighthouse
 * @param topic - MQTT topic (attendance/lighthouse/{MAC}/health)
 * @param payload - Message payload (JSON)
 */
export async function handleHealthMessage(
  topic: string,
  payload: string | Buffer
): Promise<void> {
  // Extract MAC address from topic
  const macAddress = extractMacAddress(topic);
  if (!macAddress) {
    logger.warn(`Invalid health topic format: ${topic}`);
    return;
  }

  // Parse JSON payload
  let healthData: unknown;
  try {
    healthData = JSON.parse(payload.toString("utf-8"));
  } catch (error) {
    logger.error(`Failed to parse health JSON from ${macAddress}:`, error);
    return;
  }

  // Validate payload structure
  if (!validateHealthPayload(healthData)) {
    logger.warn(`Invalid health payload structure from ${macAddress}`);
    return;
  }

  logger.debug(`Processing health from ${macAddress}: uptime=${healthData.uptime_sec}s`);

  try {
    // Look up lighthouse by deviceId (MAC)
    const db = getDatabase();
    const lighthouses = await db
      .select({ id: schema.lighthouses.id })
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, macAddress))
      .limit(1);

    if (lighthouses.length === 0 || lighthouses[0] === undefined) {
      logger.info(`Pending device health update: ${macAddress}`);
      // Update runtime state for unknown devices (pending, not registered)
      const healthPayload = convertToHealthPayload(healthData);
      updateLighthouseHealth(macAddress, healthPayload, false);

      // Broadcast health update for pending device
      broadcastDeviceHealth(macAddress, null, {
        uptimeSec: healthPayload.uptimeSec,
        freeHeapBytes: healthPayload.freeHeapBytes,
        wifiRssiDbm: healthPayload.wifiRssiDbm,
        rfidState: healthPayload.rfid.state,
        rfidIsResponsive: healthPayload.rfid.isResponsive,
      });

      return;
    }

    const lighthouseId = lighthouses[0].id;

    // Convert to internal format
    const healthPayload = convertToHealthPayload(healthData);

    // Update runtime state (mark as registered since we found it in DB)
    updateLighthouseHealth(macAddress, healthPayload, true);

    // Broadcast health update for registered device
    broadcastDeviceHealth(macAddress, lighthouseId, {
      uptimeSec: healthPayload.uptimeSec,
      freeHeapBytes: healthPayload.freeHeapBytes,
      wifiRssiDbm: healthPayload.wifiRssiDbm,
      rfidState: healthPayload.rfid.state,
      rfidIsResponsive: healthPayload.rfid.isResponsive,
    });

    // Insert health snapshot record
    await db.insert(schema.lighthouseHealthSnapshots).values({
      lighthouseId,
      uptimeSec: healthPayload.uptimeSec,
      freeHeapBytes: healthPayload.freeHeapBytes,
      minFreeHeapBytes: healthPayload.minFreeHeapBytes,
      wifiRssiDbm: healthPayload.wifiRssiDbm,
      rfidState: healthPayload.rfid.state,
      rfidIsResponsive: healthPayload.rfid.isResponsive,
      rfidPowerRailPresent: healthPayload.rfid.powerRailPresent,
      rfidFwVersion: healthPayload.rfid.fwVersion,
      rfidLastError: healthPayload.rfid.lastError,
    });

    // Update lastSeenAt timestamp on the lighthouse
    await db
      .update(schema.lighthouses)
      .set({ lastSeenAt: new Date() })
      .where(eq(schema.lighthouses.id, lighthouseId));

    logger.debug(`Stored health snapshot for lighthouse ${macAddress}`);
  } catch (error) {
    logger.error(`Failed to process health message from ${macAddress}:`, error);
  }
}
