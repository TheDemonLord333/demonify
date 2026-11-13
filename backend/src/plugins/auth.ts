import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import fp from './fp.js';
import { verifyToken, safeEqual, type AccessPayload } from '../lib/tokens.js';
import { ApiError, forbidden, unauthorized } from '../lib/errors.js';

export const COOKIE_ACCESS = 'dmf_at';
export const COOKIE_REFRESH = 'dmf_rt';
export const COOKIE_CSRF = 'dmf_csrf';

export interface AuthInfo {
  userId: string;
  sessionId: string;
  role: 'ADMIN' | 'USER';
  via: 'bearer' | 'cookie';
}

declare module 'fastify' {
  interface FastifyContextConfig {
    /** Route bleibt erreichbar, solange die Ersteinrichtung (Startpasswort ändern) aussteht */
    allowDuringSetup?: boolean;
  }
  interface FastifyRequest {
    auth: AuthInfo | null;
  }
  interface FastifyInstance {
    requireUser: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    requireAdmin: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

/**
 * Authentifizierung:
 * - App: "Authorization: Bearer <access>" (Tokens im sicheren Plattformspeicher)
 * - Web: HttpOnly-Cookie (Secure, SameSite=Strict) + Double-Submit-CSRF-Token im Header
 * Jede Anfrage prüft zusätzlich serverseitig, ob Session und Benutzer noch aktiv sind
 * (Sperren/Abmelden wirkt sofort).
 */
export default fp(async function authPlugin(app: FastifyInstance) {
  app.decorateRequest('auth', null);

  async function resolve(req: FastifyRequest): Promise<AuthInfo> {
    const header = req.headers.authorization;
    let token: string | undefined;
    let via: AuthInfo['via'] = 'bearer';
    if (header?.startsWith('Bearer ')) token = header.slice(7).trim();
    else if (req.cookies?.[COOKIE_ACCESS]) {
      token = req.cookies[COOKIE_ACCESS];
      via = 'cookie';
    }
    if (!token) throw unauthorized();
    const payload = verifyToken<AccessPayload>(token, app.config.AUTH_TOKEN_SECRET);
    if (!payload || payload.typ !== 'access') throw unauthorized('Anmeldung abgelaufen oder ungültig.', 'TOKEN_INVALID');

    if (via === 'cookie' && !SAFE_METHODS.has(req.method)) {
      const sent = req.headers['x-csrf-token'];
      const cookie = req.cookies?.[COOKIE_CSRF];
      if (typeof sent !== 'string' || !cookie || !safeEqual(sent, cookie)) {
        throw new ApiError(403, 'CSRF_FAILED', 'Sicherheitsprüfung fehlgeschlagen. Bitte Seite neu laden.');
      }
    }

    const session = await app.db.session.findUnique({
      where: { id: payload.sid },
      select: { revokedAt: true, expiresAt: true, userId: true, user: { select: { disabledAt: true, role: true, mustChangePassword: true } } },
    });
    if (!session || session.userId !== payload.sub || session.revokedAt || session.expiresAt < new Date()) {
      throw unauthorized('Sitzung beendet. Bitte erneut anmelden.', 'SESSION_REVOKED');
    }
    if (session.user.disabledAt) throw new ApiError(403, 'ACCOUNT_DISABLED', 'Dieses Konto ist gesperrt.');
    // Startpasswort: bis zum Passwortwechsel nur die Routen der Ersteinrichtung
    if (session.user.mustChangePassword && !req.routeOptions.config?.allowDuringSetup) {
      throw new ApiError(403, 'PASSWORD_CHANGE_REQUIRED', 'Bitte schließe zuerst die Ersteinrichtung ab und lege ein eigenes Passwort fest.');
    }
    // Rolle immer aus der Datenbank (Rollenänderung wirkt sofort)
    return { userId: payload.sub, sessionId: payload.sid, role: session.user.role, via };
  }

  app.decorate('requireUser', async (req: FastifyRequest) => {
    req.auth = await resolve(req);
  });
  app.decorate('requireAdmin', async (req: FastifyRequest) => {
    req.auth = await resolve(req);
    if (req.auth.role !== 'ADMIN') throw forbidden('Nur für Administratoren.');
  });
});

export function authOf(req: FastifyRequest): AuthInfo {
  if (!req.auth) throw unauthorized();
  return req.auth;
}
