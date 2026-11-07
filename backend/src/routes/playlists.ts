import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../plugins/auth.js';
import { badRequest, notFound } from '../lib/errors.js';
import { searchText } from '../lib/normalize.js';
import { toTrackDto, trackInclude } from '../services/dto.js';
import type { Db } from '../db.js';

/** Playlists sind zunächst privat: jede Abfrage ist auf ownerId = angemeldeter Benutzer begrenzt. */
async function ownPlaylist(db: Db, userId: string, id: string) {
  const p = await db.playlist.findFirst({ where: { id, ownerId: userId } });
  if (!p) throw notFound('Playlist nicht gefunden.');
  return p;
}

async function playlistCovers(db: Db, playlistId: string): Promise<string[]> {
  const entries = await db.playlistEntry.findMany({
    where: { playlistId },
    orderBy: { position: 'asc' },
    take: 20,
    select: { track: { select: { coverImageId: true, release: { select: { coverImageId: true } } } } },
  });
  const ids: string[] = [];
  for (const e of entries) {
    const id = e.track.coverImageId ?? e.track.release.coverImageId;
    if (id && !ids.includes(id)) ids.push(id);
    if (ids.length === 4) break;
  }
  return ids;
}

export default async function playlistRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  app.addHook('onRequest', app.requireUser);
  const idParam = z.object({ id: z.uuid() });
  const nameSchema = z.string().trim().min(1, 'Name darf nicht leer sein.').max(100);

  app.get('/', { schema: { tags: ['Playlists'] } }, async (req) => {
    const userId = authOf(req).userId;
    const lists = await app.db.playlist.findMany({
      where: { ownerId: userId },
      orderBy: { updatedAt: 'desc' },
      include: { _count: { select: { entries: true } } },
    });
    const items = await Promise.all(
      lists.map(async (p) => ({
        id: p.id,
        name: p.name,
        description: p.description,
        trackCount: p._count.entries,
        coverImageIds: await playlistCovers(app.db, p.id),
        updatedAt: p.updatedAt.toISOString(),
      })),
    );
    return { items };
  });

  app.post(
    '/',
    { schema: { tags: ['Playlists'], body: z.object({ name: nameSchema, description: z.string().max(500).optional(), trackIds: z.array(z.uuid()).max(500).optional() }) } },
    async (req) => {
      const userId = authOf(req).userId;
      const p = await app.db.$transaction(async (tx) => {
        const created = await tx.playlist.create({
          data: { ownerId: userId, name: req.body.name, description: req.body.description?.trim() || null, searchText: searchText(req.body.name) },
        });
        const ids = req.body.trackIds ?? [];
        if (ids.length) {
          const valid = new Set((await tx.track.findMany({ where: { id: { in: ids } }, select: { id: true } })).map((t) => t.id));
          await tx.playlistEntry.createMany({ data: ids.filter((id) => valid.has(id)).map((trackId, i) => ({ playlistId: created.id, trackId, position: i })) });
        }
        return created;
      });
      return { playlist: { id: p.id, name: p.name, description: p.description, trackCount: req.body.trackIds?.length ?? 0, coverImageIds: [], updatedAt: p.updatedAt.toISOString() } };
    },
  );

  app.get('/:id', { schema: { tags: ['Playlists'], params: idParam } }, async (req) => {
    const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
    const entries = await app.db.playlistEntry.findMany({
      where: { playlistId: p.id },
      orderBy: { position: 'asc' },
      include: { track: { include: trackInclude } },
    });
    return {
      playlist: {
        id: p.id,
        name: p.name,
        description: p.description,
        trackCount: entries.length,
        coverImageIds: await playlistCovers(app.db, p.id),
        durationMs: entries.reduce((s, e) => s + e.track.durationMs, 0),
        updatedAt: p.updatedAt.toISOString(),
      },
      entries: entries.map((e) => ({ entryId: e.id, position: e.position, addedAt: e.addedAt.toISOString(), track: toTrackDto(e.track) })),
    };
  });

  app.patch(
    '/:id',
    { schema: { tags: ['Playlists'], params: idParam, body: z.object({ name: nameSchema.optional(), description: z.string().max(500).nullable().optional() }) } },
    async (req) => {
      const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
      const updated = await app.db.playlist.update({
        where: { id: p.id },
        data: {
          name: req.body.name,
          searchText: req.body.name ? searchText(req.body.name) : undefined,
          description: req.body.description === undefined ? undefined : req.body.description?.trim() || null,
        },
      });
      return { playlist: { id: updated.id, name: updated.name, description: updated.description, updatedAt: updated.updatedAt.toISOString() } };
    },
  );

  app.delete('/:id', { schema: { tags: ['Playlists'], params: idParam } }, async (req) => {
    const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
    await app.db.playlist.delete({ where: { id: p.id } });
    return { ok: true };
  });

  app.post(
    '/:id/tracks',
    {
      schema: {
        tags: ['Playlists'],
        params: idParam,
        body: z.object({ trackIds: z.array(z.uuid()).min(1).max(500), position: z.number().int().min(0).optional() }),
      },
    },
    async (req) => {
      const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
      const valid = new Set((await app.db.track.findMany({ where: { id: { in: req.body.trackIds } }, select: { id: true } })).map((t) => t.id));
      const ids = req.body.trackIds.filter((id) => valid.has(id));
      if (!ids.length) throw badRequest('Keine gültigen Songs angegeben.');
      await app.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT id FROM "Playlist" WHERE id = ${p.id}::uuid FOR UPDATE`;
        const count = await tx.playlistEntry.count({ where: { playlistId: p.id } });
        const pos = Math.min(req.body.position ?? count, count);
        await tx.playlistEntry.updateMany({ where: { playlistId: p.id, position: { gte: pos } }, data: { position: { increment: ids.length } } });
        await tx.playlistEntry.createMany({ data: ids.map((trackId, i) => ({ playlistId: p.id, trackId, position: pos + i })) });
        await tx.playlist.update({ where: { id: p.id }, data: { updatedAt: new Date() } });
      });
      return { added: ids.length };
    },
  );

  app.delete('/:id/entries/:entryId', { schema: { tags: ['Playlists'], params: z.object({ id: z.uuid(), entryId: z.uuid() }) } }, async (req) => {
    const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
    await app.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Playlist" WHERE id = ${p.id}::uuid FOR UPDATE`;
      const entry = await tx.playlistEntry.findFirst({ where: { id: req.params.entryId, playlistId: p.id } });
      if (!entry) throw notFound('Eintrag nicht gefunden.');
      await tx.playlistEntry.delete({ where: { id: entry.id } });
      await tx.playlistEntry.updateMany({ where: { playlistId: p.id, position: { gt: entry.position } }, data: { position: { decrement: 1 } } });
      await tx.playlist.update({ where: { id: p.id }, data: { updatedAt: new Date() } });
    });
    return { ok: true };
  });

  /** Neue Reihenfolge: vollständige Liste aller Eintrags-IDs */
  app.put(
    '/:id/order',
    { schema: { tags: ['Playlists'], params: idParam, body: z.object({ entryIds: z.array(z.uuid()).max(10_000) }) } },
    async (req) => {
      const p = await ownPlaylist(app.db, authOf(req).userId, req.params.id);
      await app.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT id FROM "Playlist" WHERE id = ${p.id}::uuid FOR UPDATE`;
        const current = await tx.playlistEntry.findMany({ where: { playlistId: p.id }, select: { id: true } });
        const set = new Set(current.map((e) => e.id));
        if (current.length !== req.body.entryIds.length || !req.body.entryIds.every((id) => set.has(id)) || new Set(req.body.entryIds).size !== current.length) {
          throw badRequest('Die Reihenfolge muss alle Einträge genau einmal enthalten (Playlist wurde evtl. zwischenzeitlich geändert).');
        }
        for (let i = 0; i < req.body.entryIds.length; i++) {
          await tx.playlistEntry.update({ where: { id: req.body.entryIds[i]! }, data: { position: i } });
        }
        await tx.playlist.update({ where: { id: p.id }, data: { updatedAt: new Date() } });
      });
      return { ok: true };
    },
  );
}
