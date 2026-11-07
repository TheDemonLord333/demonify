import type { FastifyInstance } from 'fastify';
import adminCatalogRoutes from './catalog.js';
import adminUploadRoutes from './uploads.js';
import adminUserRoutes from './users.js';
import adminJobRoutes from './jobs.js';

/** Alle Verwaltungsrouten: serverseitig nur für Rolle ADMIN – unabhängig von der Sichtbarkeit in App/Web. */
export default async function adminRoutes(app: FastifyInstance) {
  app.addHook('onRequest', app.requireAdmin);
  await app.register(adminCatalogRoutes);
  await app.register(adminUploadRoutes);
  await app.register(adminUserRoutes);
  await app.register(adminJobRoutes);
}
