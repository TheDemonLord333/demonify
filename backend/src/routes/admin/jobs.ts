import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../../plugins/auth.js';
import { conflict, notFound } from '../../lib/errors.js';
import { toJobDto } from '../../services/jobs.js';
import { page, paging } from '../catalog.js';

export default async function adminJobRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const idParam = z.object({ id: z.uuid() });

  app.post('/library/scan', { schema: { tags: ['Verwaltung'] } }, async (req, reply) => {
    const job = await app.jobs.enqueue('LIBRARY_SCAN', {}, { dedupeKey: 'library-scan', createdById: authOf(req).userId });
    return reply.code(202).send({ job: toJobDto(job) });
  });

  app.post('/uploads/cleanup', { schema: { tags: ['Verwaltung'] } }, async (req, reply) => {
    const job = await app.jobs.enqueue('UPLOAD_CLEANUP', {}, { dedupeKey: 'upload-cleanup', createdById: authOf(req).userId });
    return reply.code(202).send({ job: toJobDto(job) });
  });

  app.get(
    '/jobs',
    {
      schema: {
        tags: ['Verwaltung'],
        querystring: z.object({
          ...paging,
          status: z.enum(['QUEUED', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED']).optional(),
          type: z.enum(['LIBRARY_SCAN', 'TRANSCODE', 'UPLOAD_CLEANUP']).optional(),
        }),
      },
    },
    async (req) => {
      const { offset, limit, status, type } = req.query;
      const where = { status, type };
      const [items, total] = await Promise.all([
        app.db.job.findMany({ where, orderBy: { createdAt: 'desc' }, skip: offset, take: limit }),
        app.db.job.count({ where }),
      ]);
      return page(items.map(toJobDto), offset, limit, total);
    },
  );

  app.get('/jobs/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const job = await app.db.job.findUnique({ where: { id: req.params.id } });
    if (!job) throw notFound('Auftrag nicht gefunden.');
    return { job: toJobDto(job) };
  });

  app.post('/jobs/:id/cancel', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const res = await app.db.job.updateMany({
      where: { id: req.params.id, status: { in: ['QUEUED', 'RUNNING'] } },
      data: { status: 'CANCELLED', finishedAt: new Date() },
    });
    if (res.count === 0) throw conflict('Auftrag läuft nicht mehr.');
    return { ok: true };
  });

  app.get(
    '/issues',
    {
      schema: {
        tags: ['Verwaltung'],
        querystring: z.object({
          ...paging,
          kind: z.enum(['FILE_ERROR', 'MISSING_FILE', 'INCOMPLETE_METADATA', 'TRANSCODE_ERROR']).optional(),
          resolved: z.enum(['true', 'false']).default('false'),
        }),
      },
    },
    async (req) => {
      const { offset, limit, kind, resolved } = req.query;
      const where = { kind, resolvedAt: resolved === 'true' ? { not: null } : null };
      const [items, total] = await Promise.all([
        app.db.libraryIssue.findMany({ where, orderBy: { updatedAt: 'desc' }, skip: offset, take: limit }),
        app.db.libraryIssue.count({ where }),
      ]);
      return page(
        items.map((i) => ({
          id: i.id,
          kind: i.kind,
          relPath: i.relPath,
          trackId: i.trackId,
          message: i.message,
          createdAt: i.createdAt.toISOString(),
          updatedAt: i.updatedAt.toISOString(),
          resolvedAt: i.resolvedAt?.toISOString() ?? null,
        })),
        offset,
        limit,
        total,
      );
    },
  );

  app.post('/issues/:id/resolve', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const res = await app.db.libraryIssue.updateMany({ where: { id: req.params.id, resolvedAt: null }, data: { resolvedAt: new Date() } });
    if (res.count === 0) throw notFound('Offenes Problem nicht gefunden.');
    return { ok: true };
  });
}
