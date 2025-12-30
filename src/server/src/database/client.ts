import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import { getConfig } from '../config/index.ts';
import * as schema from './schema';

let sql: ReturnType<typeof postgres> | null = null;
let db: ReturnType<typeof drizzle<typeof schema>> | null = null;

/**
 * Initialize the PostgreSQL connection pool
 */
export function initDatabase(): ReturnType<typeof drizzle<typeof schema>> {
  if (db) {
    return db;
  }

  const config = getConfig();

  sql = postgres(config.database.url, {
    max: 20, // Maximum number of connections
    idle_timeout: 20, // Close idle connections after 20 seconds
    connect_timeout: 10, // Connection timeout in seconds
    prepare: false, // Disable prepared statements for better compatibility
  });

  db = drizzle(sql, { schema });

  console.log('[Database] Connection pool initialized');

  return db;
}

/**
 * Get the database instance
 */
export function getDatabase(): ReturnType<typeof drizzle<typeof schema>> {
  if (!db) {
    return initDatabase();
  }
  return db;
}

/**
 * Get the raw postgres client (for advanced queries)
 */
export function getSql(): ReturnType<typeof postgres> {
  if (!sql) {
    initDatabase();
  }
  return sql!;
}

/**
 * Close the database connection pool gracefully
 */
export async function closeDatabase(): Promise<void> {
  if (sql) {
    await sql.end();
    sql = null;
    db = null;
    console.log('[Database] Connection pool closed');
  }
}

/**
 * Test the database connection
 */
export async function testConnection(): Promise<boolean> {
  try {
    const result = await getSql()`SELECT 1 as test`;
    return result.length > 0;
  } catch (error) {
    console.error('[Database] Connection test failed:', error);
    return false;
  }
}

export { schema };
