CREATE TYPE "public"."time_basis" AS ENUM('synced', 'estimated', 'relative');--> statement-breakpoint
ALTER TABLE "raw_scans" ADD COLUMN "time_basis" "time_basis" DEFAULT 'synced' NOT NULL;
