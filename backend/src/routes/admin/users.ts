import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../../plugins/auth.js';
import { ApiError, badRequest, notFound } from '../../lib/errors.js';
import { randomToken, sha256 } from '../../lib/tokens.js';
import { createUser, deleteUserAccount, hashPassword, revokeAllSessions, toUserDto, validatePassword } from '../../services/auth.js';

export default async function adminUserRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const idParam = z.object({ id: z.uuid() });

  async function ensureAnotherAdmin(excludeId: string) {
    const admins = await app.db.user.count({ where: { role: 'ADMIN', disabledAt: null, id: { not: excludeId } } });
    if (admins === 0) throw new ApiError(409, 'LAST_ADMIN', 'Es muss mindestens ein aktives Administratorkonto bestehen bleiben.');
  }

  app.get('/users', { schema: { tags: ['Verwaltung'] } }, async () => {
    const users = await app.db.user.findMany({ orderBy: { usernameKey: 'asc' } });
    const sessions = await app.db.session.groupBy({
      by: ['userId'],
      where: { revokedAt: null, expiresAt: { gt: new Date() } },
      _count: { _all: true },
    });
    const counts = new Map(sessions.map((s) => [s.userId, s._count._all]));
    return { items: users.map((u) => ({ ...toUserDto(u), activeSessions: counts.get(u.id) ?? 0 })) };
  });

  app.post(
    '/users',
    {
      schema: {
        tags: ['Verwaltung'],
        body: z.object({
          username: z.string().min(3).max(32),
          password: z.string().min(10).max(256),
          role: z.enum(['ADMIN', 'USER']).default('USER'),
          displayName: z.string().max(64).optional(),
        }),
      },
    },
    async (req, reply) => {
      const user = await createUser(app.db, req.body);
      return reply.code(201).send({ user: toUserDto(user) });
    },
  );

  app.patch(
    '/users/:id',
    {
      schema: {
        tags: ['Verwaltung'],
        params: idParam,
        body: z.object({
          role: z.enum(['ADMIN', 'USER']).optional(),
          disabled: z.boolean().optional(),
          displayName: z.string().max(64).nullable().optional(),
          password: z.string().min(10).max(256).optional(),
        }),
      },
    },
    async (req) => {
      const self = authOf(req).userId;
      const user = await app.db.user.findUnique({ where: { id: req.params.id } });
      if (!user) throw notFound('Benutzer nicht gefunden.');
      const { role, disabled, displayName, password } = req.body;
      if ((role === 'USER' || disabled === true) && user.role === 'ADMIN') await ensureAnotherAdmin(user.id);
      if (user.id === self && disabled === true) throw badRequest('Das eigene Konto kann nicht gesperrt werden.');
      if (password) validatePassword(password);
      const updated = await app.db.user.update({
        where: { id: user.id },
        data: {
          role,
          displayName: displayName === undefined ? undefined : displayName?.trim() || null,
          disabledAt: disabled === undefined ? undefined : disabled ? new Date() : null,
          passwordHash: password ? await hashPassword(password) : undefined,
        },
      });
      // Sperren oder Passwortänderung beendet alle Sitzungen sofort
      if (disabled === true || password) await revokeAllSessions(app.db, user.id, disabled ? 'disabled' : 'password_reset');
      return { user: toUserDto(updated) };
    },
  );

  app.post('/users/:id/revoke-sessions', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    await revokeAllSessions(app.db, req.params.id, 'admin_revoked');
    return { ok: true };
  });

  app.delete('/users/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    if (req.params.id === authOf(req).userId) {
      throw badRequest('Das eigene Konto bitte in der App unter Einstellungen → Konto löschen entfernen.');
    }
    const user = await deleteUserAccount(app.db, req.params.id);
    req.log.info({ userId: user.id, by: authOf(req).userId }, 'Konto durch Administrator gelöscht');
    return { ok: true };
  });

  // ───────── Einladungen (zeitlich begrenzt, nur Hash gespeichert)
  app.get('/invites', { schema: { tags: ['Verwaltung'] } }, async () => {
    const invites = await app.db.invite.findMany({ orderBy: { createdAt: 'desc' }, take: 100, include: { usedBy: { select: { username: true } } } });
    const now = new Date();
    return {
      items: invites.map((i) => ({
        id: i.id,
        role: i.role,
        note: i.note,
        createdAt: i.createdAt.toISOString(),
        expiresAt: i.expiresAt.toISOString(),
        usedAt: i.usedAt?.toISOString() ?? null,
        usedBy: i.usedBy?.username ?? null,
        status: i.revokedAt ? 'REVOKED' : i.usedAt ? 'USED' : i.expiresAt < now ? 'EXPIRED' : 'OPEN',
      })),
    };
  });

  app.post(
    '/invites',
    {
      schema: {
        tags: ['Verwaltung'],
        body: z.object({
          role: z.enum(['ADMIN', 'USER']).default('USER'),
          expiresInHours: z.number().int().min(1).max(24 * 30).default(72),
          note: z.string().max(200).optional(),
        }),
      },
    },
    async (req, reply) => {
      const code = randomToken(24);
      const inv = await app.db.invite.create({
        data: {
          codeHash: sha256(code),
          role: req.body.role,
          note: req.body.note?.trim() || null,
          createdById: authOf(req).userId,
          expiresAt: new Date(Date.now() + req.body.expiresInHours * 3600_000),
        },
      });
      // Der Code wird nur einmal angezeigt
      return reply.code(201).send({
        invite: { id: inv.id, role: inv.role, expiresAt: inv.expiresAt.toISOString() },
        code,
        link: `${app.config.PUBLIC_BASE_URL}/admin/einladung/${code}`,
      });
    },
  );

  app.delete('/invites/:id', { schema: { tags: ['Verwaltung'], params: idParam } }, async (req) => {
    const res = await app.db.invite.updateMany({ where: { id: req.params.id, usedAt: null }, data: { revokedAt: new Date() } });
    if (res.count === 0) throw notFound('Offene Einladung nicht gefunden.');
    return { ok: true };
  });
}
