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
} from 'drizzle-orm/pg-core'
import { sql } from 'drizzle-orm'

export const lighthousePlacement = pgEnum('lighthouse_placement', ["STANDALONE", "INSIDE", "OUTSIDE"])

export const userType = pgEnum('user_type', ["STANDALONE", "INSIDE", "OUTSIDE"])

export const scanSource = pgEnum('scan_source', ['realtime', 'offline_sync'])

export const lighthouseGroups = pgTable(
  'lighthouse_groups',
  {
    id: serial().primaryKey(),
    label: varchar({ length: 255 }).notNull(),
    description: varchar({ length: 500 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_lighthouse_groups_label").on(table.label),
  ])
)

export const lighthouses = pgTable(
  'lighthouses',
  {
    id: serial().primaryKey(),
    name: varchar({ length: 255 }).notNull().unique(),
    deviceId: varchar({ length: 255 }).notNull().unique(),
    placement: lighthousePlacement().notNull().default(lighthousePlacement.enumValues[0]),
    comment: varchar({length: 256}),
    firmwareVersion: varchar({ length: 50 }),
    lastSeenAt: timestamp({ withTimezone: true }),
    isActive: boolean().default(true),
    config: jsonb().default(sql`'{}'::jsonb`),
    groupId: integer().references(() => lighthouseGroups.id, { onDelete: 'set null' }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    cangedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_lighthouses_name").on(table.name),
    index("idx_lighthouses_device_id").on(table.deviceId),
    index("idx_lighthouses_group_id").on(table.groupId),
  ])
)

export const rawScans = pgTable(
  'raw_scans',
  {
    id: bigserial({ mode: 'bigint' }).primaryKey(),
    lighthouseId: integer().notNull().references(() => lighthouses.id),
    epc: varchar({ length: 96 }).notNull(),
    epcLength: smallint(),
    rssiDbm: integer(),
    antennaId: smallint(),
    frequency: integer(),
    sequenceNumber: integer(),
    detectionConfidence: real(),
    timestampMs: bigserial({ mode: 'bigint' }).notNull(),
    timestamp: timestamp({ withTimezone: true }).notNull(),
    receivedAt: timestamp({ withTimezone: true }).defaultNow(),
    processed: boolean().default(false),
    source: scanSource().notNull().default('realtime'),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_raw_scans_epc_timestamp").on(table.epc, table.timestamp),
    index("idx_raw_scans_lighthouse_timestamp").on(table.lighthouseId, table.timestamp),
    index("idx_raw_scans_processed").on(table.processed),
  ])
)

export const processedEvents = pgTable(
  'processed_events',
  {
    id: uuid().primaryKey().defaultRandom(),
    eventType: varchar({ length: 50 }).notNull(),
    tagId: varchar({ length: 96 }).notNull(),
    userId: uuid(),
    lighthousePair: varchar({ length: 50 }),
    timestamp: timestamp({ withTimezone: true }).notNull(),
    confidence: real(),
    syncedToIntegration: boolean().default(false),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_processed_events_tag_timestamp").on(table.tagId, table.timestamp),
    index("idx_processed_events_user_timestamp").on(table.userId, table.timestamp),
    index("idx_processed_events_timestamp").on(table.timestamp),
    index("idx_processed_events_synced").on(table.syncedToIntegration),
  ])
)

export const users = pgTable(
  'users',
  {
    id: uuid().primaryKey().defaultRandom(),
    internalId: varchar({ length: 255 }).notNull().unique(),
    remoteId: varchar({ length: 255 }),
    name: varchar({ length: 255 }),
    email: varchar({ length: 255 }),
    isActive: boolean().default(true),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_users_internal_id").on(table.internalId),
    index("idx_users_remote_id").on(table.remoteId),
  ])
)

export const tagAssignments = pgTable(
  'tag_assignments',
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: uuid().notNull().references(() => users.id),
    tagEpc: varchar({ length: 96 }).notNull(),
    assignedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    deactivatedAt: timestamp({ withTimezone: true }),
    notes: varchar({ length: 1000 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_tag_assignments_epc").on(table.tagEpc),
    index("idx_tag_assignments_user_id").on(table.userId),
    uniqueIndex("idx_tag_assignments_active").on(table.tagEpc).where(sql`deactivated_at IS NULL`),
  ])
)

export const mqttClients = pgTable(
  'mqtt_clients',
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
  (table) => ([
    index("idx_mqtt_clients_lighthouse_id").on(table.lighthouseId),
    index("idx_mqtt_clients_client_id").on(table.clientId),
  ])
)

export const auditLogs = pgTable(
  'audit_logs',
  {
    id: bigserial({ mode: 'bigint' }).primaryKey(),
    userId: uuid(),
    action: varchar({ length: 100 }).notNull(),
    resourceType: varchar({ length: 100 }),
    resourceId: uuid(),
    changes: jsonb(),
    timestamp: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_audit_logsuser_id").on(table.userId),
    index("idx_audit_logs_resource_type").on(table.resourceType),
    index("idx_audit_logs_timestamp").on(table.timestamp),
  ])
)

export const dashboardUsers = pgTable(
  'dashboard_users',
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
  (table) => ([
    index("idx_dashboard_users_username").on(table.username),
  ])
)

export const lighthouseHealthSnapshots = pgTable(
  'lighthouse_health_snapshots',
  {
    id: bigserial({ mode: 'bigint' }).primaryKey(),
    lighthouseId: integer().notNull().references(() => lighthouses.id),
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
  (table) => ([
    index("idx_health_snapshots_lighthouse_recorded").on(table.lighthouseId, table.recordedAt),
    index("idx_health_snapshots_recorded").on(table.recordedAt),
  ])
)

export const lighthouseConnectionEvents = pgTable(
  'lighthouse_connection_events',
  {
    id: bigserial({ mode: 'bigint' }).primaryKey(),
    lighthouseId: integer().notNull().references(() => lighthouses.id),
    eventType: varchar({ length: 20 }).notNull(),
    isGraceful: boolean(),
    recordedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ([
    index("idx_connection_events_lighthouse_recorded").on(table.lighthouseId, table.recordedAt),
    index("idx_connection_events_recorded").on(table.recordedAt),
  ])
)
