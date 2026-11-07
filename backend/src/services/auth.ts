import argon2 from 'argon2';
import type { AppConfig } from '../config.js';
import type { Db } from '../db.js';
import { randomToken, sha256, signToken, type AccessPayload } from '../lib/tokens.js';
import { ApiError, badRequest, unauthorized } from '../lib/errors.js';
import { cleanDisplayName, usernameKey } from '../lib/normalize.js';

/** Argon2id-Parameter (OWASP-Empfehlung: m=19 MiB, t=2 – hier etwas stärker) */
const ARGON_OPTS = { type: argon2.argon2id, memoryCost: 65536, timeCost: 3, parallelism: 1 } as const;

export async function hashPassword(pw: string): Promise<string> {
  return argon2.hash(pw, ARGON_OPTS);
}

export async function verifyPassword(hash: string, pw: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, pw);
  } catch {
    return false;
  }
}

/** Fester Dummy-Hash, damit unbekannte Benutzernamen gleich lange brauchen (Timing). */
let dummyHash: string | null = null;
async function getDummyHash() {
  dummyHash ??= await hashPassword(randomToken(16));
  return dummyHash;
}

export function validatePassword(pw: string) {
  if (pw.length < 10) throw badRequest('Das Passwort muss mindestens 10 Zeichen lang sein.');
  if (pw.length > 256) throw badRequest('Das Passwort ist zu lang.');
}

export function validateUsername(raw: string): { username: string; key: string } {
  const username = cleanDisplayName(raw);
  if (!/^[\p{L}\p{N}._-]{3,32}$/u.test(username)) {
    throw badRequest('Benutzername: 3–32 Zeichen, nur Buchstaben, Ziffern, Punkt, Unter- und Bindestrich.');
  }
  return { username, key: usernameKey(username) };
}

export interface IssuedTokens {
  accessToken: string;
  accessTokenExpiresAt: string;
  refreshToken: string;
  refreshTokenExpiresAt: string;
  sessionId: string;
}

export async function authenticate(db: Db, username: string, password: string) {
  const user = await db.user.findUnique({ where: { usernameKey: usernameKey(username) } });
  if (!user) {
    await verifyPassword(await getDummyHash(), password);
    throw unauthorized('Benutzername oder Passwort ist falsch.', 'INVALID_CREDENTIALS');
  }
  const ok = await verifyPassword(user.passwordHash, password);
  if (!ok) throw unauthorized('Benutzername oder Passwort ist falsch.', 'INVALID_CREDENTIALS');
  if (user.disabledAt) throw new ApiError(403, 'ACCOUNT_DISABLED', 'Dieses Konto ist gesperrt.');
  if (argon2.needsRehash(user.passwordHash, ARGON_OPTS)) {
    await db.user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(password) } });
  }
  return user;
}

export async function createSession(
  db: Db,
  config: AppConfig,
  user: { id: string; role: 'ADMIN' | 'USER' },
  meta: { clientType: 'WEB' | 'APP'; deviceName?: string; userAgent?: string },
): Promise<IssuedTokens> {
  const expiresAt = new Date(Date.now() + config.REFRESH_TOKEN_TTL_DAYS * 86400_000);
  const session = await db.session.create({
    data: {
      userId: user.id,
      clientType: meta.clientType,
      deviceName: meta.deviceName?.slice(0, 100),
      userAgent: meta.userAgent?.slice(0, 300),
      expiresAt,
    },
  });
  await db.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
  return issueTokens(db, config, session.id, user, expiresAt);
}

async function issueTokens(
  db: Db,
  config: AppConfig,
  sessionId: string,
  user: { id: string; role: 'ADMIN' | 'USER' },
  sessionExpiresAt: Date,
): Promise<IssuedTokens> {
  const exp = Math.floor(Date.now() / 1000) + config.ACCESS_TOKEN_TTL_SECONDS;
  const payload: AccessPayload = { sub: user.id, sid: sessionId, role: user.role, exp, typ: 'access' };
  const accessToken = signToken(payload, config.AUTH_TOKEN_SECRET);
  const refreshToken = randomToken(32);
  await db.refreshToken.create({ data: { sessionId, tokenHash: sha256(refreshToken), expiresAt: sessionExpiresAt } });
  return {
    accessToken,
    accessTokenExpiresAt: new Date(exp * 1000).toISOString(),
    refreshToken,
    refreshTokenExpiresAt: sessionExpiresAt.toISOString(),
    sessionId,
  };
}

/**
 * Refresh-Token-Rotation mit Wiederverwendungserkennung:
 * Wird ein bereits benutztes Token erneut vorgelegt, wird die gesamte Session widerrufen.
 */
export async function rotateRefreshToken(db: Db, config: AppConfig, refreshToken: string): Promise<IssuedTokens> {
  const hash = sha256(refreshToken);
  const row = await db.refreshToken.findUnique({ where: { tokenHash: hash }, include: { session: { include: { user: true } } } });
  if (!row) throw unauthorized('Sitzung ungültig. Bitte erneut anmelden.', 'INVALID_REFRESH_TOKEN');
  const s = row.session;
  if (row.usedAt) {
    // Kurzes Toleranzfenster für parallele Anfragen desselben Clients (z. B. App-Neustart)
    if (Date.now() - row.usedAt.getTime() > 10_000) {
      await db.session.update({ where: { id: s.id }, data: { revokedAt: new Date(), revokeReason: 'refresh_token_reuse' } });
    }
    throw unauthorized('Sitzung ungültig. Bitte erneut anmelden.', 'INVALID_REFRESH_TOKEN');
  }
  if (s.revokedAt || s.expiresAt < new Date() || row.expiresAt < new Date() || s.user.disabledAt) {
    throw unauthorized('Sitzung abgelaufen. Bitte erneut anmelden.', 'INVALID_REFRESH_TOKEN');
  }
  const claimed = await db.refreshToken.updateMany({ where: { id: row.id, usedAt: null }, data: { usedAt: new Date() } });
  if (claimed.count === 0) throw unauthorized('Sitzung ungültig. Bitte erneut anmelden.', 'INVALID_REFRESH_TOKEN');
  await db.session.update({ where: { id: s.id }, data: { lastUsedAt: new Date() } });
  return issueTokens(db, config, s.id, s.user, s.expiresAt);
}

export async function revokeSession(db: Db, sessionId: string, reason: string) {
  await db.session.updateMany({ where: { id: sessionId, revokedAt: null }, data: { revokedAt: new Date(), revokeReason: reason } });
}

export async function revokeAllSessions(db: Db, userId: string, reason: string) {
  await db.session.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date(), revokeReason: reason } });
}

export async function createUser(
  db: Db,
  input: { username: string; password: string; role: 'ADMIN' | 'USER'; displayName?: string | null },
) {
  const { username, key } = validateUsername(input.username);
  validatePassword(input.password);
  const existing = await db.user.findUnique({ where: { usernameKey: key } });
  if (existing) throw new ApiError(409, 'USERNAME_TAKEN', 'Dieser Benutzername ist bereits vergeben.');
  return db.user.create({
    data: {
      username,
      usernameKey: key,
      displayName: input.displayName?.trim() || null,
      passwordHash: await hashPassword(input.password),
      role: input.role,
    },
  });
}

export function toUserDto(u: { id: string; username: string; displayName: string | null; role: string; disabledAt: Date | null; createdAt: Date; lastLoginAt: Date | null }) {
  return {
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    role: u.role,
    disabled: u.disabledAt !== null,
    createdAt: u.createdAt.toISOString(),
    lastLoginAt: u.lastLoginAt?.toISOString() ?? null,
  };
}
