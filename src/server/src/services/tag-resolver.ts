import { getDatabase, schema } from "../database/client";
import { and, eq, isNull } from "drizzle-orm";

/**
 * Resolve an EPC to a userId via active tag assignments.
 * Returns the userId if the tag is actively assigned, null otherwise.
 */
export async function resolveTagUser(epc: string): Promise<string | null> {
  const db = getDatabase();

  const assignments = await db
    .select({ userId: schema.tagAssignments.userId })
    .from(schema.tagAssignments)
    .where(
      and(
        eq(schema.tagAssignments.tagEpc, epc),
        isNull(schema.tagAssignments.deactivatedAt),
      ),
    )
    .limit(1);

  return assignments[0]?.userId ?? null;
}
