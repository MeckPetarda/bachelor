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
 */
export function setLighthouseConnected(mac: string): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);

  lighthouseStates.set(normalizedMac, {
    isConnected: true,
    connectedAt: new Date(),
    disconnectedAt: null,
    lastHealthAt: existing?.lastHealthAt ?? null,
    latestHealth: existing?.latestHealth ?? null,
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

  lighthouseStates.set(normalizedMac, {
    isConnected: false,
    connectedAt: existing?.connectedAt ?? null,
    disconnectedAt: new Date(),
    lastHealthAt: existing?.lastHealthAt ?? null,
    latestHealth: existing?.latestHealth ?? null,
  });
}

/**
 * Update the health metrics for a lighthouse
 * @param mac - The lighthouse MAC address
 * @param health - The health payload
 */
export function updateLighthouseHealth(mac: string, health: HealthPayload): void {
  const normalizedMac = mac.toUpperCase();
  const existing = lighthouseStates.get(normalizedMac);

  lighthouseStates.set(normalizedMac, {
    isConnected: existing?.isConnected ?? false,
    connectedAt: existing?.connectedAt ?? null,
    disconnectedAt: existing?.disconnectedAt ?? null,
    lastHealthAt: new Date(),
    latestHealth: health,
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
