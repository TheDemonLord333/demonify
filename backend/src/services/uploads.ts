import fs from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Transform, type Readable } from 'node:stream';
import sharp from 'sharp';
import type { AppConfig } from '../config.js';
import type { Db, Prisma } from '../db.js';
import { badRequest, conflict, notFound, ApiError } from '../lib/errors.js';
import { probeAudio, probeImage, readTags } from '../lib/media.js';
import { resolveInside, AUDIO_EXTENSIONS, IMAGE_EXTENSIONS } from '../lib/fsnames.js';

/**
 * Wiederaufnehmbare Uploads in Abschnitten:
 *   POST   /admin/uploads                 → Upload anlegen (Name, Größe, Art)
 *   PUT    /admin/uploads/:id/content     → Abschnitt ab Header "Upload-Offset" anhängen
 *   GET    /admin/uploads/:id             → aktueller Stand (receivedSize) zum Fortsetzen
 *   POST   /admin/uploads/:id/complete    → tatsächliche Prüfung (ffprobe/libvips)
 *   DELETE /admin/uploads/:id             → abbrechen und Dateien entfernen
 * Unfertige Uploads liegen ausschließlich in UPLOAD_DIR, getrennt von der Bibliothek.
 */
const locks = new Map<string, Promise<void>>();

async function withLock<T>(id: string, fn: () => Promise<T>): Promise<T> {
  const prev = locks.get(id) ?? Promise.resolve();
  let release!: () => void;
  const next = new Promise<void>((r) => (release = r));
  locks.set(id, prev.then(() => next));
  await prev;
  try {
    return await fn();
  } finally {
    release();
    if (locks.get(id) === next) locks.delete(id);
  }
}

export function uploadFile(config: AppConfig, id: string): string {
  return resolveInside(config.uploadDir, `${id}/data`);
}

export async function createUpload(
  db: Db,
  config: AppConfig,
  userId: string,
  input: { kind: 'AUDIO' | 'IMAGE'; filename: string; size: number },
) {
  const ext = path.extname(input.filename).toLowerCase();
  const allowed = input.kind === 'AUDIO' ? AUDIO_EXTENSIONS : IMAGE_EXTENSIONS;
  if (!allowed.has(ext)) {
    throw badRequest(
      input.kind === 'AUDIO'
        ? 'Nicht unterstütztes Audioformat. Erlaubt: MP3, FLAC, M4A/AAC, Ogg/Opus, WAV.'
        : 'Nicht unterstütztes Bildformat. Erlaubt: JPEG, PNG, WebP.',
    );
  }
  const maxMb = input.kind === 'AUDIO' ? config.MAX_AUDIO_UPLOAD_MB : config.MAX_IMAGE_UPLOAD_MB;
  if (input.size <= 0) throw badRequest('Die Datei ist leer.');
  if (input.size > maxMb * 1024 * 1024) throw badRequest(`Die Datei ist zu groß (max. ${maxMb} MB).`);
  const upload = await db.upload.create({
    data: {
      userId,
      kind: input.kind,
      originalName: path.basename(input.filename).slice(0, 255),
      declaredSize: BigInt(input.size),
      expiresAt: new Date(Date.now() + config.UPLOAD_EXPIRY_HOURS * 3600_000),
    },
  });
  const file = uploadFile(config, upload.id);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, '', { flag: 'wx' });
  return upload;
}

export async function appendChunk(db: Db, config: AppConfig, id: string, offset: number, body: Readable, maxChunkBytes: number) {
  return withLock(id, async () => {
    const upload = await db.upload.findUnique({ where: { id } });
    if (!upload) throw notFound('Upload nicht gefunden.');
    if (upload.status !== 'RECEIVING') throw conflict('Der Upload nimmt keine Daten mehr an.');
    const received = Number(upload.receivedSize);
    if (offset !== received) {
      throw new ApiError(409, 'OFFSET_MISMATCH', 'Der Upload-Offset passt nicht zum Serverstand.', { receivedSize: received });
    }
    const declared = Number(upload.declaredSize);
    const file = uploadFile(config, id);
    // Auf den bestätigten Stand kürzen (verwirft Reste eines abgebrochenen Abschnitts)
    await fs.truncate(file, received);
    let written = 0;
    let overflow: ApiError | null = null;
    // Bei Überschreitung nichts mehr schreiben, aber den Rest des Bodys verwerfen (lesen),
    // damit der Client eine saubere Fehlerantwort statt eines Verbindungsabbruchs erhält.
    const limiter = new Transform({
      transform(chunk: Buffer, _enc, cb) {
        if (overflow) return cb();
        if (written + chunk.length > maxChunkBytes) overflow = new ApiError(413, 'CHUNK_TOO_LARGE', 'Abschnitt zu groß.');
        else if (received + written + chunk.length > declared) overflow = new ApiError(400, 'SIZE_EXCEEDED', 'Mehr Daten als angekündigt.');
        if (overflow) return cb();
        written += chunk.length;
        cb(null, chunk);
      },
    });
    try {
      await pipeline(body, limiter, createWriteStream(file, { flags: 'r+', start: received }));
    } catch (e) {
      await fs.truncate(file, received).catch(() => undefined);
      throw e;
    }
    if (overflow) {
      await fs.truncate(file, received).catch(() => undefined);
      throw overflow;
    }
    const updated = await db.upload.update({ where: { id }, data: { receivedSize: BigInt(received + written) } });
    return updated;
  });
}

