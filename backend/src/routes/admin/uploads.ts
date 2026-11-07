import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import type { Readable } from 'node:stream';
import { z } from 'zod';
import { authOf } from '../../plugins/auth.js';
import { badRequest, notFound } from '../../lib/errors.js';
import { abortUpload, appendChunk, completeUpload, createUpload, toUploadDto } from '../../services/uploads.js';
import { commitRelease } from '../../services/commit.js';

export default async function adminUploadRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const cfg = app.config;
  const idParam = z.object({ id: z.uuid() });
  const chunkBytes = cfg.UPLOAD_CHUNK_MB * 1024 * 1024;

  app.get('/uploads/config', { schema: { tags: ['Upload'] } }, async () => ({
    chunkSize: chunkBytes,
    maxAudioBytes: cfg.MAX_AUDIO_UPLOAD_MB * 1024 * 1024,
    maxImageBytes: cfg.MAX_IMAGE_UPLOAD_MB * 1024 * 1024,
    audioExtensions: ['mp3', 'flac', 'm4a', 'aac', 'mp4', 'ogg', 'oga', 'opus', 'wav'],
    imageExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  }));

  app.post(
    '/uploads',
    {
      schema: {
        tags: ['Upload'],
        body: z.object({ kind: z.enum(['AUDIO', 'IMAGE']), filename: z.string().min(1).max(255), size: z.number().int().positive() }),
      },
    },
    async (req, reply) => {
      const u = await createUpload(app.db, cfg, authOf(req).userId, req.body);
      return reply.code(201).send({ upload: toUploadDto(u), chunkSize: chunkBytes });
    },
  );

  app.get('/uploads/:id', { schema: { tags: ['Upload'], params: idParam } }, async (req) => {
    const u = await app.db.upload.findUnique({ where: { id: req.params.id } });
    if (!u) throw notFound('Upload nicht gefunden.');
    return { upload: toUploadDto(u) };
  });

  /** Abschnitt anhängen. Header "Upload-Offset" muss dem bisherigen Serverstand entsprechen. */
  app.put(
    '/uploads/:id/content',
    {
      bodyLimit: chunkBytes + 1024,
      schema: { tags: ['Upload'], params: idParam, headers: z.object({ 'upload-offset': z.coerce.number().int().min(0) }).loose() },
    },
    async (req, reply) => {
      if (!String(req.headers['content-type'] ?? '').startsWith('application/octet-stream')) {
        throw badRequest('Content-Type muss application/octet-stream sein.');
      }
      const u = await appendChunk(app.db, cfg, req.params.id, req.headers['upload-offset'], req.body as Readable, chunkBytes);
      reply.header('upload-offset', String(u.receivedSize));
      return { upload: toUploadDto(u) };
    },
  );

  app.post('/uploads/:id/complete', { schema: { tags: ['Upload'], params: idParam } }, async (req) => {
    const u = await completeUpload(app.db, cfg, req.params.id);
    return { upload: toUploadDto(u) };
  });

  app.delete('/uploads/:id', { schema: { tags: ['Upload'], params: idParam } }, async (req) => {
    const u = await abortUpload(app.db, cfg, req.params.id);
    return { upload: toUploadDto(u) };
  });

  const trackSchema = z.object({
    uploadId: z.uuid(),
    title: z.string().trim().min(1).max(300),
    discNumber: z.number().int().min(1).max(99).default(1),
    trackNumber: z.number().int().min(1).max(999),
    artistIds: z.array(z.uuid()).min(1).max(20),
    featuredArtistIds: z.array(z.uuid()).max(20).default([]),
    genre: z.string().trim().max(100).nullable().optional(),
    year: z.number().int().min(1000).max(9999).nullable().optional(),
    coverUploadId: z.uuid().nullable().optional(),
  });

  /** Upload bestätigen: Server legt Ordner/Datensätze gemäß verbindlicher Struktur an. */
  app.post(
    '/releases/commit',
    {
      schema: {
        tags: ['Upload'],
        body: z.object({
          idempotencyKey: z.string().min(16).max(100),
          artistId: z.uuid(),
          release: z.discriminatedUnion('mode', [
            z.object({
              mode: z.literal('new'),
              title: z.string().trim().min(1).max(300),
              type: z.enum(['ALBUM', 'EP', 'SINGLE']),
              year: z.number().int().min(1000).max(9999).nullable().optional(),
              genre: z.string().trim().max(100).nullable().optional(),
              coverUploadId: z.uuid().nullable().optional(),
            }),
            z.object({ mode: z.literal('existing'), releaseId: z.uuid(), coverUploadId: z.uuid().nullable().optional() }),
          ]),
          tracks: z.array(trackSchema).max(200),
        }),
      },
    },
    async (req) => {
      const result = await commitRelease(app.db, cfg, authOf(req).userId, req.body);
      return { result };
    },
  );
}
