import type { AppConfig } from '../config.js';
import type { Db } from '../db.js';
import { ApiError, badRequest, isUniqueViolation } from '../lib/errors.js';
import { cleanDisplayName, usernameKey } from '../lib/normalize.js';
import { randomToken, sha256 } from '../lib/tokens.js';
import { hashPassword, validatePassword } from './auth.js';
import { composeMail, type Mailer } from './mail.js';

/**
 * Konto-E-Mail, Bestätigung und „Passwort vergessen“.
 *
 * Normalisierung (überall gleich: Erfassen, Anmelden, Ändern, Zurücksetzen):
 *   Anzeige: NFKC, unsichtbare Zeichen entfernt, getrimmt.  Schlüssel (emailKey): zusätzlich Kleinschreibung.
 * Eindeutigkeit: emailKey ist in der Datenbank UNIQUE und enthält nur bestätigte Adressen.
 * Benutzernamen dürfen kein „@“ enthalten → ein gemeinsames Eingabefeld ist immer eindeutig auflösbar.
 */

export function normalizeEmail(raw: string): { email: string; key: string } {
  const email = cleanDisplayName(raw);
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email)) throw badRequest('Bitte eine gültige E-Mail-Adresse eingeben.');
  return { email, key: email.toLowerCase().normalize('NFKC') };
}

/** Anmeldename oder bestätigte E-Mail → Konto (oder null) */
export async function findUserByIdentifier(db: Db, identifier: string) {
  const value = cleanDisplayName(identifier);
  if (!value) return null;
  if (value.includes('@')) {
    let key: string;
    try {
      key = normalizeEmail(value).key;
    } catch {
      return null;
    }
    return db.user.findUnique({ where: { emailKey: key } });
  }
  return db.user.findUnique({ where: { usernameKey: usernameKey(value) } });
}

export type EmailTokenKind = 'VERIFY_EMAIL' | 'PASSWORD_RESET';

const tokenInvalid = () => new ApiError(410, 'TOKEN_INVALID', 'Der Link ist ungültig, abgelaufen oder wurde bereits verwendet.');

const link = (config: AppConfig, page: string, token: string) =>
  // Token im Fragment (#…): wird nicht an den Server gesendet und landet nicht in Zugriffsprotokollen
  `${config.PUBLIC_BASE_URL}/admin/konto/${page}#token=${encodeURIComponent(token)}`;

/** Offene Bestätigung (neueste, gültige) für die Anzeige in App/Verwaltung */
export async function pendingEmail(db: Db, userId: string): Promise<string | null> {
  const t = await db.emailToken.findFirst({
    where: { userId, kind: 'VERIFY_EMAIL', usedAt: null, expiresAt: { gt: new Date() } },
    orderBy: { createdAt: 'desc' },
  });
  return t?.email ?? null;
}

/**
 * Neue Adresse erfassen und Bestätigungslink senden. Die Adresse wird erst nach der Bestätigung aktiv.
 * Der Aufrufer prüft vorher das Passwort (erneute Authentifizierung).
 */
