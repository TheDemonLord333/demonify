import fs from 'node:fs/promises';
import pg from 'pg';
import path from 'node:path';
import type { AppConfig } from '../config.js';
import type { Db } from '../db.js';
import { AUDIO_EXTENSIONS, IMAGE_EXTENSIONS, COVER_BASENAMES, ARTIST_IMAGE_BASENAMES, toRel } from '../lib/fsnames.js';
import { contentFingerprint, probeAudio, readTags, splitArtists, type AudioTags, type EmbeddedPicture } from '../lib/media.js';
import { searchText } from '../lib/normalize.js';
import { findOrCreateArtist, registerImage, storeEmbeddedPicture } from './catalog.js';
import { parseLocation, isVariousArtists, type ParsedLocation } from './layout.js';
import type { JobContext } from './jobs.js';

const SCAN_LOCK_KEY = 0x44656d6f; // "Demo"

export interface ScanSummary {
  filesSeen: number;
  added: number;
  updated: number;
  moved: number;
  unchanged: number;
  missing: number;
  restored: number;
  errors: number;
  durationMs: number;
}

interface FoundFile {
  rel: string;
  full: string;
}

async function walk(root: string): Promise<{ audio: FoundFile[]; images: Map<string, string[]> }> {
  const audio: FoundFile[] = [];
  const images = new Map<string, string[]>(); // Ordner (rel) → Bilddateien (Basename)
  async function rec(dir: string) {
    let entries;
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue; // versteckt, *.partial, .Trash
      const full = path.join(dir, e.name);
      if (e.isDirectory()) await rec(full);
      else if (e.isFile()) {
        const ext = path.extname(e.name).toLowerCase();
        if (AUDIO_EXTENSIONS.has(ext)) audio.push({ rel: toRel(root, full), full });
        else if (IMAGE_EXTENSIONS.has(ext)) {
          const relDir = toRel(root, dir);
          const list = images.get(relDir) ?? [];
          list.push(e.name);
          images.set(relDir, list);
        }
      }
    }
  }
  await rec(root);
  audio.sort((a, b) => a.rel.localeCompare(b.rel));
  return { audio, images };
}

function findImage(images: Map<string, string[]>, relDir: string, basenames: string[]): string | null {
  const files = images.get(relDir === '' ? '' : relDir) ?? [];
  for (const base of basenames) {
    const hit = files.find((f) => path.parse(f).name.toLowerCase() === base);
    if (hit) return relDir ? `${relDir}/${hit}` : hit;
  }
  return null;
}

async function mapLimit<T>(items: T[], limit: number, fn: (item: T, i: number) => Promise<void>) {
  let idx = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (idx < items.length) {
      const i = idx++;
      await fn(items[i]!, i);
    }
  });
  await Promise.all(workers);
}

/**
 * Bibliotheksscan (wiederholbar, idempotent):
 * - neue Dateien importieren, geänderte (Größe/mtime) aktualisieren
 * - verschobene Dateien über Inhalts-Fingerabdruck erkennen (keine Duplikate)
 * - fehlende Dateien als nicht verfügbar markieren (Playlists/Hörverlauf bleiben erhalten)
 * - manuell gepflegte Metadaten/Cover (metaLocked/coverLocked/imageLocked) nicht überschreiben
 * - fehlerhafte Dateien einzeln als LibraryIssue melden
 */
