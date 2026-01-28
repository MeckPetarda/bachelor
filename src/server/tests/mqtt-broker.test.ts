import { describe, it, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import mqtt from "mqtt";
import { startMqttBroker, closeMqttBroker, getMqttBrokerStats } from "../src/mqtt/broker";
import { initDatabase, closeDatabase, getDatabase, schema } from "../src/database/client";
import { eq, desc } from "drizzle-orm";

// Test configuration
const MQTT_PORT = 1883;
const MQTT_URL = `mqtt://localhost:${MQTT_PORT}`;
const TEST_DEVICE_ID = "test-lighthouse-001";
const TEST_LIGHTHOUSE_ID = 999;

// Helper to wait for a condition with timeout
async function waitFor(
  condition: () => Promise<boolean>,
  timeout = 5000,
  interval = 100
): Promise<void> {
  const startTime = Date.now();
  while (Date.now() - startTime < timeout) {
    if (await condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
  throw new Error(`Timeout waiting for condition after ${timeout}ms`);
}

describe("MQTT Broker Integration", () => {
  let client: mqtt.MqttClient | null = null;

  beforeAll(async () => {
    // Initialize database
    initDatabase();
    const db = getDatabase();

    // Create test lighthouse if it doesn't exist
    const existing = await db
      .select()
      .from(schema.lighthouses)
      .where(eq(schema.lighthouses.deviceId, TEST_DEVICE_ID))
      .limit(1);

    if (existing.length === 0) {
      await db.insert(schema.lighthouses).values({
        id: TEST_LIGHTHOUSE_ID,
        name: "Test Lighthouse",
        deviceId: TEST_DEVICE_ID,
        placement: "STANDALONE",
        isActive: true,
      });
    }

    // Start MQTT broker
    startMqttBroker();

    // Wait for broker to be ready
    await new Promise((resolve) => setTimeout(resolve, 500));
  });

  afterAll(async () => {
    // Clean up MQTT client if connected
    if (client && client.connected) {
      await new Promise<void>((resolve) => {
        client!.end(false, {}, () => resolve());
      });
    }

    // Clean up test data
    const db = getDatabase();
    await db
      .delete(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));

    // Close MQTT broker
    await closeMqttBroker();

    // Close database
    await closeDatabase();
  });

  beforeEach(async () => {
    // Clean up any scans from previous tests
    const db = getDatabase();
    await db
      .delete(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
  });

  it("should start the MQTT broker on configured port", () => {
    const stats = getMqttBrokerStats();
    expect(stats.isRunning).toBe(true);
    expect(stats.port).toBe(MQTT_PORT);
  });

  it("should accept client connections", async () => {
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-client-001",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Connection timeout"));
      }, 5000);

      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });

      client!.on("error", (error) => {
        clearTimeout(timeout);
        reject(error);
      });
    });

    expect(client.connected).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should receive and store scan messages in raw_scans table", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-lighthouse-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Create test scan payload
    const scanPayload = {
      epc: "E200001234567890ABCD",
      epcLength: 96,
      rssiDbm: -45,
      antennaId: 1,
      frequency: 915000000,
      sequenceNumber: 12345,
      detectionConfidence: 0.95,
      timestampMs: Date.now(),
    };

    // Publish to scan topic
    const topic = `attendance/lighthouse/${TEST_DEVICE_ID}/scans`;
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, JSON.stringify(scanPayload), { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait for the scan to be stored in the database
    await waitFor(async () => {
      const scans = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
        .limit(1);
      return scans.length > 0;
    }, 3000);

    // Verify the scan was stored correctly
    const storedScans = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID))
      .limit(1);

    expect(storedScans.length).toBe(1);


    const storedScan = storedScans[0];

    if (storedScan === undefined) return;

    expect(storedScan.epc).toBe(scanPayload.epc);
    expect(storedScan.rssiDbm).toBe(scanPayload.rssiDbm);
    expect(storedScan.antennaId).toBe(scanPayload.antennaId);
    expect(storedScan.frequency).toBe(scanPayload.frequency);
    expect(storedScan.sequenceNumber).toBe(scanPayload.sequenceNumber);
    expect(storedScan.detectionConfidence).toBeCloseTo(scanPayload.detectionConfidence, 2);
    expect(storedScan.processed).toBe(false);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should handle multiple scan messages without dropping any", async () => {
    const db = getDatabase();
    const numScans = 10;

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-batch-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish multiple scan messages
    const topic = `attendance/lighthouse/${TEST_DEVICE_ID}/scans`;
    const publishPromises: Promise<void>[] = [];

    for (let i = 0; i < numScans; i++) {
      const scanPayload = {
        epc: `E2000012345678${i.toString().padStart(6, "0")}`,
        timestampMs: Date.now() + i,
        rssiDbm: -40 - i,
      };

      publishPromises.push(
        new Promise<void>((resolve, reject) => {
          client!.publish(topic, JSON.stringify(scanPayload), { qos: 0 }, (err) => {
            if (err) reject(err);
            else resolve();
          });
        })
      );
    }

    await Promise.all(publishPromises);

    // Wait for all scans to be stored
    await waitFor(async () => {
      const scans = await db
        .select()
        .from(schema.rawScans)
        .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
      return scans.length >= numScans;
    }, 5000);

    // Verify all scans were stored
    const storedScans = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));

    expect(storedScans.length).toBe(numScans);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should ignore messages from unknown lighthouses", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-unknown-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish from unknown device
    const topic = "attendance/lighthouse/unknown-device-xyz/scans";
    const scanPayload = {
      epc: "E200001234567890FFFF",
      timestampMs: Date.now(),
    };

    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, JSON.stringify(scanPayload), { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait a bit to ensure message is processed
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify no scan was stored (since lighthouse is unknown)
    const storedScans = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.epc, scanPayload.epc));

    expect(storedScans.length).toBe(0);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should reject invalid JSON payloads gracefully", async () => {
    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-invalid-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish invalid JSON
    const topic = `attendance/lighthouse/${TEST_DEVICE_ID}/scans`;
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "not valid json {{{", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Broker should still be running
    const stats = getMqttBrokerStats();
    expect(stats.isRunning).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should reject payloads missing required fields", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-missing-fields-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish payload missing required epc field
    const topic = `attendance/lighthouse/${TEST_DEVICE_ID}/scans`;
    const invalidPayload = {
      timestampMs: Date.now(),
      rssiDbm: -45,
    };

    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, JSON.stringify(invalidPayload), { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify nothing was stored
    const storedScans = await db
      .select()
      .from(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));

    expect(storedScans.length).toBe(0);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });
});
