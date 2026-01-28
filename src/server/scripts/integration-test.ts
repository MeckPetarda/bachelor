#!/usr/bin/env bun
/**
 * Integration Test Script for MQTT Topic Standardization
 *
 * This script provides utilities for manual integration testing of the
 * firmware and server MQTT communication. It simulates lighthouse behavior
 * and verifies server responses.
 *
 * Usage:
 *   bun run scripts/integration-test.ts [command]
 *
 * Commands:
 *   simulate-lighthouse <mac>  - Simulate a lighthouse device
 *   send-config <mac> <key> <value> - Send config to lighthouse
 *   check-status <mac>         - Check runtime status of lighthouse
 *   list-events <mac>          - List connection events for lighthouse
 *   list-health <mac>          - List health snapshots for lighthouse
 *   cleanup                    - Run retention cleanup
 */

import mqtt from "mqtt";
import { initDatabase, getDatabase, schema } from "../src/database/client";
import { eq, desc } from "drizzle-orm";
import { publishConfig } from "../src/mqtt/handlers/config";
import { getLighthouseState, getAllLighthouseStates } from "../src/mqtt/state";
import { runRetentionCleanup } from "../src/database/cleanup";
import {
  buildScanTopic,
  buildStatusTopic,
  buildHealthTopic,
  TOPIC_BASE,
} from "../src/mqtt/topics";

const MQTT_URL = process.env.MQTT_URL || "mqtt://localhost:1883";

// Helper to format dates
function formatDate(date: Date | null): string {
  if (!date) return "N/A";
  return date.toISOString();
}

// Helper to sleep
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Simulate a lighthouse device
async function simulateLighthouse(mac: string) {
  console.log(`\n=== Simulating Lighthouse: ${mac} ===\n`);

  const client = mqtt.connect(MQTT_URL, {
    clientId: mac,
    will: {
      topic: buildStatusTopic(mac),
      payload: Buffer.from("offline"),
      qos: 1,
      retain: true,
    },
  });

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Connection timeout")), 5000);
    client.on("connect", () => {
      clearTimeout(timeout);
      resolve();
    });
    client.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });

  console.log("[Connected] Publishing online status...");

  // Publish online status
  client.publish(buildStatusTopic(mac), "online", { qos: 1, retain: true });
  await sleep(500);

  // Subscribe to config topics
  const configTopic = `${TOPIC_BASE}${mac}/config/+`;
  console.log(`[Subscribing] Config topic: ${configTopic}`);
  client.subscribe(configTopic, { qos: 1 });

  client.on("message", (topic, payload) => {
    console.log(`\n[Config Received] Topic: ${topic}`);
    try {
      const parsed = JSON.parse(payload.toString());
      console.log(`  Value: ${JSON.stringify(parsed.value)}`);
      console.log(`  Timestamp: ${parsed.timestamp}`);
    } catch {
      console.log(`  Payload: ${payload.toString()}`);
    }
  });

  // Publish initial health
  console.log("\n[Publishing] Initial health metrics...");
  const healthPayload = {
    uptime_sec: 0,
    free_heap_bytes: 200000,
    min_free_heap_bytes: 180000,
    wifi_rssi_dbm: -55,
    rfid: {
      state: "RESPONSIVE",
      is_responsive: true,
      power_rail_present: true,
      fw_version: "1.0",
      last_error: 0,
    },
  };
  client.publish(buildHealthTopic(mac), JSON.stringify(healthPayload), { qos: 0 });

  console.log("\n[Simulating] Lighthouse is running. Press Ctrl+C to stop.\n");
  console.log("Commands:");
  console.log("  s - Simulate a scan event");
  console.log("  h - Publish health update");
  console.log("  d - Graceful disconnect");
  console.log("  q - Quit (ungraceful - LWT will trigger)\n");

  let uptimeCounter = 0;

  // Periodic health updates
  const healthInterval = setInterval(() => {
    uptimeCounter += 60;
    healthPayload.uptime_sec = uptimeCounter;
    healthPayload.free_heap_bytes = 180000 + Math.floor(Math.random() * 20000);
    healthPayload.wifi_rssi_dbm = -50 - Math.floor(Math.random() * 20);

    console.log(`[Health] Uptime: ${uptimeCounter}s, Heap: ${healthPayload.free_heap_bytes}, RSSI: ${healthPayload.wifi_rssi_dbm}`);
    client.publish(buildHealthTopic(mac), JSON.stringify(healthPayload), { qos: 0 });
  }, 60000);

  // Handle stdin for interactive commands
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on("data", async (key) => {
    const char = key.toString();

    if (char === "s") {
      // Simulate scan
      const scanPayload = {
        epc: `E200${Date.now().toString(16).padStart(16, "0").slice(-16)}`,
        timestampMs: Date.now(),
        rssiDbm: -40 - Math.floor(Math.random() * 20),
        antennaId: 1,
        frequency: 915000000,
        deviceId: mac,
        offline: false,
      };
      console.log(`\n[Scan] EPC: ${scanPayload.epc}, RSSI: ${scanPayload.rssiDbm}`);
      client.publish(buildScanTopic(mac), JSON.stringify(scanPayload), { qos: 2 });
    } else if (char === "h") {
      // Manual health update
      uptimeCounter += 1;
      healthPayload.uptime_sec = uptimeCounter;
      console.log(`\n[Health] Manual update, Uptime: ${uptimeCounter}s`);
      client.publish(buildHealthTopic(mac), JSON.stringify(healthPayload), { qos: 0 });
    } else if (char === "d") {
      // Graceful disconnect
      console.log("\n[Disconnecting] Graceful shutdown...");
      clearInterval(healthInterval);
      client.publish(buildStatusTopic(mac), "offline", { qos: 1, retain: true }, () => {
        client.end(false, {}, () => {
          console.log("[Disconnected] Graceful shutdown complete.");
          process.exit(0);
        });
      });
    } else if (char === "q" || char === "\u0003") {
      // Quit without graceful disconnect (Ctrl+C or q)
      console.log("\n[Quitting] Ungraceful disconnect (LWT will trigger)...");
      clearInterval(healthInterval);
      client.end(true); // Force close
      process.exit(0);
    }
  });
}

