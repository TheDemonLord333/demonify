import fs from 'node:fs/promises';
import path from 'node:path';
import type { AppConfig } from '../config.js';
import type { Db, Prisma } from '../db.js';
import { cleanDisplayName, nameKey, searchText } from '../lib/normalize.js';
import { conflict, isUniqueViolation, badRequest } from '../lib/errors.js';
import { probeImage, sha256File, pictureExtension } from '../lib/media.js';
import { resolveInside, toRel } from '../lib/fsnames.js';
import crypto from 'node:crypto';

type Tx = Prisma.TransactionClient | Db;

export function validateArtistName(raw: string): { name: string; key: string } {
  const name = cleanDisplayName(raw);
  if (!name) throw badRequest('Der Künstlername darf nicht leer sein.');
  if (name.length > 200) throw badRequest('Der Künstlername ist zu lang (max. 200 Zeichen).');
  return { name, key: nameKey(name) };
}

/**
 * Künstler anlegen – verbindlich eindeutig über nameKey (DB-Constraint).
 * Bei gleichzeitigen Anlegeversuchen liefert die Datenbank den Konflikt; der Aufrufer
 * erhält 409 ARTIST_EXISTS mit dem vorhandenen Künstler.
 */
export async function createArtist(db: Tx, rawName: string) {
  const { name, key } = validateArtistName(rawName);
  const existing = await db.artist.findUnique({ where: { nameKey: key } });
  if (existing) {
    throw conflict(`Ein Künstler mit dem Namen „${existing.name}“ existiert bereits.`, { artist: { id: existing.id, name: existing.name } }, 'ARTIST_EXISTS');
  }
  try {
    return await db.artist.create({ data: { name, nameKey: key, searchText: searchText(name), origin: 'MANUAL' } });
  } catch (e) {
    if (isUniqueViolation(e)) {
      const other = await db.artist.findUnique({ where: { nameKey: key } });
      throw conflict(
        `Ein Künstler mit dem Namen „${other?.name ?? name}“ wurde gerade angelegt.`,
        other ? { artist: { id: other.id, name: other.name } } : undefined,
        'ARTIST_EXISTS',
      );
    }
    throw e;
  }
}

/**
 * Für Scan/Import: vorhandenen Künstler wiederverwenden oder anlegen (race-sicher).
 * Neu angelegte Einträge erhalten die Herkunft SCAN; die Herkunft vorhandener Einträge bleibt unverändert.
 */
export async function findOrCreateArtist(db: Tx, rawName: string) {
  const { name, key } = validateArtistName(rawName);
  const existing = await db.artist.findUnique({ where: { nameKey: key } });
  if (existing) return existing;
  try {
    return await db.artist.create({ data: { name, nameKey: key, searchText: searchText(name), origin: 'SCAN' } });
  } catch (e) {
    if (isUniqueViolation(e)) {
      const other = await db.artist.findUnique({ where: { nameKey: key } });
      if (other) return other;
    }
    throw e;
  }
}

/** Ähnliche Namen als Hinweis (pg_trgm), ersetzt nie die verbindliche Eindeutigkeit */
export async function similarArtists(db: Db, rawName: string, limit = 5) {
  const q = searchText(rawName);
  if (!q) return [];
  return db.$queryRaw<Array<{ id: string; name: string; imageId: string | null; score: number }>>`
    SELECT id, name, "imageId", similarity("searchText", ${q})::float AS score
    FROM "Artist"
    WHERE "searchText" % ${q} OR "searchText" LIKE ${`%${q.replace(/[\\%_]/g, '\\$&')}%`}
    ORDER BY score DESC, name ASC
    LIMIT ${limit}`;
}

/**
 * Bild registrieren (Bibliotheksdatei oder Cache-Datei). Gleiche relPath → gleicher Datensatz.
 */
export async function registerImage(
  db: Tx,
  config: AppConfig,
  opts: { storage: 'LIBRARY' | 'CACHE'; relPath: string; source: 'FILE' | 'EMBEDDED' | 'UPLOAD' },
) {
  const root = opts.storage === 'LIBRARY' ? config.MUSIC_DIR : config.cacheDir;
  const full = resolveInside(root, opts.relPath);
  const info = await probeImage(full);
  const sha = await sha256File(full);
  const existing = await db.image.findUnique({ where: { storage_relPath: { storage: opts.storage, relPath: opts.relPath } } });
  if (existing) {
    if (existing.sha256 === sha) return existing;
    return db.image.update({
      where: { id: existing.id },
      data: { sha256: sha, width: info.width, height: info.height, format: info.format, source: opts.source },
    });
  }
  return db.image.create({
    data: { storage: opts.storage, relPath: opts.relPath, source: opts.source, format: info.format, width: info.width, height: info.height, sha256: sha },
  });
}

/** Eingebettetes Cover in den Cache extrahieren (Original bleibt unverändert). */
export async function storeEmbeddedPicture(db: Tx, config: AppConfig, data: Uint8Array, format: string) {
  const buf = Buffer.from(data);
  await probeImage(buf); // tatsächliche Prüfung
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  const rel = `embedded/${sha.slice(0, 2)}/${sha}.${pictureExtension(format)}`;
  const full = resolveInside(config.cacheDir, rel);
  await fs.mkdir(path.dirname(full), { recursive: true });
  try {
    await fs.writeFile(full, buf, { flag: 'wx' });
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== 'EEXIST') throw e;
  }
  return registerImage(db, config, { storage: 'CACHE', relPath: rel, source: 'EMBEDDED' });
}

export function imageFullPath(config: AppConfig, image: { storage: string; relPath: string }): string {
  return resolveInside(image.storage === 'LIBRARY' ? config.MUSIC_DIR : config.cacheDir, image.relPath);
}

export function relToMusic(config: AppConfig, full: string): string {
  return toRel(config.MUSIC_DIR, full);
}

export async function refreshTrackSearchText(db: Tx, trackId: string) {
  const t = await db.track.findUnique({ where: { id: trackId }, select: { title: true } });
  if (!t) return;
  await db.track.update({ where: { id: trackId }, data: { searchText: searchText(t.title) } });
}
