/**
 * MQTT Topic patterns and utilities for lighthouse communication
 *
 * Topic structure: attendance/lighthouse/{MAC}/[scans|status|health|config/{key}]
 * MAC format: AA:BB:CC:DD:EE:FF (17 characters)
 */

export const TOPIC_BASE = "attendance/lighthouse/";

// MAC address regex pattern: AA:BB:CC:DD:EE:FF (17 chars)
const MAC_PATTERN = "[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}";

/**
 * Pattern for scan topics: attendance/lighthouse/{MAC}/scans
 * Captures MAC address as first group
 */
export const SCAN_TOPIC_PATTERN = new RegExp(
  `^${TOPIC_BASE}(${MAC_PATTERN})/scans$`
);

/**
 * Pattern for status topics: attendance/lighthouse/{MAC}/status
 * Captures MAC address as first group
 */
export const STATUS_TOPIC_PATTERN = new RegExp(
  `^${TOPIC_BASE}(${MAC_PATTERN})/status$`
);

/**
 * Pattern for health topics: attendance/lighthouse/{MAC}/health
 * Captures MAC address as first group
 */
export const HEALTH_TOPIC_PATTERN = new RegExp(
  `^${TOPIC_BASE}(${MAC_PATTERN})/health$`
);

/**
 * Pattern for config topics: attendance/lighthouse/{MAC}/config/{key}
 * Captures MAC address as first group and config key as second group
 */
export const CONFIG_TOPIC_PATTERN = new RegExp(
  `^${TOPIC_BASE}(${MAC_PATTERN})/config/([^/]+)$`
);

/**
 * Extract MAC address from any lighthouse topic
 * @param topic - The MQTT topic string
 * @returns The MAC address or null if not found
 */
export function extractMacAddress(topic: string): string | null {
  // Try each pattern to extract MAC
  const patterns = [
    SCAN_TOPIC_PATTERN,
    STATUS_TOPIC_PATTERN,
    HEALTH_TOPIC_PATTERN,
    CONFIG_TOPIC_PATTERN,
  ];

  for (const pattern of patterns) {
    const match = topic.match(pattern);
    if (match && match[1]) {
      return match[1].toUpperCase();
    }
  }

  return null;
}

/**
 * Build a config topic for publishing configuration to a lighthouse
 * @param mac - The device MAC address
 * @param key - The configuration key
 * @returns The full config topic string
 */
export function buildConfigTopic(mac: string, key: string): string {
  return `${TOPIC_BASE}${mac}/config/${key}`;
}

/**
 * Build a status topic for a lighthouse
 * @param mac - The device MAC address
 * @returns The full status topic string
 */
export function buildStatusTopic(mac: string): string {
  return `${TOPIC_BASE}${mac}/status`;
}

/**
 * Build a health topic for a lighthouse
 * @param mac - The device MAC address
 * @returns The full health topic string
 */
export function buildHealthTopic(mac: string): string {
  return `${TOPIC_BASE}${mac}/health`;
}

/**
 * Build a scan topic for a lighthouse
 * @param mac - The device MAC address
 * @returns The full scan topic string
 */
export function buildScanTopic(mac: string): string {
  return `${TOPIC_BASE}${mac}/scans`;
}
