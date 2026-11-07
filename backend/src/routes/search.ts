import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { Prisma } from '../db.js';
import { authOf } from '../plugins/auth.js';
import { escapeLike, normalizeQuery } from '../lib/normalize.js';
import { releaseInclude, toArtistDto, toReleaseDto, toTrackDto, trackInclude } from '../services/dto.js';
import type { Db } from '../db.js';

/**
 * Suche über gespeicherte Metadaten in PostgreSQL (pg_trgm-GIN-Indizes auf searchText).
 * - Groß-/Kleinschreibung und Diakritika werden ignoriert (normalisierter searchText)
 * - 1 Zeichen: Wortanfangssuche, ab 2 Zeichen: Teilwortsuche
 * - Mehrere Wörter: jedes Wort muss in Titel, Künstler (inkl. Features) oder Veröffentlichung vorkommen
 */
function tokens(q: string): string[] {
  return normalizeQuery(q).split(' ').filter(Boolean).slice(0, 6);
}

function like(col: Prisma.Sql, tok: string): Prisma.Sql {
  const e = escapeLike(tok);
  if (tok.length === 1) return Prisma.sql`(${col} LIKE ${`${e}%`} OR ${col} LIKE ${`% ${e}%`})`;
  return Prisma.sql`${col} LIKE ${`%${e}%`}`;
}

const T = Prisma.raw('t."searchText"');
const R = Prisma.raw('r."searchText"');
const A = Prisma.raw('a."searchText"');
const AA = Prisma.raw('aa."searchText"');
const P = Prisma.raw('p."searchText"');

function trackTokenCond(tok: string): Prisma.Sql {
  return Prisma.sql`(
    ${like(T, tok)} OR ${like(R, tok)}
    OR EXISTS (SELECT 1 FROM "TrackArtist" ta JOIN "Artist" a ON a.id = ta."artistId" WHERE ta."trackId" = t.id AND ${like(A, tok)})
    OR ${like(AA, tok)}
  )`;
}

async function searchTracks(db: Db, q: string, offset: number, limit: number) {
  const toks = tokens(q);
  if (!toks.length) return { ids: [] as string[], total: 0 };
  const full = escapeLike(normalizeQuery(q));
  const where = Prisma.join(toks.map(trackTokenCond), ' AND ');
  const rows = await db.$queryRaw<Array<{ id: string; total: bigint }>>`
    SELECT t.id, count(*) OVER() AS total
    FROM "Track" t
    JOIN "Release" r ON r.id = t."releaseId"
    JOIN "Artist" aa ON aa.id = r."albumArtistId"
    WHERE ${where}
    ORDER BY
      CASE WHEN t."searchText" LIKE ${`${full}%`} THEN 0 WHEN t."searchText" LIKE ${`%${full}%`} THEN 1 ELSE 2 END,
      t.available DESC, t.title ASC, r.year DESC NULLS LAST, t.id
    OFFSET ${offset} LIMIT ${limit}`;
  return { ids: rows.map((r) => r.id), total: Number(rows[0]?.total ?? 0) };
}

async function searchArtists(db: Db, q: string, offset: number, limit: number) {
  const toks = tokens(q);
  if (!toks.length) return { ids: [] as string[], total: 0 };
  const full = escapeLike(normalizeQuery(q));
  const where = Prisma.join(toks.map((t) => like(A, t)), ' AND ');
  const rows = await db.$queryRaw<Array<{ id: string; total: bigint }>>`
    SELECT a.id, count(*) OVER() AS total FROM "Artist" a
    WHERE ${where}
      AND (EXISTS (SELECT 1 FROM "Release" r WHERE r."albumArtistId" = a.id) OR EXISTS (SELECT 1 FROM "TrackArtist" ta WHERE ta."artistId" = a.id))
    ORDER BY CASE WHEN a."searchText" LIKE ${`${full}%`} THEN 0 ELSE 1 END, a."nameKey", a.id
    OFFSET ${offset} LIMIT ${limit}`;
  return { ids: rows.map((r) => r.id), total: Number(rows[0]?.total ?? 0) };
}

async function searchReleases(db: Db, q: string, offset: number, limit: number) {
  const toks = tokens(q);
  if (!toks.length) return { ids: [] as string[], total: 0 };
  const full = escapeLike(normalizeQuery(q));
  const where = Prisma.join(toks.map((t) => Prisma.sql`(${like(R, t)} OR ${like(AA, t)})`), ' AND ');
  const rows = await db.$queryRaw<Array<{ id: string; total: bigint }>>`
    SELECT r.id, count(*) OVER() AS total FROM "Release" r JOIN "Artist" aa ON aa.id = r."albumArtistId"
    WHERE ${where} AND EXISTS (SELECT 1 FROM "Track" t WHERE t."releaseId" = r.id)
    ORDER BY CASE WHEN r."searchText" LIKE ${`${full}%`} THEN 0 WHEN r."searchText" LIKE ${`%${full}%`} THEN 1 ELSE 2 END, r.title, r.year DESC NULLS LAST, r.id
    OFFSET ${offset} LIMIT ${limit}`;
  return { ids: rows.map((r) => r.id), total: Number(rows[0]?.total ?? 0) };
}