export async function runLibraryScan(
  db: Db,
  config: AppConfig,
  opts: { jobId?: string; progress?: JobContext['progress']; isCancelled?: () => Promise<boolean>; log?: Pick<Console, 'info' | 'warn' | 'error'> } = {},
): Promise<ScanSummary> {
  const started = Date.now();
  const log = opts.log ?? console;
  // Session-Advisory-Lock auf einer eigenen Verbindung (der Prisma-Pool könnte Verbindungen wechseln)
  const lockClient = new pg.Client({ connectionString: config.DATABASE_URL });
  await lockClient.connect();
  const lock = await lockClient.query<{ ok: boolean }>('SELECT pg_try_advisory_lock($1) AS ok', [SCAN_LOCK_KEY]);
  if (!lock.rows[0]?.ok) {
    await lockClient.end();
    throw new Error('Es läuft bereits ein Bibliotheksscan.');
  }
  try {
    await fs.access(config.MUSIC_DIR).catch(() => {
      throw new Error(`Musikverzeichnis nicht erreichbar: ${config.MUSIC_DIR}`);
    });
    const summary: ScanSummary = { filesSeen: 0, added: 0, updated: 0, moved: 0, unchanged: 0, missing: 0, restored: 0, errors: 0, durationMs: 0 };
    const { audio, images } = await walk(config.MUSIC_DIR);
    summary.filesSeen = audio.length;
    await opts.progress?.(0, audio.length, 'Dateien werden geprüft …');

    const existing = await db.track.findMany({
      select: { id: true, audioRelPath: true, fileSize: true, fileMtime: true, contentHash: true, available: true, metaLocked: true },
    });
    const byPath = new Map(existing.map((t) => [t.audioRelPath, t]));
    const seenPaths = new Set<string>();
    const touchedReleases = new Set<string>();
    const touchedArtistFolders = new Map<string, string>(); // artistId → folderRel
    const pendingNew: Array<{ file: FoundFile; size: number; mtime: Date; hash: string }> = [];
    let done = 0;

    // Phase 1: unveränderte und geänderte bekannte Dateien
    await mapLimit(audio, config.SCAN_CONCURRENCY, async (file) => {
      try {
        const st = await fs.stat(file.full);
        const known = byPath.get(file.rel);
        seenPaths.add(file.rel);
        if (known) {
          const same = Number(known.fileSize) === st.size && known.fileMtime?.getTime() === st.mtime.getTime();
          if (same) {
            if (!known.available) {
              await db.track.update({ where: { id: known.id }, data: { available: true, missingSince: null } });
              summary.restored++;
            } else summary.unchanged++;
          } else {
            await importFile(db, config, file, { existingId: known.id, metaLocked: known.metaLocked }, images, touchedReleases, touchedArtistFolders);
            summary.updated++;
          }
          await resolveIssues(db, file.rel, ['FILE_ERROR', 'MISSING_FILE']);
        } else {
          const fp = await contentFingerprint(file.full);
          pendingNew.push({ file, size: fp.size, mtime: fp.mtime, hash: fp.hash });
        }
      } catch (e) {
        summary.errors++;
        await reportIssue(db, 'FILE_ERROR', file.rel, e, opts.jobId);
        log.warn(`Scan: Fehler bei ${file.rel}: ${(e as Error).message}`);
      } finally {
        done++;
        await opts.progress?.(done, audio.length + 0, `Geprüft: ${file.rel}`);
      }
      if (opts.isCancelled && done % 50 === 0 && (await opts.isCancelled())) throw new Error('Scan abgebrochen.');
    });

    // Phase 2: neue Dateien – zuerst Verschiebungen erkennen (gleicher Fingerabdruck, alte Datei fehlt)
    const missingByHash = new Map<string, string>();
    for (const t of existing) {
      if (!seenPaths.has(t.audioRelPath) && t.contentHash) missingByHash.set(t.contentHash, t.id);
    }
    for (const p of pendingNew) {
      try {
        const movedId = missingByHash.get(p.hash);
        if (movedId) {
          missingByHash.delete(p.hash);
          const moved = await db.track.update({
            where: { id: movedId },
            data: { audioRelPath: p.file.rel, fileSize: BigInt(p.size), fileMtime: p.mtime, available: true, missingSince: null },
          });
          seenPaths.add(p.file.rel);
          const old = existing.find((t) => t.id === movedId);
          if (old) seenPaths.add(old.audioRelPath); // nicht mehr als fehlend werten
          touchedReleases.add(moved.releaseId);
          summary.moved++;
          continue;
        }
        await importFile(db, config, p.file, { fingerprint: p }, images, touchedReleases, touchedArtistFolders);
        summary.added++;
        await resolveIssues(db, p.file.rel, ['FILE_ERROR']);
      } catch (e) {
        summary.errors++;
        await reportIssue(db, 'FILE_ERROR', p.file.rel, e, opts.jobId);
        log.warn(`Scan: Fehler bei ${p.file.rel}: ${(e as Error).message}`);
      }
    }

    // Phase 3: fehlende Dateien markieren (nicht löschen)
    for (const t of existing) {
      if (seenPaths.has(t.audioRelPath)) continue;
      if (t.available) {
        await db.track.update({ where: { id: t.id }, data: { available: false, missingSince: new Date() } });
      }
      await reportIssue(db, 'MISSING_FILE', t.audioRelPath, new Error('Audiodatei fehlt im Musikverzeichnis.'), opts.jobId, t.id);
      summary.missing++;
    }

    // Phase 4: Cover für betroffene Veröffentlichungen, Künstlerbilder
    for (const releaseId of touchedReleases) {
      try {
        await assignReleaseCover(db, config, releaseId, images);
      } catch (e) {
        log.warn(`Scan: Cover für Veröffentlichung ${releaseId} nicht übernommen: ${(e as Error).message}`);
      }
    }
    for (const [artistId, folder] of touchedArtistFolders) {
      try {
        const artist = await db.artist.findUnique({ where: { id: artistId } });
        if (!artist || artist.imageLocked) continue;
        const rel = findImage(images, folder, ARTIST_IMAGE_BASENAMES);
        if (rel) {
          const img = await registerImage(db, config, { storage: 'LIBRARY', relPath: rel, source: 'FILE' });
          if (artist.imageId !== img.id) await db.artist.update({ where: { id: artistId }, data: { imageId: img.id } });
        }
      } catch (e) {
        log.warn(`Scan: Künstlerbild ${folder} nicht übernommen: ${(e as Error).message}`);
      }
    }

    summary.durationMs = Date.now() - started;
    await opts.progress?.(audio.length, audio.length, 'Scan abgeschlossen');
    return summary;
  } finally {
    await lockClient.query('SELECT pg_advisory_unlock($1)', [SCAN_LOCK_KEY]).catch(() => undefined);
    await lockClient.end().catch(() => undefined);
  }
}

