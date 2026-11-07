import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import { parseFile, type IAudioMetadata } from 'music-metadata';
import sharp from 'sharp';

/** Begrenzung, damit ein manipuliertes Bild keine Ressourcen erschöpft */
sharp.concurrency(1);
const MAX_IMAGE_PIXELS = 100_000_000;

export interface ProbeResult {
  durationMs: number;
  codec: string | null;
  container: string | null;
  bitrate: number | null;
  sampleRate: number | null;
  channels: number | null;
  bitDepth: number | null;
}

export interface AudioTags {
  title?: string;
  artist?: string;
  artists?: string[];
  albumArtist?: string;
  album?: string;
  year?: number;
  genre?: string;
  trackNumber?: number;
  trackTotal?: number;
  discNumber?: number;
  discTotal?: number;
}

export interface EmbeddedPicture {
  data: Uint8Array;
  format: string;
}

export function runProcess(
  cmd: string,
  args: string[],
  opts: { timeoutMs?: number; maxOutput?: number } = {},
): Promise<{ code: number; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const max = opts.maxOutput ?? 4 * 1024 * 1024;
    child.stdout.on('data', (d: Buffer) => {
      if (stdout.length < max) stdout += d.toString('utf8');
    });
    child.stderr.on('data', (d: Buffer) => {
      if (stderr.length < 64 * 1024) stderr += d.toString('utf8');
    });
    const timer = opts.timeoutMs
      ? setTimeout(() => {
          child.kill('SIGKILL');
        }, opts.timeoutMs)
      : null;
    child.on('error', (e) => {
      if (timer) clearTimeout(timer);
      reject(e);
    });
    child.on('close', (code) => {
      if (timer) clearTimeout(timer);
      resolve({ code: code ?? -1, stdout, stderr });
    });
  });
}

/**
 * Prüft eine Audiodatei tatsächlich mit ffprobe (nicht anhand von Endung/MIME).
 * Wirft, wenn keine dekodierbare Audiospur vorhanden ist.
 */
export async function probeAudio(ffprobe: string, file: string): Promise<ProbeResult> {
  const { code, stdout, stderr } = await runProcess(
    ffprobe,
    ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', '-select_streams', 'a', file],
    { timeoutMs: 60_000 },
  );
  if (code !== 0) throw new Error(`ffprobe konnte die Datei nicht lesen: ${stderr.trim().slice(0, 300)}`);
  const json = JSON.parse(stdout) as {
    streams?: Array<Record<string, string | number | undefined>>;
    format?: Record<string, string | number | undefined>;
  };
  const stream = json.streams?.find((s) => s.codec_type === 'audio');
  if (!stream) throw new Error('Keine Audiospur gefunden.');
  const duration = Number(stream.duration ?? json.format?.duration ?? 0);
  if (!Number.isFinite(duration) || duration <= 0) throw new Error('Audiodauer konnte nicht ermittelt werden.');
  const num = (v: unknown) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
  };
  return {
    durationMs: Math.round(duration * 1000),
    codec: (stream.codec_name as string) ?? null,
    container: (json.format?.format_name as string)?.split(',')[0] ?? null,
    bitrate: num(stream.bit_rate ?? json.format?.bit_rate),
    sampleRate: num(stream.sample_rate),
    channels: num(stream.channels),
    bitDepth: num(stream.bits_per_raw_sample ?? stream.bits_per_sample),
  };
}

/** Tags und eingebettetes Cover lesen; Fehler hier sind nicht fatal. */
export async function readTags(file: string): Promise<{ tags: AudioTags; picture: EmbeddedPicture | null }> {
  let meta: IAudioMetadata;
  try {
    meta = await parseFile(file, { duration: false, skipCovers: false });
  } catch {
    return { tags: {}, picture: null };
  }
  const c = meta.common;
  const clean = (s: string | undefined | null) => (s && s.trim() ? s.trim() : undefined);
  const tags: AudioTags = {
    title: clean(c.title),
    artist: clean(c.artist),
    artists: c.artists?.map((a) => a.trim()).filter(Boolean),
    albumArtist: clean(c.albumartist),
    album: clean(c.album),
    year: c.year && c.year > 0 && c.year < 10000 ? c.year : undefined,
    genre: clean(c.genre?.[0]),
    trackNumber: c.track?.no ?? undefined,
    trackTotal: c.track?.of ?? undefined,
    discNumber: c.disk?.no ?? undefined,
    discTotal: c.disk?.of ?? undefined,
  };
  const pic = c.picture?.find((p) => /front/i.test(p.type ?? '')) ?? c.picture?.[0];
  return { tags, picture: pic ? { data: pic.data, format: pic.format } : null };
}

