import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../plugins/auth.js';
import { cleanDisplayNameInput, deleteUserAccount, hashPassword, toUserDto, validatePassword, verifyPassword } from '../services/auth.js';
import { pendingEmail, requestEmailVerification } from '../services/account.js';
import { COOKIE_ACCESS, COOKIE_CSRF, COOKIE_REFRESH } from '../plugins/auth.js';
import { ApiError, notFound } from '../lib/errors.js';
import type { Prisma } from '../db.js';

export default async function meRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  app.addHook('onRequest', app.requireUser);

  const cfg = app.config;
  const setupInfo = async (userId: string) => ({
    emailRequired: cfg.mailEnabled,
    passwordResetAvailable: cfg.mailEnabled,
    pendingEmail: await pendingEmail(app.db, userId),
  });

  app.get('/', { config: { allowDuringSetup: true }, schema: { tags: ['Konto'] } }, async (req) => {
    const user = await app.db.user.findUniqueOrThrow({ where: { id: authOf(req).userId } });
    return { user: toUserDto(user), setup: await setupInfo(user.id) };
  });

  /** Anzeigename selbst setzen/ändern (Anmeldename und Konto-ID bleiben unverändert) */
  app.patch(
    '/',
    { config: { allowDuringSetup: true }, schema: { tags: ['Konto'], body: z.object({ displayName: z.string().max(200).nullable() }) } },
    async (req) => {
      const user = await app.db.user.update({
        where: { id: authOf(req).userId },
        data: { displayName: cleanDisplayNameInput(req.body.displayName) },
      });
      return { user: toUserDto(user) };
    },
  );

  /**
   * Ersteinrichtung nach Anmeldung mit Startpasswort: Anzeigename + eigenes Passwort.
   * Das Startpasswort ist danach ungültig; andere Sitzungen werden beendet.
   */
  app.post(
    '/setup',
    {
      config: { allowDuringSetup: true, rateLimit: { max: 10, timeWindow: '5 minutes' } },
      schema: {
        tags: ['Konto'],
        body: z.object({
          displayName: z.string().min(1).max(200),
          currentPassword: z.string().min(1).max(256),
          newPassword: z.string().min(1).max(256),
        }),
      },
    },
    async (req) => {
      const auth = authOf(req);
      const user = await app.db.user.findUniqueOrThrow({ where: { id: auth.userId } });
      const displayName = cleanDisplayNameInput(req.body.displayName);
      if (!displayName) throw new ApiError(400, 'DISPLAY_NAME_REQUIRED', 'Bitte gib einen Anzeigenamen an.');
      if (!(await verifyPassword(user.passwordHash, req.body.currentPassword))) {
        throw new ApiError(400, 'WRONG_PASSWORD', 'Das Startpasswort ist falsch.');
      }
      validatePassword(req.body.newPassword);
      if (req.body.newPassword === req.body.currentPassword) {
        throw new ApiError(400, 'SAME_PASSWORD', 'Das neue Passwort muss sich vom Startpasswort unterscheiden.');
      }
      const updated = await app.db.user.update({
        where: { id: user.id },
        data: { displayName, passwordHash: await hashPassword(req.body.newPassword), mustChangePassword: false },
      });
      await app.db.session.updateMany({
        where: { userId: user.id, revokedAt: null, id: { not: auth.sessionId } },
        data: { revokedAt: new Date(), revokeReason: 'initial_setup' },
      });
      req.log.info({ userId: user.id }, 'Ersteinrichtung abgeschlossen');
      return { user: toUserDto(updated), setup: await setupInfo(user.id) };
    },
  );

  /**
   * E-Mail-Adresse erfassen oder ändern: erneute Authentifizierung mit dem Passwort, dann Bestätigungslink
   * an die neue Adresse. Die bisherige Adresse bleibt bis zur Bestätigung aktiv.
   */
  app.post(
    '/email',
    {
      // pro Konto begrenzt (nach der Anmeldungsprüfung ausgewertet)
      config: { rateLimit: { hook: 'preHandler', max: 5, timeWindow: '15 minutes', keyGenerator: (r: { auth: { userId: string } | null; ip: string }) => `email:${r.auth?.userId ?? r.ip}` } },
      schema: { tags: ['Konto'], body: z.object({ email: z.string().min(3).max(254), password: z.string().min(1).max(256) }) },
    },
    async (req) => {
      const user = await app.db.user.findUniqueOrThrow({ where: { id: authOf(req).userId } });
      if (!(await verifyPassword(user.passwordHash, req.body.password))) {
        throw new ApiError(400, 'WRONG_PASSWORD', 'Das Passwort ist falsch.');
      }
      const res = await requestEmailVerification(app.db, cfg, app.mailer, user, req.body.email);
      return { ok: true, ...res };
    },
  );

  app.post(
    '/password',
    {
      config: { allowDuringSetup: true, rateLimit: { max: 5, timeWindow: '5 minutes' } },
      schema: { tags: ['Konto'], body: z.object({ currentPassword: z.string().min(1).max(256), newPassword: z.string().min(10).max(256) }) },
    },
    async (req) => {
      const auth = authOf(req);
      const user = await app.db.user.findUniqueOrThrow({ where: { id: auth.userId } });
      if (!(await verifyPassword(user.passwordHash, req.body.currentPassword))) {
        throw new ApiError(400, 'WRONG_PASSWORD', 'Das aktuelle Passwort ist falsch.');
      }
      validatePassword(req.body.newPassword);
      if (user.mustChangePassword && req.body.newPassword === req.body.currentPassword) {
        throw new ApiError(400, 'SAME_PASSWORD', 'Das neue Passwort muss sich vom Startpasswort unterscheiden.');
      }
      await app.db.user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(req.body.newPassword), mustChangePassword: false } });
      // Alle anderen Sitzungen beenden
      await app.db.session.updateMany({
        where: { userId: user.id, revokedAt: null, id: { not: auth.sessionId } },
        data: { revokedAt: new Date(), revokeReason: 'password_changed' },
      });
      return { ok: true };
    },
  );

  /** Eigenes Konto löschen – Bestätigung mit dem aktuellen Passwort */
  app.delete(
    '/',
    {
      config: { rateLimit: { max: 5, timeWindow: '5 minutes' } },
      schema: { tags: ['Konto'], body: z.object({ password: z.string().min(1).max(256) }) },
    },
    async (req, reply) => {
      const auth = authOf(req);
      const user = await app.db.user.findUniqueOrThrow({ where: { id: auth.userId } });
      if (!(await verifyPassword(user.passwordHash, req.body.password))) {
        throw new ApiError(400, 'WRONG_PASSWORD', 'Das Passwort ist falsch.');
      }
      await deleteUserAccount(app.db, user.id);
      req.log.info({ userId: user.id }, 'Konto vom Benutzer gelöscht');
      reply.clearCookie(COOKIE_ACCESS, { path: '/api/' });
      reply.clearCookie(COOKIE_REFRESH, { path: '/api/v1/auth/' });
      reply.clearCookie(COOKIE_CSRF, { path: '/' });
      return { ok: true };
    },
  );

  app.get('/sessions', { schema: { tags: ['Konto'] } }, async (req) => {
    const auth = authOf(req);
    const sessions = await app.db.session.findMany({
      where: { userId: auth.userId, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { lastUsedAt: 'desc' },
    });
    return {
      items: sessions.map((s) => ({
        id: s.id,
        clientType: s.clientType,
        deviceName: s.deviceName,
        createdAt: s.createdAt.toISOString(),
        lastUsedAt: s.lastUsedAt.toISOString(),
        current: s.id === auth.sessionId,
      })),
    };
  });

  app.delete('/sessions/:id', { schema: { tags: ['Konto'], params: z.object({ id: z.uuid() }) } }, async (req) => {
    const auth = authOf(req);
    const res = await app.db.session.updateMany({
      where: { id: req.params.id, userId: auth.userId, revokedAt: null },
      data: { revokedAt: new Date(), revokeReason: 'user_revoked' },
    });
    if (res.count === 0) throw notFound('Sitzung nicht gefunden.');
    return { ok: true };
  });

  // Benutzerbezogene Einstellungen (geräteübergreifend). Gerätespezifisches wie EQ bleibt lokal in der App.
  const settingsSchema = z
    .object({
      streamingQuality: z.enum(['original', 'high', 'normal', 'low']).optional(),
      downloadQuality: z.enum(['original', 'high', 'normal', 'low']).optional(),
    })
    .strict();

  app.get('/settings', { schema: { tags: ['Konto'] } }, async (req) => {
    const s = await app.db.userSettings.findUnique({ where: { userId: authOf(req).userId } });
    return { settings: { streamingQuality: 'original', downloadQuality: 'original', ...((s?.data as object) ?? {}) } };
  });

  app.put('/settings', { schema: { tags: ['Konto'], body: settingsSchema } }, async (req) => {
    const userId = authOf(req).userId;
    const current = await app.db.userSettings.findUnique({ where: { userId } });
    const data = { ...((current?.data as object) ?? {}), ...req.body } as Prisma.InputJsonValue;
    const s = await app.db.userSettings.upsert({ where: { userId }, create: { userId, data }, update: { data } });
    return { settings: s.data };
  });
}
