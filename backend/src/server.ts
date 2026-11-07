import { loadConfig } from './config.js';
import { createDb } from './db.js';
import { buildApp } from './app.js';
import fs from 'node:fs/promises';

async function main() {
  const config = loadConfig();
  for (const dir of [config.uploadDir, config.cacheDir]) await fs.mkdir(dir, { recursive: true });
  const db = createDb(config.DATABASE_URL);
  const app = await buildApp(config, db);
  const shutdown = async (signal: string) => {
    app.log.info(`${signal} empfangen – fahre herunter`);
    await app.close();
    await db.$disconnect();
    process.exit(0);
  };
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  await app.listen({ host: config.HOST, port: config.PORT });
  // Abgelaufene Uploads regelmäßig bereinigen
  const cleanup = setInterval(() => {
    void app.jobs.enqueue('UPLOAD_CLEANUP', {}, { dedupeKey: 'upload-cleanup' }).catch(() => undefined);
  }, 6 * 3600_000);
  cleanup.unref();
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