export interface ImageInfo {
  format: 'jpeg' | 'png' | 'webp';
  width: number;
  height: number;
}

/** Prüft Bilddaten tatsächlich (Dekodierung der Kopfdaten durch libvips). */
export async function probeImage(input: string | Buffer | Uint8Array): Promise<ImageInfo> {
  const meta = await sharp(input as string | Buffer, { limitInputPixels: MAX_IMAGE_PIXELS, failOn: 'error' }).metadata();
  if (!meta.format || !['jpeg', 'png', 'webp'].includes(meta.format)) {
    throw new Error('Nicht unterstütztes Bildformat (erlaubt: JPEG, PNG, WebP).');
  }
  if (!meta.width || !meta.height || meta.width < 16 || meta.height < 16) throw new Error('Bild ist zu klein.');
  if (meta.width > 12000 || meta.height > 12000) throw new Error('Bild ist zu groß (max. 12000 px).');
  return { format: meta.format as ImageInfo['format'], width: meta.width, height: meta.height };
}

/** Vollständig dekodieren (erkennt beschädigte Bilder) und als JPEG-Variante schreiben. */
export async function renderImageVariant(
  src: string | Buffer,
  dest: string,
  size: number | null,
  crop?: { left: number; top: number; width: number; height: number },
): Promise<void> {
  let img = sharp(src as string | Buffer, { limitInputPixels: MAX_IMAGE_PIXELS, failOn: 'error' }).rotate();
  if (crop) img = img.extract(crop);
  if (size) img = img.resize(size, size, { fit: 'cover', withoutEnlargement: true });
  const tmp = `${dest}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  await img.jpeg({ quality: 86, mozjpeg: true }).toFile(tmp);
  await fs.rename(tmp, dest);
}

/**
 * Schneller Inhalts-Fingerabdruck: Größe + erste und letzte MiB.
 * Erkennt verschobene/umbenannte Dateien ohne komplettes Einlesen großer FLACs.
 */
export async function contentFingerprint(file: string): Promise<{ hash: string; size: number; mtime: Date }> {
  const fh = await fs.open(file, 'r');
  try {
    const st = await fh.stat();
    const chunk = 1024 * 1024;
    const h = crypto.createHash('sha256');
    h.update(String(st.size));
    const head = Buffer.alloc(Math.min(chunk, st.size));
    await fh.read(head, 0, head.length, 0);
    h.update(head);
    if (st.size > chunk) {
      const tailLen = Math.min(chunk, st.size - chunk);
      const tail = Buffer.alloc(tailLen);
      await fh.read(tail, 0, tailLen, st.size - tailLen);
      h.update(tail);
    }
    return { hash: h.digest('hex'), size: st.size, mtime: st.mtime };
  } finally {
    await fh.close();
  }
}

export async function sha256File(file: string): Promise<string> {
  const h = crypto.createHash('sha256');
  const fh = await fs.open(file, 'r');
  try {
    for await (const chunk of fh.createReadStream()) h.update(chunk as Buffer);
  } finally {
    await fh.close().catch(() => undefined);
  }
  return h.digest('hex');
}

/** Künstlerangaben aus Tags/Ordnernamen aufteilen: Hauptkünstler + Features */
export function splitArtists(raw: string | undefined, title?: string): { primary: string[]; featured: string[] } {
  const primary: string[] = [];
  const featured: string[] = [];
  if (raw) {
    const [main, ...feat] = raw.split(/\s+(?:feat\.?|ft\.?|featuring)\s+/i);
    for (const p of (main ?? '').split(/\s*;\s*|\s*\/\s*|\s*\\\\\s*/)) if (p.trim()) primary.push(p.trim());
    for (const f of feat) for (const p of f.split(/\s*[;,&]\s*/)) if (p.trim()) featured.push(p.trim());
  }
  if (title) {
    const m = title.match(/[([]\s*(?:feat\.?|ft\.?|featuring)\s+([^)\]]+)[)\]]/i);
    if (m?.[1]) for (const p of m[1].split(/\s*[;,&]\s*/)) if (p.trim()) featured.push(p.trim());
  }
  const uniq = (arr: string[]) => [...new Map(arr.map((a) => [a.toLowerCase(), a])).values()];
  const prim = uniq(primary);
  return { primary: prim, featured: uniq(featured).filter((f) => !prim.some((p) => p.toLowerCase() === f.toLowerCase())) };
}

export function pictureExtension(format: string): string {
  if (/png/i.test(format)) return 'png';
  if (/webp/i.test(format)) return 'webp';
  return 'jpg';
}
