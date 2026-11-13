import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../plugins/auth.js';
import { notFound } from '../lib/errors.js';
import { releaseInclude, toArtistDto, toReleaseDto, toTrackDto, trackInclude, trackOrder } from '../services/dto.js';
import type { Prisma } from '../db.js';

export const paging = {
  offset: z.coerce.number().int().min(0).max(100_000).default(0),
  limit: z.coerce.number().int().min(1).max(100).default(50),
};

export function page<T>(items: T[], offset: number, limit: number, total: number) {
  return { items, offset, limit, total, nextOffset: offset + items.length < total ? offset + items.length : null };
}

export default async function catalogRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  app.addHook('onRequest', app.requireUser);

  // ───────── Startseite: ausschließlich echte Bibliotheksinhalte
  app.get('/home', { schema: { tags: ['Katalog'] } }, async (req) => {
    const userId = authOf(req).userId;
    const recent = await app.db.$queryRaw<Array<{ trackId: string; lastPlayed: Date }>>`
      SELECT "trackId", max("playedAt") AS "lastPlayed" FROM "PlayHistory"
      WHERE "userId" = ${userId}::uuid GROUP BY "trackId" ORDER BY "lastPlayed" DESC LIMIT 12`;
    const recentTracks = await app.db.track.findMany({ where: { id: { in: recent.map((r) => r.trackId) } }, include: trackInclude });
    const recentSorted = recent.map((r) => recentTracks.find((t) => t.id === r.trackId)).filter((t) => !!t);
    const [newReleases, playlists, favoritesCount, followed] = await Promise.all([
      app.db.release.findMany({ where: { tracks: { some: { available: true } } }, orderBy: { createdAt: 'desc' }, take: 12, include: releaseInclude }),
      app.db.playlist.findMany({ where: { ownerId: userId }, orderBy: { updatedAt: 'desc' }, take: 12, include: { _count: { select: { entries: true } } } }),
      app.db.favoriteTrack.count({ where: { userId } }),
      app.db.followedArtist.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 12, include: { artist: true } }),
    ]);
    return {
      recentlyPlayed: recentSorted.map(toTrackDto),
      newReleases: newReleases.map(toReleaseDto),
      playlists: playlists.map((p) => ({ id: p.id, name: p.name, trackCount: p._count.entries, updatedAt: p.updatedAt.toISOString() })),
      favoritesCount,
      followedArtists: followed.map((f) => toArtistDto(f.artist)),
    };
  });

  // ───────── Künstler
  app.get(
    '/artists',
    {
      schema: {
        tags: ['Katalog'],
        querystring: z.object({ ...paging, sort: z.enum(['name', 'recent']).default('name'), withReleases: z.coerce.boolean().default(false) }),
      },
    },
    async (req) => {
      const { offset, limit, sort, withReleases } = req.query;
      const where: Prisma.ArtistWhereInput = withReleases ? { releases: { some: {} } } : { OR: [{ releases: { some: {} } }, { tracks: { some: {} } }] };
      const [items, total] = await Promise.all([
        app.db.artist.findMany({ where, orderBy: sort === 'name' ? { nameKey: 'asc' } : { createdAt: 'desc' }, skip: offset, take: limit }),
        app.db.artist.count({ where }),
      ]);
      return page(items.map(toArtistDto), offset, limit, total);
    },
  );

  app.get('/artists/:id', { schema: { tags: ['Katalog'], params: z.object({ id: z.uuid() }) } }, async (req) => {
    const userId = authOf(req).userId;
    const artist = await app.db.artist.findUnique({ where: { id: req.params.id } });
    if (!artist) throw notFound('Künstler nicht gefunden.');
    const [releases, appearsOn, following, trackCount] = await Promise.all([
      app.db.release.findMany({ where: { albumArtistId: artist.id }, orderBy: [{ year: 'desc' }, { createdAt: 'desc' }], include: releaseInclude }),
      app.db.release.findMany({
        where: { albumArtistId: { not: artist.id }, tracks: { some: { artists: { some: { artistId: artist.id } } } } },
        orderBy: [{ year: 'desc' }],
        include: releaseInclude,
        take: 50,
      }),
      app.db.followedArtist.findUnique({ where: { userId_artistId: { userId, artistId: artist.id } } }),
      app.db.track.count({ where: { artists: { some: { artistId: artist.id } } } }),
    ]);
    const popular = await app.db.track.findMany({
      where: { artists: { some: { artistId: artist.id } }, available: true },
      include: trackInclude,
      orderBy: [{ history: { _count: 'desc' } }, { createdAt: 'desc' }],
      take: 10,
    });
    return {
      artist: toArtistDto(artist),
      following: !!following,
      trackCount,
      releases: releases.map(toReleaseDto),
      appearsOn: appearsOn.map(toReleaseDto),
      topTracks: popular.map(toTrackDto),
    };
  });

  app.get(
    '/artists/:id/tracks',
    { schema: { tags: ['Katalog'], params: z.object({ id: z.uuid() }), querystring: z.object(paging) } },
    async (req) => {
      const { offset, limit } = req.query;
      const where: Prisma.TrackWhereInput = { artists: { some: { artistId: req.params.id } } };
      const [items, total] = await Promise.all([
        app.db.track.findMany({
          where,
          include: trackInclude,
          orderBy: [{ release: { year: 'desc' } }, { releaseId: 'asc' }, ...trackOrder],
          skip: offset,
          take: limit,
        }),
        app.db.track.count({ where }),
      ]);
      return page(items.map(toTrackDto), offset, limit, total);
    },
  );

  // ───────── Veröffentlichungen
  app.get(
    '/releases',
    {
      schema: {
        tags: ['Katalog'],
        querystring: z.object({
          ...paging,
          type: z.enum(['ALBUM', 'EP', 'SINGLE']).optional(),
          artistId: z.uuid().optional(),
          sort: z.enum(['recent', 'title', 'year']).default('recent'),
        }),
      },
    },
    async (req) => {
      const { offset, limit, type, artistId, sort } = req.query;
      const where: Prisma.ReleaseWhereInput = { type, albumArtistId: artistId, tracks: { some: {} } };
      const orderBy: Prisma.ReleaseOrderByWithRelationInput[] =
        sort === 'title' ? [{ title: 'asc' }] : sort === 'year' ? [{ year: { sort: 'desc', nulls: 'last' } }, { title: 'asc' }] : [{ createdAt: 'desc' }];
      const [items, total] = await Promise.all([
        app.db.release.findMany({ where, orderBy, skip: offset, take: limit, include: releaseInclude }),
        app.db.release.count({ where }),
      ]);
      return page(items.map(toReleaseDto), offset, limit, total);
    },
  );

  app.get('/releases/:id', { schema: { tags: ['Katalog'], params: z.object({ id: z.uuid() }) } }, async (req) => {
    const userId = authOf(req).userId;
    const release = await app.db.release.findUnique({ where: { id: req.params.id }, include: releaseInclude });
    if (!release) throw notFound('Veröffentlichung nicht gefunden.');
    const [tracks, saved] = await Promise.all([
      app.db.track.findMany({ where: { releaseId: release.id }, include: trackInclude, orderBy: trackOrder }),
      app.db.savedRelease.findUnique({ where: { userId_releaseId: { userId, releaseId: release.id } } }),
    ]);
    const durationMs = tracks.reduce((s, t) => s + t.durationMs, 0);
    return { release: { ...toReleaseDto(release), durationMs }, saved: !!saved, tracks: tracks.map(toTrackDto) };
  });

  // ───────── Tracks
  app.get('/tracks/:id', { schema: { tags: ['Katalog'], params: z.object({ id: z.uuid() }) } }, async (req) => {
    const t = await app.db.track.findUnique({ where: { id: req.params.id }, include: trackInclude });
    if (!t) throw notFound('Song nicht gefunden.');
    return { track: toTrackDto(t) };
  });

  /**
   * Autoplay: ähnliche, abspielbare Titel in zufälliger Reihenfolge.
   * Stufen: 1) gleiches Genre UND gemeinsamer Künstler, 2) gleiches Genre, 3) gemeinsamer Künstler
   * (Track-Künstler oder Albumkünstler). Der Ausgangstitel und `exclude` werden nie geliefert.
   * Keine Treffer → leere Liste (die Wiedergabe endet regulär).
   */
  app.get(
    '/tracks/:id/similar',
    {
      schema: {
        tags: ['Katalog'],
        params: z.object({ id: z.uuid() }),
        querystring: z.object({
          limit: z.coerce.number().int().min(1).max(50).default(20),
          /** Kommagetrennte Track-IDs (z. B. zuletzt gespielte), höchstens 200 */
          exclude: z.string().max(200 * 37).optional(),
        }),
      },
    },
    async (req) => {
      const base = await app.db.track.findUnique({
        where: { id: req.params.id },
        select: { id: true, genre: true, release: { select: { genre: true, albumArtistId: true } }, artists: { select: { artistId: true } } },
      });
      if (!base) throw notFound('Song nicht gefunden.');
      const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const exclude = [base.id, ...(req.query.exclude ?? '').split(',').map((x) => x.trim()).filter((x) => uuid.test(x))].slice(0, 201);
      const genre = (base.genre ?? base.release.genre)?.trim().toLowerCase() || null;
      const artistIds = [...new Set([...base.artists.map((a) => a.artistId), base.release.albumArtistId])];
      const rows = await app.db.$queryRaw<Array<{ id: string; tier: number }>>`
        WITH c AS (
          SELECT t.id,
            (${genre}::text IS NOT NULL AND lower(trim(coalesce(t.genre, r.genre))) = ${genre}::text) AS same_genre,
            (r."albumArtistId" = ANY(${artistIds}::uuid[])
              OR EXISTS (SELECT 1 FROM "TrackArtist" ta WHERE ta."trackId" = t.id AND ta."artistId" = ANY(${artistIds}::uuid[]))) AS same_artist
          FROM "Track" t JOIN "Release" r ON r.id = t."releaseId"
          WHERE t.available AND NOT (t.id = ANY(${exclude}::uuid[]))
        )
        SELECT id, CASE WHEN same_genre AND same_artist THEN 1 WHEN same_genre THEN 2 ELSE 3 END AS tier
        FROM c WHERE same_genre OR same_artist
        ORDER BY tier, random()
        LIMIT ${req.query.limit}`;
      const tracks = await app.db.track.findMany({ where: { id: { in: rows.map((r) => r.id) } }, include: trackInclude });
      const byId = new Map(tracks.map((t) => [t.id, t]));
      return {
        items: rows
          .map((r) => byId.get(r.id))
          .filter((t) => !!t)
          .map(toTrackDto),
      };
    },
  );

  // Mehrere Tracks auf einmal (z. B. Wiederherstellung der Warteschlange)
  app.post('/tracks/batch', { schema: { tags: ['Katalog'], body: z.object({ ids: z.array(z.uuid()).max(500) }) } }, async (req) => {
    const tracks = await app.db.track.findMany({ where: { id: { in: req.body.ids } }, include: trackInclude });
    const byId = new Map(tracks.map((t) => [t.id, toTrackDto(t)]));
    return { items: req.body.ids.map((id) => byId.get(id)).filter((t) => !!t) };
  });
}