// Send config to lighthouse
async function sendConfig(mac: string, key: string, value: string) {
  console.log(`\n=== Sending Config to ${mac} ===\n`);

  // Try to parse value as JSON, otherwise use as string
  let parsedValue: unknown = value;
  try {
    parsedValue = JSON.parse(value);
  } catch {
    // Keep as string if not valid JSON
  }

  console.log(`Key: ${key}`);
  console.log(`Value: ${JSON.stringify(parsedValue)}`);

  publishConfig(mac, key, parsedValue);
  console.log("\nConfig published successfully.");
}

// Check runtime status
async function checkStatus(mac: string) {
  console.log(`\n=== Runtime Status for ${mac} ===\n`);

  const state = getLighthouseState(mac);

  if (!state) {
    console.log("No runtime state found for this device.");
    console.log("The device may not have connected since server startup.");
    return;
  }

  console.log(`Connected: ${state.isConnected}`);
  console.log(`Connected At: ${formatDate(state.connectedAt)}`);
  console.log(`Disconnected At: ${formatDate(state.disconnectedAt)}`);
  console.log(`Last Health At: ${formatDate(state.lastHealthAt)}`);

  if (state.latestHealth) {
    console.log("\nLatest Health:");
    console.log(`  Uptime: ${state.latestHealth.uptimeSec}s`);
    console.log(`  Free Heap: ${state.latestHealth.freeHeapBytes} bytes`);
    console.log(`  Min Free Heap: ${state.latestHealth.minFreeHeapBytes} bytes`);
    console.log(`  WiFi RSSI: ${state.latestHealth.wifiRssiDbm} dBm`);
    console.log(`  RFID State: ${state.latestHealth.rfid.state}`);
    console.log(`  RFID Responsive: ${state.latestHealth.rfid.isResponsive}`);
  }
}

// List all runtime states
async function listAllStates() {
  console.log(`\n=== All Lighthouse Runtime States ===\n`);

  const states = getAllLighthouseStates();

  if (states.size === 0) {
    console.log("No runtime states found.");
    return;
  }

  for (const [mac, state] of states) {
    console.log(`${mac}:`);
    console.log(`  Connected: ${state.isConnected}`);
    console.log(`  Last Health: ${formatDate(state.lastHealthAt)}`);
    console.log("");
  }
}

