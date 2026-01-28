CREATE TABLE "lighthouse_connection_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"lighthouse_id" integer NOT NULL,
	"event_type" varchar(20) NOT NULL,
	"is_graceful" boolean,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL
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
ALTER TABLE "lighthouses" ADD COLUMN "label" varchar(255);--> statement-breakpoint
ALTER TABLE "lighthouse_connection_events" ADD CONSTRAINT "lighthouse_connection_events_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lighthouse_health_snapshots" ADD CONSTRAINT "lighthouse_health_snapshots_lighthouse_id_lighthouses_id_fk" FOREIGN KEY ("lighthouse_id") REFERENCES "public"."lighthouses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_connection_events_lighthouse_recorded" ON "lighthouse_connection_events" USING btree ("lighthouse_id","recorded_at");--> statement-breakpoint
CREATE INDEX "idx_connection_events_recorded" ON "lighthouse_connection_events" USING btree ("recorded_at");--> statement-breakpoint
CREATE INDEX "idx_health_snapshots_lighthouse_recorded" ON "lighthouse_health_snapshots" USING btree ("lighthouse_id","recorded_at");--> statement-breakpoint
CREATE INDEX "idx_health_snapshots_recorded" ON "lighthouse_health_snapshots" USING btree ("recorded_at");