async function reportIssue(db: Db, kind: 'FILE_ERROR' | 'MISSING_FILE' | 'INCOMPLETE_METADATA', relPath: string, e: unknown, jobId?: string, trackId?: string) {
  const message = (e instanceof Error ? e.message : String(e)).slice(0, 1000);
  await db.libraryIssue.upsert({
    where: { kind_relPath: { kind, relPath } },
    create: { kind, relPath, message, jobId, trackId },
    update: { message, jobId, trackId, resolvedAt: null },
  });
}

async function resolveIssues(db: Db, relPath: string, kinds: Array<'FILE_ERROR' | 'MISSING_FILE' | 'INCOMPLETE_METADATA'>) {
  await db.libraryIssue.updateMany({ where: { relPath, kind: { in: kinds }, resolvedAt: null }, data: { resolvedAt: new Date() } });
}

/**
 * Datei importieren oder (bei Änderung) aktualisieren.
 */
async function importFile(
  db: Db,
  config: AppConfig,
  file: FoundFile,
  opts: { existingId?: string; metaLocked?: boolean; fingerprint?: { size: number; mtime: Date; hash: string } },
  images: Map<string, string[]>,
  touchedReleases: Set<string>,
  touchedArtistFolders: Map<string, string>,
) {
  const probe = await probeAudio(config.FFPROBE_PATH, file.full);
  const fp = opts.fingerprint ?? (await contentFingerprint(file.full));
  const { tags, picture } = await readTags(file.full);
  const loc = parseLocation(file.rel);
  const technical = {
    durationMs: probe.durationMs,
    codec: probe.codec,
    container: probe.container,
    bitrate: probe.bitrate,
    sampleRate: probe.sampleRate,
    channels: probe.channels,
    bitDepth: probe.bitDepth,
    fileSize: BigInt(fp.size),
    fileMtime: fp.mtime,
    contentHash: fp.hash,
    available: true,
    missingSince: null,
  };

  if (opts.existingId && opts.metaLocked) {
    const t = await db.track.update({ where: { id: opts.existingId }, data: technical });
    touchedReleases.add(t.releaseId);
    return;
  }

  const meta = deriveMetadata(loc, tags, file.rel);

  // Albumkünstler & Veröffentlichung
  const albumArtist = await findOrCreateArtist(db, meta.albumArtist);
  if (loc.structured && loc.artistFolderRel) {
    if (!albumArtist.folderRelPath) {
      await db.artist.update({ where: { id: albumArtist.id }, data: { folderRelPath: loc.artistFolderRel } }).catch(() => undefined);
    }
    touchedArtistFolders.set(albumArtist.id, loc.artistFolderRel);
  }

  let release = await db.release.findUnique({ where: { folderRelPath: loc.releaseFolderRel } });
  if (!release) {
    release = await db.release.create({
      data: {
        title: meta.releaseTitle,
        type: meta.releaseType,
        year: meta.year,
        genre: meta.genre,
        albumArtistId: albumArtist.id,
        folderRelPath: loc.releaseFolderRel,
        searchText: searchText(meta.releaseTitle),
      },
    });
  } else if (!release.metaLocked && !release.year && meta.year) {
    release = await db.release.update({ where: { id: release.id }, data: { year: meta.year } });
  }
  touchedReleases.add(release.id);

  // Track-Künstler (Hauptkünstler + Features)
  const artistIds: Array<{ id: string; role: 'PRIMARY' | 'FEATURED'; position: number }> = [];
  let pos = 0;
  for (const name of meta.primaryArtists) {
    const a = await findOrCreateArtist(db, name);
    if (!artistIds.some((x) => x.id === a.id)) artistIds.push({ id: a.id, role: 'PRIMARY', position: pos++ });
  }
  for (const name of meta.featuredArtists) {
    const a = await findOrCreateArtist(db, name);
    if (!artistIds.some((x) => x.id === a.id)) artistIds.push({ id: a.id, role: 'FEATURED', position: pos++ });
  }

  // Songcover: eigene Datei im Track-Ordner > eingebettetes Cover
  let coverImageId: string | null | undefined;
  let coverFromEmbedded: EmbeddedPicture | null = null;
  if (loc.trackFolderRel) {
    const coverRel = findImage(images, loc.trackFolderRel, COVER_BASENAMES);
    if (coverRel) coverImageId = (await registerImage(db, config, { storage: 'LIBRARY', relPath: coverRel, source: 'FILE' })).id;
  }
  if (coverImageId === undefined && picture) coverFromEmbedded = picture;

  const data = {
    title: meta.title,
    discNumber: meta.disc,
    trackNumber: meta.track,
    genre: meta.genre,
    year: meta.year,
    needsReview: meta.needsReview,
    searchText: searchText(meta.title),
    ...technical,
  };

  let trackId: string;
  if (opts.existingId) {
    const current = await db.track.findUniqueOrThrow({ where: { id: opts.existingId } });
    const t = await db.track.update({
      where: { id: opts.existingId },
      data: { ...data, releaseId: release.id },
    });
    trackId = t.id;
    await db.trackArtist.deleteMany({ where: { trackId } });
    if (!current.coverLocked && coverImageId !== undefined) await db.track.update({ where: { id: trackId }, data: { coverImageId } });
  } else {
    const t = await db.track.create({
      data: { ...data, releaseId: release.id, audioRelPath: file.rel, coverImageId: coverImageId ?? null },
    });
    trackId = t.id;
  }
  if (artistIds.length) {
    await db.trackArtist.createMany({ data: artistIds.map((a) => ({ trackId, artistId: a.id, role: a.role, position: a.position })) });
  }

  if (coverFromEmbedded) {
    const t = await db.track.findUniqueOrThrow({ where: { id: trackId } });
    if (!t.coverLocked && !t.coverImageId) {
      try {
        const img = await storeEmbeddedPicture(db, config, coverFromEmbedded.data, coverFromEmbedded.format);
        await db.track.update({ where: { id: trackId }, data: { coverImageId: img.id } });
      } catch {
        /* beschädigtes eingebettetes Bild ignorieren */
      }
    }
  }

  if (meta.needsReview) {
    await reportIssue(db, 'INCOMPLETE_METADATA', file.rel, new Error(meta.reviewReason), undefined, trackId);
  } else {
    await resolveIssues(db, file.rel, ['INCOMPLETE_METADATA']);
  }
}

