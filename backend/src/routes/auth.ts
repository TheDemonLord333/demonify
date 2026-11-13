import type { FastifyInstance, FastifyReply } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { authenticate, createSession, createUser, revokeSession, rotateRefreshToken, toUserDto, type IssuedTokens } from '../services/auth.js';
import { COOKIE_ACCESS, COOKIE_CSRF, COOKIE_REFRESH, authOf } from '../plugins/auth.js';
import { ApiError, unauthorized } from '../lib/errors.js';
import { randomToken, sha256 } from '../lib/tokens.js';
import { usernameKey } from '../lib/normalize.js';
import {
  FORGOT_NEUTRAL_MESSAGE,
  checkToken,
  confirmEmail,
  pendingEmail,
  requestEmailVerification,
  requestPasswordReset,
  resetPassword,
  normalizeEmail,
} from '../services/account.js';

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
      // Schlüssel: IP + normalisierte Eingabe (Anmeldename oder E-Mail)
      keyGenerator: (req: { ip: string; body?: unknown }) => {
        const b = req.body as { username?: string; identifier?: string } | undefined;
        return `login:${req.ip}:${usernameKey(String(b?.identifier ?? b?.username ?? '')).slice(0, 254)}`;
      },
    },
  };

  /** Zusatzinfos für die Ersteinrichtung in App/Web */
  async function setupInfo(userId: string) {
    return { emailRequired: cfg.mailEnabled, passwordResetAvailable: cfg.mailEnabled, pendingEmail: await pendingEmail(app.db, userId) };
  }

  // Einlösen/Prüfen von Links: pro IP begrenzt (Tokens sind 256 Bit zufällig – Raten ist aussichtslos)
  const tokenLimit = { rateLimit: { max: Math.max(10, cfg.FORGOT_RATE_LIMIT_MAX * 2), timeWindow: '15 minutes' } };

  app.get('/config', { schema: { tags: ['Auth'], security: [] } }, async () => ({
    emailRequired: cfg.mailEnabled,
    passwordResetAvailable: cfg.mailEnabled,
  }));

  app.post(
    '/login',
    {
      config: loginLimit,
      schema: {
        tags: ['Auth'],
        security: [],
        body: z
          .object({
            /** Anmeldename oder bestätigte E-Mail-Adresse */
            identifier: z.string().min(1).max(254).optional(),
            /** Ältere Clients: nur Anmeldename */
            username: z.string().min(1).max(254).optional(),
            password: z.string().min(1).max(256),
            client: z.enum(['app', 'web']).default('app'),
            deviceName: z.string().max(100).optional(),
          })
          .refine((b) => !!(b.identifier ?? b.username), { message: 'Anmeldename oder E-Mail fehlt.' }),
      },
    },
    async (req, reply) => {
      const { identifier, username, password, client, deviceName } = req.body;
      const user = await authenticate(app.db, (identifier ?? username)!, password);
      const tokens = await createSession(app.db, cfg, user, {
        clientType: client === 'web' ? 'WEB' : 'APP',
        deviceName,
        userAgent: req.headers['user-agent'],
      });
      req.log.info({ userId: user.id, client }, 'Anmeldung erfolgreich');
      const setup = await setupInfo(user.id);
      if (client === 'web') {
        const csrfToken = setWebCookies(reply, tokens);
        return { user: toUserDto(user), setup, csrfToken, accessTokenExpiresAt: tokens.accessTokenExpiresAt };
      }
      return { user: toUserDto(user), setup, ...tokens };
    },
  );

  app.post(
    '/refresh',
    {
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
      schema: { tags: ['Auth'], security: [], body: z.object({ refreshToken: z.string().min(10).max(200).optional() }).nullish() },
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

  app.post('/logout', { onRequest: app.requireUser, config: { allowDuringSetup: true }, schema: { tags: ['Auth'] } }, async (req, reply) => {
    const auth = authOf(req);
    await revokeSession(app.db, auth.sessionId, 'logout');
    clearWebCookies(reply);
    return { ok: true };
  });

  // Web-Session prüfen (für die Verwaltungsseite beim Laden)
  app.get('/session', { onRequest: app.requireUser, config: { allowDuringSetup: true }, schema: { tags: ['Auth'] } }, async (req) => {
    const auth = authOf(req);
    const user = await app.db.user.findUniqueOrThrow({ where: { id: auth.userId } });
    return { user: toUserDto(user), setup: await setupInfo(user.id), csrfToken: req.cookies[COOKIE_CSRF] ?? null };
  });

  // ───────── Passwort vergessen (Link per Mail an die bestätigte Adresse)
  app.post(
    '/password/forgot',
    {
      // pro IP begrenzt; pro Konto zusätzlich im Dienst (3/Stunde, 1/Minute)
      config: { rateLimit: { max: cfg.FORGOT_RATE_LIMIT_MAX, timeWindow: '15 minutes', keyGenerator: (req: { ip: string }) => `forgot:${req.ip}` } },
      schema: { tags: ['Auth'], security: [], body: z.object({ identifier: z.string().min(1).max(254) }) },
    },
    async (req) => {
      // Nicht abwarten: gleiche Antwort und gleiches Zeitverhalten, egal ob das Konto existiert
      void requestPasswordReset(app.db, cfg, app.mailer, req.body.identifier).catch((e: Error) =>
        req.log.warn({ err: e.message }, 'Passwort-Reset-Mail konnte nicht gesendet werden'),
      );
      return { ok: true, message: FORGOT_NEUTRAL_MESSAGE };
    },
  );

  app.post(
    '/password/reset',
    {
      config: tokenLimit,
      schema: { tags: ['Auth'], security: [], body: z.object({ token: z.string().min(20).max(200), password: z.string().min(1).max(256) }) },
    },
    async (req) => {
      const user = await resetPassword(app.db, app.mailer, req.body.token, req.body.password);
      req.log.info({ userId: user.id }, 'Passwort über Reset-Link geändert');
      return { ok: true };
    },
  );

  /** Link prüfen, ohne ihn zu verbrauchen (Webseite zeigt sonst gleich „abgelaufen“) */
  app.post(
    '/tokens/check',
    {
      config: { rateLimit: { max: Math.max(30, cfg.FORGOT_RATE_LIMIT_MAX * 2), timeWindow: '15 minutes' } },
      schema: {
        tags: ['Auth'],
        security: [],
        body: z.object({ token: z.string().min(20).max(200), kind: z.enum(['VERIFY_EMAIL', 'PASSWORD_RESET']) }),
      },
    },
    async (req) => checkToken(app.db, req.body.token, req.body.kind),
  );

  app.post(
    '/email/confirm',
    {
      config: tokenLimit,
      schema: { tags: ['Auth'], security: [], body: z.object({ token: z.string().min(20).max(200) }) },
    },
    async (req) => {
      const user = await confirmEmail(app.db, app.mailer, req.body.token);
      req.log.info({ userId: user.id }, 'E-Mail-Adresse bestätigt');
      return { ok: true, email: user.email };
    },
  );

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
          email: z.string().max(254).optional(),
        }),
      },
    },
    async (req) => {
      const { code, username, password, displayName, email } = req.body;
      if (cfg.mailEnabled) {
        if (!email?.trim()) throw new ApiError(400, 'EMAIL_REQUIRED', 'Bitte gib deine E-Mail-Adresse an.');
        const taken = await app.db.user.findUnique({ where: { emailKey: normalizeEmail(email).key } });
        if (taken) throw new ApiError(409, 'EMAIL_TAKEN', 'Diese E-Mail-Adresse wird bereits von einem anderen Konto verwendet.');
        if (!displayName?.trim()) throw new ApiError(400, 'DISPLAY_NAME_REQUIRED', 'Bitte gib einen Anzeigenamen an.');
      }
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
        let emailSent = false;
        let emailError: string | null = null;
        if (cfg.mailEnabled && email) {
          try {
            await requestEmailVerification(app.db, cfg, app.mailer, user, email);
            emailSent = true;
          } catch (e) {
            // Konto ist angelegt; die Adresse kann nach dem Anmelden erneut eingegeben werden
            emailError = e instanceof ApiError ? e.message : 'Die Bestätigungsmail konnte nicht gesendet werden.';
            req.log.warn({ userId: user.id, err: (e as Error).message }, 'Bestätigungsmail nach Einladung fehlgeschlagen');
          }
        }
        return { user: toUserDto(user), emailSent, emailError };
      } catch (e) {
        await app.db.invite.update({ where: { id: inv.id }, data: { usedAt: null } });
        throw e;
      }
    },
  );
}
