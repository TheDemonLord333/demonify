import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import type { FastifyInstance } from 'fastify';
import { loadConfig, type AppConfig } from '../src/config.js';
import { createDb, type Db } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { createUser } from '../src/services/auth.js';

export interface TestEnv {
  app: FastifyInstance;
  db: Db;
  config: AppConfig;
  root: string;
  close: () => Promise<void>;
}

const TEST_DB = process.env.TEST_DATABASE_URL ?? 'postgresql://demonify:devpass@127.0.0.1:5432/demonify_test';

export async function createTestEnv(overrides: Record<string, string> = {}): Promise<TestEnv> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'demonify-test-'));
  const config = loadConfig({
    NODE_ENV: 'test',
    DATABASE_URL: TEST_DB,
    MUSIC_DIR: path.join(root, 'music'),
    DATA_DIR: path.join(root, 'data'),
    AUTH_TOKEN_SECRET: 'test-auth-secret-0123456789abcdefghijklmnop',
    STREAM_URL_SECRET: 'test-stream-secret-0123456789abcdefghijklmn',
    LOG_LEVEL: 'silent',
    COOKIE_SECURE: 'false',
    WORKER_ENABLED: 'false',
    UPLOAD_CHUNK_MB: '1',
    ...overrides,
  });
  await fs.mkdir(config.MUSIC_DIR, { recursive: true });
  await fs.mkdir(config.uploadDir, { recursive: true });
  await fs.mkdir(config.cacheDir, { recursive: true });
  const db = createDb(TEST_DB);
  await resetDb(db);
  const app = await buildApp(config, db, { logger: false, startWorker: false });
  await app.ready();
  return {
    app,
    db,
    config,
    root,
    close: async () => {
      await app.close();
      await db.$disconnect();
      await fs.rm(root, { recursive: true, force: true });
    },
  };
}

export async function resetDb(db: Db) {
  const tables = await db.$queryRaw<Array<{ tablename: string }>>`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'`;
  if (tables.length) {
    await db.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} CASCADE`);
  }
}

export async function makeUser(env: TestEnv, username: string, role: 'ADMIN' | 'USER' = 'USER', password = 'TestPasswort123') {
  await createUser(env.db, { username, password, role });
  const res = await env.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { username, password } });
  if (res.statusCode !== 200) throw new Error(`Login fehlgeschlagen: ${res.body}`);
  const body = res.json() as { accessToken: string; refreshToken: string; user: { id: string } };
  return { token: body.accessToken, refreshToken: body.refreshToken, id: body.user.id, auth: { authorization: `Bearer ${body.accessToken}` } };
}

/** Erzeugt eine echte Audiodatei mit Tags über ffmpeg */
export function makeAudio(
  file: string,
  opts: { freq?: number; seconds?: number; tags?: Record<string, string>; format?: 'flac' | 'mp3' | 'ogg' | 'wav' | 'm4a'; coverPng?: string } = {},
) {
  const args = ['-nostdin', '-v', 'error', '-y', '-f', 'lavfi', '-i', `sine=frequency=${opts.freq ?? 440}:duration=${opts.seconds ?? 2}`];
  if (opts.coverPng) args.push('-i', opts.coverPng, '-map', '0:a', '-map', '1:v', '-c:v', 'png', '-disposition:v', 'attached_pic');
  for (const [k, v] of Object.entries(opts.tags ?? {})) args.push('-metadata', `${k}=${v}`);
  if (opts.format === 'm4a') args.push('-c:a', 'aac');
  args.push(file);
  execFileSync('ffmpeg', args);
}

export function makePng(file: string, color = 'purple', size = 64) {
  execFileSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', '-f', 'lavfi', '-i', `color=c=${color}:s=${size}x${size}:d=1`, '-frames:v', '1', file]);
}

/** Datei per Abschnitts-Upload hochladen und prüfen lassen */
export async function uploadFileChunked(env: TestEnv, auth: Record<string, string>, file: string, kind: 'AUDIO' | 'IMAGE', name?: string) {
  const data = await fs.readFile(file);
  const create = await env.app.inject({
    method: 'POST',
    url: '/api/v1/admin/uploads',
    headers: auth,
    payload: { kind, filename: name ?? path.basename(file), size: data.length },
  });
  if (create.statusCode !== 201) throw new Error(create.body);
  const { upload, chunkSize } = create.json() as { upload: { id: string }; chunkSize: number };
  for (let off = 0; off < data.length; off += chunkSize) {
    const res = await env.app.inject({
      method: 'PUT',
      url: `/api/v1/admin/uploads/${upload.id}/content`,
      headers: { ...auth, 'content-type': 'application/octet-stream', 'upload-offset': String(off) },
      payload: data.subarray(off, Math.min(off + chunkSize, data.length)),
    });
    if (res.statusCode !== 200) throw new Error(res.body);
  }
  const done = await env.app.inject({ method: 'POST', url: `/api/v1/admin/uploads/${upload.id}/complete`, headers: auth });
  return done.json() as { upload: { id: string; status: string; error: string | null; probe: Record<string, unknown> } };
}

export async function exists(p: string) {
  return fs.access(p).then(
    () => true,
    () => false,
  );
}
