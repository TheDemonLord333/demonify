import crypto from 'node:crypto';

/**
 * Kompakte, HMAC-SHA256-signierte Tokens: base64url(payload).base64url(signatur)
 * Verwendet für kurzlebige Access-Tokens. Refresh-Tokens sind dagegen zufällige,
 * opake Werte, die nur gehasht in der Datenbank liegen.
 */
export interface AccessPayload {
  /** Benutzer-ID */
  sub: string;
  /** Session-ID */
  sid: string;
  role: 'ADMIN' | 'USER';
  /** Ablauf (Unix-Sekunden) */
  exp: number;
  typ: 'access';
}

const b64 = (b: Buffer | string) => Buffer.from(b).toString('base64url');

export function signToken(payload: object, secret: string): string {
  const body = b64(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', secret).update(body).digest('base64url');
  return `${body}.${sig}`;
}

export function verifyToken<T extends { exp: number }>(token: string, secret: string, nowSec = Date.now() / 1000): T | null {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [body, sig] = parts as [string, string];
  const expected = crypto.createHmac('sha256', secret).update(body).digest();
  let given: Buffer;
  try {
    given = Buffer.from(sig, 'base64url');
  } catch {
    return null;
  }
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as T;
    if (typeof payload.exp !== 'number' || payload.exp <= nowSec) return null;
    return payload;
  } catch {
    return null;
  }
}

export function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function sha256(value: string | Buffer): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

/**
 * Kurzlebige, auf genau eine Ressource begrenzte Streaming-Signatur.
 * Enthält keine Login-Tokens; nur Ressource, Qualität, Benutzer/Session und Ablaufzeit.
 */
export function streamSignature(
  secret: string,
  parts: { trackId: string; quality: string; uid: string; sid: string; exp: number },
): string {
  const data = `stream|${parts.trackId}|${parts.quality}|${parts.uid}|${parts.sid}|${parts.exp}`;
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}