export function deriveMetadata(loc: ParsedLocation, tags: AudioTags, rel: string) {
  const fileTitle = path.posix.basename(rel, path.posix.extname(rel));
  const reasons: string[] = [];
  const albumArtist = loc.artistFolder ?? tags.albumArtist ?? tags.artist ?? 'Unbekannter Künstler';
  if (!loc.artistFolder && !tags.albumArtist && !tags.artist) reasons.push('Künstler unbekannt');

  const folderTitle = loc.trackTitle ?? (loc.structured && !loc.trackFolderRel ? loc.releaseTitle : null);
  const title = tags.title ?? folderTitle ?? fileTitle;
  // Titel aus der verbindlichen Ordnerstruktur ist in Ordnung; nur aus losem Dateinamen → prüfen
  if (!tags.title && !(loc.structured && folderTitle)) reasons.push('Titel nur aus Dateinamen abgeleitet');

  const various = isVariousArtists(albumArtist);
  const artistSource = tags.artist ?? (tags.artists?.length ? tags.artists.join('; ') : undefined) ?? loc.trackArtist ?? (various ? undefined : albumArtist);
  const split = splitArtists(artistSource, title);
  if (split.primary.length === 0) {
    if (various) reasons.push('Interpret des Sampler-Titels unbekannt');
    split.primary.push(various ? 'Unbekannter Künstler' : albumArtist);
  }

  const releaseTitle = loc.releaseTitle ?? tags.album ?? (loc.releaseFolderRel ? path.posix.basename(loc.releaseFolderRel) : 'Unbekannte Veröffentlichung');
  const type = loc.type ?? (tags.trackTotal && tags.trackTotal <= 3 ? 'SINGLE' : 'ALBUM');
  const track = tags.trackNumber ?? loc.trackNumber ?? 1;
  if (!tags.trackNumber && !loc.trackNumber && type !== 'SINGLE') reasons.push('Tracknummer fehlt');

  return {
    albumArtist,
    title,
    primaryArtists: split.primary,
    featuredArtists: split.featured,
    releaseTitle,
    releaseType: type,
    year: tags.year ?? loc.releaseYear ?? null,
    genre: tags.genre ?? null,
    disc: tags.discNumber ?? loc.discNumber ?? 1,
    track,
    needsReview: reasons.length > 0,
    reviewReason: reasons.join('; '),
  };
}

