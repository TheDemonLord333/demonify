import type { FastifyInstance } from 'fastify';

/** Health-Check ohne sensible Informationen (keine Versionen, Pfade oder Fehlertexte) */
export default async function healthRoutes(app: FastifyInstance) {
  app.get('/health', { schema: { tags: ['System'], security: [] } }, async (_req, reply) => {
    let database = 'ok';
    try {
      await app.db.$queryRaw`SELECT 1`;
    } catch {
      database = 'error';
    }
    const ok = database === 'ok';
    return reply.code(ok ? 200 : 503).send({ status: ok ? 'ok' : 'degraded', database });
  });
}
