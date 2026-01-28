/**
 * Config publisher for sending configuration commands to lighthouses
 */

import { getMqttBroker } from "../broker";
import { buildConfigTopic } from "../topics";
import { createLogger } from "../../utils/logger";

const logger = createLogger("Config Publisher");

/**
 * Config payload structure sent to lighthouse
 */
export interface ConfigPayload<T = unknown> {
  value: T;
  timestamp: string;
}

/**
 * Publish a configuration value to a lighthouse
 * @param mac - The lighthouse MAC address
 * @param key - The configuration key (e.g., "scan_interval", "health_interval")
 * @param value - The configuration value
 */
export function publishConfig(mac: string, key: string, value: unknown): void {
  const broker = getMqttBroker();
  if (!broker) {
    logger.warn("Cannot publish config: MQTT broker not running");
    return;
  }

  const topic = buildConfigTopic(mac, key);
  const payload: ConfigPayload = {
    value,
    timestamp: new Date().toISOString(),
  };

  const payloadStr = JSON.stringify(payload);

  broker.publish(
    {
      topic,
      payload: Buffer.from(payloadStr),
      qos: 1, // Use QoS 1 for config messages to ensure delivery
      retain: false,
      cmd: "publish",
      dup: false,
    },
    (error) => {
      if (error) {
        logger.error(`Failed to publish config to ${topic}:`, error.message);
      } else {
        logger.debug(`Published config to ${topic}: ${key}=${JSON.stringify(value)}`);
      }
    }
  );
}

/**
 * Publish multiple configuration values to a lighthouse
 * @param mac - The lighthouse MAC address
 * @param configs - Object with config key-value pairs
 */
export function publishConfigs(mac: string, configs: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(configs)) {
    publishConfig(mac, key, value);
  }
}
