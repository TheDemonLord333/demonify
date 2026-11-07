import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../plugins/auth.js';
import { notFound } from '../lib/errors.js';
import { releaseInclude, toArtistDto, toReleaseDto, toTrackDto, trackInclude } from '../services/dto.js';
import { page, paging } from './catalog.js';

/** Benutzerbezogene Bibliothek – alle Abfragen strikt auf den angemeldeten Benutzer begrenzt. */
export default async function libraryRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  app.addHook('onRequest', app.requireUser);
  const idParam = z.object({ id: z.uuid() });

  // ───────── Lieblingssongs
  app.get('/favorites', { schema: { tags: ['Bibliothek'], querystring: z.object(paging) } }, async (req) => {
    const userId = authOf(req).userId;
    const { offset, limit } = req.query;
    const [rows, total] = await Promise.all([
      app.db.favoriteTrack.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, skip: offset, take: limit, include: { track: { include: trackInclude } } }),
      app.db.favoriteTrack.count({ where: { userId } }),
    ]);
    return page(rows.map((r) => ({ ...toTrackDto(r.track), favoritedAt: r.createdAt.toISOString() })), offset, limit, total);
  });

  app.get('/favorites/ids', { schema: { tags: ['Bibliothek'] } }, async (req) => {
    const rows = await app.db.favoriteTrack.findMany({ where: { userId: authOf(req).userId }, select: { trackId: true } });
    return { ids: rows.map((r) => r.trackId) };
  });

  app.put('/favorites/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    const userId = authOf(req).userId;
    if (!(await app.db.track.findUnique({ where: { id: req.params.id }, select: { id: true } }))) throw notFound('Song nicht gefunden.');
    await app.db.favoriteTrack.upsert({
      where: { userId_trackId: { userId, trackId: req.params.id } },
      create: { userId, trackId: req.params.id },
      update: {},
    });
    return { favorite: true };
  });

  app.delete('/favorites/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    await app.db.favoriteTrack.deleteMany({ where: { userId: authOf(req).userId, trackId: req.params.id } });
    return { favorite: false };
  });

  // ───────── Gespeicherte Veröffentlichungen
  app.get(
    '/releases',
    { schema: { tags: ['Bibliothek'], querystring: z.object({ ...paging, type: z.enum(['ALBUM', 'EP', 'SINGLE']).optional() }) } },
    async (req) => {
      const userId = authOf(req).userId;
      const { offset, limit, type } = req.query;
      const where = { userId, release: type ? { type } : undefined };
      const [rows, total] = await Promise.all([
        app.db.savedRelease.findMany({ where, orderBy: { createdAt: 'desc' }, skip: offset, take: limit, include: { release: { include: releaseInclude } } }),
        app.db.savedRelease.count({ where }),
      ]);
      return page(rows.map((r) => ({ ...toReleaseDto(r.release), savedAt: r.createdAt.toISOString() })), offset, limit, total);
    },
  );
  app.put('/releases/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    const userId = authOf(req).userId;
    if (!(await app.db.release.findUnique({ where: { id: req.params.id }, select: { id: true } }))) throw notFound('Veröffentlichung nicht gefunden.');
    await app.db.savedRelease.upsert({ where: { userId_releaseId: { userId, releaseId: req.params.id } }, create: { userId, releaseId: req.params.id }, update: {} });
    return { saved: true };
  });
  app.delete('/releases/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    await app.db.savedRelease.deleteMany({ where: { userId: authOf(req).userId, releaseId: req.params.id } });
    return { saved: false };
  });

  // ───────── Gefolgte Künstler
  app.get('/artists', { schema: { tags: ['Bibliothek'], querystring: z.object(paging) } }, async (req) => {
    const userId = authOf(req).userId;
    const { offset, limit } = req.query;
    const [rows, total] = await Promise.all([
      app.db.followedArtist.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, skip: offset, take: limit, include: { artist: true } }),
      app.db.followedArtist.count({ where: { userId } }),
    ]);
    return page(rows.map((r) => ({ ...toArtistDto(r.artist), followedAt: r.createdAt.toISOString() })), offset, limit, total);
  });
  app.put('/artists/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    const userId = authOf(req).userId;
    if (!(await app.db.artist.findUnique({ where: { id: req.params.id }, select: { id: true } }))) throw notFound('Künstler nicht gefunden.');
    await app.db.followedArtist.upsert({ where: { userId_artistId: { userId, artistId: req.params.id } }, create: { userId, artistId: req.params.id }, update: {} });
    return { following: true };
  });
  app.delete('/artists/:id', { schema: { tags: ['Bibliothek'], params: idParam } }, async (req) => {
    await app.db.followedArtist.deleteMany({ where: { userId: authOf(req).userId, artistId: req.params.id } });
    return { following: false };
  });

  // ───────── Hörverlauf
  app.post(
    '/history',
    {
      schema: {
        tags: ['Bibliothek'],
        body: z.object({
          trackId: z.uuid(),
          playedAt: z.iso.datetime().optional(),
          contextType: z.enum(['release', 'playlist', 'artist', 'favorites', 'search', 'queue', 'downloads']).optional(),
          contextId: z.string().max(64).optional(),
        }),
      },
    },
    async (req) => {
      const userId = authOf(req).userId;
      if (!(await app.db.track.findUnique({ where: { id: req.body.trackId }, select: { id: true } }))) throw notFound('Song nicht gefunden.');
      const playedAt = req.body.playedAt ? new Date(req.body.playedAt) : new Date();
      // Offline nachgereichte Einträge nicht in der Zukunft speichern
      await app.db.playHistory.create({
        data: {
          userId,
          trackId: req.body.trackId,
          playedAt: playedAt > new Date() ? new Date() : playedAt,
          contextType: req.body.contextType,
          contextId: req.body.contextId,
        },
      });
      return { ok: true };
    },
  );

  app.get('/history', { schema: { tags: ['Bibliothek'], querystring: z.object(paging) } }, async (req) => {
    const userId = authOf(req).userId;
    const { offset, limit } = req.query;
    const [rows, total] = await Promise.all([
      app.db.playHistory.findMany({ where: { userId }, orderBy: { playedAt: 'desc' }, skip: offset, take: limit, include: { track: { include: trackInclude } } }),
      app.db.playHistory.count({ where: { userId } }),
    ]);
    return page(rows.map((r) => ({ id: r.id, playedAt: r.playedAt.toISOString(), track: toTrackDto(r.track) })), offset, limit, total);
  });
}
