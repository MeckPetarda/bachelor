import Aedes from "aedes";
import { createServer, Server } from "net";
import { getConfig } from "../config";
import { createLogger } from "../utils/logger";
import { handleScanMessage, SCAN_TOPIC_PATTERN } from "./handlers";

const logger = createLogger("MQTT Broker");

let aedes: Aedes | null = null;
let server: Server | null = null;
let isShuttingDown = false;

export interface MqttBrokerStats {
  isRunning: boolean;
  port: number | null;
  connectedClients: number;
}

/**
 * Initialize and start the Aedes MQTT broker
 * @returns The Aedes broker instance
 */
export function startMqttBroker(): Aedes {
  if (aedes) {
    logger.debug("MQTT broker already running, returning existing instance");
    return aedes;
  }

  const config = getConfig();
  const port = config.mqtt.port;

  logger.info(`Starting MQTT broker on port ${port}...`);

  // Create Aedes broker instance
  aedes = new Aedes();

  // Client connection handler
  aedes.on("client", (client) => {
    logger.info(`Client connected: ${client.id}`);
  });

  // Client disconnection handler
  aedes.on("clientDisconnect", (client) => {
    logger.info(`Client disconnected: ${client.id}`);
  });

  // Client error handler
  aedes.on("clientError", (client, error) => {
    logger.error(`Client error for ${client.id}:`, error.message);
  });

  // Connection error handler
  aedes.on("connectionError", (client, error) => {
    logger.error(`Connection error for ${client.id}:`, error.message);
  });

  // Subscribe handler (for logging)
  aedes.on("subscribe", (subscriptions, client) => {
    const topics = subscriptions.map((s) => s.topic).join(", ");
    logger.debug(`Client ${client.id} subscribed to: ${topics}`);
  });

  // Unsubscribe handler
  aedes.on("unsubscribe", (unsubscriptions, client) => {
    logger.debug(`Client ${client.id} unsubscribed from: ${unsubscriptions.join(", ")}`);
  });

  // Publish handler - route messages to appropriate handlers
  aedes.on("publish", async (packet, client) => {
    // Ignore internal MQTT messages (starting with $)
    if (packet.topic.startsWith("$")) {
      return;
    }

    // Only log if client is present (not internal publishes)
    if (client) {
      logger.debug(`Message received from ${client.id} on topic: ${packet.topic}`);
    }

    // Check if this is a scan topic
    if (SCAN_TOPIC_PATTERN.test(packet.topic)) {
      try {
        await handleScanMessage(packet.topic, packet.payload);
      } catch (error) {
        logger.error(`Failed to handle scan message:`, error);
      }
    }
  });

  // Create TCP server
  server = createServer(aedes.handle);

  server.on("error", (error) => {
    logger.error("Server error:", error.message);
  });

  // Start listening
  server.listen(port, () => {
    logger.info(`MQTT broker is listening on port ${port}`);
  });

  return aedes;
}

/**
 * Get the current MQTT broker instance
 * @returns The Aedes instance or null if not started
 */
export function getMqttBroker(): Aedes | null {
  return aedes;
}

/**
 * Get statistics about the MQTT broker
 */
export function getMqttBrokerStats(): MqttBrokerStats {
  const config = getConfig();
  return {
    isRunning: aedes !== null && server !== null,
    port: aedes ? config.mqtt.port : null,
    connectedClients: aedes ? aedes.connectedClients : 0,
  };
}

/**
 * Publish a message to a topic
 * @param topic - The topic to publish to
 * @param payload - The message payload
 */
export function publishMessage(topic: string, payload: string | Buffer): void {
  if (!aedes) {
    logger.warn("Cannot publish: MQTT broker not running");
    return;
  }

  aedes.publish(
    {
      topic,
      payload: typeof payload === "string" ? Buffer.from(payload) : payload,
      qos: 0,
      retain: false,
      cmd: "publish",
      dup: false,
    },
    (error) => {
      if (error) {
        logger.error(`Failed to publish to ${topic}:`, error.message);
      }
    }
  );
}

/**
 * Close the MQTT broker gracefully
 * @param timeout - Maximum time to wait for closing (ms)
 */
export async function closeMqttBroker(timeout = 5000): Promise<void> {
  if (!aedes || !server) {
    logger.debug("No MQTT broker to close");
    return;
  }

  if (isShuttingDown) {
    logger.warn("MQTT broker shutdown already in progress");
    return;
  }

  isShuttingDown = true;
  logger.info("Closing MQTT broker...");

  return new Promise<void>((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      logger.warn("MQTT broker shutdown timed out, forcing close");
      forceClose();
      resolve();
    }, timeout);

    // Close aedes broker first (disconnects all clients)
    aedes!.close(() => {
      clearTimeout(timeoutId);
      logger.debug("Aedes broker closed");

      // Then close TCP server
      server!.close((error) => {
        if (error) {
          logger.error("Error closing TCP server:", error.message);
        } else {
          logger.debug("TCP server closed");
        }

        cleanup();
        logger.info("MQTT broker closed successfully");
        resolve();
      });
    });
  });
}

function forceClose(): void {
  if (server) {
    server.close();
  }
  cleanup();
}

function cleanup(): void {
  aedes = null;
  server = null;
  isShuttingDown = false;
}
