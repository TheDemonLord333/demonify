import path from 'node:path';
import { sanitizeSegment } from '../lib/fsnames.js';
import { nameKey } from '../lib/normalize.js';

/**
 * Verbindliche Ablage:  <Künstler>/<Alben|EPs|Singles>/<JJJJ - Titel>/[<NN - Titel>/]audio.ext
 * Mehrere Discs: Trackordner "D-NN - Titel" (z. B. "2-03 - Titel") oder Zwischenordner "Disc 2"/"CD 2".
 * Sampler: Albumkünstler "Various Artists", Trackordner "NN - Künstler - Titel".
 */
export type ReleaseTypeName = 'ALBUM' | 'EP' | 'SINGLE';

export const TYPE_DIR_NAMES: Record<ReleaseTypeName, string> = {
  ALBUM: 'Alben',
  EP: 'EPs',
  SINGLE: 'Singles',
};

const TYPE_ALIASES: Record<string, ReleaseTypeName> = {
  alben: 'ALBUM',
  albums: 'ALBUM',
  album: 'ALBUM',
  eps: 'EP',
  ep: 'EP',
  singles: 'SINGLE',
  single: 'SINGLE',
};

export const VARIOUS_ARTISTS = 'Various Artists';
export const isVariousArtists = (name: string) => nameKey(name) === nameKey(VARIOUS_ARTISTS);

export interface ParsedLocation {
  structured: boolean;
  artistFolder: string | null;
  artistFolderRel: string | null;
  type: ReleaseTypeName | null;
  releaseFolderRel: string;
  releaseYear: number | null;
  releaseTitle: string | null;
  /** Ordner des Tracks, wenn der Track einen eigenen Unterordner besitzt */
  trackFolderRel: string | null;
  discNumber: number | null;
  trackNumber: number | null;
  trackTitle: string | null;
  /** Künstler aus "NN - Künstler - Titel" (Sampler) */
  trackArtist: string | null;
}

const ID_SUFFIX = /\s*\[[0-9a-f]{6,12}(?:-[0-9a-f]{4})?\]$/i;
const RELEASE_RE = /^(\d{4})\s+-\s+(.+)$/;
const TRACK_RE = /^(?:(\d{1,2})-)?(\d{1,3})\s*(?:-|\.)\s*(.+)$/;
const DISC_RE = /^(?:disc|cd|disk)\s*(\d{1,2})$/i;

export function stripIdSuffix(name: string): string {
  return name.replace(ID_SUFFIX, '').trim();
}

export function parseReleaseFolder(name: string): { year: number | null; title: string } {
  const clean = stripIdSuffix(name);
  const m = clean.match(RELEASE_RE);
  if (m) return { year: Number(m[1]), title: m[2]!.trim() };
  return { year: null, title: clean };
}

export function parseTrackName(name: string, various: boolean): {
  disc: number | null;
  track: number | null;
  title: string;
  artist: string | null;
} {
  const clean = stripIdSuffix(name);
  const m = clean.match(TRACK_RE);
  let disc: number | null = null;
  let track: number | null = null;
  let rest = clean;
  if (m) {
    disc = m[1] ? Number(m[1]) : null;
    track = Number(m[2]);
    rest = m[3]!.trim();
  }
  let artist: string | null = null;
  if (various) {
    const idx = rest.indexOf(' - ');
    if (idx > 0) {
      artist = rest.slice(0, idx).trim();
      rest = rest.slice(idx + 3).trim();
    }
  }
  return { disc, track, title: rest, artist };
}

export function parseLocation(relPath: string): ParsedLocation {
  const segs = relPath.split('/');
  const fileBase = path.posix.basename(relPath, path.posix.extname(relPath));
  const type = segs.length >= 4 ? TYPE_ALIASES[segs[1]!.toLowerCase()] ?? null : null;

  if (type && segs.length >= 4) {
    const artistFolder = segs[0]!;
    const various = isVariousArtists(artistFolder);
    const releaseFolderRel = segs.slice(0, 3).join('/');
    const rel = parseReleaseFolder(segs[2]!);
    const inner = segs.slice(3, -1); // Ordner zwischen Veröffentlichung und Datei
    let disc: number | null = null;
    let trackFolder: string | null = null;
    for (const s of inner) {
      const dm = s.match(DISC_RE);
      if (dm && trackFolder === null) disc = Number(dm[1]);
      else trackFolder = s;
    }
    const trackFolderRel = trackFolder ? segs.slice(0, -1).join('/') : null;
    // Bei Track-Unterordnern beschreibt der Ordnername den Track ("01 - Titel"),
    // sonst der Dateiname ("01 - Titel.mp3"); "audio.flac" o. Ä. liefert keine Info.
    const source = trackFolder ?? (/^(audio|track)$/i.test(fileBase) ? null : fileBase);
    const parsed = source ? parseTrackName(source, various) : null;
    return {
      structured: true,
      artistFolder,
      artistFolderRel: artistFolder,
      type,
      releaseFolderRel,
      releaseYear: rel.year,
      releaseTitle: rel.title,
      trackFolderRel,
      discNumber: parsed?.disc ?? disc,
      trackNumber: parsed?.track ?? null,
      trackTitle: parsed?.title ?? null,
      trackArtist: parsed?.artist ?? null,
    };
  }

  // Unstrukturierte Ablage: Tags entscheiden, Ordner der Datei = Veröffentlichung
  const parsed = parseTrackName(fileBase, false);
  return {
    structured: false,
    artistFolder: null,
    artistFolderRel: null,
    type: null,
    releaseFolderRel: path.posix.dirname(relPath) === '.' ? '' : path.posix.dirname(relPath),
    releaseYear: null,
    releaseTitle: null,
    trackFolderRel: null,
    discNumber: parsed.disc,
    trackNumber: parsed.track,
    trackTitle: parsed.title,
    trackArtist: null,
  };
}

/** Ordnernamen für neue Ablagen (Upload) */
export function releaseFolderName(year: number | null | undefined, title: string): string {
  const t = sanitizeSegment(title);
  return year ? `${year} - ${t}` : t;
}

export function trackFolderName(opts: {
  disc: number;
  track: number;
  title: string;
  multiDisc: boolean;
  artistPrefix?: string | null;
}): string {
  const num = String(opts.track).padStart(2, '0');
  const prefix = opts.multiDisc ? `${opts.disc}-${num}` : num;
  const title = opts.artistPrefix ? `${opts.artistPrefix} - ${opts.title}` : opts.title;
  return `${prefix} - ${sanitizeSegment(title)}`;
}
