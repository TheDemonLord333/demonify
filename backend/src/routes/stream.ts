import fs from 'node:fs';
import fsp from 'node:fs/promises';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../plugins/auth.js';
import { ApiError, notFound } from '../lib/errors.js';
import { safeEqual, streamSignature } from '../lib/tokens.js';
import { QUALITIES, resolveStreamFile, type Quality } from '../services/transcoder.js';

/** Pfadsegmente für X-Accel-Redirect kodieren (Nginx dekodiert sie wieder) */
export function accelPath(prefix: string, relPath: string): string {
  return prefix + relPath.split('/').map(encodeURIComponent).join('/');
}

/**
 * Datei mit HTTP-Range-Unterstützung ausliefern (Entwicklung bzw. MEDIA_ACCEL_REDIRECT=false).
 * In Produktion übernimmt Nginx per X-Accel-Redirect (sendfile, Range, kein Node-Durchsatz).
 */
export async function sendFileWithRange(req: FastifyRequest, reply: FastifyReply, fullPath: string, mime: string, cacheControl: string) {
  const st = await fsp.stat(fullPath).catch(() => null);
  if (!st || !st.isFile()) throw notFound('Datei nicht verfügbar.');
  const size = st.size;
  reply.header('accept-ranges', 'bytes');
  reply.header('content-type', mime);
  reply.header('cache-control', cacheControl);
  reply.header('last-modified', st.mtime.toUTCString());
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (!m || (m[1] === '' && m[2] === '')) {
      reply.header('content-range', `bytes */${size}`);
      return reply.code(416).send();
    }
    let start: number;
    let end: number;
    if (m[1] === '') {
      const suffix = Number(m[2]);
      start = Math.max(0, size - suffix);
      end = size - 1;
    } else {
      start = Number(m[1]);
      end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
    }
    if (start >= size || start > end) {
      reply.header('content-range', `bytes */${size}`);
      return reply.code(416).send();
    }
    reply.code(206);
    reply.header('content-range', `bytes ${start}-${end}/${size}`);
    reply.header('content-length', String(end - start + 1));
    if (req.method === 'HEAD') return reply.send();
    return reply.send(fs.createReadStream(fullPath, { start, end }));
  }
  reply.header('content-length', String(size));
  if (req.method === 'HEAD') return reply.send();
  return reply.send(fs.createReadStream(fullPath));
}

export default async function streamRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const cfg = app.config;

  /**
   * Kurzlebige, auf genau diesen Track begrenzte Streaming-URL ausstellen.
   * Die URL enthält kein Login-Token; sie ist an Benutzer, Session, Qualität und Ablaufzeit gebunden.
   */
  app.post(
    '/tracks/:id/stream-url',
    {
      onRequest: app.requireUser,
      schema: {
        tags: ['Wiedergabe'],
        params: z.object({ id: z.uuid() }),
        body: z.object({ quality: z.enum(QUALITIES).default('original') }).nullish(),
      },
    },
    async (req) => {
      const auth = authOf(req);
      const track = await app.db.track.findUnique({ where: { id: req.params.id } });
      if (!track) throw notFound('Song nicht gefunden.');
      if (!track.available) throw new ApiError(410, 'TRACK_UNAVAILABLE', 'Die Audiodatei ist derzeit nicht verfügbar.');
      const quality = req.body?.quality ?? 'original';
      // Transkodierung ggf. vorab anstoßen
      const file = await resolveStreamFile(app.db, cfg, app.jobs, track, quality);
      const exp = Math.floor(Date.now() / 1000) + cfg.STREAM_URL_TTL_SECONDS;
      const sig = streamSignature(cfg.STREAM_URL_SECRET, { trackId: track.id, quality, uid: auth.userId, sid: auth.sessionId, exp });
      const qs = new URLSearchParams({ q: quality, uid: auth.userId, sid: auth.sessionId, exp: String(exp), sig });
      return {
        url: `/api/v1/stream/${track.id}?${qs.toString()}`,
        expiresAt: new Date(exp * 1000).toISOString(),
        requestedQuality: quality,
        currentQuality: file.servedQuality,
        mime: file.mime,
        durationMs: track.durationMs,
      };
    },
  );

  const streamHandler = async (
    req: FastifyRequest<{ Params: { trackId: string }; Querystring: { q: Quality; uid: string; sid: string; exp: number; sig: string } }>,
    reply: FastifyReply,
  ) => {
    const { q, uid, sid, exp, sig } = req.query;
    const { trackId } = req.params;
    const expected = streamSignature(cfg.STREAM_URL_SECRET, { trackId, quality: q, uid, sid, exp });
    if (!safeEqual(expected, sig)) throw new ApiError(403, 'STREAM_SIGNATURE_INVALID', 'Ungültige Streaming-Adresse.');
    if (exp < Date.now() / 1000) throw new ApiError(403, 'STREAM_URL_EXPIRED', 'Streaming-Adresse abgelaufen.');
    const session = await app.db.session.findUnique({ where: { id: sid }, select: { userId: true, revokedAt: true, expiresAt: true, user: { select: { disabledAt: true } } } });
    if (!session || session.userId !== uid || session.revokedAt || session.expiresAt < new Date() || session.user.disabledAt) {
      throw new ApiError(403, 'SESSION_REVOKED', 'Sitzung beendet.');
    }
    const track = await app.db.track.findUnique({ where: { id: trackId } });
    if (!track || !track.available) throw notFound('Song nicht verfügbar.');
    const file = await resolveStreamFile(app.db, cfg, null, track, q);
    reply.header('x-demonify-quality', file.servedQuality);
    const cacheControl = 'private, max-age=3600';
    if (cfg.MEDIA_ACCEL_REDIRECT) {
      const prefix = file.storage === 'LIBRARY' ? cfg.ACCEL_PREFIX_MUSIC : cfg.ACCEL_PREFIX_CACHE;
      reply.header('content-type', file.mime);
      reply.header('cache-control', cacheControl);
      reply.header('x-accel-redirect', accelPath(prefix, file.relPath));
      reply.header('x-accel-buffering', 'no');
      return reply.code(200).send();
    }
    return sendFileWithRange(req, reply, file.fullPath, file.mime, cacheControl);
  };

  const streamSchema = {
    tags: ['Wiedergabe'],
    security: [],
    params: z.object({ trackId: z.uuid() }),
    querystring: z.object({
      q: z.enum(QUALITIES),
      uid: z.uuid(),
      sid: z.uuid(),
      exp: z.coerce.number().int(),
      sig: z.string().min(20).max(100),
    }),
  };
  app.get('/stream/:trackId', { schema: streamSchema }, streamHandler);
}
