import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import type { AppConfig } from '../config.js';
import type { Db } from '../db.js';
import { resolveInside } from '../lib/fsnames.js';
import { runProcess } from '../lib/media.js';
import type { JobQueue, JobContext } from './jobs.js';

export const QUALITIES = ['original', 'high', 'normal', 'low'] as const;
export type Quality = (typeof QUALITIES)[number];

/** AAC-Bitraten (kbit/s) der transkodierten Varianten */
export const QUALITY_KBPS: Record<Exclude<Quality, 'original'>, number> = { high: 256, normal: 160, low: 96 };

export interface StreamFile {
  storage: 'LIBRARY' | 'CACHE';
  relPath: string;
  fullPath: string;
  mime: string;
  servedQuality: Quality;
}

const MIME_BY_EXT: Record<string, string> = {
  '.mp3': 'audio/mpeg',
  '.flac': 'audio/flac',
  '.m4a': 'audio/mp4',
  '.mp4': 'audio/mp4',
  '.aac': 'audio/aac',
  '.ogg': 'audio/ogg',
  '.oga': 'audio/ogg',
  '.opus': 'audio/ogg',
  '.wav': 'audio/wav',
};

export function audioMime(relPath: string): string {
  return MIME_BY_EXT[path.extname(relPath).toLowerCase()] ?? 'application/octet-stream';
}

/** Muss überhaupt transkodiert werden? Verlustbehaftete Quellen ≤ Zielbitrate bleiben original. */
export function needsTranscode(track: { codec: string | null; bitrate: number | null }, quality: Quality): boolean {
  if (quality === 'original') return false;
  const target = QUALITY_KBPS[quality] * 1000;
  const lossy = ['mp3', 'aac', 'vorbis', 'opus'].includes(track.codec ?? '');
  if (lossy && track.bitrate && track.bitrate <= target * 1.1) return false;
  return true;
}

/**
 * Datei für die gewünschte Qualität bestimmen. Ist die transkodierte Variante noch nicht
 * vorhanden, wird ein Hintergrundauftrag eingereiht und vorerst das Original ausgeliefert.
 */
export async function resolveStreamFile(
  db: Db,
  config: AppConfig,
  queue: JobQueue | null,
  track: { id: string; audioRelPath: string; codec: string | null; bitrate: number | null; contentHash: string | null },
  quality: Quality,
): Promise<StreamFile> {
  const original: StreamFile = {
    storage: 'LIBRARY',
    relPath: track.audioRelPath,
    fullPath: resolveInside(config.MUSIC_DIR, track.audioRelPath),
    mime: audioMime(track.audioRelPath),
    servedQuality: 'original',
  };
  if (!needsTranscode(track, quality)) return original;
  const tf = await db.transcodedFile.findUnique({ where: { trackId_quality: { trackId: track.id, quality } } });
  if (tf && tf.sourceHash === track.contentHash) {
    const full = resolveInside(config.cacheDir, tf.relPath);
    try {
      await fs.access(full);
      return { storage: 'CACHE', relPath: tf.relPath, fullPath: full, mime: 'audio/mp4', servedQuality: quality };
    } catch {
      await db.transcodedFile.delete({ where: { id: tf.id } }).catch(() => undefined);
    }
  }
  if (queue) {
    await queue.enqueue('TRANSCODE', { trackId: track.id, quality }, { dedupeKey: `transcode:${track.id}:${quality}` });
  }
  return original;
}

export async function transcodeJob(payload: Record<string, unknown>, ctx: JobContext) {
  const trackId = String(payload.trackId);
  const quality = String(payload.quality) as Quality;
  if (quality === 'original' || !(quality in QUALITY_KBPS)) throw new Error('Ungültige Qualitätsstufe');
  const track = await ctx.db.track.findUnique({ where: { id: trackId } });
  if (!track) throw new Error('Track nicht gefunden');
  const src = resolveInside(ctx.config.MUSIC_DIR, track.audioRelPath);
  const rel = `transcode/${trackId.slice(0, 2)}/${trackId}/${quality}.m4a`;
  const dest = resolveInside(ctx.config.cacheDir, rel);
  await fs.mkdir(path.dirname(dest), { recursive: true });
  const tmp = `${dest}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  await ctx.progress(0, 1, `Transkodiere „${track.title}“ (${quality})`);
  const kbps = QUALITY_KBPS[quality as Exclude<Quality, 'original'>];
  const args = [
    '-nostdin', '-hide_banner', '-v', 'error', '-y',
    '-i', src,
    '-map', '0:a:0', '-vn', '-map_metadata', '-1',
    '-c:a', 'aac', '-b:a', `${kbps}k`,
    '-threads', '1',
    '-movflags', '+faststart',
    '-f', 'mp4', tmp,
  ];
  const res = await runProcess(ctx.config.FFMPEG_PATH, args, { timeoutMs: 30 * 60_000 });
  if (res.code !== 0) {
    await fs.rm(tmp, { force: true });
    await ctx.db.libraryIssue.upsert({
      where: { kind_relPath: { kind: 'TRANSCODE_ERROR', relPath: track.audioRelPath } },
      create: { kind: 'TRANSCODE_ERROR', relPath: track.audioRelPath, trackId, message: res.stderr.slice(0, 1000), jobId: ctx.jobId },
      update: { message: res.stderr.slice(0, 1000), resolvedAt: null, jobId: ctx.jobId },
    });
    throw new Error(`ffmpeg fehlgeschlagen: ${res.stderr.trim().slice(0, 300)}`);
  }
  await fs.rename(tmp, dest);
  const st = await fs.stat(dest);
  await ctx.db.transcodedFile.upsert({
    where: { trackId_quality: { trackId, quality } },
    create: { trackId, quality, relPath: rel, fileSize: BigInt(st.size), sourceHash: track.contentHash },
    update: { relPath: rel, fileSize: BigInt(st.size), sourceHash: track.contentHash, createdAt: new Date() },
  });
  await ctx.progress(1, 1, 'Fertig');
  return { trackId, quality, bytes: st.size };
}
