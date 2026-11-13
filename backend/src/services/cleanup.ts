import fs from 'node:fs/promises';
import path from 'node:path';
import type { AppConfig } from '../config.js';
import type { Db } from '../db.js';
import { resolveInside, sanitizeSegment, shortId, toRel } from '../lib/fsnames.js';
import { ApiError } from '../lib/errors.js';
import { withLibraryLock } from './scanlock.js';

/**
 * Katalogbereinigung (gemeinsam genutzt von Bibliotheksscan und Künstler-Löschung).
 *
 * Grundsätze:
 * - Tracks werden nur entfernt, wenn ihre Audiodatei nachweislich gelöscht wurde (Scan) oder ein Admin
 *   die Veröffentlichung ausdrücklich gelöscht hat.
 * - Eine Veröffentlichung verschwindet, sobald sie keinen Track mehr hat.
 * - Künstler mit Herkunft SCAN verschwinden, sobald nichts mehr auf sie verweist (Albumkünstler,
 *   Hauptkünstler, Gast/Feature – über alle Verzeichnisse hinweg). MANUAL und LEGACY bleiben.
 */

/** Ordner im Musikverzeichnis für absichtlich gelöschte Audiodateien. Beginnt mit „.“ → vom Scan ignoriert. */
export const TRASH_DIR = '.demonify-papierkorb';

/** Tracks aus dem Katalog entfernen (Playlists/Favoriten/Verlauf per Kaskade) und zugehörige Cache-Dateien löschen. */
export async function removeTracks(db: Db, config: AppConfig, trackIds: string[]): Promise<{ removed: number; releaseIds: Set<string> }> {
  const releaseIds = new Set<string>();
  let removed = 0;
  for (let i = 0; i < trackIds.length; i += 200) {
    const batch = trackIds.slice(i, i + 200);
    const tracks = await db.track.findMany({ where: { id: { in: batch } }, select: { id: true, releaseId: true, audioRelPath: true, transcodes: { select: { relPath: true } } } });
    if (!tracks.length) continue;
    const res = await db.track.deleteMany({ where: { id: { in: tracks.map((t) => t.id) } } });
    removed += res.count;
    tracks.forEach((t) => releaseIds.add(t.releaseId));
    await db.libraryIssue.updateMany({
      where: { resolvedAt: null, OR: [{ trackId: { in: tracks.map((t) => t.id) } }, { relPath: { in: tracks.map((t) => t.audioRelPath) } }] },
      data: { resolvedAt: new Date() },
    });
    for (const tf of tracks.flatMap((t) => t.transcodes)) {
      try {
        await fs.rm(resolveInside(config.cacheDir, tf.relPath), { force: true });
      } catch {
        /* Cache-Datei ohne Bedeutung */
      }
    }
  }
  return { removed, releaseIds };
}

/** Veröffentlichungen ohne Tracks entfernen (nur vor `before` angelegte – laufende Uploads bleiben unberührt). */
export async function pruneEmptyReleases(db: Db, before: Date): Promise<number> {
  const res = await db.release.deleteMany({ where: { createdAt: { lt: before }, tracks: { none: {} } } });
  return res.count;
}

/**
 * Automatisch erkannte Künstler (SCAN) ohne jede Verbindung entfernen.
 * Ein einzelnes DELETE … NOT EXISTS prüft Albumkünstler und alle Track-Rollen atomar.
 */
export async function pruneOrphanScanArtists(db: Db, before: Date): Promise<string[]> {
  const rows = await db.$queryRaw<Array<{ name: string }>>`
    DELETE FROM "Artist" a
    WHERE a.origin = 'SCAN' AND a."createdAt" < ${before}
      AND NOT EXISTS (SELECT 1 FROM "Release" r WHERE r."albumArtistId" = a.id)
      AND NOT EXISTS (SELECT 1 FROM "TrackArtist" ta WHERE ta."artistId" = a.id)
    RETURNING a.name`;
  return rows.map((r) => r.name);
}

/** Extrahierte Cover im Cache, auf die nichts mehr verweist, entfernen. */
export async function pruneOrphanCacheImages(db: Db, config: AppConfig): Promise<number> {
  const rows = await db.$queryRaw<Array<{ relPath: string }>>`
    DELETE FROM "Image" i
    WHERE i.storage = 'CACHE'
      AND NOT EXISTS (SELECT 1 FROM "Artist" a WHERE a."imageId" = i.id)
      AND NOT EXISTS (SELECT 1 FROM "Release" r WHERE r."coverImageId" = i.id)
      AND NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."coverImageId" = i.id)
    RETURNING i."relPath"`;
  for (const r of rows) {
    try {
      await fs.rm(resolveInside(config.cacheDir, r.relPath), { force: true });
    } catch {
      /* ignorieren */
    }
  }
  return rows.length;
}

export interface ArtistDeletePreview {
  artist: { id: string; name: string; origin: string };
  ownReleases: number;
  ownTracks: number;
  /** Fremde/gemeinsame Veröffentlichungen, auf denen der Künstler nur mitwirkt → bleiben erhalten */
  otherReleases: number;
  otherTracks: number;
  followers: number;
}

export async function artistDeletePreview(db: Db, artistId: string): Promise<ArtistDeletePreview> {
  const artist = await db.artist.findUnique({ where: { id: artistId } });
  if (!artist) throw new ApiError(404, 'NOT_FOUND', 'Künstler nicht gefunden.');
  const [ownReleases, ownTracks, other, followers] = await Promise.all([
    db.release.count({ where: { albumArtistId: artistId } }),
    db.track.count({ where: { release: { albumArtistId: artistId } } }),
    db.track.findMany({ where: { artists: { some: { artistId } }, release: { albumArtistId: { not: artistId } } }, select: { releaseId: true } }),
    db.followedArtist.count({ where: { artistId } }),
  ]);
  return {
    artist: { id: artist.id, name: artist.name, origin: artist.origin },
    ownReleases,
    ownTracks,
    otherReleases: new Set(other.map((t) => t.releaseId)).size,
    otherTracks: other.length,
    followers,
  };
}

