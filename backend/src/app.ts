import Fastify, { type FastifyInstance, type FastifyError } from 'fastify';
import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import {
  validatorCompiler,
  serializerCompiler,
  jsonSchemaTransform,
  hasZodFastifySchemaValidationErrors,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';
import type { AppConfig } from './config.js';
import type { Db } from './db.js';
import { ApiError, errorBody } from './lib/errors.js';
import authPlugin from './plugins/auth.js';
import { JobQueue } from './services/jobs.js';
import { runLibraryScan } from './services/scanner.js';
import { transcodeJob } from './services/transcoder.js';
import { cleanupUploads } from './services/uploads.js';
import { registerRoutes } from './routes/index.js';

declare module 'fastify' {
  interface FastifyInstance {
    config: AppConfig;
    db: Db;
    jobs: JobQueue;
  }
}

export const API_PREFIX = '/api/v1';

export async function buildApp(config: AppConfig, db: Db, opts: { logger?: boolean; startWorker?: boolean } = {}): Promise<FastifyInstance> {
  const trustProxy = config.TRUST_PROXY.split(',').map((s) => s.trim()).filter(Boolean);
  const app = Fastify({
    logger:
      opts.logger === false
        ? false
        : {
            level: config.LOG_LEVEL,
            // Keine Passwörter/Tokens in Logs: Header und Query-Signaturen schwärzen
            redact: {
              paths: ['req.headers.authorization', 'req.headers.cookie', 'req.headers["x-csrf-token"]', 'res.headers["set-cookie"]'],
              censor: '[geschwärzt]',
            },
            serializers: {
              req(req) {
                const url = (req.url ?? '').replace(/([?&](?:sig|exp|uid|sid|code)=)[^&]*/g, '$1…');
                return { method: req.method, url, remoteAddress: req.ip };
              },
            },
          },
    trustProxy: trustProxy.length ? trustProxy : false,
    bodyLimit: 1024 * 1024,
    requestTimeout: 0,
    routerOptions: { ignoreTrailingSlash: true },
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  app.decorate('config', config);
  app.decorate('db', db);
  const jobs = new JobQueue(db, config, app.log, {
    LIBRARY_SCAN: 1,
    TRANSCODE: config.TRANSCODE_CONCURRENCY,
    UPLOAD_CLEANUP: 1,
  });
  jobs.register('LIBRARY_SCAN', async (_payload, ctx) =>
    runLibraryScan(db, config, { jobId: ctx.jobId, progress: ctx.progress, isCancelled: ctx.isCancelled, log: console }),
  );
  jobs.register('TRANSCODE', transcodeJob);
  jobs.register('UPLOAD_CLEANUP', async () => cleanupUploads(db, config));
  app.decorate('jobs', jobs);

  await app.register(cookie);
  await app.register(helmet, {
    // API liefert JSON; strikte Header, keine Inline-Ressourcen nötig
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'same-origin' },
  });
  await app.register(cors, {
    // Keine pauschale Freigabe: nur ausdrücklich konfigurierte Entwicklungs-Origins
    origin: config.CORS_ORIGINS.length ? config.CORS_ORIGINS : false,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: ['Authorization', 'Content-Type', 'X-CSRF-Token', 'Upload-Offset'],
    exposedHeaders: ['Upload-Offset'],
  });
  await app.register(rateLimit, { global: false });

  await app.register(swagger, {
    openapi: {
      info: { title: 'Demonify API', description: 'Private Musikplattform – API v1', version: '1.0.0' },
      servers: [{ url: '/' }],
      components: {
        securitySchemes: {
          bearerAuth: { type: 'http', scheme: 'bearer' },
          cookieAuth: { type: 'apiKey', in: 'cookie', name: 'dmf_at' },
        },
      },
      security: [{ bearerAuth: [] }, { cookieAuth: [] }],
    },
    transform: jsonSchemaTransform,
  });
  if (config.OPENAPI_UI) {
    await app.register(swaggerUi, { routePrefix: `${API_PREFIX}/docs` });
  }

  await app.register(authPlugin);

  // Rohdaten für Upload-Abschnitte (Stream, Größe wird im Dienst begrenzt)
  app.addContentTypeParser('application/octet-stream', (_req, payload, done) => done(null, payload));

  // Authentifizierte Antworten nie öffentlich cachen
  app.addHook('onSend', async (req, reply, payload) => {
    if (!reply.hasHeader('cache-control')) reply.header('cache-control', 'no-store');
    return payload;
  });

  app.setErrorHandler((err: FastifyError | ApiError, req, reply) => {
    if (err instanceof ApiError) {
      return reply.code(err.statusCode).send(errorBody(err.code, err.message, err.details));
    }
    if (hasZodFastifySchemaValidationErrors(err)) {
      return reply.code(400).send(
        errorBody('VALIDATION_ERROR', 'Ungültige Eingabe.', {
          issues: err.validation.map((v) => ({ path: v.instancePath, message: v.message })),
        }),
      );
    }
    const fe = err as FastifyError;
    if (fe.statusCode === 429) {
      return reply.code(429).send(errorBody('RATE_LIMITED', 'Zu viele Versuche. Bitte später erneut versuchen.'));
    }
    if (fe.statusCode && fe.statusCode >= 400 && fe.statusCode < 500) {
      return reply.code(fe.statusCode).send(errorBody(fe.code ?? 'BAD_REQUEST', fe.message));
    }
    req.log.error({ err }, 'Unerwarteter Fehler');
    return reply.code(500).send(errorBody('INTERNAL', 'Interner Serverfehler.'));
  });

  // Unbekannte Routen: immer JSON, niemals HTML
  app.setNotFoundHandler((req, reply) => {
    reply.code(404).send(errorBody('NOT_FOUND', `Unbekannter Endpunkt: ${req.method} ${req.url.split('?')[0]}`));
  });

  await app.register(registerRoutes, { prefix: API_PREFIX });

  app.get('/api/v1/openapi.json', { schema: { hide: true } }, async () => app.swagger());

  if (opts.startWorker ?? config.WORKER_ENABLED) {
    app.addHook('onReady', async () => {
      await jobs.start();
    });
  }
  app.addHook('onClose', async () => {
    await jobs.stop();
  });

  return app;
}
