import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import type { AppConfig } from '../config.js';
import type { Db, Prisma } from '../db.js';
import { badRequest, conflict, notFound, isUniqueViolation, ApiError } from '../lib/errors.js';
import { createUniqueDir, ensureDir, placeFileExclusive, resolveInside, sanitizeSegment, toRel, shortId } from '../lib/fsnames.js';
import { contentFingerprint, readTags, type ProbeResult } from '../lib/media.js';
import { searchText, nameKey } from '../lib/normalize.js';
import { registerImage, storeEmbeddedPicture } from './catalog.js';
import { TYPE_DIR_NAMES, releaseFolderName, trackFolderName, isVariousArtists } from './layout.js';
import { uploadFile } from './uploads.js';

export interface CommitTrackInput {
  uploadId: string;
  title: string;
  discNumber: number;
  trackNumber: number;
  artistIds: string[];
  featuredArtistIds: string[];
  genre?: string | null;
  year?: number | null;
  coverUploadId?: string | null;
}

export interface CommitInput {
  idempotencyKey: string;
  artistId: string;
  release:
    | { mode: 'new'; title: string; type: 'ALBUM' | 'EP' | 'SINGLE'; year?: number | null; genre?: string | null; coverUploadId?: string | null }
    | { mode: 'existing'; releaseId: string; coverUploadId?: string | null };
  tracks: CommitTrackInput[];
}

export interface CommitResult {
  releaseId: string;
  trackIds: string[];
  releaseFolder: string;
}

const EXT_BY_CODEC: Record<string, string> = { flac: '.flac', mp3: '.mp3', aac: '.m4a', alac: '.m4a', vorbis: '.ogg', opus: '.ogg' };

function audioExtension(originalName: string, probe: ProbeResult): string {
  const ext = path.extname(originalName).toLowerCase();
  if (probe.codec?.startsWith('pcm_')) return '.wav';
  const byCodec = probe.codec ? EXT_BY_CODEC[probe.codec] : undefined;
  if (ext === '.opus' && probe.codec === 'opus') return '.opus';
  return byCodec ?? (ext || '.bin');
}

function imageExtension(format: string): string {
  return format === 'png' ? '.png' : format === 'webp' ? '.webp' : '.jpg';
}

/**
 * Upload-Abschluss: legt Ordner gemäß verbindlicher Struktur an, verschiebt validierte Dateien
 * (nie überschreibend) in die Bibliothek und erstellt alle Datenbankeinträge.
 * Idempotent über idempotencyKey; bei Fehlern werden angelegte Dateien/Ordner wieder entfernt.
 */
export async function commitRelease(db: Db, config: AppConfig, userId: string, input: CommitInput): Promise<CommitResult> {
  // 1) Idempotenz
  try {
    await db.uploadCommit.create({ data: { idempotencyKey: input.idempotencyKey, userId, status: 'PROCESSING' } });
  } catch (e) {
    if (!isUniqueViolation(e)) throw e;
    const prev = await db.uploadCommit.findUnique({ where: { idempotencyKey: input.idempotencyKey } });
    if (prev?.status === 'DONE') return prev.result as unknown as CommitResult;
    if (prev?.status === 'PROCESSING') throw conflict('Dieser Upload wird bereits verarbeitet.', undefined, 'COMMIT_IN_PROGRESS');
    const retried = await db.uploadCommit.updateMany({
      where: { idempotencyKey: input.idempotencyKey, status: 'FAILED' },
      data: { status: 'PROCESSING', error: null },
    });
    if (retried.count === 0) throw conflict('Dieser Upload wird bereits verarbeitet.', undefined, 'COMMIT_IN_PROGRESS');
  }

  const createdFiles: string[] = [];
  const createdDirs: string[] = [];
  try {
    const result = await doCommit(db, config, input, createdFiles, createdDirs);
    await db.uploadCommit.update({
      where: { idempotencyKey: input.idempotencyKey },
      data: { status: 'DONE', releaseId: result.releaseId, result: result as unknown as Prisma.InputJsonValue },
    });
    return result;
  } catch (e) {
    for (const f of createdFiles.reverse()) await fs.rm(f, { force: true }).catch(() => undefined);
    for (const d of createdDirs.reverse()) await fs.rmdir(d).catch(() => undefined); // nur leere Ordner
    await db.uploadCommit
      .update({ where: { idempotencyKey: input.idempotencyKey }, data: { status: 'FAILED', error: (e as Error).message.slice(0, 1000) } })
      .catch(() => undefined);
    throw e;
  }
}