/**
 * Künstler ausdrücklich löschen (Verwaltung):
 * - Eigene Veröffentlichungen (Albumkünstler) werden aus dem Katalog entfernt. Deren Audiodateien werden
 *   nicht endgültig gelöscht, sondern in den Papierkorb-Ordner im Musikverzeichnis verschoben – so kehren
 *   sie beim nächsten Scan nicht zurück und lassen sich bei Bedarf wiederherstellen.
 *   Verschoben werden nur die Audiodateien dieser Tracks (jede gehört genau einem Track). Bilder, Ordner
 *   und Dateien anderer Veröffentlichungen bleiben unangetastet.
 * - Fremde/gemeinsame Veröffentlichungen bleiben verfügbar; nur die Mitwirkung des Künstlers wird entfernt.
 *   Verliert ein Track dadurch alle Hauptkünstler, wird der Albumkünstler seiner Veröffentlichung Hauptkünstler.
 * - Läuft gerade ein Scan, wird abgelehnt (gleicher Lock wie der Scan).
 */
export async function deleteArtist(db: Db, config: AppConfig, artistId: string, log?: Pick<Console, 'warn'>) {
  return withLibraryLock(config.DATABASE_URL, 'Gerade läuft ein Bibliotheksscan. Bitte nach dessen Ende erneut versuchen.', async () => {
    const started = new Date();
    const artist = await db.artist.findUnique({ where: { id: artistId } });
    if (!artist) throw new ApiError(404, 'NOT_FOUND', 'Künstler nicht gefunden.');
    const ownTracks = await db.track.findMany({ where: { release: { albumArtistId: artistId } }, select: { id: true, audioRelPath: true } });

    // 1) Audiodateien in den Papierkorb verschieben (bei Fehler alles zurück)
    const stamp = started.toISOString().replace(/[:T]/g, '-').slice(0, 19);
    const trashRoot = path.join(config.MUSIC_DIR, TRASH_DIR, `${stamp} ${sanitizeSegment(artist.name)} [${shortId(artist.id)}]`);
    const moved: Array<{ from: string; to: string }> = [];
    try {
      for (const t of ownTracks) {
        const from = resolveInside(config.MUSIC_DIR, t.audioRelPath);
        const to = path.join(trashRoot, t.audioRelPath);
        await fs.mkdir(path.dirname(to), { recursive: true });
        try {
          await fs.rename(from, to);
          moved.push({ from, to });
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code === 'ENOENT') continue; // Datei bereits weg
          throw e;
        }
      }
    } catch (e) {
      await restore(moved);
      throw new ApiError(500, 'FILE_MOVE_FAILED', `Audiodateien konnten nicht in den Papierkorb verschoben werden: ${(e as Error).message}`);
    }

    // 2) Katalog in einer Transaktion bereinigen
    let removedReleases = 0;
    try {
      await db.$transaction(
        async (tx) => {
          await tx.track.deleteMany({ where: { id: { in: ownTracks.map((t) => t.id) } } });
          removedReleases = (await tx.release.deleteMany({ where: { albumArtistId: artistId } })).count;
          const affected = await tx.trackArtist.findMany({ where: { artistId }, select: { trackId: true } });
          await tx.trackArtist.deleteMany({ where: { artistId } });
          for (const { trackId } of affected) {
            const primaries = await tx.trackArtist.count({ where: { trackId, role: 'PRIMARY' } });
            if (primaries > 0) continue;
            const track = await tx.track.findUnique({ where: { id: trackId }, select: { release: { select: { albumArtistId: true } } } });
            if (!track) continue;
            await tx.trackArtist.upsert({
              where: { trackId_artistId: { trackId, artistId: track.release.albumArtistId } },
              create: { trackId, artistId: track.release.albumArtistId, role: 'PRIMARY', position: 0 },
              update: { role: 'PRIMARY', position: 0 },
            });
          }
          await tx.artist.delete({ where: { id: artistId } });
        },
        { timeout: 60_000 },
      );
    } catch (e) {
      await restore(moved);
      throw e;
    }

    // 3) Folgearbeiten (nicht kritisch)
    await db.libraryIssue.updateMany({
      where: { resolvedAt: null, OR: [{ trackId: { in: ownTracks.map((t) => t.id) } }, { relPath: { in: ownTracks.map((t) => t.audioRelPath) } }] },
      data: { resolvedAt: new Date() },
    });
    const removedArtists = await pruneOrphanScanArtists(db, started).catch((e: Error) => {
      log?.warn(`Künstlerbereinigung übersprungen: ${e.message}`);
      return [] as string[];
    });
    await pruneOrphanCacheImages(db, config).catch(() => 0);
    return {
      removedReleases,
      removedTracks: ownTracks.length,
      movedFiles: moved.length,
      trashFolder: moved.length ? toRel(config.MUSIC_DIR, trashRoot) : null,
      removedArtists,
    };
  });
}

async function restore(moved: Array<{ from: string; to: string }>) {
  for (const m of moved.reverse()) {
    await fs.mkdir(path.dirname(m.from), { recursive: true }).catch(() => undefined);
    await fs.rename(m.to, m.from).catch(() => undefined);
  }
}
