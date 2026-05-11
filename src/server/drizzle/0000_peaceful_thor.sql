CREATE TYPE "public"."algorithm_type" AS ENUM('temporal_centroid', 'rssi_weighted_centroid', 'manual');--> statement-breakpoint
CREATE TYPE "public"."direction_type" AS ENUM('in', 'out', 'unknown');--> statement-breakpoint
CREATE TYPE "public"."lighthouse_placement" AS ENUM('STANDALONE', 'INSIDE', 'OUTSIDE');--> statement-breakpoint
CREATE TYPE "public"."orphan_reason_type" AS ENUM('insufficient_data', 'misconfigured_group', 'unsyncable');--> statement-breakpoint
CREATE TYPE "public"."scan_source" AS ENUM('realtime', 'offline_sync');--> statement-breakpoint
CREATE TYPE "public"."time_basis" AS ENUM('synced', 'estimated', 'relative');--> statement-breakpoint
CREATE TYPE "public"."user_type" AS ENUM('STANDALONE', 'INSIDE', 'OUTSIDE');--> statement-breakpoint
CREATE TABLE "audit_logs" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" uuid,
	"action" varchar(100) NOT NULL,
	"resource_type" varchar(100),
	"resource_id" uuid,
	"changes" jsonb,
	"timestamp" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "dashboard_users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"username" varchar(255) NOT NULL,
	"password_hash" varchar(255) NOT NULL,
	"role" "user_type" NOT NULL,
	"is_active" boolean DEFAULT true,
	"last_login" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "dashboard_users_username_unique" UNIQUE("username")
);
--> statement-breakpoint
CREATE TABLE "lighthouse_connection_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"lighthouse_id" integer NOT NULL,
	"event_type" varchar(20) NOT NULL,
	"is_graceful" boolean,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "lighthouse_groups" (
	"id" serial PRIMARY KEY NOT NULL,
	"label" varchar(255) NOT NULL,
	"description" varchar(500),
	"activity_timeout_ms" integer DEFAULT 4000 NOT NULL,
	"orphan_timeout_ms" integer DEFAULT 8000 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "lighthouse_health_snapshots" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"lighthouse_id" integer NOT NULL,
	"uptime_sec" integer,
	"free_heap_bytes" integer,
	"min_free_heap_bytes" integer,
	"wifi_rssi_dbm" integer,
	"rfid_state" varchar(50),
	"rfid_is_responsive" boolean,
	"rfid_power_rail_present" boolean,
	"rfid_fw_version" varchar(20),
	"rfid_last_error" integer,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "lighthouses" (
	"id" serial PRIMARY KEY NOT NULL,
	"name" varchar(255) NOT NULL,
	"device_id" varchar(255) NOT NULL,
	"placement" "lighthouse_placement" DEFAULT 'STANDALONE' NOT NULL,
	"comment" varchar(256),
	"firmware_version" varchar(50),
	"last_seen_at" timestamp with time zone,
	"is_active" boolean DEFAULT true,
	"config" jsonb DEFAULT '{}'::jsonb,
	"group_id" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"canged_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "lighthouses_name_unique" UNIQUE("name"),
	CONSTRAINT "lighthouses_deviceId_unique" UNIQUE("device_id")
);
--> statement-breakpoint
CREATE TABLE "mqtt_clients" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"lighthouse_id" integer,
	"client_id" varchar(255) NOT NULL,
	"connected_at" timestamp with time zone,
	"last_activity" timestamp with time zone,
	"is_connected" boolean DEFAULT false,
	"ip_address" varchar(45),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "mqtt_clients_clientId_unique" UNIQUE("client_id")
);
--> statement-breakpoint
CREATE TABLE "processed_event_scans" (
	"processed_event_id" uuid NOT NULL,
	"raw_scan_id" bigserial NOT NULL,
	CONSTRAINT "processed_event_scans_processed_event_id_raw_scan_id_pk" PRIMARY KEY("processed_event_id","raw_scan_id")
);
--> statement-breakpoint
CREATE TABLE "processed_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"algorithm_id" "algorithm_type" NOT NULL,
	"direction" "direction_type" NOT NULL,
	"tag_epc" varchar(96) NOT NULL,
	"user_id" uuid,
	"group_id" integer NOT NULL,
	"confidence" real NOT NULL,
	"centroid_separation_factor" real NOT NULL,
	"cluster_size_factor" real NOT NULL,
	"bilateral_coverage_factor" real NOT NULL,
	"rssi_trend_consistency_factor" real,
	"timestamp" timestamp with time zone NOT NULL,
	"cluster_started_at" timestamp with time zone NOT NULL,
	"cluster_ended_at" timestamp with time zone NOT NULL,
	"metadata" jsonb,
	"synced_to_integration" boolean DEFAULT false,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"navigo3_record_id" integer
);
--> statement-breakpoint
CREATE TABLE "raw_scans" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"lighthouse_id" integer NOT NULL,
	"epc" varchar(96) NOT NULL,
	"epc_length" smallint,
	"rssi_dbm" integer,
	"antenna_id" smallint,
	"frequency" integer,
	"sequence_number" integer,
	"detection_confidence" real,
	"timestamp_ms" bigserial NOT NULL,
	"timestamp" timestamp with time zone NOT NULL,
	"received_at" timestamp with time zone DEFAULT now(),
	"processed_at" timestamp with time zone,
	"orphaned_at" timestamp with time zone,
	"orphan_reason" "orphan_reason_type",
	"source" "scan_source" DEFAULT 'realtime' NOT NULL,
	"time_basis" time_basis DEFAULT 'synced' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tag_assignments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid,
	"tag_epc" varchar(96) NOT NULL,
	"assigned_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deactivated_at" timestamp with time zone,
	"notes" varchar(1000),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sync_id" varchar(255),
	"name" varchar(255),
	"email" varchar(255),
	"is_active" boolean DEFAULT true,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "lighthouse_connection_events" ADD CONSTRAINT "lighthouse_connection_events_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lighthouse_health_snapshots" ADD CONSTRAINT "lighthouse_health_snapshots_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lighthouses" ADD CONSTRAINT "lighthouses_group_id_lighthouse_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."lighthouse_groups"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mqtt_clients" ADD CONSTRAINT "mqtt_clients_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "processed_event_scans" ADD CONSTRAINT "processed_event_scans_processed_event_id_processed_events_id_fk" FOREIGN KEY ("processed_event_id") REFERENCES "public"."processed_events"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "processed_event_scans" ADD CONSTRAINT "processed_event_scans_raw_scan_id_raw_scans_id_fk" FOREIGN KEY ("raw_scan_id") REFERENCES "public"."raw_scans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "processed_events" ADD CONSTRAINT "processed_events_group_id_lighthouse_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."lighthouse_groups"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "raw_scans" ADD CONSTRAINT "raw_scans_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tag_assignments" ADD CONSTRAINT "tag_assignments_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_audit_logsuser_id" ON "audit_logs" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_audit_logs_resource_type" ON "audit_logs" USING btree ("resource_type");--> statement-breakpoint
