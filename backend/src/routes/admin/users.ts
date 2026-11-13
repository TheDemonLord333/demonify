import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authOf } from '../../plugins/auth.js';
import { ApiError, badRequest, notFound } from '../../lib/errors.js';
import { randomToken, sha256 } from '../../lib/tokens.js';
import {
  cleanDisplayNameInput,
  createUser,
  deleteUserAccount,
  hashPassword,
  revokeAllSessions,
  toUserDto,
  validatePassword,
  validateUsername,
} from '../../services/auth.js';
import { isUniqueViolation } from '../../lib/errors.js';
import { pendingEmail } from '../../services/account.js';

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
    const pending = await app.db.emailToken.findMany({
      where: { kind: 'VERIFY_EMAIL', usedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'asc' },
      select: { userId: true, email: true },
    });
    const pendingBy = new Map(pending.map((p) => [p.userId, p.email]));
    return { items: users.map((u) => ({ ...toUserDto(u), pendingEmail: pendingBy.get(u.id) ?? null, activeSessions: counts.get(u.id) ?? 0 })) };
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
          /** Startpasswort → erste Anmeldung führt durch die Ersteinrichtung (Standard) */
          requirePasswordChange: z.boolean().default(true),
        }),
      },
    },
    async (req, reply) => {
      const { requirePasswordChange, ...input } = req.body;
      const user = await createUser(app.db, { ...input, mustChangePassword: requirePasswordChange });
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
          /** Anmeldename (eindeutig) – Konto-ID, Bibliothek, Playlists und Favoriten bleiben unverändert */
          username: z.string().min(1).max(64).optional(),
          /** Anzeigename (nur Darstellung) */
          displayName: z.string().max(200).nullable().optional(),
          /** Manueller Reset: neues Startpasswort */
          password: z.string().min(10).max(256).optional(),
          /** Beim manuellen Reset Passwortwechsel bei der nächsten Anmeldung verlangen (Standard) */
          requirePasswordChange: z.boolean().default(true),
        }),
      },
    },
    async (req) => {
      const self = authOf(req).userId;
      const user = await app.db.user.findUnique({ where: { id: req.params.id } });
      if (!user) throw notFound('Benutzer nicht gefunden.');
      const { role, disabled, displayName, password, requirePasswordChange } = req.body;
      let usernameData: { username: string; usernameKey: string } | undefined;
      if (req.body.username !== undefined) {
        const { username, key } = validateUsername(req.body.username);
        const other = await app.db.user.findUnique({ where: { usernameKey: key } });
        if (other && other.id !== user.id) throw new ApiError(409, 'USERNAME_TAKEN', 'Dieser Anmeldename ist bereits vergeben.');
        usernameData = { username, usernameKey: key };
      }
      if ((role === 'USER' || disabled === true) && user.role === 'ADMIN') await ensureAnotherAdmin(user.id);
      if (user.id === self && disabled === true) throw badRequest('Das eigene Konto kann nicht gesperrt werden.');
      if (password) validatePassword(password);
      const updated = await app.db.user
        .update({
          where: { id: user.id },
          data: {
            role,
            ...usernameData,
            displayName: displayName === undefined ? undefined : cleanDisplayNameInput(displayName),
            disabledAt: disabled === undefined ? undefined : disabled ? new Date() : null,
            passwordHash: password ? await hashPassword(password) : undefined,
            mustChangePassword: password ? requirePasswordChange : undefined,
          },
        })
        .catch((e) => {
          if (isUniqueViolation(e)) throw new ApiError(409, 'USERNAME_TAKEN', 'Dieser Anmeldename ist bereits vergeben.');
          throw e;
        });
      // Sperren oder Passwortänderung beendet alle Sitzungen sofort
      if (disabled === true || password) await revokeAllSessions(app.db, user.id, disabled ? 'disabled' : 'password_reset');
      return { user: { ...toUserDto(updated), pendingEmail: await pendingEmail(app.db, updated.id) } };
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