export function toUploadDto(u: {
  id: string;
  kind: string;
  originalName: string;
  declaredSize: bigint;
  receivedSize: bigint;
  status: string;
  probe: unknown;
  error: string | null;
  expiresAt: Date;
}) {
  return {
    id: u.id,
    kind: u.kind,
    originalName: u.originalName,
    declaredSize: Number(u.declaredSize),
    receivedSize: Number(u.receivedSize),
    status: u.status,
    probe: u.probe,
    error: u.error,
    expiresAt: u.expiresAt.toISOString(),
  };
}

export async function completeUpload(db: Db, config: AppConfig, id: string) {
  return withLock(id, async () => {
    const upload = await db.upload.findUnique({ where: { id } });
    if (!upload) throw notFound('Upload nicht gefunden.');
    if (upload.status === 'VALIDATED' || upload.status === 'INVALID') return upload;
    if (upload.status !== 'RECEIVING') throw conflict('Upload ist nicht mehr aktiv.');
    if (upload.receivedSize !== upload.declaredSize) {
      throw new ApiError(409, 'INCOMPLETE_UPLOAD', 'Der Upload ist noch nicht vollständig.', {
        receivedSize: Number(upload.receivedSize),
        declaredSize: Number(upload.declaredSize),
      });
    }
    const file = uploadFile(config, id);
    try {
      let probe: Prisma.InputJsonValue;
      if (upload.kind === 'AUDIO') {
        const tech = await probeAudio(config.FFPROBE_PATH, file);
        const { tags, picture } = await readTags(file);
        probe = { ...tech, tags: tags as Prisma.InputJsonValue, hasEmbeddedPicture: !!picture } as Prisma.InputJsonValue;
      } else {
        const info = await probeImage(file);
        // Vollständige Dekodierung → beschädigte/manipulierte Bilder werden erkannt
        await sharp(file, { limitInputPixels: 100_000_000, failOn: 'error' }).stats();
        probe = info as unknown as Prisma.InputJsonValue;
      }
      return await db.upload.update({ where: { id }, data: { status: 'VALIDATED', probe, error: null } });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return db.upload.update({
        where: { id },
        data: { status: 'INVALID', error: `Datei ungültig: ${msg.slice(0, 500)}` },
      });
    }
  });
}

export async function abortUpload(db: Db, config: AppConfig, id: string) {
  return withLock(id, async () => {
    const upload = await db.upload.findUnique({ where: { id } });
    if (!upload) throw notFound('Upload nicht gefunden.');
    if (upload.status === 'CONSUMED') throw conflict('Upload wurde bereits übernommen.');
    await fs.rm(path.dirname(uploadFile(config, id)), { recursive: true, force: true });
    return db.upload.update({ where: { id }, data: { status: 'ABORTED' } });
  });
}

/** Abgelaufene, nicht übernommene Uploads sowie verwaiste Ordner entfernen. */
export async function cleanupUploads(db: Db, config: AppConfig) {
  const expired = await db.upload.findMany({
    where: { status: { in: ['RECEIVING', 'VALIDATED', 'INVALID'] }, expiresAt: { lt: new Date() } },
  });
  for (const u of expired) {
    await fs.rm(path.dirname(uploadFile(config, u.id)), { recursive: true, force: true });
    await db.upload.update({ where: { id: u.id }, data: { status: 'ABORTED' } });
  }
  let orphans = 0;
  try {
    const dirs = await fs.readdir(config.uploadDir);
    const known = new Set(
      (await db.upload.findMany({ where: { status: { in: ['RECEIVING', 'VALIDATED', 'INVALID'] } }, select: { id: true } })).map((u) => u.id),
    );
    for (const d of dirs) {
      if (/^[0-9a-f-]{36}$/.test(d) && !known.has(d)) {
        await fs.rm(path.join(config.uploadDir, d), { recursive: true, force: true });
        orphans++;
      }
    }
  } catch {
    /* Upload-Verzeichnis existiert noch nicht */
  }
  return { expired: expired.length, orphans };
}
