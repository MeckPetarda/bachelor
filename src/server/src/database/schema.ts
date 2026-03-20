import {
  pgTable,
  uuid,
  varchar,
  timestamp,
  boolean,
  integer,
  smallint,
  real,
  bigserial,
  jsonb,
  index,
  uniqueIndex,
  pgEnum,
  serial,
  primaryKey,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

export const lighthousePlacement = pgEnum("lighthouse_placement", [
  "STANDALONE",
  "INSIDE",
  "OUTSIDE",
]);

export const userType = pgEnum("user_type", [
  "STANDALONE",
  "INSIDE",
  "OUTSIDE",
]);

export const scanSource = pgEnum("scan_source", ["realtime", "offline_sync"]);

export const timeBasis = pgEnum("time_basis", [
  "synced",
  "estimated",
  "relative",
]);

export const directionType = pgEnum("direction_type", ["in", "out", "unknown"]);

export const algorithmType = pgEnum("algorithm_type", [
  "temporal_centroid",
  "rssi_weighted_centroid",
  "manual",
]);

export const orphanReasonType = pgEnum("orphan_reason_type", [
  "insufficient_data",
  "misconfigured_group",
  "unsyncable",
]);

export const lighthouseGroups = pgTable(
  "lighthouse_groups",
  {
    id: serial().primaryKey(),
    label: varchar({ length: 255 }).notNull(),
    description: varchar({ length: 500 }),
    activityTimeoutMs: integer().notNull().default(4000),
    orphanTimeoutMs: integer().notNull().default(8000),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [index("idx_lighthouse_groups_label").on(table.label)],
);

export const lighthouses = pgTable(
  "lighthouses",
  {
    id: serial().primaryKey(),
    name: varchar({ length: 255 }).notNull().unique(),
    deviceId: varchar({ length: 255 }).notNull().unique(),
    placement: lighthousePlacement()
      .notNull()
      .default(lighthousePlacement.enumValues[0]),
    comment: varchar({ length: 256 }),
    firmwareVersion: varchar({ length: 50 }),
    lastSeenAt: timestamp({ withTimezone: true }),
    isActive: boolean().default(true),
    config: jsonb().default(sql`'{}'::jsonb`),
    groupId: integer().references(() => lighthouseGroups.id, {
      onDelete: "set null",
    }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    cangedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_lighthouses_name").on(table.name),
    index("idx_lighthouses_device_id").on(table.deviceId),
    index("idx_lighthouses_group_id").on(table.groupId),
  ],
);

export const rawScans = pgTable(
  "raw_scans",
  {
    id: bigserial({ mode: "bigint" }).primaryKey(),
    lighthouseId: integer()
      .notNull()
      .references(() => lighthouses.id),
    epc: varchar({ length: 96 }).notNull(),
    epcLength: smallint(),
    rssiDbm: integer(),
    antennaId: smallint(),
    frequency: integer(),
    sequenceNumber: integer(),
    detectionConfidence: real(),
    timestampMs: bigserial({ mode: "bigint" }).notNull(),
    timestamp: timestamp({ withTimezone: true }).notNull(),
    receivedAt: timestamp({ withTimezone: true }).defaultNow(),
    processedAt: timestamp({ withTimezone: true }),
    orphanedAt: timestamp({ withTimezone: true }),
    orphanReason: orphanReasonType(),
    source: scanSource().notNull().default("realtime"),
    timeBasis: timeBasis().notNull().default("synced"),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_raw_scans_epc_timestamp").on(table.epc, table.timestamp),
    index("idx_raw_scans_lighthouse_timestamp").on(
      table.lighthouseId,
      table.timestamp,
    ),
    index("idx_raw_scans_unprocessed")
      .on(table.epc, table.timestamp)
      .where(sql`processed_at IS NULL AND orphaned_at IS NULL`),
    index("idx_raw_scans_orphaned")
      .on(table.orphanedAt)
      .where(sql`orphaned_at IS NOT NULL`),
  ],
);

export const processedEvents = pgTable(
  "processed_events",
  {
    id: uuid().primaryKey().defaultRandom(),
    algorithmId: algorithmType().notNull(),
    direction: directionType().notNull(),
    tagEpc: varchar({ length: 96 }).notNull(),
    userId: uuid(),
    groupId: integer()
      .notNull()
      .references(() => lighthouseGroups.id),
    confidence: real().notNull(),
    centroidSeparationFactor: real().notNull(),
    clusterSizeFactor: real().notNull(),
    bilateralCoverageFactor: real().notNull(),
    rssiTrendConsistencyFactor: real(),
    timestamp: timestamp({ withTimezone: true }).notNull(),
    clusterStartedAt: timestamp({ withTimezone: true }).notNull(),
    clusterEndedAt: timestamp({ withTimezone: true }).notNull(),
    metadata: jsonb(),
    syncedToIntegration: boolean().default(false),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_processed_events_tag_timestamp").on(table.tagEpc, table.timestamp),
    index("idx_processed_events_user_timestamp").on(table.userId, table.timestamp),
    index("idx_processed_events_timestamp").on(table.timestamp),
    index("idx_processed_events_synced").on(table.syncedToIntegration),
    index("idx_processed_events_algorithm").on(table.algorithmId, table.timestamp),
    index("idx_processed_events_group").on(table.groupId, table.timestamp),
  ],
);

export const processedEventScans = pgTable(
  "processed_event_scans",
  {
    processedEventId: uuid()
      .notNull()
      .references(() => processedEvents.id, { onDelete: "cascade" }),
    rawScanId: bigserial({ mode: "bigint" })
      .notNull()
      .references(() => rawScans.id),
  },
  (table) => [
    primaryKey({ columns: [table.processedEventId, table.rawScanId] }),
    index("idx_processed_event_scans_raw_scan").on(table.rawScanId),
  ],
);

export const users = pgTable(
  "users",
  {
    id: uuid().primaryKey().defaultRandom(),
    syncId: varchar({ length: 255 }),
    name: varchar({ length: 255 }),
    email: varchar({ length: 255 }),
    isActive: boolean().default(true),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [index("idx_users_sync_id").on(table.syncId)],
);

export const tagAssignments = pgTable(
  "tag_assignments",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: uuid()
      .references(() => users.id, { onDelete: "set null" }),
    tagEpc: varchar({ length: 96 }).notNull(),
    assignedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    deactivatedAt: timestamp({ withTimezone: true }),
    notes: varchar({ length: 1000 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_tag_assignments_epc").on(table.tagEpc),
    index("idx_tag_assignments_user_id").on(table.userId),
    uniqueIndex("idx_tag_assignments_active")
      .on(table.tagEpc)
      .where(sql`deactivated_at IS NULL`),
  ],
);

export const mqttClients = pgTable(
  "mqtt_clients",
  {
    id: uuid().primaryKey().defaultRandom(),
    lighthouseId: integer().references(() => lighthouses.id),
    clientId: varchar({ length: 255 }).notNull().unique(),
    connectedAt: timestamp({ withTimezone: true }),
    lastActivity: timestamp({ withTimezone: true }),
    isConnected: boolean().default(false),
    ipAddress: varchar({ length: 45 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_mqtt_clients_lighthouse_id").on(table.lighthouseId),
    index("idx_mqtt_clients_client_id").on(table.clientId),
  ],
);

export const auditLogs = pgTable(
  "audit_logs",
  {
    id: bigserial({ mode: "bigint" }).primaryKey(),
    userId: uuid(),
    action: varchar({ length: 100 }).notNull(),
    resourceType: varchar({ length: 100 }),
    resourceId: uuid(),
    changes: jsonb(),
    timestamp: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_audit_logsuser_id").on(table.userId),
    index("idx_audit_logs_resource_type").on(table.resourceType),
    index("idx_audit_logs_timestamp").on(table.timestamp),
  ],
);

export const dashboardUsers = pgTable(
  "dashboard_users",
  {
    id: uuid().primaryKey().defaultRandom(),
    username: varchar({ length: 255 }).notNull().unique(),
    passwordHash: varchar({ length: 255 }).notNull(),
    role: userType().notNull(),
    isActive: boolean().default(true),
    lastLogin: timestamp({ withTimezone: true }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [index("idx_dashboard_users_username").on(table.username)],
);

export const lighthouseHealthSnapshots = pgTable(
  "lighthouse_health_snapshots",
  {
    id: bigserial({ mode: "bigint" }).primaryKey(),
    lighthouseId: integer()
      .notNull()
      .references(() => lighthouses.id),
    uptimeSec: integer(),
    freeHeapBytes: integer(),
    minFreeHeapBytes: integer(),
    wifiRssiDbm: integer(),
    rfidState: varchar({ length: 50 }),
    rfidIsResponsive: boolean(),
    rfidPowerRailPresent: boolean(),
    rfidFwVersion: varchar({ length: 20 }),
    rfidLastError: integer(),
    recordedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_health_snapshots_lighthouse_recorded").on(
      table.lighthouseId,
      table.recordedAt,
    ),
    index("idx_health_snapshots_recorded").on(table.recordedAt),
  ],
);

export const lighthouseConnectionEvents = pgTable(
  "lighthouse_connection_events",
  {
    id: bigserial({ mode: "bigint" }).primaryKey(),
    lighthouseId: integer()
      .notNull()
      .references(() => lighthouses.id),
    eventType: varchar({ length: 20 }).notNull(),
    isGraceful: boolean(),
    recordedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_connection_events_lighthouse_recorded").on(
      table.lighthouseId,
      table.recordedAt,
    ),
    index("idx_connection_events_recorded").on(table.recordedAt),
  ],
);