async function doCommit(db: Db, config: AppConfig, input: CommitInput, createdFiles: string[], createdDirs: string[]): Promise<CommitResult> {
  if (input.tracks.length === 0 && !input.release.coverUploadId) throw badRequest('Keine Audiodateien ausgewählt.');
  const uploadIds = [...input.tracks.map((t) => t.uploadId)];
  if (new Set(uploadIds).size !== uploadIds.length) throw badRequest('Eine Audiodatei wurde mehrfach zugeordnet.');

  const artist = await db.artist.findUnique({ where: { id: input.artistId } });
  if (!artist) throw notFound('Künstler nicht gefunden.');

  // Alle Uploads prüfen
  const allUploadIds = [
    ...uploadIds,
    ...input.tracks.map((t) => t.coverUploadId).filter((x): x is string => !!x),
    ...(input.release.coverUploadId ? [input.release.coverUploadId] : []),
  ];
  const uploads = await db.upload.findMany({ where: { id: { in: [...new Set(allUploadIds)] } } });
  const byId = new Map(uploads.map((u) => [u.id, u]));
  for (const id of allUploadIds) {
    const u = byId.get(id);
    if (!u) throw notFound(`Upload ${id} nicht gefunden.`);
    if (u.status !== 'VALIDATED') throw new ApiError(422, 'UPLOAD_NOT_READY', `„${u.originalName}“ ist nicht geprüft oder ungültig.`);
  }
  for (const t of input.tracks) {
    if (byId.get(t.uploadId)!.kind !== 'AUDIO') throw badRequest('Für einen Track wurde keine Audiodatei angegeben.');
    if (t.coverUploadId && byId.get(t.coverUploadId)!.kind !== 'IMAGE') throw badRequest('Songcover muss ein Bild sein.');
    if (!t.title.trim()) throw badRequest('Jeder Track benötigt einen Titel.');
    if (t.artistIds.length === 0) throw badRequest(`Track „${t.title}“ benötigt mindestens einen Künstler.`);
  }
  if (input.release.coverUploadId && byId.get(input.release.coverUploadId)!.kind !== 'IMAGE') throw badRequest('Cover muss ein Bild sein.');
  const trackArtistIds = [...new Set(input.tracks.flatMap((t) => [...t.artistIds, ...t.featuredArtistIds]))];
  const foundArtists = await db.artist.findMany({ where: { id: { in: trackArtistIds } }, select: { id: true, name: true } });
  if (foundArtists.length !== trackArtistIds.length) throw notFound('Mindestens ein Track-Künstler existiert nicht.');
  const artistName = new Map(foundArtists.map((a) => [a.id, a.name]));

  // Veröffentlichung bestimmen
  let existingRelease: Awaited<ReturnType<typeof db.release.findUnique>> = null;
  let type: 'ALBUM' | 'EP' | 'SINGLE';
  let title: string;
  let year: number | null;
  if (input.release.mode === 'existing') {
    existingRelease = await db.release.findUnique({ where: { id: input.release.releaseId } });
    if (!existingRelease) throw notFound('Veröffentlichung nicht gefunden.');
    if (existingRelease.albumArtistId !== artist.id) throw badRequest('Die Veröffentlichung gehört zu einem anderen Künstler.');
    type = existingRelease.type;
    title = existingRelease.title;
    year = existingRelease.year;
  } else {
    type = input.release.type;
    title = input.release.title.trim();
    year = input.release.year ?? null;
    if (!title) throw badRequest('Die Veröffentlichung benötigt einen Titel.');
  }
  const existingTracks = existingRelease
    ? await db.track.findMany({ where: { releaseId: existingRelease.id }, select: { discNumber: true, trackNumber: true } })
    : [];
  const multiDisc = [...existingTracks, ...input.tracks].some((t) => t.discNumber > 1);
  const releaseId = existingRelease?.id ?? crypto.randomUUID();

  // 2) Ordner: Künstler → Typ → Veröffentlichung
  const artistDir = await resolveArtistDir(db, config, artist, createdDirs);
  const typeDir = path.join(artistDir, TYPE_DIR_NAMES[type]);
  if (!(await exists(typeDir))) {
    await ensureDir(typeDir);
    createdDirs.push(typeDir);
  }
  let releaseDir: string;
  if (existingRelease?.folderRelPath) {
    releaseDir = resolveInside(config.MUSIC_DIR, existingRelease.folderRelPath);
    await ensureDir(releaseDir);
  } else {
    releaseDir = await createUniqueDir(typeDir, releaseFolderName(year, title), releaseId);
    createdDirs.push(releaseDir);
  }

  // Einzel-Single ohne Track-Unterordner (Datei direkt im Veröffentlichungsordner)
  const flatSingle = type === 'SINGLE' && !existingRelease && input.tracks.length === 1;
  const various = isVariousArtists(artist.name);

  // 3) Dateien platzieren
  interface Planned {
    input: CommitTrackInput;
    id: string;
    audioFull: string;
    coverFull: string | null;
    probe: ProbeResult;
  }
  const planned: Planned[] = [];
  for (const t of input.tracks) {
    const upload = byId.get(t.uploadId)!;
    const probe = upload.probe as unknown as ProbeResult;
    const id = crypto.randomUUID();
    let dir = releaseDir;
    if (!flatSingle) {
      const primaryName = artistName.get(t.artistIds[0]!) ?? '';
      dir = await createUniqueDir(
        releaseDir,
        trackFolderName({ disc: t.discNumber, track: t.trackNumber, title: t.title.trim(), multiDisc, artistPrefix: various ? primaryName : null }),
        id,
      );
      createdDirs.push(dir);
    }
    const audioFull = await placeUnique(dir, 'audio', audioExtension(upload.originalName, probe), uploadFile(config, upload.id), id);
    createdFiles.push(audioFull);
    let coverFull: string | null = null;
    if (t.coverUploadId) {
      const cu = byId.get(t.coverUploadId)!;
      const fmt = (cu.probe as { format: string }).format;
      coverFull = await placeUnique(dir, 'cover', imageExtension(fmt), uploadFile(config, cu.id), id);
      createdFiles.push(coverFull);
    }
    planned.push({ input: t, id, audioFull, coverFull, probe });
  }
  let releaseCoverFull: string | null = null;
  if (input.release.coverUploadId) {
    const cu = byId.get(input.release.coverUploadId)!;
    const fmt = (cu.probe as { format: string }).format;
    releaseCoverFull = await placeUnique(releaseDir, 'cover', imageExtension(fmt), uploadFile(config, cu.id), releaseId);
    createdFiles.push(releaseCoverFull);
  }

  // 4) Datenbank (eine Transaktion)
  const fingerprints = await Promise.all(planned.map((p) => contentFingerprint(p.audioFull)));
  await db.$transaction(
    async (tx) => {
      if (!existingRelease) {
        await tx.release.create({
          data: {
            id: releaseId,
            title,
            type,
            year,
            genre: input.release.mode === 'new' ? (input.release.genre?.trim() || null) : null,
            albumArtistId: artist.id,
            folderRelPath: toRel(config.MUSIC_DIR, releaseDir),
            searchText: searchText(title),
            metaLocked: true,
          },
        });
      } else if (!existingRelease.folderRelPath) {
        await tx.release.update({ where: { id: releaseId }, data: { folderRelPath: toRel(config.MUSIC_DIR, releaseDir) } });
      }
      if (releaseCoverFull) {
        const img = await registerImage(tx, config, { storage: 'LIBRARY', relPath: toRel(config.MUSIC_DIR, releaseCoverFull), source: 'UPLOAD' });
        await tx.release.update({ where: { id: releaseId }, data: { coverImageId: img.id, coverLocked: true } });
      }
      for (let i = 0; i < planned.length; i++) {
        const p = planned[i]!;
        const fp = fingerprints[i]!;
        let coverImageId: string | null = null;
        if (p.coverFull) {
          coverImageId = (await registerImage(tx, config, { storage: 'LIBRARY', relPath: toRel(config.MUSIC_DIR, p.coverFull), source: 'UPLOAD' })).id;
        }
        await tx.track.create({
          data: {
            id: p.id,
            releaseId,
            title: p.input.title.trim(),
            discNumber: p.input.discNumber,
            trackNumber: p.input.trackNumber,
            genre: p.input.genre?.trim() || null,
            year: p.input.year ?? null,
            durationMs: p.probe.durationMs,
            codec: p.probe.codec,
            container: p.probe.container,
            bitrate: p.probe.bitrate,
            sampleRate: p.probe.sampleRate,
            channels: p.probe.channels,
            bitDepth: p.probe.bitDepth,
            fileSize: BigInt(fp.size),
            fileMtime: fp.mtime,
            contentHash: fp.hash,
            audioRelPath: toRel(config.MUSIC_DIR, p.audioFull),
            coverImageId,
            coverLocked: coverImageId !== null,
            metaLocked: true,
            searchText: searchText(p.input.title),
          },
        });
        const links = [
          ...p.input.artistIds.map((id, idx) => ({ trackId: p.id, artistId: id, role: 'PRIMARY' as const, position: idx })),
          ...p.input.featuredArtistIds
            .filter((id) => !p.input.artistIds.includes(id))
            .map((id, idx) => ({ trackId: p.id, artistId: id, role: 'FEATURED' as const, position: p.input.artistIds.length + idx })),
        ];
        await tx.trackArtist.createMany({ data: links });
      }
      await tx.upload.updateMany({ where: { id: { in: allUploadIds } }, data: { status: 'CONSUMED' } });
    },
    { timeout: 60_000 },
  );

  // 5) Eingebettete Cover (außerhalb der Transaktion, nicht kritisch)
  await applyEmbeddedCovers(db, config, releaseId, planned.filter((p) => !p.coverFull).map((p) => ({ id: p.id, file: p.audioFull })));

  // Upload-Rohdaten entfernen
  for (const id of allUploadIds) await fs.rm(path.dirname(uploadFile(config, id)), { recursive: true, force: true }).catch(() => undefined);

  return { releaseId, trackIds: planned.map((p) => p.id), releaseFolder: toRel(config.MUSIC_DIR, releaseDir) };
}

