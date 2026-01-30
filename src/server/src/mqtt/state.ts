/**
 * Runtime state management for lighthouse connection and health tracking
 *
 * This module maintains an in-memory state of lighthouse connections and
 * health metrics for real-time dashboard access.
 */

/**
 * Health payload structure received from lighthouse
 */
export interface HealthPayload {
  uptimeSec: number;
  freeHeapBytes: number;
  minFreeHeapBytes: number;
  wifiRssiDbm: number;
  rfid: {
    state: string;
    isResponsive: boolean;
    powerRailPresent: boolean;
    fwVersion: string;
    lastError: number;
  };
}

/**
 * Runtime state for a single lighthouse
 */
export interface LighthouseRuntimeState {
  isConnected: boolean;
  connectedAt: Date | null;
  disconnectedAt: Date | null;
  lastHealthAt: Date | null;
  latestHealth: HealthPayload | null;
  firstSeenAt: Date;
  isRegistered: boolean;
}

// In-memory state store keyed by MAC address
const lighthouseStates = new Map<string, LighthouseRuntimeState>();

/**
 * Get the runtime state for a lighthouse
 * @param mac - The lighthouse MAC address
 * @returns The runtime state or undefined if not found
 */
export function getLighthouseState(mac: string): LighthouseRuntimeState | undefined {
  return lighthouseStates.get(mac.toUpperCase());
}

/**
 * Initialize or update a lighthouse as connected
 * @param mac - The lighthouse MAC address
 * @param isRegistered - Whether the device is registered in the database
 */
export function setLighthouseConnected(mac: string, isRegistered: boolean = false): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);
  const now = new Date();

  lighthouseStates.set(normalizedMac, {
    isConnected: true,
    connectedAt: now,
    disconnectedAt: null,
    lastHealthAt: existing?.lastHealthAt ?? null,
    latestHealth: existing?.latestHealth ?? null,
    firstSeenAt: existing?.firstSeenAt ?? now,
    isRegistered: isRegistered || existing?.isRegistered || false,
  });
}

/**
 * Mark a lighthouse as disconnected
 * @param mac - The lighthouse MAC address
 * @param graceful - Whether the disconnection was graceful (explicit offline message)
 */
export function setLighthouseDisconnected(mac: string, graceful: boolean): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);
  const now = new Date();

  lighthouseStates.set(normalizedMac, {
    isConnected: false,
    connectedAt: existing?.connectedAt ?? null,
    disconnectedAt: now,
    lastHealthAt: existing?.lastHealthAt ?? null,
    latestHealth: existing?.latestHealth ?? null,
    firstSeenAt: existing?.firstSeenAt ?? now,
    isRegistered: existing?.isRegistered ?? false,
  });
}

/**
 * Update the health metrics for a lighthouse
 * @param mac - The lighthouse MAC address
 * @param health - The health payload
 * @param isRegistered - Whether the device is registered in the database
 */
export function updateLighthouseHealth(mac: string, health: HealthPayload, isRegistered: boolean = false): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);
  const now = new Date();

  lighthouseStates.set(normalizedMac, {
    isConnected: existing?.isConnected ?? false,
    connectedAt: existing?.connectedAt ?? null,
    disconnectedAt: existing?.disconnectedAt ?? null,
    lastHealthAt: now,
    latestHealth: health,
    firstSeenAt: existing?.firstSeenAt ?? now,
    isRegistered: isRegistered || existing?.isRegistered || false,
  });
}

/**
 * Get all lighthouse states
 * @returns A new Map containing all lighthouse states
 */
export function getAllLighthouseStates(): Map<string, LighthouseRuntimeState> {
  return new Map(lighthouseStates);
}

/**
 * Check if a lighthouse was previously connected (for graceful detection)
 * @param mac - The lighthouse MAC address
 * @returns true if the lighthouse was previously marked as connected
 */
export function wasLighthouseConnected(mac: string): boolean {
  const state = lighthouseStates.get(mac.toUpperCase());
  return state?.isConnected ?? false;
}

/**
 * Clear all lighthouse states (for testing)
 */
export function clearAllStates(): void {
  lighthouseStates.clear();
}

/**
 * Get all pending (unregistered) device states
 * @returns A Map of pending device states keyed by MAC address
 */
export function getPendingDeviceStates(): Map<string, LighthouseRuntimeState> {
  const pending = new Map<string, LighthouseRuntimeState>();
  for (const [mac, state] of lighthouseStates) {
    if (!state.isRegistered) {
      pending.set(mac, state);
    }
  }
  return pending;
}

/**
 * Mark a device as registered (claimed)
 * @param mac - The device MAC address
 */
export function markDeviceAsRegistered(mac: string): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);
  if (existing) {
    existing.isRegistered = true;
    lighthouseStates.set(normalizedMac, existing);
  }
}

/**
 * Remove a pending device from state (used after claiming)
 * @param mac - The device MAC address
 */
export function removePendingDevice(mac: string): void {
  const normalizedMac = mac.toUpperCase();
  const state = lighthouseStates.get(normalizedMac);
  if (state && !state.isRegistered) {
    lighthouseStates.delete(normalizedMac);
  }
}

/**
 * Check if a device exists in pending state
 * @param mac - The device MAC address
 * @returns true if the device is pending (in state and not registered)
 */
export function isPendingDevice(mac: string): boolean {
  const state = lighthouseStates.get(mac.toUpperCase());
  return state !== undefined && !state.isRegistered;
}
