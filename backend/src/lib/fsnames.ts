import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

/**
 * Sichere Dateisystemnamen.
 * - Unicode NFC
 * - Verbotene Zeichen (Windows/macOS/Linux) und Steuerzeichen → Ersatz
 * - Keine Namen aus nur Punkten, keine führenden/abschließenden Punkte/Leerzeichen
 * - Reservierte Windows-Gerätenamen werden ergänzt
 * - Länge auf 120 UTF-8-Bytes begrenzt (Platz für ID-Zusatz)
 */
const FORBIDDEN = /[<>:"/\\|?*\u0000-\u001F\u007F]/gu;
const RESERVED = /^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$/i;

export function sanitizeSegment(input: string, fallback = 'Unbenannt'): string {
  let s = input.normalize('NFC').replace(FORBIDDEN, ' ').replace(/\s+/gu, ' ').trim();
  s = s.replace(/^[.\s]+|[.\s]+$/gu, '');
  if (!s) s = fallback;
  if (RESERVED.test(s)) s = `_${s}`;
  return truncateBytes(s, 120).replace(/[.\s]+$/u, '') || fallback;
}

function truncateBytes(s: string, maxBytes: number): string {
  if (Buffer.byteLength(s, 'utf8') <= maxBytes) return s;
  let out = '';
  for (const ch of s) {
    if (Buffer.byteLength(out + ch, 'utf8') > maxBytes) break;
    out += ch;
  }
  return out;
}

export function shortId(id: string): string {
  return id.replace(/-/g, '').slice(0, 8);
}

/**
 * Löst einen relativen Pfad innerhalb von root auf und verhindert Pfad-Traversal.
 * Wirft bei absoluten Pfaden, "..", NUL-Bytes oder Pfaden außerhalb von root.
 */
export function resolveInside(root: string, relPath: string): string {
  if (relPath.includes('\0')) throw new Error('Ungültiger Pfad');
  if (path.isAbsolute(relPath) || /^[a-zA-Z]:/.test(relPath)) throw new Error('Absoluter Pfad nicht erlaubt');
  const resolvedRoot = path.resolve(root);
  const full = path.resolve(resolvedRoot, relPath);
  const rel = path.relative(resolvedRoot, full);
  if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('Pfad außerhalb des erlaubten Bereichs');
  return full;
}

/** Relativer Pfad mit Schrägstrichen (plattformunabhängig in der DB) */
export function toRel(root: string, full: string): string {
  return path.relative(root, full).split(path.sep).join('/');
}

async function listLower(dir: string): Promise<Set<string>> {
  try {
    const entries = await fs.readdir(dir);
    return new Set(entries.map((e) => e.normalize('NFC').toLowerCase()));
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === 'ENOENT') return new Set();
    throw e;
  }
}

/**
 * Legt einen neuen, eindeutigen Ordner an. Kollidiert der bereinigte Name (auch nur in
 * Groß-/Kleinschreibung) mit einem vorhandenen Eintrag, wird ein stabiler ID-Zusatz
 * " [abcd1234]" angehängt. Vorhandene Ordner werden nie wiederverwendet → keine
 * versehentliche Zusammenführung verschiedener Einträge.
 */
export async function createUniqueDir(parent: string, baseName: string, stableId: string): Promise<string> {
  await fs.mkdir(parent, { recursive: true });
  const existing = await listLower(parent);
  const candidates = [baseName, `${baseName} [${shortId(stableId)}]`];
  for (let i = 0; i < 20; i++) candidates.push(`${baseName} [${shortId(stableId)}-${crypto.randomBytes(2).toString('hex')}]`);
  for (const name of candidates) {
    if (existing.has(name.normalize('NFC').toLowerCase())) continue;
    const full = path.join(parent, name);
    try {
      await fs.mkdir(full); // nicht rekursiv → schlägt fehl, wenn inzwischen vorhanden
      return full;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'EEXIST') continue;
      throw e;
    }
  }
  throw new Error(`Kein eindeutiger Ordnername für "${baseName}" möglich`);
}

/** Ordner sicherstellen (für Künstler-/Typordner, die bewusst geteilt werden). */
export async function ensureDir(full: string): Promise<void> {
  await fs.mkdir(full, { recursive: true });
}

/**
 * Datei an Ziel kopieren, ohne jemals eine vorhandene Datei zu überschreiben.
 * Kopiert zunächst in eine temporäre Datei im Zielordner und verknüpft sie dann
 * exklusiv (link schlägt fehl, wenn das Ziel existiert).
 */
export async function placeFileExclusive(src: string, dest: string): Promise<void> {
  const tmp = path.join(path.dirname(dest), `.${path.basename(dest)}.${crypto.randomBytes(4).toString('hex')}.partial`);
  await fs.copyFile(src, tmp, fs.constants.COPYFILE_EXCL);
  try {
    await fs.link(tmp, dest);
  } finally {
    await fs.rm(tmp, { force: true });
  }
}

export const AUDIO_EXTENSIONS = new Set(['.mp3', '.flac', '.m4a', '.aac', '.mp4', '.ogg', '.oga', '.opus', '.wav']);
export const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
export const COVER_BASENAMES = ['cover', 'folder', 'front', 'album'];
export const ARTIST_IMAGE_BASENAMES = ['artist'];
