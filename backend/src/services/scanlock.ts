import pg from 'pg';
import { ApiError } from '../lib/errors.js';

/** Gemeinsamer Advisory-Lock für Bibliotheksscan und Katalog-Löschvorgänge („Demo“) */
export const SCAN_LOCK_KEY = 0x44656d6f;

/**
 * Führt fn exklusiv zum Bibliotheksscan aus. Der Session-Lock liegt auf einer eigenen Verbindung,
 * weil der Prisma-Pool Verbindungen wechseln kann.
 */
export async function withLibraryLock<T>(databaseUrl: string, busyMessage: string, fn: () => Promise<T>): Promise<T> {
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    const lock = await client.query<{ ok: boolean }>('SELECT pg_try_advisory_lock($1) AS ok', [SCAN_LOCK_KEY]);
    if (!lock.rows[0]?.ok) throw new ApiError(409, 'LIBRARY_BUSY', busyMessage);
    try {
      return await fn();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [SCAN_LOCK_KEY]).catch(() => undefined);
    }
  } finally {
    await client.end().catch(() => undefined);
  }
}
