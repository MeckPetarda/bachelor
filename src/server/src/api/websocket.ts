/**
 * WebSocket endpoint for real-time dashboard updates
 */

import { createLogger } from "../utils/logger";
import type { ScanEventData } from "../mqtt/handlers/scan";

const logger = createLogger("WebSocket");

/**
 * Message types for WebSocket communication
 */
export type WebSocketMessageType =
  | "scan"
  | "device:online"
  | "device:offline"
  | "device:health"
  | "device:pending"
  | "event:new"
  | "event:orphaned";

/**
 * Base WebSocket message structure
 */
export interface WebSocketMessage<T = unknown> {
  type: WebSocketMessageType;
  payload: T;
  timestamp: string;
}

/**
 * Scan event payload
 */
export interface ScanPayload {
  id: string;
  lighthouseId: number;
  lighthouseName?: string;
  epc: string;
  rssiDbm: number | null;
  timestamp: string;
  source: "realtime" | "offline_sync";
}

/**
 * Device online/offline payload
 */
export interface DeviceStatusPayload {
  deviceId: string;
  lighthouseId: number | null;
  isGraceful?: boolean;
}

/**
 * Device health payload
 */
export interface DeviceHealthPayload {
  deviceId: string;
  lighthouseId: number | null;
  health: {
    uptimeSec: number;
    freeHeapBytes: number;
    wifiRssiDbm: number;
    rfidState: string;
    rfidIsResponsive: boolean;
  };
}

/**
 * Pending device payload
 */
export interface PendingDevicePayload {
  deviceId: string;
}

// Store connected WebSocket clients
const connectedClients = new Set<WebSocket>();

/**
 * Get the count of connected WebSocket clients
 */
export function getConnectedClientCount(): number {
  return connectedClients.size;
}

/**
 * Handle WebSocket connection open
 */
export function handleWebSocketOpen(ws: WebSocket): void {
  connectedClients.add(ws);
  logger.info(
    `WebSocket client connected. Total clients: ${connectedClients.size}`,
  );
}

/**
 * Handle WebSocket connection close
 */
export function handleWebSocketClose(ws: WebSocket): void {
  connectedClients.delete(ws);
  logger.info(
    `WebSocket client disconnected. Total clients: ${connectedClients.size}`,
  );
}

/**
 * Handle WebSocket message (client -> server)
 */
export function handleWebSocketMessage(
  ws: WebSocket,
  message: string | Buffer,
): void {
  // For now, we don't handle client messages
  // Could be used for subscription management in the future
  logger.debug("Received WebSocket message from client:", message.toString());
}

/**
 * Broadcast a message to all connected clients
 */
function broadcast<T>(type: WebSocketMessageType, payload: T): void {
  if (connectedClients.size === 0) {
    return;
  }

  const message: WebSocketMessage<T> = {
    type,
    payload,
    timestamp: new Date().toISOString(),
  };

  const messageStr = JSON.stringify(message);

  for (const client of connectedClients) {
    try {
      if (client.readyState === WebSocket.OPEN) {
        client.send(messageStr);
      }
    } catch (error) {
      logger.error("Failed to send WebSocket message:", error);
      // Remove dead client
      connectedClients.delete(client);
    }
  }

  logger.debug(`Broadcast ${type} to ${connectedClients.size} clients`);
}

/**
 * Broadcast a new scan event
 */
export function broadcastScan(
  data: ScanEventData,
  lighthouseName?: string,
): void {
  const payload: ScanPayload = {
    id: data.scanId.toString(),
    lighthouseId: data.lighthouseId,
    lighthouseName,
    epc: data.epc,
    rssiDbm: data.rssiDbm,
    timestamp: data.timestamp.toISOString(),
    source: data.source,
  };

  broadcast("scan", payload);
}

/**
 * Broadcast device online event
 */
export function broadcastDeviceOnline(
  deviceId: string,
  lighthouseId: number | null,
): void {
  const payload: DeviceStatusPayload = {
    deviceId,
    lighthouseId,
  };

  broadcast("device:online", payload);
}

/**
 * Broadcast device offline event
 */
export function broadcastDeviceOffline(
  deviceId: string,
  lighthouseId: number | null,
  isGraceful: boolean,
): void {
  const payload: DeviceStatusPayload = {
    deviceId,
    lighthouseId,
    isGraceful,
  };

  broadcast("device:offline", payload);
}

/**
 * Broadcast device health update
 */
export function broadcastDeviceHealth(
  deviceId: string,
  lighthouseId: number | null,
  health: DeviceHealthPayload["health"],
): void {
  const payload: DeviceHealthPayload = {
    deviceId,
    lighthouseId,
    health,
  };

  broadcast("device:health", payload);
}

/**
 * Broadcast new pending device detected
 */
export function broadcastPendingDevice(deviceId: string): void {
  const payload: PendingDevicePayload = {
    deviceId,
  };

  broadcast("device:pending", payload);
}

// --- Traversal / orphan event payloads ---------------------------------------

export interface TraversalEventPayload {
  id: string;
  algorithmId: string;
  direction: string;
  tagEpc: string;
  userId: string | null;
  groupId: number;
  confidence: number;
  timestamp: string;
  clusterStartedAt: string;
  clusterEndedAt: string;
  scanCount: number;
}

export interface OrphanedScanPayload {
  scanId: string;
  epc: string;
  lighthouseId: number;
  timestamp: string;
  orphanReason: string;
}

/**
 * Broadcast a processed traversal event (called once per algorithm result)
 */
export function broadcastTraversalEvent(data: TraversalEventPayload): void {
  broadcast("event:new", data);
}

/**
 * Broadcast an orphaned scan notification
 */
export function broadcastOrphanedScan(data: OrphanedScanPayload): void {
  broadcast("event:orphaned", data);
}

/**
 * Clean up all WebSocket connections
 */
export function closeAllConnections(): void {
  for (const client of connectedClients) {
    try {
      client.close();
    } catch (error) {
      // Ignore errors during cleanup
    }
  }
  connectedClients.clear();
  logger.info("All WebSocket connections closed");
}
