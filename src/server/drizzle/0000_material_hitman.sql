CREATE TYPE "public"."lighthouse_placement" AS ENUM('STANDALONE', 'INSIDE', 'OUTSIDE');

--> statement-breakpoint
CREATE TYPE "public"."user_type" AS ENUM('STANDALONE', 'INSIDE', 'OUTSIDE');

--> statement-breakpoint
CREATE TABLE "audit_logs" (
    "id" bigserial PRIMARY KEY NOT NULL,
    "user_id" uuid,
    "action" varchar(100) NOT NULL,
    "resource_type" varchar(100),
    "resource_id" uuid,
    "changes" jsonb,
    "timestamp" timestamp WITH time zone DEFAULT NOW() NOT NULL
);

--> statement-breakpoint
CREATE TABLE "dashboard_users" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "username" varchar(255) NOT NULL,
    "password_hash" varchar(255) NOT NULL,
    "role" "user_type" NOT NULL,
    "is_active" boolean DEFAULT TRUE,
    "last_login" timestamp WITH time zone,
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    "updated_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    CONSTRAINT "dashboard_users_username_unique" UNIQUE("username")
);

--> statement-breakpoint
CREATE TABLE "lighthouses" (
    "id" serial PRIMARY KEY NOT NULL,
    "name" varchar(255) NOT NULL,
    "device_id" varchar(255) NOT NULL,
    "placement" "lighthouse_placement" DEFAULT 'STANDALONE' NOT NULL,
    "comment" varchar(256),
    "firmware_version" varchar(50),
    "last_seen_at" timestamp WITH time zone,
    "is_active" boolean DEFAULT TRUE,
    "config" jsonb DEFAULT '{}'::jsonb,
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    "canged_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    CONSTRAINT "lighthouses_name_unique" UNIQUE("name"),
    CONSTRAINT "lighthouses_deviceId_unique" UNIQUE("device_id")
);

--> statement-breakpoint
CREATE TABLE "mqtt_clients" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "lighthouse_id" integer,
    "client_id" varchar(255) NOT NULL,
    "connected_at" timestamp WITH time zone,
    "last_activity" timestamp WITH time zone,
    "is_connected" boolean DEFAULT false,
    "ip_address" varchar(45),
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    CONSTRAINT "mqtt_clients_clientId_unique" UNIQUE("client_id")
);

--> statement-breakpoint
CREATE TABLE "processed_events" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "event_type" varchar(50) NOT NULL,
    "tag_id" varchar(96) NOT NULL,
    "user_id" uuid,
    "lighthouse_pair" varchar(50),
    "timestamp" timestamp WITH time zone NOT NULL,
    "confidence" real,
    "synced_to_integration" boolean DEFAULT false,
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL
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
    "timestamp" timestamp WITH time zone NOT NULL,
    "received_at" timestamp WITH time zone DEFAULT NOW(),
    "processed" boolean DEFAULT false,
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL
);

--> statement-breakpoint
CREATE TABLE "tag_assignments" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "user_id" uuid NOT NULL,
    "tag_epc" varchar(96) NOT NULL,
    "assigned_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    "deactivated_at" timestamp WITH time zone,
    "notes" varchar(1000),
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL
);

--> statement-breakpoint
CREATE TABLE "users" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "internal_id" varchar(255) NOT NULL,
    "remote_id" varchar(255),
    "name" varchar(255),
    "email" varchar(255),
    "is_active" boolean DEFAULT TRUE,
    "created_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    "updated_at" timestamp WITH time zone DEFAULT NOW() NOT NULL,
    CONSTRAINT "users_internalId_unique" UNIQUE("internal_id")
);

--> statement-breakpoint
ALTER TABLE
    "mqtt_clients"
ADD
    CONSTRAINT "mqtt_clients_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no ACTION ON UPDATE no ACTION;

--> statement-breakpoint
ALTER TABLE
    "raw_scans"
ADD
    CONSTRAINT "raw_scans_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no ACTION ON UPDATE no ACTION;

--> statement-breakpoint
ALTER TABLE
    "tag_assignments"
ADD
    CONSTRAINT "tag_assignments_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no ACTION ON UPDATE no ACTION;

--> statement-breakpoint
CREATE INDEX "idx_audit_logsuser_id" ON "audit_logs" USING btree ("user_id");

--> statement-breakpoint
CREATE INDEX "idx_audit_logs_resource_type" ON "audit_logs" USING btree ("resource_type");

--> statement-breakpoint
CREATE INDEX "idx_audit_logs_timestamp" ON "audit_logs" USING btree ("timestamp");

--> statement-breakpoint
CREATE INDEX "idx_dashboard_users_username" ON "dashboard_users" USING btree ("username");

--> statement-breakpoint
CREATE INDEX "idx_lighthouses_name" ON "lighthouses" USING btree ("name");

--> statement-breakpoint
CREATE INDEX "idx_lighthouses_device_id" ON "lighthouses" USING btree ("device_id");

--> statement-breakpoint
CREATE INDEX "idx_mqtt_clients_lighthouse_id" ON "mqtt_clients" USING btree ("lighthouse_id");

--> statement-breakpoint
CREATE INDEX "idx_mqtt_clients_client_id" ON "mqtt_clients" USING btree ("client_id");

--> statement-breakpoint
CREATE INDEX "idx_processed_events_tag_timestamp" ON "processed_events" USING btree ("tag_id", "timestamp");

--> statement-breakpoint
CREATE INDEX "idx_processed_events_user_timestamp" ON "processed_events" USING btree ("user_id", "timestamp");

--> statement-breakpoint
CREATE INDEX "idx_processed_events_timestamp" ON "processed_events" USING btree ("timestamp");

--> statement-breakpoint
CREATE INDEX "idx_processed_events_synced" ON "processed_events" USING btree ("synced_to_integration");

--> statement-breakpoint
CREATE INDEX "idx_raw_scans_epc_timestamp" ON "raw_scans" USING btree ("epc", "timestamp");

--> statement-breakpoint
CREATE INDEX "idx_raw_scans_lighthouse_timestamp" ON "raw_scans" USING btree ("lighthouse_id", "timestamp");

--> statement-breakpoint
CREATE INDEX "idx_raw_scans_processed" ON "raw_scans" USING btree ("processed");

--> statement-breakpoint
CREATE INDEX "idx_tag_assignments_epc" ON "tag_assignments" USING btree ("tag_epc");

--> statement-breakpoint
CREATE INDEX "idx_tag_assignments_user_id" ON "tag_assignments" USING btree ("user_id");

--> statement-breakpoint
CREATE UNIQUE INDEX "idx_tag_assignments_active" ON "tag_assignments" USING btree ("tag_epc")
WHERE
    deactivated_at IS NULL;

--> statement-breakpoint
CREATE INDEX "idx_users_internal_id" ON "users" USING btree ("internal_id");

--> statement-breakpoint
CREATE INDEX "idx_users_remote_id" ON "users" USING btree ("remote_id");

