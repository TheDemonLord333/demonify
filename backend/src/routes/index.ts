import type { FastifyInstance } from 'fastify';
import healthRoutes from './health.js';
import authRoutes from './auth.js';
import meRoutes from './me.js';
import catalogRoutes from './catalog.js';
import searchRoutes from './search.js';
import libraryRoutes from './library.js';
import playlistRoutes from './playlists.js';
import streamRoutes from './stream.js';
import imageRoutes from './images.js';
import adminRoutes from './admin/index.js';

export async function registerRoutes(app: FastifyInstance) {
  await app.register(healthRoutes);
  await app.register(authRoutes, { prefix: '/auth' });
  await app.register(meRoutes, { prefix: '/me' });
  await app.register(catalogRoutes);
  await app.register(searchRoutes, { prefix: '/search' });
  await app.register(libraryRoutes, { prefix: '/library' });
  await app.register(playlistRoutes, { prefix: '/playlists' });
  await app.register(streamRoutes);
  await app.register(imageRoutes, { prefix: '/images' });
  await app.register(adminRoutes, { prefix: '/admin' });
}