CREATE INDEX "idx_audit_logs_timestamp" ON "audit_logs" USING btree ("timestamp");--> statement-breakpoint
CREATE INDEX "idx_dashboard_users_username" ON "dashboard_users" USING btree ("username");--> statement-breakpoint
CREATE INDEX "idx_connection_events_lighthouse_recorded" ON "lighthouse_connection_events" USING btree ("lighthouse_id","recorded_at");--> statement-breakpoint
CREATE INDEX "idx_connection_events_recorded" ON "lighthouse_connection_events" USING btree ("recorded_at");--> statement-breakpoint
CREATE INDEX "idx_lighthouse_groups_label" ON "lighthouse_groups" USING btree ("label");--> statement-breakpoint
CREATE INDEX "idx_health_snapshots_lighthouse_recorded" ON "lighthouse_health_snapshots" USING btree ("lighthouse_id","recorded_at");--> statement-breakpoint
CREATE INDEX "idx_health_snapshots_recorded" ON "lighthouse_health_snapshots" USING btree ("recorded_at");--> statement-breakpoint
CREATE INDEX "idx_lighthouses_name" ON "lighthouses" USING btree ("name");--> statement-breakpoint
CREATE INDEX "idx_lighthouses_device_id" ON "lighthouses" USING btree ("device_id");--> statement-breakpoint
CREATE INDEX "idx_lighthouses_group_id" ON "lighthouses" USING btree ("group_id");--> statement-breakpoint
CREATE INDEX "idx_mqtt_clients_lighthouse_id" ON "mqtt_clients" USING btree ("lighthouse_id");--> statement-breakpoint
CREATE INDEX "idx_mqtt_clients_client_id" ON "mqtt_clients" USING btree ("client_id");--> statement-breakpoint
CREATE INDEX "idx_processed_event_scans_raw_scan" ON "processed_event_scans" USING btree ("raw_scan_id");--> statement-breakpoint
CREATE INDEX "idx_processed_events_tag_timestamp" ON "processed_events" USING btree ("tag_epc","timestamp");--> statement-breakpoint
CREATE INDEX "idx_processed_events_user_timestamp" ON "processed_events" USING btree ("user_id","timestamp");--> statement-breakpoint
CREATE INDEX "idx_processed_events_timestamp" ON "processed_events" USING btree ("timestamp");--> statement-breakpoint
CREATE INDEX "idx_processed_events_synced" ON "processed_events" USING btree ("synced_to_integration");--> statement-breakpoint
CREATE INDEX "idx_processed_events_algorithm" ON "processed_events" USING btree ("algorithm_id","timestamp");--> statement-breakpoint
CREATE INDEX "idx_processed_events_group" ON "processed_events" USING btree ("group_id","timestamp");--> statement-breakpoint
CREATE INDEX "idx_raw_scans_epc_timestamp" ON "raw_scans" USING btree ("epc","timestamp");--> statement-breakpoint
CREATE INDEX "idx_raw_scans_lighthouse_timestamp" ON "raw_scans" USING btree ("lighthouse_id","timestamp");--> statement-breakpoint
CREATE INDEX "idx_raw_scans_unprocessed" ON "raw_scans" USING btree ("epc","timestamp") WHERE processed_at IS NULL AND orphaned_at IS NULL;--> statement-breakpoint
CREATE INDEX "idx_raw_scans_orphaned" ON "raw_scans" USING btree ("orphaned_at") WHERE orphaned_at IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "raw_scans_offline_dedup" ON "raw_scans" USING btree ("lighthouse_id","epc","timestamp_ms") WHERE source = 'offline_sync';--> statement-breakpoint
CREATE INDEX "idx_tag_assignments_epc" ON "tag_assignments" USING btree ("tag_epc");--> statement-breakpoint
CREATE INDEX "idx_tag_assignments_user_id" ON "tag_assignments" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_tag_assignments_active" ON "tag_assignments" USING btree ("tag_epc") WHERE deactivated_at IS NULL;--> statement-breakpoint
CREATE INDEX "idx_users_sync_id" ON "users" USING btree ("sync_id");