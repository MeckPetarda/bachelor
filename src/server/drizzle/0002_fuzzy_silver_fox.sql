CREATE TYPE "public"."scan_source" AS ENUM('realtime', 'offline_sync');--> statement-breakpoint
CREATE TABLE "lighthouse_groups" (
	"id" serial PRIMARY KEY NOT NULL,
	"label" varchar(255) NOT NULL,
	"description" varchar(500),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "lighthouses" ADD COLUMN "group_id" integer;--> statement-breakpoint
ALTER TABLE "raw_scans" ADD COLUMN "source" "scan_source" DEFAULT 'realtime' NOT NULL;--> statement-breakpoint
CREATE INDEX "idx_lighthouse_groups_label" ON "lighthouse_groups" USING btree ("label");--> statement-breakpoint
ALTER TABLE "lighthouses" ADD CONSTRAINT "lighthouses_group_id_lighthouse_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."lighthouse_groups"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_lighthouses_group_id" ON "lighthouses" USING btree ("group_id");--> statement-breakpoint
ALTER TABLE "lighthouses" DROP COLUMN "label";
