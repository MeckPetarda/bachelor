import {
  describe,
  it,
  expect,
  beforeAll,
  afterAll,
  beforeEach,
} from "bun:test";
import mqtt from "mqtt";
import {
  startMqttBroker,
  closeMqttBroker,
  getMqttBrokerStats,
} from "../src/mqtt/broker";
import {
  initDatabase,
  closeDatabase,
  getDatabase,
  schema,
} from "../src/database/client";
import { eq, desc } from "drizzle-orm";
import {
  buildScanTopic,
  buildStatusTopic,
  buildHealthTopic,
  buildConfigTopic,
} from "../src/mqtt/topics";
import { publishConfig } from "../src/mqtt/handlers/config";
import { clearAllStates, getLighthouseState } from "../src/mqtt/state";

// Test configuration
const MQTT_PORT = 1883;
const MQTT_URL = `mqtt://localhost:${MQTT_PORT}`;
// Use valid MAC address format for device ID
const TEST_DEVICE_ID = "AA:BB:CC:DD:EE:01";
const TEST_LIGHTHOUSE_ID = 999;

// Helper to wait for a condition with timeout
async function waitFor(
  condition: () => Promise<boolean>,
  timeout = 5000,
  interval = 100,
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
    // Clean up any data from previous tests
    const db = getDatabase();
    await db
      .delete(schema.rawScans)
      .where(eq(schema.rawScans.lighthouseId, TEST_LIGHTHOUSE_ID));
    await db
      .delete(schema.lighthouseHealthSnapshots)
      .where(
        eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID),
      );
    await db
      .delete(schema.lighthouseConnectionEvents)
      .where(
        eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID),
      );
    // Clear runtime state
    clearAllStates();
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
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
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
    const topic = buildScanTopic(TEST_DEVICE_ID);
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
    expect(storedScan.detectionConfidence).toBeCloseTo(
      scanPayload.detectionConfidence,
      2,
    );
    expect(storedScan.processedAt).toBeNull();

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
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
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
    const topic = buildScanTopic(TEST_DEVICE_ID);
    const publishPromises: Promise<void>[] = [];

    for (let i = 0; i < numScans; i++) {
      const scanPayload = {
        epc: `E2000012345678${i.toString().padStart(6, "0")}`,
        timestampMs: Date.now() + i,
        rssiDbm: -40 - i,
      };

      publishPromises.push(
        new Promise<void>((resolve, reject) => {
          client!.publish(
            topic,
            JSON.stringify(scanPayload),
            { qos: 0 },
            (err) => {
              if (err) reject(err);
              else resolve();
            },
          );
        }),
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
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish from unknown device (use valid MAC format for unknown device)
    const unknownMac = "FF:FF:FF:FF:FF:FF";
    const topic = buildScanTopic(unknownMac);
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
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
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
    const topic = buildScanTopic(TEST_DEVICE_ID);
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
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
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
    const topic = buildScanTopic(TEST_DEVICE_ID);
    const invalidPayload = {
      timestampMs: Date.now(),
      rssiDbm: -45,
    };

    await new Promise<void>((resolve, reject) => {
      client!.publish(
        topic,
        JSON.stringify(invalidPayload),
        { qos: 0 },
        (err) => {
          if (err) reject(err);
          else resolve();
        },
      );
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

  // ==================== Status Handler Tests ====================

  it("should update runtime state on online message", async () => {
    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-status-online-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish online status
    const topic = buildStatusTopic(TEST_DEVICE_ID);
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "online", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait for state update
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify runtime state
    const state = getLighthouseState(TEST_DEVICE_ID);
    expect(state).toBeDefined();
    expect(state?.isConnected).toBe(true);
    expect(state?.connectedAt).toBeDefined();

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should record connection event on status change", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-status-event-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish online status
    const topic = buildStatusTopic(TEST_DEVICE_ID);
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "online", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait for event to be recorded
    await waitFor(async () => {
      const events = await db
        .select()
        .from(schema.lighthouseConnectionEvents)
        .where(
          eq(
            schema.lighthouseConnectionEvents.lighthouseId,
            TEST_LIGHTHOUSE_ID,
          ),
        )
        .limit(1);
      return events.length > 0;
    }, 3000);

    // Verify connection event was recorded
    const events = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(
        eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID),
      )
      .limit(1);

    expect(events.length).toBe(1);
    expect(events[0]?.eventType).toBe("connected");

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should mark lighthouse disconnected on offline message", async () => {
    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-status-offline-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    const topic = buildStatusTopic(TEST_DEVICE_ID);

    // First send online
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "online", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 300));

    // Then send offline
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "offline", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify runtime state shows disconnected
    const state = getLighthouseState(TEST_DEVICE_ID);
    expect(state).toBeDefined();
    expect(state?.isConnected).toBe(false);
    expect(state?.disconnectedAt).toBeDefined();

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should handle unknown lighthouse status gracefully", async () => {
    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-status-unknown-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish status from unknown device
    const unknownMac = "FF:FF:FF:FF:FF:FE";
    const topic = buildStatusTopic(unknownMac);
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "online", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Broker should still be running
    const stats = getMqttBrokerStats();
    expect(stats.isRunning).toBe(true);

    // Runtime state should still be updated for unknown device
    const state = getLighthouseState(unknownMac);
    expect(state).toBeDefined();
    expect(state?.isConnected).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  // ==================== Health Handler Tests ====================

  it("should store health snapshot from valid message", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-health-store-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Create valid health payload
    const healthPayload = {
      uptime_sec: 3600,
      free_heap_bytes: 45000,
      min_free_heap_bytes: 38000,
      wifi_rssi_dbm: -52,
      rfid: {
        state: "RESPONSIVE",
        is_responsive: true,
        power_rail_present: true,
        fw_version: "1.2",
        last_error: 0,
      },
    };

    // Publish health message
    const topic = buildHealthTopic(TEST_DEVICE_ID);
    await new Promise<void>((resolve, reject) => {
      client!.publish(
        topic,
        JSON.stringify(healthPayload),
        { qos: 0 },
        (err) => {
          if (err) reject(err);
          else resolve();
        },
      );
    });

    // Wait for snapshot to be stored
    await waitFor(async () => {
      const snapshots = await db
        .select()
        .from(schema.lighthouseHealthSnapshots)
        .where(
          eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID),
        )
        .limit(1);
      return snapshots.length > 0;
    }, 3000);

    // Verify snapshot was stored
    const snapshots = await db
      .select()
      .from(schema.lighthouseHealthSnapshots)
      .where(
        eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID),
      )
      .limit(1);

    expect(snapshots.length).toBe(1);
    const snapshot = snapshots[0];
    expect(snapshot?.uptimeSec).toBe(3600);
    expect(snapshot?.freeHeapBytes).toBe(45000);
    expect(snapshot?.wifiRssiDbm).toBe(-52);
    expect(snapshot?.rfidState).toBe("RESPONSIVE");
    expect(snapshot?.rfidIsResponsive).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should update runtime health state", async () => {
    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-health-runtime-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Create valid health payload
    const healthPayload = {
      uptime_sec: 7200,
      free_heap_bytes: 40000,
      min_free_heap_bytes: 35000,
      wifi_rssi_dbm: -60,
      rfid: {
        state: "IDLE",
        is_responsive: true,
        power_rail_present: true,
        fw_version: "1.3",
        last_error: 0,
      },
    };

    // Publish health message
    const topic = buildHealthTopic(TEST_DEVICE_ID);
    await new Promise<void>((resolve, reject) => {
      client!.publish(
        topic,
        JSON.stringify(healthPayload),
        { qos: 0 },
        (err) => {
          if (err) reject(err);
          else resolve();
        },
      );
    });

    // Wait for state update
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify runtime state
    const state = getLighthouseState(TEST_DEVICE_ID);
    expect(state).toBeDefined();
    expect(state?.latestHealth).toBeDefined();
    expect(state?.latestHealth?.uptimeSec).toBe(7200);
    expect(state?.latestHealth?.freeHeapBytes).toBe(40000);
    expect(state?.lastHealthAt).toBeDefined();

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should reject malformed health payload", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-health-malformed-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish malformed health message (missing required fields)
    const topic = buildHealthTopic(TEST_DEVICE_ID);
    await new Promise<void>((resolve, reject) => {
      client!.publish(
        topic,
        JSON.stringify({ uptime_sec: 100 }),
        { qos: 0 },
        (err) => {
          if (err) reject(err);
          else resolve();
        },
      );
    });

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Verify no snapshot was stored
    const snapshots = await db
      .select()
      .from(schema.lighthouseHealthSnapshots)
      .where(
        eq(schema.lighthouseHealthSnapshots.lighthouseId, TEST_LIGHTHOUSE_ID),
      );

    expect(snapshots.length).toBe(0);

    // Broker should still be running
    const stats = getMqttBrokerStats();
    expect(stats.isRunning).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should handle unknown lighthouse health gracefully", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-health-unknown-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Publish health from unknown device
    const unknownMac = "FF:FF:FF:FF:FF:FD";
    const topic = buildHealthTopic(unknownMac);
    const healthPayload = {
      uptime_sec: 100,
      free_heap_bytes: 50000,
      min_free_heap_bytes: 45000,
      wifi_rssi_dbm: -50,
      rfid: {
        state: "READY",
        is_responsive: true,
        power_rail_present: true,
        fw_version: "1.0",
        last_error: 0,
      },
    };

    await new Promise<void>((resolve, reject) => {
      client!.publish(
        topic,
        JSON.stringify(healthPayload),
        { qos: 0 },
        (err) => {
          if (err) reject(err);
          else resolve();
        },
      );
    });

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Broker should still be running
    const stats = getMqttBrokerStats();
    expect(stats.isRunning).toBe(true);

    // Runtime state should still be updated
    const state = getLighthouseState(unknownMac);
    expect(state?.latestHealth).toBeDefined();

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  // ==================== Graceful/Ungraceful Disconnect Tests ====================

  it("should record graceful disconnect with isGraceful=true", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-graceful-disconnect-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    const topic = buildStatusTopic(TEST_DEVICE_ID);

    // Send online status first
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "online", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 300));

    // Simulate graceful disconnect by sending offline before disconnecting
    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "offline", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait for event to be recorded
    await waitFor(async () => {
      const events = await db
        .select()
        .from(schema.lighthouseConnectionEvents)
        .where(
          eq(
            schema.lighthouseConnectionEvents.lighthouseId,
            TEST_LIGHTHOUSE_ID,
          ),
        )
        .orderBy(desc(schema.lighthouseConnectionEvents.recordedAt));
      return events.some((e) => e.eventType === "disconnected");
    }, 3000);

    // Verify disconnect event was recorded as graceful
    const events = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(
        eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID),
      )
      .orderBy(desc(schema.lighthouseConnectionEvents.recordedAt));

    const disconnectEvent = events.find((e) => e.eventType === "disconnected");
    expect(disconnectEvent).toBeDefined();
    expect(disconnectEvent?.isGraceful).toBe(true);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should record ungraceful disconnect with isGraceful=false when no prior online seen", async () => {
    const db = getDatabase();

    // Connect MQTT client
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-ungraceful-disconnect-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    const topic = buildStatusTopic(TEST_DEVICE_ID);

    // Simulate LWT-triggered offline (no prior online message in this test run)
    // Clear state first to simulate fresh scenario
    clearAllStates();

    await new Promise<void>((resolve, reject) => {
      client!.publish(topic, "offline", { qos: 0 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Wait for event to be recorded
    await waitFor(async () => {
      const events = await db
        .select()
        .from(schema.lighthouseConnectionEvents)
        .where(
          eq(
            schema.lighthouseConnectionEvents.lighthouseId,
            TEST_LIGHTHOUSE_ID,
          ),
        )
        .orderBy(desc(schema.lighthouseConnectionEvents.recordedAt));
      return events.some((e) => e.eventType === "disconnected");
    }, 3000);

    // Verify disconnect event was recorded as ungraceful
    const events = await db
      .select()
      .from(schema.lighthouseConnectionEvents)
      .where(
        eq(schema.lighthouseConnectionEvents.lighthouseId, TEST_LIGHTHOUSE_ID),
      )
      .orderBy(desc(schema.lighthouseConnectionEvents.recordedAt));

    const disconnectEvent = events.find((e) => e.eventType === "disconnected");
    expect(disconnectEvent).toBeDefined();
    expect(disconnectEvent?.isGraceful).toBe(false);

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  // ==================== Config Publisher Tests ====================

  it("should publish config message to correct topic", async () => {
    let receivedMessage: { topic: string; payload: string } | null = null;

    // Connect MQTT client as subscriber
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-config-subscriber-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Subscribe to config topics for our test device
    const configTopic = buildConfigTopic(TEST_DEVICE_ID, "+");
    await new Promise<void>((resolve, reject) => {
      client!.subscribe(configTopic, { qos: 1 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Set up message handler
    client.on("message", (topic, payload) => {
      receivedMessage = { topic, payload: payload.toString() };
    });

    // Use the server's publishConfig function
    publishConfig(TEST_DEVICE_ID, "scan_interval", 30);

    // Wait for message to be received
    await waitFor(async () => receivedMessage !== null, 3000);

    // Verify the message
    expect(receivedMessage).not.toBeNull();
    expect(receivedMessage?.topic).toBe(
      buildConfigTopic(TEST_DEVICE_ID, "scan_interval"),
    );

    const payload = JSON.parse(receivedMessage!.payload);
    expect(payload.value).toBe(30);
    expect(payload.timestamp).toBeDefined();

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });

  it("should publish config with various value types", async () => {
    const receivedMessages: Array<{ topic: string; payload: string }> = [];

    // Connect MQTT client as subscriber
    client = mqtt.connect(MQTT_URL, {
      clientId: "test-config-types-client",
      connectTimeout: 5000,
    });

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Connection timeout")),
        5000,
      );
      client!.on("connect", () => {
        clearTimeout(timeout);
        resolve();
      });
      client!.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Subscribe to config topics
    const configTopic = buildConfigTopic(TEST_DEVICE_ID, "+");
    await new Promise<void>((resolve, reject) => {
      client!.subscribe(configTopic, { qos: 1 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Set up message handler
    client.on("message", (topic, payload) => {
      receivedMessages.push({ topic, payload: payload.toString() });
    });

    // Publish configs with different value types
    publishConfig(TEST_DEVICE_ID, "string_config", "test_value");
    publishConfig(TEST_DEVICE_ID, "number_config", 42.5);
    publishConfig(TEST_DEVICE_ID, "boolean_config", true);
    publishConfig(TEST_DEVICE_ID, "object_config", {
      nested: "value",
      count: 10,
    });

    // Wait for all messages to be received
    await waitFor(async () => receivedMessages.length >= 4, 3000);

    // Verify each message type
    const stringMsg = receivedMessages.find((m) =>
      m.topic.includes("string_config"),
    );
    const numberMsg = receivedMessages.find((m) =>
      m.topic.includes("number_config"),
    );
    const boolMsg = receivedMessages.find((m) =>
      m.topic.includes("boolean_config"),
    );
    const objectMsg = receivedMessages.find((m) =>
      m.topic.includes("object_config"),
    );

    expect(JSON.parse(stringMsg!.payload).value).toBe("test_value");
    expect(JSON.parse(numberMsg!.payload).value).toBe(42.5);
    expect(JSON.parse(boolMsg!.payload).value).toBe(true);
    expect(JSON.parse(objectMsg!.payload).value).toEqual({
      nested: "value",
      count: 10,
    });

    // Disconnect
    await new Promise<void>((resolve) => {
      client!.end(false, {}, () => resolve());
    });
    client = null;
  });
});