export async function requestEmailVerification(db: Db, config: AppConfig, mailer: Mailer, user: { id: string; emailKey: string | null }, rawEmail: string) {
  if (!mailer.enabled) throw new ApiError(503, 'MAIL_DISABLED', 'Der Mailversand ist auf dem Server nicht eingerichtet.');
  const { email, key } = normalizeEmail(rawEmail);
  const taken = await db.user.findUnique({ where: { emailKey: key } });
  if (taken && taken.id !== user.id) throw new ApiError(409, 'EMAIL_TAKEN', 'Diese E-Mail-Adresse wird bereits von einem anderen Konto verwendet.');
  if (taken && taken.id === user.id) throw new ApiError(409, 'EMAIL_UNCHANGED', 'Diese Adresse ist bereits bestätigt.');
  // Frühere offene Bestätigungen verfallen
  await db.emailToken.updateMany({ where: { userId: user.id, kind: 'VERIFY_EMAIL', usedAt: null }, data: { usedAt: new Date() } });
  const token = randomToken(32);
  await db.emailToken.create({
    data: {
      userId: user.id,
      kind: 'VERIFY_EMAIL',
      tokenHash: sha256(token),
      email,
      emailKey: key,
      expiresAt: new Date(Date.now() + config.EMAIL_VERIFY_TTL_HOURS * 3600_000),
    },
  });
  await mailer.send(
    composeMail(
      email,
      'Demonify: E-Mail-Adresse bestätigen',
      [
        'Hallo,',
        'bitte bestätige diese E-Mail-Adresse für dein Demonify-Konto. Danach kannst du dich auch mit ihr anmelden und dein Passwort zurücksetzen, falls du es vergisst.',
        `Der Link ist ${config.EMAIL_VERIFY_TTL_HOURS} Stunden gültig.`,
      ],
      { label: 'E-Mail-Adresse bestätigen', url: link(config, 'email-bestaetigen', token) },
      'Du hast diese Adresse nicht angegeben? Dann ignoriere diese Nachricht – ohne Bestätigung passiert nichts.',
    ),
  );
  return { pendingEmail: email };
}

/** Bestätigungslink einlösen (einmalig, auch bei parallelen Anfragen) */
export async function confirmEmail(db: Db, mailer: Mailer, token: string) {
  const hash = sha256(token);
  let previous = null as string | null;
  let user;
  try {
    user = await db.$transaction(async (tx) => {
      const claimed = await tx.$queryRaw<Array<{ userId: string; email: string; emailKey: string }>>`
        UPDATE "EmailToken" SET "usedAt" = now()
        WHERE "tokenHash" = ${hash} AND kind = 'VERIFY_EMAIL' AND "usedAt" IS NULL AND "expiresAt" > now()
        RETURNING "userId", email, "emailKey"`;
      const row = claimed[0];
      if (!row) throw tokenInvalid();
      const current = await tx.user.findUnique({ where: { id: row.userId } });
      if (!current) throw tokenInvalid();
      previous = current.email;
      const updated = await tx.user.update({
        where: { id: row.userId },
        data: { email: row.email, emailKey: row.emailKey, emailVerifiedAt: new Date() },
      });
      // Offene Reset-Links gingen an die alte Adresse → ungültig
      await tx.emailToken.updateMany({ where: { userId: row.userId, usedAt: null }, data: { usedAt: new Date() } });
      return updated;
    });
  } catch (e) {
    if (isUniqueViolation(e)) throw new ApiError(409, 'EMAIL_TAKEN', 'Diese E-Mail-Adresse wurde inzwischen von einem anderen Konto bestätigt.');
    throw e;
  }
  if (previous && previous.toLowerCase() !== user.email?.toLowerCase() && mailer.enabled) {
    await mailer
      .send(
        composeMail(previous, 'Demonify: E-Mail-Adresse geändert', [
          `Die E-Mail-Adresse deines Demonify-Kontos „${user.username}“ wurde auf ${user.email} geändert.`,
          'Warst du das nicht? Dann wende dich bitte sofort an die Administration.',
        ]),
      )
      .catch(() => undefined);
  }
  return user;
}

/** Gültigkeit eines Links prüfen (ohne ihn zu verbrauchen) – für die Webseite vor dem Formular */
export async function checkToken(db: Db, token: string, kind: EmailTokenKind) {
  const t = await db.emailToken.findUnique({ where: { tokenHash: sha256(token) } });
  const valid = !!t && t.kind === kind && !t.usedAt && t.expiresAt > new Date();
  return { valid, email: valid && kind === 'VERIFY_EMAIL' ? t!.email : null };
}

export const FORGOT_NEUTRAL_MESSAGE =
  'Falls ein passendes Konto mit bestätigter E-Mail-Adresse existiert, haben wir einen Link zum Zurücksetzen gesendet. Bitte prüfe auch den Spam-Ordner.';

