import type { FastifyInstance, FastifyReply } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authenticate, createSession, createUser, revokeSession, rotateRefreshToken, toUserDto, type IssuedTokens } from '../services/auth.js';
import { COOKIE_ACCESS, COOKIE_CSRF, COOKIE_REFRESH, authOf } from '../plugins/auth.js';
import { ApiError, unauthorized } from '../lib/errors.js';
import { randomToken, sha256 } from '../lib/tokens.js';
import { usernameKey } from '../lib/normalize.js';

export default async function authRoutes(fastify: FastifyInstance) {
  const app = fastify.withTypeProvider<ZodTypeProvider>();
  const cfg = app.config;

  function setWebCookies(reply: FastifyReply, t: IssuedTokens) {
    const base = { httpOnly: true, secure: cfg.cookieSecure, sameSite: 'strict' as const };
    reply.setCookie(COOKIE_ACCESS, t.accessToken, { ...base, path: '/api/', expires: new Date(t.accessTokenExpiresAt) });
    reply.setCookie(COOKIE_REFRESH, t.refreshToken, { ...base, path: '/api/v1/auth/', expires: new Date(t.refreshTokenExpiresAt) });
    const csrf = randomToken(24);
    // CSRF-Token ist absichtlich lesbar (Double-Submit), aber an SameSite=Strict gebunden
    reply.setCookie(COOKIE_CSRF, csrf, { httpOnly: false, secure: cfg.cookieSecure, sameSite: 'strict', path: '/', expires: new Date(t.refreshTokenExpiresAt) });
    return csrf;
  }

  function clearWebCookies(reply: FastifyReply) {
    reply.clearCookie(COOKIE_ACCESS, { path: '/api/' });
    reply.clearCookie(COOKIE_REFRESH, { path: '/api/v1/auth/' });
    reply.clearCookie(COOKIE_CSRF, { path: '/' });
  }

  const loginLimit = {
    rateLimit: {
      // erst nach dem Parsen des Bodys auswerten, damit der Benutzername in den Schlüssel eingeht
      hook: 'preHandler' as const,
      max: cfg.LOGIN_RATE_LIMIT_MAX,
      timeWindow: cfg.LOGIN_RATE_LIMIT_WINDOW,
      // Schlüssel: IP + normalisierter Benutzername
      keyGenerator: (req: { ip: string; body?: unknown }) => {
        const u = (req.body as { username?: string } | undefined)?.username ?? '';
        return `login:${req.ip}:${usernameKey(String(u)).slice(0, 64)}`;
      },
    },
  };

  app.post(
    '/login',
    {
      config: loginLimit,
      schema: {
        tags: ['Auth'],
        security: [],
        body: z.object({
          username: z.string().min(1).max(64),
          password: z.string().min(1).max(256),
          client: z.enum(['app', 'web']).default('app'),
          deviceName: z.string().max(100).optional(),
        }),
      },
    },
    async (req, reply) => {
      const { username, password, client, deviceName } = req.body;
      const user = await authenticate(app.db, username, password);
      const tokens = await createSession(app.db, cfg, user, {
        clientType: client === 'web' ? 'WEB' : 'APP',
        deviceName,
        userAgent: req.headers['user-agent'],
      });
      req.log.info({ userId: user.id, client }, 'Anmeldung erfolgreich');
      if (client === 'web') {
        const csrfToken = setWebCookies(reply, tokens);
        return { user: toUserDto(user), csrfToken, accessTokenExpiresAt: tokens.accessTokenExpiresAt };
      }
      return { user: toUserDto(user), ...tokens };
    },
  );

  app.post(
    '/refresh',
    {
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
      schema: { tags: ['Auth'], security: [], body: z.object({ refreshToken: z.string().min(10).max(200).optional() }).optional() },
    },
    async (req, reply) => {
      const fromBody = req.body?.refreshToken;
      const fromCookie = req.cookies[COOKIE_REFRESH];
      if (!fromBody && !fromCookie) throw unauthorized('Keine Sitzung vorhanden.', 'INVALID_REFRESH_TOKEN');
      if (!fromBody) {
        // Cookie-basiert → CSRF prüfen
        const sent = req.headers['x-csrf-token'];
        if (typeof sent !== 'string' || sent !== req.cookies[COOKIE_CSRF]) {
          throw new ApiError(403, 'CSRF_FAILED', 'Sicherheitsprüfung fehlgeschlagen. Bitte Seite neu laden.');
        }
      }
      try {
        const tokens = await rotateRefreshToken(app.db, cfg, (fromBody ?? fromCookie)!);
        const session = await app.db.session.findUniqueOrThrow({ where: { id: tokens.sessionId }, include: { user: true } });
        if (!fromBody) {
          const csrfToken = setWebCookies(reply, tokens);
          return { user: toUserDto(session.user), csrfToken, accessTokenExpiresAt: tokens.accessTokenExpiresAt };
        }
        return { user: toUserDto(session.user), ...tokens };
      } catch (e) {
        if (!fromBody) clearWebCookies(reply);
        throw e;
      }
    },
  );

  app.post('/logout', { onRequest: app.requireUser, schema: { tags: ['Auth'] } }, async (req, reply) => {
    const auth = authOf(req);
    await revokeSession(app.db, auth.sessionId, 'logout');
    clearWebCookies(reply);
    return { ok: true };
  });

  // Web-Session prüfen (für die Verwaltungsseite beim Laden)
  app.get('/session', { onRequest: app.requireUser, schema: { tags: ['Auth'] } }, async (req) => {
    const auth = authOf(req);
    const user = await app.db.user.findUniqueOrThrow({ where: { id: auth.userId } });
    return { user: toUserDto(user), csrfToken: req.cookies[COOKIE_CSRF] ?? null };
  });

  app.get(
    '/invites/:code',
    {
      config: { rateLimit: { max: 20, timeWindow: '5 minutes' } },
      schema: { tags: ['Auth'], security: [], params: z.object({ code: z.string().min(10).max(100) }) },
    },
    async (req) => {
      const inv = await app.db.invite.findUnique({ where: { codeHash: sha256(req.params.code) } });
      const valid = !!inv && !inv.usedAt && !inv.revokedAt && inv.expiresAt > new Date();
      return { valid, expiresAt: valid ? inv!.expiresAt.toISOString() : null };
    },
  );

  app.post(
    '/invites/redeem',
    {
      config: { rateLimit: { max: 10, timeWindow: '5 minutes' } },
      schema: {
        tags: ['Auth'],
        security: [],
        body: z.object({
          code: z.string().min(10).max(100),
          username: z.string().min(3).max(32),
          password: z.string().min(10).max(256),
          displayName: z.string().max(64).optional(),
        }),
      },
    },
    async (req) => {
      const { code, username, password, displayName } = req.body;
      const inv = await app.db.invite.findUnique({ where: { codeHash: sha256(code) } });
      if (!inv || inv.usedAt || inv.revokedAt || inv.expiresAt < new Date()) {
        throw new ApiError(410, 'INVITE_INVALID', 'Die Einladung ist ungültig oder abgelaufen.');
      }
      // Einladung atomar beanspruchen
      const claimed = await app.db.invite.updateMany({ where: { id: inv.id, usedAt: null }, data: { usedAt: new Date() } });
      if (claimed.count === 0) throw new ApiError(410, 'INVITE_INVALID', 'Die Einladung wurde bereits verwendet.');
      try {
        const user = await createUser(app.db, { username, password, role: inv.role, displayName });
        await app.db.invite.update({ where: { id: inv.id }, data: { usedById: user.id } });
        return { user: toUserDto(user) };
      } catch (e) {
        await app.db.invite.update({ where: { id: inv.id }, data: { usedAt: null } });
        throw e;
      }
    },
  );
}