// List connection events
async function listEvents(mac: string) {
  console.log(`\n=== Connection Events for ${mac} ===\n`);

  initDatabase();
  const db = getDatabase();

  // Find lighthouse by device ID
  const lighthouse = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, mac))
    .limit(1);

  if (lighthouse.length === 0) {
    console.log(`Lighthouse with device ID ${mac} not found in database.`);
    return;
  }

  const events = await db
    .select()
    .from(schema.lighthouseConnectionEvents)
    .where(eq(schema.lighthouseConnectionEvents.lighthouseId, lighthouse[0].id))
    .orderBy(desc(schema.lighthouseConnectionEvents.recordedAt))
    .limit(20);

  if (events.length === 0) {
    console.log("No connection events found.");
    return;
  }

  console.log("Recent Events (newest first):\n");
  for (const event of events) {
    const graceful = event.isGraceful === null ? "N/A" : event.isGraceful ? "Yes" : "No";
    console.log(`  ${formatDate(event.recordedAt)} - ${event.eventType} (graceful: ${graceful})`);
  }
}

// List health snapshots
async function listHealth(mac: string) {
  console.log(`\n=== Health Snapshots for ${mac} ===\n`);

  initDatabase();
  const db = getDatabase();

  // Find lighthouse by device ID
  const lighthouse = await db
    .select()
    .from(schema.lighthouses)
    .where(eq(schema.lighthouses.deviceId, mac))
    .limit(1);

  if (lighthouse.length === 0) {
    console.log(`Lighthouse with device ID ${mac} not found in database.`);
    return;
  }

  const snapshots = await db
    .select()
    .from(schema.lighthouseHealthSnapshots)
    .where(eq(schema.lighthouseHealthSnapshots.lighthouseId, lighthouse[0].id))
    .orderBy(desc(schema.lighthouseHealthSnapshots.recordedAt))
    .limit(10);

  if (snapshots.length === 0) {
    console.log("No health snapshots found.");
    return;
  }

  console.log("Recent Snapshots (newest first):\n");
  for (const snapshot of snapshots) {
    console.log(`  ${formatDate(snapshot.recordedAt)}`);
    console.log(`    Uptime: ${snapshot.uptimeSec}s, Heap: ${snapshot.freeHeapBytes}, RSSI: ${snapshot.wifiRssiDbm}`);
    console.log(`    RFID: ${snapshot.rfidState} (responsive: ${snapshot.rfidIsResponsive})`);
    console.log("");
  }
}

// Run retention cleanup
async function cleanup() {
  console.log(`\n=== Running Retention Cleanup ===\n`);

  initDatabase();
  await runRetentionCleanup();

  console.log("\nCleanup complete.");
}

// Main entry point
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "simulate-lighthouse":
      if (!args[1]) {
        console.error("Usage: simulate-lighthouse <mac>");
        console.error("Example: simulate-lighthouse AA:BB:CC:DD:EE:01");
        process.exit(1);
      }
      await simulateLighthouse(args[1]);
      break;

    case "send-config":
      if (!args[1] || !args[2] || !args[3]) {
        console.error("Usage: send-config <mac> <key> <value>");
        console.error("Example: send-config AA:BB:CC:DD:EE:01 scan_interval 30");
        process.exit(1);
      }
      await sendConfig(args[1], args[2], args[3]);
      break;

    case "check-status":
      if (!args[1]) {
        console.error("Usage: check-status <mac>");
        process.exit(1);
      }
      await checkStatus(args[1]);
      break;

    case "list-all":
      await listAllStates();
      break;

    case "list-events":
      if (!args[1]) {
        console.error("Usage: list-events <mac>");
        process.exit(1);
      }
      await listEvents(args[1]);
      break;

    case "list-health":
      if (!args[1]) {
        console.error("Usage: list-health <mac>");
        process.exit(1);
      }
      await listHealth(args[1]);
      break;

    case "cleanup":
      await cleanup();
      break;

    default:
      console.log(`
Integration Test Script for MQTT Topic Standardization

Usage:
  bun run scripts/integration-test.ts [command]

Commands:
  simulate-lighthouse <mac>        Simulate a lighthouse device
  send-config <mac> <key> <value>  Send config to lighthouse
  check-status <mac>               Check runtime status of lighthouse
  list-all                         List all runtime states
  list-events <mac>                List connection events for lighthouse
  list-health <mac>                List health snapshots for lighthouse
  cleanup                          Run retention cleanup

Examples:
  bun run scripts/integration-test.ts simulate-lighthouse AA:BB:CC:DD:EE:01
  bun run scripts/integration-test.ts send-config AA:BB:CC:DD:EE:01 scan_interval 30
  bun run scripts/integration-test.ts check-status AA:BB:CC:DD:EE:01
`);
      break;
  }
}

main().catch(console.error);