async function exists(p: string) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

/** Nie überschreiben: "audio.flac" oder bei Kollision "audio [abcd1234].flac" */
async function placeUnique(dir: string, base: string, ext: string, src: string, stableId: string): Promise<string> {
  const names = [`${base}${ext}`, `${base} [${shortId(stableId)}]${ext}`, `${base} [${crypto.randomBytes(4).toString('hex')}]${ext}`];
  for (const name of names) {
    const dest = path.join(dir, name);
    try {
      await placeFileExclusive(src, dest);
      return dest;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'EEXIST') continue;
      throw e;
    }
  }
  throw new Error(`Konnte ${base}${ext} nicht ohne Überschreiben ablegen.`);
}

async function resolveArtistDir(
  db: Db,
  config: AppConfig,
  artist: { id: string; name: string; nameKey: string; folderRelPath: string | null },
  createdDirs: string[],
): Promise<string> {
  if (artist.folderRelPath) {
    const full = resolveInside(config.MUSIC_DIR, artist.folderRelPath);
    await ensureDir(full);
    return full;
  }
  const base = sanitizeSegment(artist.name);
  const candidate = path.join(config.MUSIC_DIR, base);
  // Vorhandenen Ordner nur übernehmen, wenn er eindeutig zu diesem Künstler gehört
  if (await exists(candidate)) {
    const owner = await db.artist.findFirst({ where: { folderRelPath: base } });
    if (!owner && nameKey(base) === artist.nameKey) {
      await db.artist.update({ where: { id: artist.id }, data: { folderRelPath: base } });
      return candidate;
    }
  }
  await fs.mkdir(config.MUSIC_DIR, { recursive: true });
  const dir = await createUniqueDir(config.MUSIC_DIR, base, artist.id);
  createdDirs.push(dir);
  await db.artist.update({ where: { id: artist.id }, data: { folderRelPath: toRel(config.MUSIC_DIR, dir) } });
  return dir;
}

async function applyEmbeddedCovers(db: Db, config: AppConfig, releaseId: string, tracks: Array<{ id: string; file: string }>) {
  const release = await db.release.findUnique({ where: { id: releaseId }, include: { coverImage: true } });
  for (const t of tracks) {
    try {
      const { picture } = await readTags(t.file);
      if (!picture) continue;
      const img = await storeEmbeddedPicture(db, config, picture.data, picture.format);
      if (!release?.coverImageId) {
        await db.release.update({ where: { id: releaseId }, data: { coverImageId: img.id } });
        if (release) {
          release.coverImageId = img.id;
          release.coverImage = img;
        }
        continue; // identisch mit Veröffentlichungscover → kein eigenes Songcover
      }
      if (release.coverImage?.sha256 === img.sha256) continue;
      await db.track.update({ where: { id: t.id }, data: { coverImageId: img.id } });
    } catch {
      /* eingebettetes Cover unlesbar → ignorieren */
    }
  }
}