/**
 * „Passwort vergessen“: Link ausschließlich an die bestätigte Adresse des passenden Kontos.
 * Pro Konto höchstens 3 Links pro Stunde und einer pro Minute (zusätzlich IP-Begrenzung in der Route).
 * Der Aufrufer antwortet immer neutral und wartet nicht auf das Ergebnis (gleiches Zeitverhalten).
 */
export async function requestPasswordReset(db: Db, config: AppConfig, mailer: Mailer, identifier: string): Promise<'sent' | 'skipped'> {
  if (!mailer.enabled) return 'skipped';
  const user = await findUserByIdentifier(db, identifier);
  if (!user || !user.emailKey || !user.email || !user.emailVerifiedAt || user.disabledAt) return 'skipped';
  const recent = await db.emailToken.findMany({
    where: { userId: user.id, kind: 'PASSWORD_RESET', createdAt: { gt: new Date(Date.now() - 3600_000) } },
    orderBy: { createdAt: 'desc' },
    select: { createdAt: true },
  });
  if (recent.length >= 3 || (recent[0] && Date.now() - recent[0].createdAt.getTime() < 60_000)) return 'skipped';
  const token = randomToken(32);
  await db.emailToken.create({
    data: {
      userId: user.id,
      kind: 'PASSWORD_RESET',
      tokenHash: sha256(token),
      expiresAt: new Date(Date.now() + config.PASSWORD_RESET_TTL_MINUTES * 60_000),
    },
  });
  await mailer.send(
    composeMail(
      user.email,
      'Demonify: Passwort zurücksetzen',
      [
        `Hallo ${user.displayName ?? user.username},`,
        'für dein Demonify-Konto wurde das Zurücksetzen des Passworts angefordert.',
        `Der Link ist ${config.PASSWORD_RESET_TTL_MINUTES} Minuten gültig und kann nur einmal verwendet werden.`,
      ],
      { label: 'Neues Passwort festlegen', url: link(config, 'passwort-zuruecksetzen', token) },
      'Du hast das nicht angefordert? Dann ignoriere diese Nachricht – dein Passwort bleibt unverändert.',
    ),
  );
  return 'sent';
}

/**
 * Neues Passwort über den Reset-Link setzen. Token-Verbrauch und Passwortänderung laufen in einer
 * Transaktion; das UPDATE … WHERE "usedAt" IS NULL stellt sicher, dass parallele Anfragen genau
 * einmal erfolgreich sind. Danach: alle Sitzungen beendet, weitere offene Reset-Links ungültig.
 */
export async function resetPassword(db: Db, mailer: Mailer, token: string, newPassword: string) {
  validatePassword(newPassword);
  const hash = sha256(token);
  const passwordHash = await hashPassword(newPassword);
  const user = await db.$transaction(async (tx) => {
    const claimed = await tx.$queryRaw<Array<{ userId: string }>>`
      UPDATE "EmailToken" SET "usedAt" = now()
      WHERE "tokenHash" = ${hash} AND kind = 'PASSWORD_RESET' AND "usedAt" IS NULL AND "expiresAt" > now()
      RETURNING "userId"`;
    const row = claimed[0];
    if (!row) throw tokenInvalid();
    const u = await tx.user.update({ where: { id: row.userId }, data: { passwordHash, mustChangePassword: false } });
    await tx.emailToken.updateMany({ where: { userId: u.id, kind: 'PASSWORD_RESET', usedAt: null }, data: { usedAt: new Date() } });
    await tx.session.updateMany({ where: { userId: u.id, revokedAt: null }, data: { revokedAt: new Date(), revokeReason: 'password_reset' } });
    return u;
  });
  if (user.email && mailer.enabled) {
    await mailer
      .send(
        composeMail(user.email, 'Demonify: Passwort geändert', [
          `Das Passwort deines Demonify-Kontos „${user.username}“ wurde soeben über „Passwort vergessen“ geändert.`,
          'Alle Geräte wurden abgemeldet. Melde dich mit dem neuen Passwort wieder an.',
          'Warst du das nicht? Dann wende dich bitte sofort an die Administration.',
        ]),
      )
      .catch(() => undefined);
  }
  return user;
}
