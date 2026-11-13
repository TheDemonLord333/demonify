import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import type { Prisma } from '../../db.js';
import { badRequest, conflict, notFound, isUniqueViolation } from '../../lib/errors.js';
import { escapeLike, normalizeQuery, searchText } from '../../lib/normalize.js';
import { createUniqueDir, ensureDir, placeFileExclusive, resolveInside, sanitizeSegment, toRel } from '../../lib/fsnames.js';
import { renderImageVariant } from '../../lib/media.js';
import { createArtist, registerImage, similarArtists, validateArtistName } from '../../services/catalog.js';
import { artistDeletePreview, deleteArtist } from '../../services/cleanup.js';
import { releaseInclude, toArtistDto, toReleaseDto, toTrackDto, trackInclude, trackOrder } from '../../services/dto.js';
import { uploadFile } from '../../services/uploads.js';
import { page, paging } from '../catalog.js';
import { nameKey } from '../../lib/normalize.js';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';

export default async function adminCatalogRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const cfg = app.config;
  const idParam = z.object({ id: z.uuid() });

  async function validatedImageUpload(uploadId: string) {
    const u = await app.db.upload.findUnique({ where: { id: uploadId } });
    if (!u) throw notFound('Bild-Upload nicht gefunden.');
    if (u.kind !== 'IMAGE' || u.status !== 'VALIDATED') throw badRequest('Der Upload ist kein geprüftes Bild.');
    return u;
  }

  async function artistDir(artist: { id: string; name: string; nameKey: string; folderRelPath: string | null }) {
    if (artist.folderRelPath) {
      const full = resolveInside(cfg.MUSIC_DIR, artist.folderRelPath);
      await ensureDir(full);
      return full;
    }
    const base = sanitizeSegment(artist.name);
    const owner = await app.db.artist.findFirst({ where: { folderRelPath: base } });
    const candidate = path.join(cfg.MUSIC_DIR, base);
    const exists = await fs.access(candidate).then(() => true, () => false);
    let dir: string;
    if (exists && !owner && nameKey(base) === artist.nameKey) dir = candidate;
    else dir = await createUniqueDir(cfg.MUSIC_DIR, base, artist.id);
    await app.db.artist.update({ where: { id: artist.id }, data: { folderRelPath: toRel(cfg.MUSIC_DIR, dir) } });
    return dir;
  }

  async function placeImage(dir: string, base: string, src: string, ext: string) {
    for (const name of [`${base}${ext}`, `${base} [${crypto.randomBytes(4).toString('hex')}]${ext}`, `${base} [${crypto.randomBytes(4).toString('hex')}]${ext}`]) {
      const dest = path.join(dir, name);
      try {
        await placeFileExclusive(src, dest);
        return dest;
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== 'EEXIST') throw e;
      }
    }
    throw new Error('Bild konnte nicht ohne Überschreiben abgelegt werden.');
  }

  // ───────── Künstler: Live-Vorschläge ab dem ersten Buchstaben
  app.get(
    '/artists/suggest',
    { schema: { tags: ['Verwaltung'], querystring: z.object({ q: z.string().max(200).default(''), limit: z.coerce.number().int().min(1).max(20).default(8) }) } },
    async (req) => {
      const q = normalizeQuery(req.query.q);
      if (!q) return { items: [], exactMatch: null };
      const e = escapeLike(q);
      const rows = await app.db.$queryRaw<Array<{ id: string; name: string; imageId: string | null }>>`
        SELECT id, name, "imageId" FROM "Artist"
        WHERE "searchText" LIKE ${`${e}%`} OR "searchText" LIKE ${`% ${e}%`} OR (length(${q}) > 1 AND "searchText" LIKE ${`%${e}%`})
        ORDER BY CASE WHEN "searchText" LIKE ${`${e}%`} THEN 0 ELSE 1 END, "nameKey"
        LIMIT ${req.query.limit}`;
      const exact = await app.db.artist.findUnique({ where: { nameKey: nameKey(req.query.q) } }).catch(() => null);
      return { items: rows.map(toArtistDto), exactMatch: exact ? toArtistDto(exact) : null };
    },
  );

  /** Vor dem Speichern: exaktes (normalisiertes) Duplikat + ähnliche Namen als Hinweis */
  app.get('/artists/check', { schema: { tags: ['Verwaltung'], querystring: z.object({ name: z.string().min(1).max(200) }) } }, async (req) => {
    const { key, name } = validateArtistName(req.query.name);
    const exact = await app.db.artist.findUnique({ where: { nameKey: key } });
    const similar = (await similarArtists(app.db, name, 5)).filter((a) => a.id !== exact?.id && a.score >= 0.3);
    return { normalizedKey: key, exists: !!exact, artist: exact ? toArtistDto(exact) : null, similar: similar.map((s) => ({ ...toArtistDto(s), score: s.score })) };
  });

  app.get(
    '/artists',
    { schema: { tags: ['Verwaltung'], querystring: z.object({ ...paging, q: z.string().max(200).optional() }) } },
    async (req) => {
      const { offset, limit, q } = req.query;
      const where: Prisma.ArtistWhereInput = q ? { searchText: { contains: normalizeQuery(q) } } : {};
      const [items, total] = await Promise.all([
        app.db.artist.findMany({ where, orderBy: { nameKey: 'asc' }, skip: offset, take: limit, include: { _count: { select: { releases: true, tracks: true } } } }),
        app.db.artist.count({ where }),
      ]);
      return page(
        items.map((a) => ({ ...toArtistDto(a), releaseCount: a._count.releases, trackCount: a._count.tracks, folder: a.folderRelPath, origin: a.origin })),
        offset,
        limit,
        total,
      );
    },
  );

  app.post('/artists', { schema: { tags: ['Verwaltung'], body: z.object({ name: z.string().min(1).max(200) }) } }, async (req, reply) => {
    const artist = await createArtist(app.db, req.body.name);
    const similar = (await similarArtists(app.db, artist.name, 5)).filter((a) => a.id !== artist.id && a.score >= 0.3);
    return reply.code(201).send({ artist: toArtistDto(artist), similar: similar.map(toArtistDto) });
  });

  app.patch(
    '/artists/:id',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({ name: z.string().min(1).max(200).optional(), origin: z.enum(['MANUAL', 'SCAN']).optional() }),
      },
    },
    async (req) => {
    if (req.body.origin) {
      // Herkunft einstufen: SCAN = darf nach einem Scan automatisch entfernt werden, MANUAL = bleibt
      const a = await app.db.artist.update({ where: { id: req.params.id }, data: { origin: req.body.origin } }).catch(() => null);
      if (!a) throw notFound('Künstler nicht gefunden.');
      if (!req.body.name) return { artist: { ...toArtistDto(a), origin: a.origin } };
    }
    if (!req.body.name) throw badRequest('Keine Änderung angegeben.');
    const { name, key } = validateArtistName(req.body.name);
    const other = await app.db.artist.findUnique({ where: { nameKey: key } });
    if (other && other.id !== req.params.id) {
      throw conflict(`Ein Künstler mit dem Namen „${other.name}“ existiert bereits.`, { artist: toArtistDto(other) }, 'ARTIST_EXISTS');
    }
    try {
      const a = await app.db.artist.update({ where: { id: req.params.id }, data: { name, nameKey: key, searchText: searchText(name) } });
      return { artist: { ...toArtistDto(a), origin: a.origin } };
    } catch (e) {
      if (isUniqueViolation(e)) throw conflict('Ein Künstler mit diesem Namen wurde gerade angelegt.', undefined, 'ARTIST_EXISTS');
      throw e;
    }
    },
  );

  /** Was passiert beim Löschen? (für die Sicherheitsabfrage) */
  app.get('/artists/:id/delete-preview', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => artistDeletePreview(app.db, req.params.id));

  /**
   * Künstler löschen: eigene Veröffentlichungen werden aus dem Katalog entfernt (Audiodateien → Papierkorb-Ordner),
   * fremde/gemeinsame Veröffentlichungen bleiben, nur die Mitwirkung wird entfernt.
   */
  app.delete('/artists/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const res = await deleteArtist(app.db, cfg, req.params.id, req.log);
    req.log.info({ artistId: req.params.id, ...res }, 'Künstler gelöscht');
    return { ok: true, ...res };
  });

  /** Profilbild hochladen/ersetzen, optional zuschneiden (Pixelkoordinaten im Originalbild). */
  app.put(
    '/artists/:id/image',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({
          uploadId: z.uuid(),
          crop: z.object({ left: z.number().int().min(0), top: z.number().int().min(0), width: z.number().int().min(16), height: z.number().int().min(16) }).optional(),
        }),
      },
    },
    async (req) => {
      const artist = await app.db.artist.findUnique({ where: { id: req.params.id } });
      if (!artist) throw notFound('Künstler nicht gefunden.');
      const upload = await validatedImageUpload(req.body.uploadId);
      const probe = upload.probe as { width: number; height: number };
      const crop = req.body.crop;
      if (crop && (crop.left + crop.width > probe.width || crop.top + crop.height > probe.height)) {
        throw badRequest('Zuschnitt liegt außerhalb des Bildes.');
      }
      const dir = await artistDir(artist);
      // Zugeschnittenes Profilbild als JPEG (Quelldatei des Uploads bleibt bis zur Bereinigung erhalten)
      const tmp = path.join(path.dirname(uploadFile(cfg, upload.id)), 'artist.jpg');
      await renderImageVariant(uploadFile(cfg, upload.id), tmp, null, crop);
      const dest = await placeImage(dir, 'artist', tmp, '.jpg');
      const img = await registerImage(app.db, cfg, { storage: 'LIBRARY', relPath: toRel(cfg.MUSIC_DIR, dest), source: 'UPLOAD' });
      const updated = await app.db.artist.update({ where: { id: artist.id }, data: { imageId: img.id, imageLocked: true } });
      await app.db.upload.update({ where: { id: upload.id }, data: { status: 'CONSUMED' } });
      await fs.rm(path.dirname(uploadFile(cfg, upload.id)), { recursive: true, force: true });
      return { artist: toArtistDto(updated) };
    },
  );

  /** Profilbild entfernen (Datei bleibt erhalten; Scan setzt es nicht erneut). */
  app.delete('/artists/:id/image', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const a = await app.db.artist.update({ where: { id: req.params.id }, data: { imageId: null, imageLocked: true } }).catch(() => null);
    if (!a) throw notFound('Künstler nicht gefunden.');
    return { artist: toArtistDto(a) };
  });

  // ───────── Veröffentlichungen
  app.get(
    '/releases',
    {
      schema: {
        tags: ['Verwaltung'],
        querystring: z.object({ ...paging, artistId: z.uuid().optional(), type: z.enum(['ALBUM', 'EP', 'SINGLE']).optional(), q: z.string().max(200).optional() }),
      },
    },
    async (req) => {
      const { offset, limit, artistId, type, q } = req.query;
      const where: Prisma.ReleaseWhereInput = { albumArtistId: artistId, type, searchText: q ? { contains: normalizeQuery(q) } : undefined };
      const [items, total] = await Promise.all([
        app.db.release.findMany({ where, orderBy: [{ createdAt: 'desc' }], skip: offset, take: limit, include: releaseInclude }),
        app.db.release.count({ where }),
      ]);
      return page(items.map((r) => ({ ...toReleaseDto(r), folder: r.folderRelPath })), offset, limit, total);
    },
  );

  app.get('/releases/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const r = await app.db.release.findUnique({ where: { id: req.params.id }, include: releaseInclude });
    if (!r) throw notFound('Veröffentlichung nicht gefunden.');
    const tracks = await app.db.track.findMany({ where: { releaseId: r.id }, include: trackInclude, orderBy: trackOrder });
    return {
      release: { ...toReleaseDto(r), folder: r.folderRelPath, metaLocked: r.metaLocked, coverLocked: r.coverLocked },
      tracks: tracks.map((t) => ({ ...toTrackDto(t), audioPath: t.audioRelPath, needsReview: t.needsReview })),
    };
  });

  app.patch(
    '/releases/:id',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({
          title: z.string().trim().min(1).max(300).optional(),
          type: z.enum(['ALBUM', 'EP', 'SINGLE']).optional(),
          year: z.number().int().min(1000).max(9999).nullable().optional(),
          genre: z.string().trim().max(100).nullable().optional(),
          albumArtistId: z.uuid().optional(),
        }),
      },
    },
    async (req) => {
      if (req.body.albumArtistId && !(await app.db.artist.findUnique({ where: { id: req.body.albumArtistId } }))) throw notFound('Künstler nicht gefunden.');
      const r = await app.db.release
        .update({
          where: { id: req.params.id },
          data: {
            ...req.body,
            genre: req.body.genre === undefined ? undefined : req.body.genre || null,
            searchText: req.body.title ? searchText(req.body.title) : undefined,
            metaLocked: true,
          },
          include: releaseInclude,
        })
        .catch(() => null);
      if (!r) throw notFound('Veröffentlichung nicht gefunden.');
      return { release: toReleaseDto(r) };
    },
  );

  app.put('/releases/:id/cover', { schema: { tags: ['Verwaltung'], params: idParam, body: z.object({ uploadId: z.uuid() }) } }, async (req) => {
    const r = await app.db.release.findUnique({ where: { id: req.params.id }, include: { albumArtist: true } });
    if (!r) throw notFound('Veröffentlichung nicht gefunden.');
    const upload = await validatedImageUpload(req.body.uploadId);
    let dir: string;
    if (r.folderRelPath) dir = resolveInside(cfg.MUSIC_DIR, r.folderRelPath);
    else {
      const aDir = await artistDir(r.albumArtist);
      const typeDir = path.join(aDir, { ALBUM: 'Alben', EP: 'EPs', SINGLE: 'Singles' }[r.type]);
      dir = await createUniqueDir(typeDir, r.year ? `${r.year} - ${sanitizeSegment(r.title)}` : sanitizeSegment(r.title), r.id);
      await app.db.release.update({ where: { id: r.id }, data: { folderRelPath: toRel(cfg.MUSIC_DIR, dir) } });
    }
    await ensureDir(dir);
    const fmt = (upload.probe as { format: string }).format;
    const dest = await placeImage(dir, 'cover', uploadFile(cfg, upload.id), fmt === 'png' ? '.png' : fmt === 'webp' ? '.webp' : '.jpg');
    const img = await registerImage(app.db, cfg, { storage: 'LIBRARY', relPath: toRel(cfg.MUSIC_DIR, dest), source: 'UPLOAD' });
    const updated = await app.db.release.update({ where: { id: r.id }, data: { coverImageId: img.id, coverLocked: true }, include: releaseInclude });
    await app.db.upload.update({ where: { id: upload.id }, data: { status: 'CONSUMED' } });
    await fs.rm(path.dirname(uploadFile(cfg, upload.id)), { recursive: true, force: true });
    return { release: toReleaseDto(updated) };
  });

  app.delete('/releases/:id/cover', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const r = await app.db.release.update({ where: { id: req.params.id }, data: { coverImageId: null, coverLocked: true }, include: releaseInclude }).catch(() => null);
    if (!r) throw notFound('Veröffentlichung nicht gefunden.');
    return { release: toReleaseDto(r) };
  });

  /** Trackreihenfolge: Liste von Track-IDs in neuer Reihenfolge (+ optionale Discnummern) */
  app.put(
    '/releases/:id/order',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({ tracks: z.array(z.object({ id: z.uuid(), discNumber: z.number().int().min(1).max(99).default(1) })).min(1).max(500) }),
      },
    },
    async (req) => {
      const existing = await app.db.track.findMany({ where: { releaseId: req.params.id }, select: { id: true } });
      const ids = new Set(existing.map((t) => t.id));
      if (existing.length !== req.body.tracks.length || !req.body.tracks.every((t) => ids.has(t.id))) {
        throw badRequest('Die Reihenfolge muss alle Tracks der Veröffentlichung genau einmal enthalten.');
      }
      const counters = new Map<number, number>();
      await app.db.$transaction(
        req.body.tracks.map((t) => {
          const n = (counters.get(t.discNumber) ?? 0) + 1;
          counters.set(t.discNumber, n);
          return app.db.track.update({ where: { id: t.id }, data: { discNumber: t.discNumber, trackNumber: n, metaLocked: true } });
        }),
      );
      return { ok: true };
    },
  );

  app.delete('/releases/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const count = await app.db.track.count({ where: { releaseId: req.params.id } });
    if (count > 0) throw conflict('Nur Veröffentlichungen ohne Tracks können entfernt werden.');
    await app.db.release.delete({ where: { id: req.params.id } }).catch(() => {
      throw notFound('Veröffentlichung nicht gefunden.');
    });
    return { ok: true };
  });

  // ───────── Tracks
  app.get(
    '/tracks',
    {
      schema: {
        tags: ['Verwaltung'],
        querystring: z.object({ ...paging, available: z.enum(['true', 'false']).optional(), needsReview: z.enum(['true', 'false']).optional(), q: z.string().max(200).optional() }),
      },
    },
    async (req) => {
      const { offset, limit, available, needsReview, q } = req.query;
      const where: Prisma.TrackWhereInput = {
        available: available === undefined ? undefined : available === 'true',
        needsReview: needsReview === undefined ? undefined : needsReview === 'true',
        searchText: q ? { contains: normalizeQuery(q) } : undefined,
      };
      const [items, total] = await Promise.all([
        app.db.track.findMany({ where, include: trackInclude, orderBy: [{ updatedAt: 'desc' }], skip: offset, take: limit }),
        app.db.track.count({ where }),
      ]);
      return page(
        items.map((t) => ({ ...toTrackDto(t), audioPath: t.audioRelPath, needsReview: t.needsReview, missingSince: t.missingSince?.toISOString() ?? null })),
        offset,
        limit,
        total,
      );
    },
  );

  app.patch(
    '/tracks/:id',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({
          title: z.string().trim().min(1).max(300).optional(),
          artistIds: z.array(z.uuid()).min(1).max(20).optional(),
          featuredArtistIds: z.array(z.uuid()).max(20).optional(),
          genre: z.string().trim().max(100).nullable().optional(),
          year: z.number().int().min(1000).max(9999).nullable().optional(),
          discNumber: z.number().int().min(1).max(99).optional(),
          trackNumber: z.number().int().min(1).max(999).optional(),
        }),
      },
    },
    async (req) => {
      const t = await app.db.track.findUnique({ where: { id: req.params.id }, include: { artists: true } });
      if (!t) throw notFound('Song nicht gefunden.');
      const { artistIds, featuredArtistIds, ...rest } = req.body;
      await app.db.$transaction(async (tx) => {
        await tx.track.update({
          where: { id: t.id },
          data: {
            ...rest,
            genre: rest.genre === undefined ? undefined : rest.genre || null,
            searchText: rest.title ? searchText(rest.title) : undefined,
            metaLocked: true,
            needsReview: false,
          },
        });
        if (artistIds || featuredArtistIds) {
          const primary = artistIds ?? t.artists.filter((a) => a.role === 'PRIMARY').sort((a, b) => a.position - b.position).map((a) => a.artistId);
          const featured = (featuredArtistIds ?? t.artists.filter((a) => a.role === 'FEATURED').map((a) => a.artistId)).filter((id) => !primary.includes(id));
          const all = [...new Set([...primary, ...featured])];
          if ((await tx.artist.count({ where: { id: { in: all } } })) !== all.length) throw notFound('Mindestens ein Künstler existiert nicht.');
          await tx.trackArtist.deleteMany({ where: { trackId: t.id } });
          await tx.trackArtist.createMany({
            data: [
              ...primary.map((artistId, i) => ({ trackId: t.id, artistId, role: 'PRIMARY' as const, position: i })),
              ...featured.map((artistId, i) => ({ trackId: t.id, artistId, role: 'FEATURED' as const, position: primary.length + i })),
            ],
          });
        }
      });
      await app.db.libraryIssue.updateMany({ where: { trackId: t.id, kind: 'INCOMPLETE_METADATA', resolvedAt: null }, data: { resolvedAt: new Date() } });
      const updated = await app.db.track.findUniqueOrThrow({ where: { id: t.id }, include: trackInclude });
      return { track: toTrackDto(updated) };
    },
  );

  app.put('/tracks/:id/cover', { schema: { tags: ['Verwaltung'], params: idParam, body: z.object({ uploadId: z.uuid() }) } }, async (req) => {
    const t = await app.db.track.findUnique({ where: { id: req.params.id } });
    if (!t) throw notFound('Song nicht gefunden.');
    const upload = await validatedImageUpload(req.body.uploadId);
    const dir = path.dirname(resolveInside(cfg.MUSIC_DIR, t.audioRelPath));
    const fmt = (upload.probe as { format: string }).format;
    // Liegt der Track direkt im Veröffentlichungsordner (Einzel-Single), wird ein eindeutiger Name verwendet
    const dest = await placeImage(dir, 'cover', uploadFile(cfg, upload.id), fmt === 'png' ? '.png' : fmt === 'webp' ? '.webp' : '.jpg');
    const img = await registerImage(app.db, cfg, { storage: 'LIBRARY', relPath: toRel(cfg.MUSIC_DIR, dest), source: 'UPLOAD' });
    await app.db.track.update({ where: { id: t.id }, data: { coverImageId: img.id, coverLocked: true } });
    await app.db.upload.update({ where: { id: upload.id }, data: { status: 'CONSUMED' } });
    await fs.rm(path.dirname(uploadFile(cfg, upload.id)), { recursive: true, force: true });
    const updated = await app.db.track.findUniqueOrThrow({ where: { id: t.id }, include: trackInclude });
    return { track: toTrackDto(updated) };
  });

  /** Individuelles Songcover entfernen → Veröffentlichungscover wird verwendet */
  app.delete('/tracks/:id/cover', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const t = await app.db.track.update({ where: { id: req.params.id }, data: { coverImageId: null, coverLocked: true }, include: trackInclude }).catch(() => null);
    if (!t) throw notFound('Song nicht gefunden.');
    return { track: toTrackDto(t) };
  });

  /** Nur nicht verfügbare Tracks dürfen aus dem Katalog entfernt werden (Dateien werden nie gelöscht). */
  app.delete('/tracks/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const t = await app.db.track.findUnique({ where: { id: req.params.id } });
    if (!t) throw notFound('Song nicht gefunden.');
    if (t.available) throw conflict('Nur nicht verfügbare Songs können aus dem Katalog entfernt werden.');
    await app.db.track.delete({ where: { id: t.id } });
    await app.db.libraryIssue.updateMany({ where: { trackId: t.id, resolvedAt: null }, data: { resolvedAt: new Date() } });
    return { ok: true };
  });

  app.get('/stats', { schema: { tags: ['Verwaltung'] } }, async () => {
    const [artists, releases, tracks, unavailable, needsReview, users, openIssues, runningJobs] = await Promise.all([
      app.db.artist.count(),
      app.db.release.count(),
      app.db.track.count(),
      app.db.track.count({ where: { available: false } }),
      app.db.track.count({ where: { needsReview: true } }),
      app.db.user.count(),
      app.db.libraryIssue.count({ where: { resolvedAt: null } }),
      app.db.job.count({ where: { status: { in: ['QUEUED', 'RUNNING'] } } }),
    ]);
    return { artists, releases, tracks, unavailable, needsReview, users, openIssues, runningJobs };
  });
}
