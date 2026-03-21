import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import {
  initDatabase,
  closeDatabase,
  getDatabase,
  schema,
} from "../src/database/client";
import { resolveTagUser } from "../src/services/tag-resolver";
import { eq, or } from "drizzle-orm";

// --- Test data ----------------------------------------------------------------

const TEST_USER_ID = "00000000-0000-0000-0001-000000000001";
const TEST_EPC_ACTIVE = "ETEST_ACTIVE_0000001";
const TEST_EPC_DEACTIVATED = "ETEST_DEACTIVATED001";
const TEST_EPC_UNASSIGNED = "ETEST_UNASSIGNED0001";

// --- Suite lifecycle ----------------------------------------------------------

describe("Tag Resolver", () => {
  beforeAll(async () => {
    initDatabase();
    const db = getDatabase();

    // Insert test user
    await db
      .insert(schema.users)
      .values({
        id: TEST_USER_ID,
        name: "Tag Resolver Test User",
        isActive: true,
      })
      .onConflictDoNothing();

    // Insert an active tag assignment
    await db
      .insert(schema.tagAssignments)
      .values({
        userId: TEST_USER_ID,
        tagEpc: TEST_EPC_ACTIVE,
        assignedAt: new Date(),
        deactivatedAt: null,
      })
      .onConflictDoNothing();

    // Insert a deactivated tag assignment
    await db
      .insert(schema.tagAssignments)
      .values({
        userId: TEST_USER_ID,
        tagEpc: TEST_EPC_DEACTIVATED,
        assignedAt: new Date(Date.now() - 86400_000), // 1 day ago
        deactivatedAt: new Date(),
      })
      .onConflictDoNothing();
  });

  afterAll(async () => {
    const db = getDatabase();

    // Clean up tag assignments
    await db
      .delete(schema.tagAssignments)
      .where(
        or(
          eq(schema.tagAssignments.tagEpc, TEST_EPC_ACTIVE),
          eq(schema.tagAssignments.tagEpc, TEST_EPC_DEACTIVATED),
        ),
      );

    // Clean up user
    await db.delete(schema.users).where(eq(schema.users.id, TEST_USER_ID));

    await closeDatabase();
  });

  // --- Test 1: Returns userId for an EPC with an active assignment ------------

  it("should return userId for an EPC with an active assignment", async () => {
    const result = await resolveTagUser(TEST_EPC_ACTIVE);
    expect(result).toBe(TEST_USER_ID);
  });

  // --- Test 2: Returns null for an EPC with no assignment at all -------------

  it("should return null for an EPC with no assignment", async () => {
    const result = await resolveTagUser(TEST_EPC_UNASSIGNED);
    expect(result).toBeNull();
  });

  // --- Test 3: Returns null for an EPC whose assignment has been deactivated --

  it("should return null for an EPC whose assignment has been deactivated", async () => {
    const result = await resolveTagUser(TEST_EPC_DEACTIVATED);
    expect(result).toBeNull();
  });
});
