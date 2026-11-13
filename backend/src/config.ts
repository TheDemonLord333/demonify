import 'dotenv/config';
import path from 'node:path';
import { z } from 'zod';

/**
 * Zentrale Konfiguration. Alle Werte kommen aus Umgebungsvariablen
 * (in Produktion aus /srv/nodeapps/demonify/shared/.env, siehe deploy/env.example).
 * Fehlende Pflicht-Secrets führen zu einem klaren Startfehler – es gibt keine Standard-Secrets.
 */
const bool = z
  .enum(['true', 'false', '1', '0', 'yes', 'no'])
  .transform((v) => v === 'true' || v === '1' || v === 'yes');

const csv = z
  .string()
  .default('')
  .transform((v) =>
    v
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );

const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('production'),
  HOST: z.string().default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(1340),
  PUBLIC_BASE_URL: z.string().url().default('https://demonify.thedemonlord333.me'),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL fehlt'),

  MUSIC_DIR: z.string().default('/srv/music'),
  DATA_DIR: z.string().default('/srv/nodeapps/demonify/data'),
  UPLOAD_DIR: z.string().optional(),
  CACHE_DIR: z.string().optional(),

  /** Mindestens 32 Zeichen, z. B. `openssl rand -base64 48` */
  AUTH_TOKEN_SECRET: z.string().min(32, 'AUTH_TOKEN_SECRET muss mindestens 32 Zeichen lang sein'),
  STREAM_URL_SECRET: z.string().min(32, 'STREAM_URL_SECRET muss mindestens 32 Zeichen lang sein'),

  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(60),
  STREAM_URL_TTL_SECONDS: z.coerce.number().int().min(300).max(86400).default(21600),

  /** true: Nginx liefert Medien per X-Accel-Redirect aus (Produktion). false: Node liefert selbst aus. */
  MEDIA_ACCEL_REDIRECT: bool.default(false),
  ACCEL_PREFIX_MUSIC: z.string().default('/_protected/music/'),
  ACCEL_PREFIX_CACHE: z.string().default('/_protected/cache/'),

  /** Vertrauenswürdige Proxys (nur die tatsächliche Kette, z. B. 127.0.0.1) */
  TRUST_PROXY: z.string().default('127.0.0.1,::1'),
  /** Erlaubte CORS-Origins (nur für lokale Entwicklung nötig; Produktion ist Same-Origin) */
  CORS_ORIGINS: csv,
  /** Cookies nur über HTTPS (in Produktion immer true) */
  COOKIE_SECURE: bool.optional(),

  LOGIN_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(10),
  LOGIN_RATE_LIMIT_WINDOW: z.string().default('5 minutes'),
  /** „Passwort vergessen“: Anfragen pro IP und 15 Minuten (pro Konto zusätzlich 3/Stunde) */
  FORGOT_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(5),

  MAX_AUDIO_UPLOAD_MB: z.coerce.number().int().min(1).default(2048),
  MAX_IMAGE_UPLOAD_MB: z.coerce.number().int().min(1).default(30),
  /** Größe eines Upload-Abschnitts. Unter Cloudflare-Proxy muss dies deutlich unter 100 MB liegen. */
  UPLOAD_CHUNK_MB: z.coerce.number().int().min(1).max(95).default(8),
  UPLOAD_EXPIRY_HOURS: z.coerce.number().int().min(1).default(48),

  TRANSCODE_CONCURRENCY: z.coerce.number().int().min(1).max(8).default(1),
  FFMPEG_PATH: z.string().default('ffmpeg'),
  FFPROBE_PATH: z.string().default('ffprobe'),
  /** Parallel geprüfte Dateien beim Bibliotheksscan */
  SCAN_CONCURRENCY: z.coerce.number().int().min(1).max(16).default(2),

  /**
   * Mailversand für E-Mail-Bestätigung und „Passwort vergessen“:
   *   disabled – kein Versand (E-Mail-Pflicht und Passwort-Reset per Mail sind dann aus)
   *   smtp     – Versand über SMTP (Produktion)
   *   log      – Mails nur ins Log schreiben (nur Entwicklung; enthält Links mit Token!)
   *   memory   – im Speicher sammeln (nur automatisierte Tests)
   */
  MAIL_TRANSPORT: z.enum(['disabled', 'smtp', 'log', 'memory']).default('disabled'),
  /** Absender, z. B. "Demonify <noreply@thedemonlord333.me>" */
  MAIL_FROM: z.string().optional(),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.coerce.number().int().min(1).max(65535).default(587),
  /** true = TLS ab Verbindungsaufbau (Port 465); false = STARTTLS (Port 587, wird erzwungen) */
  SMTP_SECURE: bool.default(false),
  SMTP_USER: z.string().optional(),
  SMTP_PASSWORD: z.string().optional(),
  /** Gültigkeit von Passwort-Reset-Links */
  PASSWORD_RESET_TTL_MINUTES: z.coerce.number().int().min(5).max(240).default(30),
  /** Gültigkeit von Links zur E-Mail-Bestätigung */
  EMAIL_VERIFY_TTL_HOURS: z.coerce.number().int().min(1).max(168).default(24),

  OPENAPI_UI: bool.default(true),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  /** Optionale Beispieldaten nur im ausdrücklichen Entwicklungsmodus */
  DEV_SEED_ENABLED: bool.default(false),
  /** Hintergrund-Worker in diesem Prozess starten */
  WORKER_ENABLED: bool.default(true),
});

export type AppConfig = z.infer<typeof schema> & {
  uploadDir: string;
  cacheDir: string;
  cookieSecure: boolean;
  /** Mailversand eingerichtet → E-Mail-Pflicht und „Passwort vergessen“ aktiv */
  mailEnabled: boolean;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const msg = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Ungültige Konfiguration:\n${msg}`);
  }
  const c = parsed.data;
  if (c.AUTH_TOKEN_SECRET === c.STREAM_URL_SECRET) {
    throw new Error('AUTH_TOKEN_SECRET und STREAM_URL_SECRET müssen unterschiedlich sein.');
  }
  if (c.MAIL_TRANSPORT === 'smtp' && (!c.SMTP_HOST || !c.MAIL_FROM)) {
    throw new Error('MAIL_TRANSPORT=smtp benötigt SMTP_HOST und MAIL_FROM.');
  }
  if ((c.MAIL_TRANSPORT === 'log' || c.MAIL_TRANSPORT === 'memory') && c.NODE_ENV === 'production') {
    throw new Error(`MAIL_TRANSPORT=${c.MAIL_TRANSPORT} ist nur für Entwicklung/Tests gedacht (Links mit Token würden im Log landen).`);
  }
  if (c.DEV_SEED_ENABLED && c.NODE_ENV === 'production') {
    throw new Error('DEV_SEED_ENABLED darf in Produktion nicht aktiv sein.');
  }
  return {
    ...c,
    MUSIC_DIR: path.resolve(c.MUSIC_DIR),
    DATA_DIR: path.resolve(c.DATA_DIR),
    uploadDir: path.resolve(c.UPLOAD_DIR ?? path.join(c.DATA_DIR, 'uploads')),
    cacheDir: path.resolve(c.CACHE_DIR ?? path.join(c.DATA_DIR, 'cache')),
    cookieSecure: c.COOKIE_SECURE ?? c.NODE_ENV === 'production',
    PUBLIC_BASE_URL: c.PUBLIC_BASE_URL.replace(/\/+$/, ''),
    mailEnabled: c.MAIL_TRANSPORT !== 'disabled',
  };
}
