#!/usr/bin/env node
/**
 * Demonify-Verwaltungsbefehle:
 *   create-admin --username <name> [--display-name <name>]   Erstes/weiteres Admin-Konto (Passwort interaktiv oder per stdin)
 *   reset-password --username <name>                          Passwort neu setzen und Sitzungen beenden
 *   scan                                                      Bibliotheksscan (wiederholbar)
 *   cleanup-uploads                                           Abgelaufene Uploads entfernen
 *   seed-dev                                                  Testtöne erzeugen (nur DEV_SEED_ENABLED=true, nie in Produktion)
 */
import { Command } from 'commander';
import fs from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';
import { Writable } from 'node:stream';
import { loadConfig } from '../config.js';
import { createDb } from '../db.js';
import { createUser, hashPassword, revokeAllSessions, validatePassword } from '../services/auth.js';
import { runLibraryScan } from '../services/scanner.js';
import { cleanupUploads } from '../services/uploads.js';
import { usernameKey } from '../lib/normalize.js';
import { runProcess } from '../lib/media.js';
import { ApiError } from '../lib/errors.js';

async function readPassword(prompt: string, fromStdin: boolean): Promise<string> {
  if (fromStdin || !process.stdin.isTTY) {
    const chunks: Buffer[] = [];
    for await (const c of process.stdin) chunks.push(c as Buffer);
    return Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');
  }
  let muted = false;
  const out = new Writable({
    write(chunk, _enc, cb) {
      if (!muted) process.stdout.write(chunk);
      cb();
    },
  });
  const rl = readline.createInterface({ input: process.stdin, output: out, terminal: true });
  const ask = (q: string) =>
    new Promise<string>((resolve) => {
      process.stdout.write(q);
      muted = true;
      rl.question('', (a) => {
        muted = false;
        process.stdout.write('\n');
        resolve(a);
      });
    });
  const a = await ask(prompt);
  const b = await ask('Passwort wiederholen: ');
  rl.close();
  if (a !== b) throw new Error('Die Passwörter stimmen nicht überein.');
  return a;
}

const program = new Command();
program.name('demonify').description('Demonify-Verwaltungsbefehle');

program
  .command('create-admin')
  .requiredOption('--username <name>', 'Benutzername')
  .option('--display-name <name>', 'Anzeigename')
  .option('--password-stdin', 'Passwort von stdin lesen (für Automatisierung)')
  .action(async (opts: { username: string; displayName?: string; passwordStdin?: boolean }) => {
    const config = loadConfig();
    const db = createDb(config.DATABASE_URL);
    try {
      const pw = await readPassword('Neues Passwort (mind. 10 Zeichen): ', !!opts.passwordStdin);
      validatePassword(pw);
      const user = await createUser(db, { username: opts.username, password: pw, role: 'ADMIN', displayName: opts.displayName });
      console.log(`Administrator „${user.username}“ wurde angelegt.`);
    } finally {
      await db.$disconnect();
    }
  });

program
  .command('reset-password')
  .requiredOption('--username <name>', 'Benutzername')
  .option('--password-stdin', 'Passwort von stdin lesen')
  .action(async (opts: { username: string; passwordStdin?: boolean }) => {
    const config = loadConfig();
    const db = createDb(config.DATABASE_URL);
    try {
      const user = await db.user.findUnique({ where: { usernameKey: usernameKey(opts.username) } });
      if (!user) throw new Error('Benutzer nicht gefunden.');
      const pw = await readPassword('Neues Passwort (mind. 10 Zeichen): ', !!opts.passwordStdin);
      validatePassword(pw);
      await db.user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(pw) } });
      await revokeAllSessions(db, user.id, 'password_reset_cli');
      console.log('Passwort geändert, alle Sitzungen beendet.');
    } finally {
      await db.$disconnect();
    }
  });

program
  .command('scan')
  .description('Musikverzeichnis scannen (neue, geänderte, verschobene und fehlende Dateien)')
  .action(async () => {
    const config = loadConfig();
    const db = createDb(config.DATABASE_URL);
    const job = await db.job.create({ data: { type: 'LIBRARY_SCAN', status: 'RUNNING', startedAt: new Date(), payload: { source: 'cli' } } });
    try {
      let lastPct = -1;
      const summary = await runLibraryScan(db, config, {
        jobId: job.id,
        progress: async (done, total) => {
          const pct = total ? Math.floor((done / total) * 100) : 100;
          if (pct !== lastPct && pct % 5 === 0) {
            lastPct = pct;
            process.stdout.write(`\rFortschritt: ${pct}% (${done}/${total})   `);
            await db.job.update({ where: { id: job.id }, data: { done, total, progress: total ? done / total : 1 } });
          }
        },
      });
      process.stdout.write('\n');
      await db.job.update({ where: { id: job.id }, data: { status: 'SUCCEEDED', progress: 1, finishedAt: new Date(), result: summary as object } });
      console.log('Scan abgeschlossen:', summary);
    } catch (e) {
      await db.job.update({ where: { id: job.id }, data: { status: 'FAILED', error: (e as Error).message, finishedAt: new Date() } });
      throw e;
    } finally {
      await db.$disconnect();
    }
  });

program.command('cleanup-uploads').action(async () => {
  const config = loadConfig();
  const db = createDb(config.DATABASE_URL);
  try {
    console.log('Bereinigt:', await cleanupUploads(db, config));
  } finally {
    await db.$disconnect();
  }
});

program
  .command('seed-dev')
  .description('Erzeugt klar gekennzeichnete Testtöne (nur im Entwicklungsmodus)')
  .action(async () => {
    const config = loadConfig();
    if (!config.DEV_SEED_ENABLED || config.NODE_ENV === 'production') {
      throw new Error('seed-dev ist nur mit DEV_SEED_ENABLED=true außerhalb der Produktion erlaubt.');
    }
    const base = path.join(config.MUSIC_DIR, 'Demonify Testsignale', 'Alben', '2026 - Testtöne (Entwicklung)');
    const tones = [
      ['01 - Sinus 220 Hz', 220],
      ['02 - Sinus 440 Hz', 440],
      ['03 - Sinus 880 Hz', 880],
    ] as const;
    for (const [name, freq] of tones) {
      const dir = path.join(base, name);
      await fs.mkdir(dir, { recursive: true });
      const out = path.join(dir, 'audio.flac');
      try {
        await fs.access(out);
        continue;
      } catch {
        /* erzeugen */
      }
      const res = await runProcess(config.FFMPEG_PATH, [
        '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', `sine=frequency=${freq}:duration=20`,
        '-metadata', `title=${name.slice(5)}`, '-metadata', 'artist=Demonify Testsignale', '-metadata', 'album=Testtöne (Entwicklung)',
        '-metadata', `track=${name.slice(0, 2)}`, '-metadata', 'date=2026', out,
      ]);
      if (res.code !== 0) throw new Error(res.stderr);
    }
    console.log(`Testtöne angelegt unter ${base}. Jetzt "scan" ausführen.`);
  });

program.parseAsync(process.argv).catch((e: unknown) => {
  const msg = e instanceof ApiError || e instanceof Error ? e.message : String(e);
  console.error(`Fehler: ${msg}`);
  process.exit(1);
});
