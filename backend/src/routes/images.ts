import fs from 'node:fs/promises';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { notFound } from '../lib/errors.js';
import { renderImageVariant } from '../lib/media.js';
import { resolveInside } from '../lib/fsnames.js';
import { imageFullPath } from '../services/catalog.js';
import { accelPath, sendFileWithRange } from './stream.js';

export const IMAGE_SIZES = { thumb: 96, small: 300, medium: 640, large: 1200 } as const;

/** Begrenzte Parallelität beim Erzeugen von Covervarianten */
let activeRenders = 0;
const waiters: Array<() => void> = [];
async function withRenderSlot<T>(fn: () => Promise<T>): Promise<T> {
  if (activeRenders >= 2) await new Promise<void>((r) => waiters.push(r));
  activeRenders++;
  try {
    return await fn();
  } finally {
    activeRenders--;
    waiters.shift()?.();
  }
}

export default async function imageRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const cfg = app.config;

  app.get(
    '/:id',
    {
      onRequest: app.requireUser,
      schema: {
        tags: ['Medien'],
        params: z.object({ id: z.uuid() }),
        querystring: z.object({ size: z.enum(['thumb', 'small', 'medium', 'large', 'original']).default('medium') }),
      },
    },
    async (req, reply) => {
      const img = await app.db.image.findUnique({ where: { id: req.params.id } });
      if (!img) throw notFound('Bild nicht gefunden.');
      const src = imageFullPath(cfg, img);
      const size = req.query.size;
      // Covervarianten liegen im Cache, nie in der Originalbibliothek
      const variantRel = `images/${img.id.slice(0, 2)}/${img.id}/${img.sha256.slice(0, 12)}-${size}.jpg`;
      const variant = resolveInside(cfg.cacheDir, variantRel);
      try {
        await fs.access(variant);
      } catch {
        await fs.mkdir(path.dirname(variant), { recursive: true });
        try {
          await withRenderSlot(() => renderImageVariant(src, variant, size === 'original' ? null : IMAGE_SIZES[size]));
        } catch {
          throw notFound('Bilddatei nicht verfügbar.');
        }
      }
      const cacheControl = 'private, max-age=604800';
      reply.header('etag', `"${img.sha256.slice(0, 16)}-${size}"`);
      if (req.headers['if-none-match'] === `"${img.sha256.slice(0, 16)}-${size}"`) {
        reply.header('cache-control', cacheControl);
        return reply.code(304).send();
      }
      if (cfg.MEDIA_ACCEL_REDIRECT) {
        reply.header('content-type', 'image/jpeg');
        reply.header('cache-control', cacheControl);
        reply.header('x-accel-redirect', accelPath(cfg.ACCEL_PREFIX_CACHE, variantRel));
        return reply.code(200).send();
      }
      return sendFileWithRange(req, reply, variant, 'image/jpeg', cacheControl);
    },
  );
}