async function assignReleaseCover(db: Db, config: AppConfig, releaseId: string, images: Map<string, string[]>) {
  const release = await db.release.findUnique({ where: { id: releaseId }, include: { coverImage: true } });
  if (!release || release.coverLocked) return;
  let coverId: string | null = release.coverImageId;
  if (release.folderRelPath !== null) {
    const rel = findImage(images, release.folderRelPath, COVER_BASENAMES);
    if (rel) coverId = (await registerImage(db, config, { storage: 'LIBRARY', relPath: rel, source: 'FILE' })).id;
  }
  if (!coverId) {
    // Eingebettetes Cover des ersten Tracks als Veröffentlichungscover
    const first = await db.track.findFirst({
      where: { releaseId, coverImage: { source: 'EMBEDDED' } },
      orderBy: [{ discNumber: 'asc' }, { trackNumber: 'asc' }],
      select: { coverImageId: true },
    });
    coverId = first?.coverImageId ?? null;
  }
  if (coverId !== release.coverImageId) await db.release.update({ where: { id: releaseId }, data: { coverImageId: coverId } });
  if (coverId) {
    // Eingebettete Track-Cover, die identisch zum Veröffentlichungscover sind, sind kein individuelles Songcover
    await db.track.updateMany({
      where: { releaseId, coverLocked: false, coverImageId: coverId, coverImage: { source: 'EMBEDDED' } },
      data: { coverImageId: null },
    });
    const cover = await db.image.findUnique({ where: { id: coverId } });
    if (cover) {
      const sameSha = await db.track.findMany({
        where: { releaseId, coverLocked: false, coverImage: { source: 'EMBEDDED', sha256: cover.sha256 } },
        select: { id: true },
      });
      if (sameSha.length) await db.track.updateMany({ where: { id: { in: sameSha.map((t) => t.id) } }, data: { coverImageId: null } });
    }
  }
}
