import type { Prisma } from '../db.js';

/** Gemeinsame Includes für Track-Antworten */
export const trackInclude = {
  artists: { include: { artist: { select: { id: true, name: true, imageId: true } } }, orderBy: [{ role: 'asc' }, { position: 'asc' }] },
  release: { select: { id: true, title: true, type: true, year: true, coverImageId: true, albumArtist: { select: { id: true, name: true } } } },
} satisfies Prisma.TrackInclude;

export type TrackWithRelations = Prisma.TrackGetPayload<{ include: typeof trackInclude }>;

export interface TrackDto {
  id: string;
  title: string;
  discNumber: number;
  trackNumber: number;
  durationMs: number;
  available: boolean;
  genre: string | null;
  year: number | null;
  codec: string | null;
  bitrate: number | null;
  sampleRate: number | null;
  /** Effektives Cover: individuelles Songcover, sonst Veröffentlichungscover, sonst null (→ Platzhalter) */
  coverImageId: string | null;
  hasOwnCover: boolean;
  artists: Array<{ id: string; name: string; role: 'PRIMARY' | 'FEATURED' }>;
  release: {
    id: string;
    title: string;
    type: 'ALBUM' | 'EP' | 'SINGLE';
    year: number | null;
    coverImageId: string | null;
    albumArtist: { id: string; name: string };
  };
}

export function toTrackDto(t: TrackWithRelations): TrackDto {
  return {
    id: t.id,
    title: t.title,
    discNumber: t.discNumber,
    trackNumber: t.trackNumber,
    durationMs: t.durationMs,
    available: t.available,
    genre: t.genre,
    year: t.year ?? t.release.year,
    codec: t.codec,
    bitrate: t.bitrate,
    sampleRate: t.sampleRate,
    coverImageId: t.coverImageId ?? t.release.coverImageId ?? null,
    hasOwnCover: t.coverImageId !== null,
    artists: t.artists.map((a) => ({ id: a.artist.id, name: a.artist.name, role: a.role })),
    release: {
      id: t.release.id,
      title: t.release.title,
      type: t.release.type,
      year: t.release.year,
      coverImageId: t.release.coverImageId,
      albumArtist: t.release.albumArtist,
    },
  };
}

export const releaseInclude = {
  albumArtist: { select: { id: true, name: true, imageId: true } },
  _count: { select: { tracks: true } },
} satisfies Prisma.ReleaseInclude;

export type ReleaseWithRelations = Prisma.ReleaseGetPayload<{ include: typeof releaseInclude }>;

export function toReleaseDto(r: ReleaseWithRelations) {
  return {
    id: r.id,
    title: r.title,
    type: r.type,
    year: r.year,
    genre: r.genre,
    coverImageId: r.coverImageId,
    albumArtist: { id: r.albumArtist.id, name: r.albumArtist.name },
    trackCount: r._count.tracks,
    createdAt: r.createdAt.toISOString(),
  };
}

export function toArtistDto(a: { id: string; name: string; imageId: string | null; createdAt?: Date }) {
  return { id: a.id, name: a.name, imageId: a.imageId };
}

export const trackOrder: Prisma.TrackOrderByWithRelationInput[] = [{ discNumber: 'asc' }, { trackNumber: 'asc' }, { title: 'asc' }];
