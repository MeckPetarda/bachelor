/**
 * Status message handler for lighthouse online/offline status tracking
 */

import { eq } from "drizzle-orm";
import { getDatabase, schema } from "../../database/client";
import { createLogger } from "../../utils/logger";
import { extractMacAddress } from "../topics";
import {
  setLighthouseConnected,
  setLighthouseDisconnected,
  wasLighthouseConnected,
} from "../state";

const logger = createLogger("Status Handler");

/**
 * Handle incoming status message from lighthouse
 * @param topic - MQTT topic (attendance/lighthouse/{MAC}/status)
 * @param payload - Message payload ("online" or "offline")
 */
export async function handleStatusMessage(
  topic: string,
  payload: string | Buffer
): Promise<void> {
  // Extract MAC address from topic
  const macAddress = extractMacAddress(topic);
  if (!macAddress) {
    logger.warn(`Invalid status topic format: ${topic}`);
    return;
  }

  // Parse payload
  const statusStr = payload.toString("utf-8").trim().toLowerCase();
  if (statusStr !== "online" && statusStr !== "offline") {
    logger.warn(`Invalid status payload from ${macAddress}: "${statusStr}"`);
    return;
  }

  const isOnline = statusStr === "online";

  logger.debug(`Processing status from ${macAddress}: ${statusStr}`);

  try {
    // Look up lighthouse by deviceId (MAC)
    const db = getDatabase();
    const lighthouses = await db
      .select({ id: schema.lighthouses.id })
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, macAddress))
      .limit(1);

    if (lighthouses.length === 0 || lighthouses[0] === undefined) {
      logger.warn(`Unknown lighthouse device: ${macAddress}`);
      // Still update runtime state for unknown devices
      if (isOnline) {
        setLighthouseConnected(macAddress);
      } else {
        setLighthouseDisconnected(macAddress, false);
      }

      // This should not really be automatic and there should be a more defined process
      await db.insert(schema.lighthouses).values({
        name: macAddress, 
        placement: "STANDALONE",
        isActive: true,
        deviceId: macAddress
      })
      return;
    }

    const lighthouseId = lighthouses[0].id;

    // Determine if this is a graceful disconnection
    let isGraceful: boolean | null = null;
    if (!isOnline) {
      // For offline messages, check if we previously saw an "online" message
      // If we never saw "online", this is likely an LWT (ungraceful)
      // If we did see "online", and now we get "offline", it could be either:
      // - Graceful: device explicitly published "offline" before disconnect
      // - Ungraceful: LWT triggered after connection loss
      // We assume graceful if we receive the offline message while still "connected"
      // (broker hasn't yet marked it as disconnected via LWT timing)
      isGraceful = wasLighthouseConnected(macAddress);
    }

    // Update runtime state
    if (isOnline) {
      setLighthouseConnected(macAddress);
    } else {
      setLighthouseDisconnected(macAddress, isGraceful ?? false);
    }

    // Insert connection event record
    await db.insert(schema.lighthouseConnectionEvents).values({
      lighthouseId,
      eventType: isOnline ? "connected" : "disconnected",
      isGraceful,
    });

    // Update lastSeenAt timestamp on the lighthouse
    await db
      .update(schema.lighthouses)
      .set({ lastSeenAt: new Date() })
      .where(eq(schema.lighthouses.id, lighthouseId));

    logger.info(
      `Lighthouse ${macAddress} ${isOnline ? "connected" : `disconnected (graceful: ${isGraceful})`}`
    );
  } catch (error) {
    logger.error(`Failed to process status message from ${macAddress}:`, error);
  }
}
