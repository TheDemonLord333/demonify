import nodemailer from 'nodemailer';
import type { AppConfig } from '../config.js';

export interface MailMessage {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface Mailer {
  readonly enabled: boolean;
  send(msg: MailMessage): Promise<void>;
  /** Nur bei MAIL_TRANSPORT=memory (Tests): versendete Nachrichten */
  readonly sent: MailMessage[];
}

type Log = { info: (o: object | string, m?: string) => void; warn: (o: object | string, m?: string) => void };

/**
 * Mailversand. Zugangsdaten kommen ausschließlich aus der Server-Konfiguration (.env).
 * Mails enthalten nur die nötigen Links; Tokens werden nie protokolliert (außer im Entwicklungsmodus „log“).
 */
export function createMailer(config: AppConfig, log: Log): Mailer {
  const sent: MailMessage[] = [];
  switch (config.MAIL_TRANSPORT) {
    case 'disabled':
      return {
        enabled: false,
        sent,
        async send() {
          throw new Error('Mailversand ist nicht eingerichtet (MAIL_TRANSPORT=disabled).');
        },
      };
    case 'memory':
      return {
        enabled: true,
        sent,
        async send(msg) {
          sent.push(msg);
        },
      };
    case 'log':
      return {
        enabled: true,
        sent,
        async send(msg) {
          log.info({ to: msg.to, subject: msg.subject }, `[Entwicklung] Mail nicht versendet:\n${msg.text}`);
        },
      };
    case 'smtp': {
      const transport = nodemailer.createTransport({
        host: config.SMTP_HOST,
        port: config.SMTP_PORT,
        secure: config.SMTP_SECURE,
        requireTLS: !config.SMTP_SECURE,
        auth: config.SMTP_USER ? { user: config.SMTP_USER, pass: config.SMTP_PASSWORD ?? '' } : undefined,
        connectionTimeout: 15_000,
        greetingTimeout: 15_000,
        socketTimeout: 30_000,
      });
      return {
        enabled: true,
        sent,
        async send(msg) {
          await transport.sendMail({ from: config.MAIL_FROM, to: msg.to, subject: msg.subject, text: msg.text, html: msg.html });
          log.info({ subject: msg.subject }, 'Mail versendet');
        },
      };
    }
  }
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/** Einheitliche, schlichte Demonify-Mail (Text + HTML) */
export function composeMail(to: string, subject: string, paragraphs: string[], action?: { label: string; url: string }, footer?: string): MailMessage {
  const text = [
    ...paragraphs,
    ...(action ? [`${action.label}:\n${action.url}`] : []),
    footer ?? 'Diese Nachricht wurde automatisch von Demonify gesendet.',
  ].join('\n\n');
  const html = `<!doctype html><html lang="de"><body style="margin:0;background:#121212;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#f5f5f5">
<div style="max-width:520px;margin:0 auto;padding:32px 20px">
<h1 style="font-size:22px;margin:0 0 20px;color:#9146FF">Demonify</h1>
${paragraphs.map((p) => `<p style="font-size:15px;line-height:1.5;margin:0 0 14px">${esc(p)}</p>`).join('\n')}
${action ? `<p style="margin:24px 0"><a href="${esc(action.url)}" style="display:inline-block;background:#9146FF;color:#fff;text-decoration:none;padding:12px 22px;border-radius:24px;font-weight:600">${esc(action.label)}</a></p>
<p style="font-size:12px;color:#a7a7a7;word-break:break-all">Falls der Knopf nicht funktioniert: ${esc(action.url)}</p>` : ''}
<p style="font-size:12px;color:#a7a7a7;margin-top:28px">${esc(footer ?? 'Diese Nachricht wurde automatisch von Demonify gesendet.')}</p>
</div></body></html>`;
  return { to, subject, text, html };
}