async function searchPlaylists(db: Db, userId: string, q: string, offset: number, limit: number) {
  const toks = tokens(q);
  if (!toks.length) return { ids: [] as string[], total: 0 };
  const where = Prisma.join(toks.map((t) => like(P, t)), ' AND ');
  const rows = await db.$queryRaw<Array<{ id: string; total: bigint }>>`
    SELECT p.id, count(*) OVER() AS total FROM "Playlist" p
    WHERE p."ownerId" = ${userId}::uuid AND ${where}
    ORDER BY p.name, p.id OFFSET ${offset} LIMIT ${limit}`;
  return { ids: rows.map((r) => r.id), total: Number(rows[0]?.total ?? 0) };
}

function ordered<T extends { id: string }>(ids: string[], items: T[]): T[] {
  const m = new Map(items.map((i) => [i.id, i]));
  return ids.map((id) => m.get(id)).filter((x): x is T => !!x);
}

export default async function searchRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  app.addHook('onRequest', app.requireUser);

  const loadTracks = async (ids: string[]) => ordered(ids, await app.db.track.findMany({ where: { id: { in: ids } }, include: trackInclude })).map(toTrackDto);
  const loadArtists = async (ids: string[]) => ordered(ids, await app.db.artist.findMany({ where: { id: { in: ids } } })).map(toArtistDto);
  const loadReleases = async (ids: string[]) => ordered(ids, await app.db.release.findMany({ where: { id: { in: ids } }, include: releaseInclude })).map(toReleaseDto);
  const loadPlaylists = async (ids: string[]) =>
    ordered(ids, await app.db.playlist.findMany({ where: { id: { in: ids } }, include: { _count: { select: { entries: true } } } })).map((p) => ({
      id: p.id,
      name: p.name,
      trackCount: p._count.entries,
      updatedAt: p.updatedAt.toISOString(),
    }));

  app.get(
    '/',
    { schema: { tags: ['Suche'], querystring: z.object({ q: z.string().max(200).default(''), limit: z.coerce.number().int().min(1).max(20).default(8) }) } },
    async (req) => {
      const { q, limit } = req.query;
      const userId = authOf(req).userId;
      const [t, a, r, p] = await Promise.all([
        searchTracks(app.db, q, 0, limit),
        searchArtists(app.db, q, 0, limit),
        searchReleases(app.db, q, 0, limit),
        searchPlaylists(app.db, userId, q, 0, limit),
      ]);
      const [tracks, artists, releases, playlists] = await Promise.all([loadTracks(t.ids), loadArtists(a.ids), loadReleases(r.ids), loadPlaylists(p.ids)]);
      return {
        query: q,
        tracks: { items: tracks, total: t.total },
        artists: { items: artists, total: a.total },
        releases: { items: releases, total: r.total },
        playlists: { items: playlists, total: p.total },
      };
    },
  );

  app.get(
    '/:type',
    {
      schema: {
        tags: ['Suche'],
        params: z.object({ type: z.enum(['tracks', 'artists', 'releases', 'playlists']) }),
        querystring: z.object({
          q: z.string().max(200).default(''),
          offset: z.coerce.number().int().min(0).max(10_000).default(0),
          limit: z.coerce.number().int().min(1).max(50).default(30),
        }),
      },
    },
    async (req) => {
      const { q, offset, limit } = req.query;
      const userId = authOf(req).userId;
      let res: { ids: string[]; total: number };
      let items: unknown[];
      switch (req.params.type) {
        case 'tracks':
          res = await searchTracks(app.db, q, offset, limit);
          items = await loadTracks(res.ids);
          break;
        case 'artists':
          res = await searchArtists(app.db, q, offset, limit);
          items = await loadArtists(res.ids);
          break;
        case 'releases':
          res = await searchReleases(app.db, q, offset, limit);
          items = await loadReleases(res.ids);
          break;
        default:
          res = await searchPlaylists(app.db, userId, q, offset, limit);
          items = await loadPlaylists(res.ids);
      }
      return { items, offset, limit, total: res.total, nextOffset: offset + items.length < res.total ? offset + items.length : null };
    },
  );
}
