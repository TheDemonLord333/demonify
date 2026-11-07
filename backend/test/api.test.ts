import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { createTestEnv, makeAudio, makePng, makeUser, uploadFileChunked, exists, type TestEnv } from './helpers.js';
import { signToken } from '../src/lib/tokens.js';
import { runLibraryScan } from '../src/services/scanner.js';

let env: TestEnv;
let admin: Awaited<ReturnType<typeof makeUser>>;
let alice: Awaited<ReturnType<typeof makeUser>>;
let bob: Awaited<ReturnType<typeof makeUser>>;
const API = '/api/v1';

beforeAll(async () => {
  env = await createTestEnv();
  admin = await makeUser(env, 'chef', 'ADMIN');
  alice = await makeUser(env, 'alice');
  bob = await makeUser(env, 'bob');
});
afterAll(async () => env?.close());

const get = (url: string, headers: Record<string, string>) => env.app.inject({ method: 'GET', url: API + url, headers });
const send = (method: 'POST' | 'PUT' | 'PATCH' | 'DELETE', url: string, headers: Record<string, string>, payload?: object) =>
  env.app.inject({ method, url: API + url, headers, payload });

describe('API-Grundlagen', () => {
  it('Health-Endpunkt ohne sensible Daten', async () => {
    const res = await env.app.inject({ method: 'GET', url: `${API}/health` });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', database: 'ok' });
  });
  it('unbekannte API-Routen liefern JSON-404 statt HTML', async () => {
    const res = await env.app.inject({ method: 'GET', url: `${API}/gibtsnicht` });
    expect(res.statusCode).toBe(404);
    expect(res.headers['content-type']).toContain('application/json');
    expect(res.json().error.code).toBe('NOT_FOUND');
  });
  it('authentifizierte Antworten sind nicht cachebar', async () => {
    const res = await get('/me', alice.auth);
    expect(res.headers['cache-control']).toBe('no-store');
  });
  it('OpenAPI-Dokumentation ist verfügbar', async () => {
    const res = await env.app.inject({ method: 'GET', url: `${API}/openapi.json` });
    expect(res.statusCode).toBe(200);
    expect(Object.keys(res.json().paths)).toEqual(expect.arrayContaining(['/api/v1/search', '/api/v1/admin/releases/commit']));
  });
});

describe('Authentifizierung', () => {
  it('lehnt falsche Passwörter einheitlich ab', async () => {
    const res = await send('POST', '/auth/login', {}, { username: 'alice', password: 'falschfalsch' });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('INVALID_CREDENTIALS');
    const res2 = await send('POST', '/auth/login', {}, { username: 'niemand', password: 'falschfalsch' });
    expect(res2.json().error.code).toBe('INVALID_CREDENTIALS');
  });
  it('lehnt abgelaufene und ungültige Tokens ab', async () => {
    const expired = signToken({ sub: alice.id, sid: crypto.randomUUID(), role: 'USER', exp: Math.floor(Date.now() / 1000) - 5, typ: 'access' }, env.config.AUTH_TOKEN_SECRET);
    expect((await get('/me', { authorization: `Bearer ${expired}` })).statusCode).toBe(401);
    expect((await get('/me', { authorization: 'Bearer kaputt.token' })).statusCode).toBe(401);
    const forged = signToken({ sub: alice.id, sid: crypto.randomUUID(), role: 'ADMIN', exp: Math.floor(Date.now() / 1000) + 60, typ: 'access' }, 'falsches-geheimnis-0123456789abcdefghijkl');
    expect((await get('/me', { authorization: `Bearer ${forged}` })).statusCode).toBe(401);
  });
  it('rotiert Refresh-Tokens und erkennt Wiederverwendung', async () => {
    const u = await makeUser(env, 'rotator');
    const r1 = await send('POST', '/auth/refresh', {}, { refreshToken: u.refreshToken });
    expect(r1.statusCode).toBe(200);
    const t2 = r1.json() as { accessToken: string; refreshToken: string };
    expect(t2.refreshToken).not.toBe(u.refreshToken);
    // altes Token erneut → abgelehnt
    expect((await send('POST', '/auth/refresh', {}, { refreshToken: u.refreshToken })).statusCode).toBe(401);
    expect((await get('/me', { authorization: `Bearer ${t2.accessToken}` })).statusCode).toBe(200);
  });
  it('Abmelden widerruft die Sitzung sofort', async () => {
    const u = await makeUser(env, 'abmelder');
    expect((await send('POST', '/auth/logout', u.auth)).statusCode).toBe(200);
    expect((await get('/me', u.auth)).statusCode).toBe(401);
    expect((await send('POST', '/auth/refresh', {}, { refreshToken: u.refreshToken })).statusCode).toBe(401);
  });
  it('Sperren eines Benutzers beendet alle Sitzungen', async () => {
    const u = await makeUser(env, 'gesperrt');
    const res = await send('PATCH', `/admin/users/${u.id}`, admin.auth, { disabled: true });
    expect(res.statusCode).toBe(200);
    expect((await get('/me', u.auth)).statusCode).toBe(401);
    const login = await send('POST', '/auth/login', {}, { username: 'gesperrt', password: 'TestPasswort123' });
    expect(login.statusCode).toBe(403);
  });
  it('Web-Login setzt HttpOnly-Cookies und verlangt CSRF-Token', async () => {
    const res = await send('POST', '/auth/login', {}, { username: 'alice', password: 'TestPasswort123', client: 'web' });
    expect(res.statusCode).toBe(200);
    const cookies = res.cookies as Array<{ name: string; value: string; httpOnly?: boolean; sameSite?: string }>;
    const at = cookies.find((c) => c.name === 'dmf_at')!;
    const csrf = cookies.find((c) => c.name === 'dmf_csrf')!;
    expect(at.httpOnly).toBe(true);
    expect(at.sameSite).toBe('Strict');
    expect(res.json().accessToken).toBeUndefined();
    const cookieHeader = `dmf_at=${at.value}; dmf_csrf=${csrf.value}`;
    expect((await get('/me', { cookie: cookieHeader })).statusCode).toBe(200);
    // Zustandsändernde Anfrage ohne CSRF-Header → 403
    const noCsrf = await send('POST', '/playlists', { cookie: cookieHeader }, { name: 'X' });
    expect(noCsrf.statusCode).toBe(403);
    const withCsrf = await send('POST', '/playlists', { cookie: cookieHeader, 'x-csrf-token': csrf.value }, { name: 'X' });
    expect(withCsrf.statusCode).toBe(200);
  });
  it('Einladung kann genau einmal eingelöst werden', async () => {
    const inv = await send('POST', '/admin/invites', admin.auth, { role: 'USER', expiresInHours: 1 });
    expect(inv.statusCode).toBe(201);
    const { code } = inv.json() as { code: string };
    const r1 = await send('POST', '/auth/invites/redeem', {}, { code, username: 'eingeladen', password: 'EinPasswort123' });
    expect(r1.statusCode).toBe(200);
    const r2 = await send('POST', '/auth/invites/redeem', {}, { code, username: 'nochmal', password: 'EinPasswort123' });
    expect(r2.statusCode).toBe(410);
  });
});

describe('Berechtigungen', () => {
  it('normale Benutzer können keine Verwaltungsfunktionen verwenden', async () => {
    for (const [m, url] of [
      ['GET', '/admin/users'],
      ['POST', '/admin/artists'],
      ['POST', '/admin/library/scan'],
      ['POST', '/admin/uploads'],
      ['GET', '/admin/jobs'],
      ['POST', '/admin/invites'],
    ] as const) {
      const res = await env.app.inject({ method: m, url: API + url, headers: alice.auth, payload: m === 'GET' ? undefined : { name: 'x' } });
      expect(res.statusCode, `${m} ${url}`).toBe(403);
    }
  });
  it('Rollenentzug wirkt sofort, auch mit gültigem Token', async () => {
    const u = await makeUser(env, 'zweitadmin', 'ADMIN');
    expect((await get('/admin/stats', u.auth)).statusCode).toBe(200);
    await send('PATCH', `/admin/users/${u.id}`, admin.auth, { role: 'USER' });
    expect((await get('/admin/stats', u.auth)).statusCode).toBe(403);
  });
  it('letzter Administrator kann nicht entfernt werden', async () => {
    const res = await send('PATCH', `/admin/users/${admin.id}`, admin.auth, { role: 'USER' });
    expect(res.statusCode).toBe(409);
  });
});

describe('Künstler-Eindeutigkeit', () => {
  it('verhindert normalisierte Duplikate (inkl. DB-Constraint)', async () => {
    const r1 = await send('POST', '/admin/artists', admin.auth, { name: 'The Demon Lord' });
    expect(r1.statusCode).toBe(201);
    for (const name of ['the demon lord', '  THE   DEMON LORD ', 'Ｔｈｅ Demon Lord']) {
      const r = await send('POST', '/admin/artists', admin.auth, { name });
      expect(r.statusCode, name).toBe(409);
      expect(r.json().error.code).toBe('ARTIST_EXISTS');
    }
    await expect(
      env.db.artist.create({ data: { name: 'x', nameKey: 'the demon lord', searchText: 'x' } }),
    ).rejects.toMatchObject({ code: 'P2002' });
  });
  it('gleichzeitige Anlage desselben Namens ergibt genau einen Künstler', async () => {
    const results = await Promise.all(
      Array.from({ length: 5 }, () => send('POST', '/admin/artists', admin.auth, { name: 'Gleichzeitig' })),
    );
    expect(results.filter((r) => r.statusCode === 201)).toHaveLength(1);
    expect(results.filter((r) => r.statusCode === 409)).toHaveLength(4);
  });
  it('liefert Live-Vorschläge ab dem ersten Buchstaben und Ähnlichkeitshinweise', async () => {
    await send('POST', '/admin/artists', admin.auth, { name: 'Björk' });
    const s = await get('/admin/artists/suggest?q=t', admin.auth);
    expect(s.json().items.map((a: { name: string }) => a.name)).toContain('The Demon Lord');
    const check = await get(`/admin/artists/check?name=${encodeURIComponent('Bjork')}`, admin.auth);
    expect(check.json().exists).toBe(false);
    expect(check.json().similar.map((a: { name: string }) => a.name)).toContain('Björk');
    // Ähnlich, aber verschieden → darf angelegt werden
    expect((await send('POST', '/admin/artists', admin.auth, { name: 'Bjork' })).statusCode).toBe(201);
  });
});

describe('Upload und automatische Ablage', () => {
  let releaseId: string;
  let artistId: string;
  let featId: string;
  const fixtures = () => path.join(env.root, 'fixtures');

  it('legt Album mit Track-Unterordnern, Release- und Songcover korrekt ab', async () => {
    await fs.mkdir(fixtures(), { recursive: true });
    makeAudio(path.join(fixtures(), 'eins.flac'), { freq: 300, tags: { title: 'Erster Song' } });
    makeAudio(path.join(fixtures(), 'zwei.mp3'), { freq: 500, format: 'mp3' });
    makePng(path.join(fixtures(), 'album.png'), 'purple');
    makePng(path.join(fixtures(), 'song.png'), 'green');
    artistId = (await send('POST', '/admin/artists', admin.auth, { name: 'Upload Künstler' })).json().artist.id;
    featId = (await send('POST', '/admin/artists', admin.auth, { name: 'Gast' })).json().artist.id;

    const a1 = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'eins.flac'), 'AUDIO');
    const a2 = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'zwei.mp3'), 'AUDIO');
    const cover = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'album.png'), 'IMAGE');
    const songCover = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'song.png'), 'IMAGE');
    expect([a1, a2, cover, songCover].map((u) => u.upload.status)).toEqual(['VALIDATED', 'VALIDATED', 'VALIDATED', 'VALIDATED']);
    expect(a1.upload.probe.tags).toMatchObject({ title: 'Erster Song' });

    const key = crypto.randomUUID();
    const body = {
      idempotencyKey: key,
      artistId,
      release: { mode: 'new', title: 'Albumtitel', type: 'ALBUM', year: 2026, coverUploadId: cover.upload.id },
      tracks: [
        { uploadId: a1.upload.id, title: 'Erster Song', discNumber: 1, trackNumber: 1, artistIds: [artistId], featuredArtistIds: [] },
        { uploadId: a2.upload.id, title: 'Zweiter Song', discNumber: 1, trackNumber: 2, artistIds: [artistId], featuredArtistIds: [featId], coverUploadId: songCover.upload.id },
      ],
    };
    const res = await send('POST', '/admin/releases/commit', admin.auth, body);
    expect(res.statusCode, res.body).toBe(200);
    releaseId = res.json().result.releaseId;
    const m = env.config.MUSIC_DIR;
    expect(await exists(path.join(m, 'Upload Künstler/Alben/2026 - Albumtitel/cover.png'))).toBe(true);
    expect(await exists(path.join(m, 'Upload Künstler/Alben/2026 - Albumtitel/01 - Erster Song/audio.flac'))).toBe(true);
    expect(await exists(path.join(m, 'Upload Künstler/Alben/2026 - Albumtitel/02 - Zweiter Song/audio.mp3'))).toBe(true);
    expect(await exists(path.join(m, 'Upload Künstler/Alben/2026 - Albumtitel/02 - Zweiter Song/cover.png'))).toBe(true);

    // Wiederholte Abschlussanfrage → gleiches Ergebnis, keine Duplikate
    const again = await send('POST', '/admin/releases/commit', admin.auth, body);
    expect(again.statusCode).toBe(200);
    expect(again.json().result.releaseId).toBe(releaseId);
    expect(await env.db.release.count({ where: { title: 'Albumtitel' } })).toBe(1);
    expect(await env.db.track.count({ where: { releaseId } })).toBe(2);
  });

  it('verwendet Songcover, sonst Veröffentlichungscover', async () => {
    const res = await get(`/releases/${releaseId}`, alice.auth);
    const { release, tracks } = res.json();
    expect(release.coverImageId).toBeTruthy();
    expect(tracks[0].hasOwnCover).toBe(false);
    expect(tracks[0].coverImageId).toBe(release.coverImageId);
    expect(tracks[1].hasOwnCover).toBe(true);
    expect(tracks[1].coverImageId).not.toBe(release.coverImageId);
    expect(tracks[1].artists.map((a: { name: string; role: string }) => `${a.name}:${a.role}`)).toEqual(['Upload Künstler:PRIMARY', 'Gast:FEATURED']);
    const img = await get(`/images/${tracks[1].coverImageId}?size=thumb`, alice.auth);
    expect(img.statusCode).toBe(200);
    expect(img.headers['content-type']).toBe('image/jpeg');
    expect(img.headers['cache-control']).toContain('private');
    expect((await env.app.inject({ method: 'GET', url: `${API}/images/${tracks[1].coverImageId}` })).statusCode).toBe(401);
  });

  it('gleichnamige Veröffentlichung desselben Künstlers → eigener Ordner, nichts überschrieben', async () => {
    const before = await fs.readFile(path.join(env.config.MUSIC_DIR, 'Upload Künstler/Alben/2026 - Albumtitel/01 - Erster Song/audio.flac'));
    makeAudio(path.join(fixtures(), 'drei.ogg'), { freq: 700, format: 'ogg' });
    const a = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'drei.ogg'), 'AUDIO');
    const res = await send('POST', '/admin/releases/commit', admin.auth, {
      idempotencyKey: crypto.randomUUID(),
      artistId,
      release: { mode: 'new', title: 'Albumtitel', type: 'ALBUM', year: 2026 },
      tracks: [{ uploadId: a.upload.id, title: 'Erster Song', discNumber: 1, trackNumber: 1, artistIds: [artistId], featuredArtistIds: [] }],
    });
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().result.releaseFolder).toMatch(/^Upload Künstler\/Alben\/2026 - Albumtitel \[[0-9a-f]{8}\]$/);
    const after = await fs.readFile(path.join(env.config.MUSIC_DIR, 'Upload Künstler/Alben/2026 - Albumtitel/01 - Erster Song/audio.flac'));
    expect(after.equals(before)).toBe(true);
    expect(await env.db.release.count({ where: { title: 'Albumtitel', albumArtistId: artistId } })).toBe(2);
  });

  it('Einzel-Single landet direkt im Veröffentlichungsordner', async () => {
    makeAudio(path.join(fixtures(), 'single.m4a'), { freq: 900, format: 'm4a' });
    makePng(path.join(fixtures(), 'single.png'), 'red');
    const a = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'single.m4a'), 'AUDIO');
    const c = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'single.png'), 'IMAGE');
    const res = await send('POST', '/admin/releases/commit', admin.auth, {
      idempotencyKey: crypto.randomUUID(),
      artistId,
      release: { mode: 'new', title: 'Singletitel', type: 'SINGLE', year: 2026, coverUploadId: c.upload.id },
      tracks: [{ uploadId: a.upload.id, title: 'Singletitel', discNumber: 1, trackNumber: 1, artistIds: [artistId], featuredArtistIds: [] }],
    });
    expect(res.statusCode, res.body).toBe(200);
    const dir = path.join(env.config.MUSIC_DIR, 'Upload Künstler/Singles/2026 - Singletitel');
    expect((await fs.readdir(dir)).sort()).toEqual(['audio.m4a', 'cover.png']);
  });

  it('weist manipulierte Dateien zurück (Inhalt statt Endung geprüft)', async () => {
    await fs.writeFile(path.join(fixtures(), 'fake.mp3'), Buffer.from('Das ist kein Audio '.repeat(100)));
    const u = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'fake.mp3'), 'AUDIO');
    expect(u.upload.status).toBe('INVALID');
    await fs.writeFile(path.join(fixtures(), 'fake.png'), Buffer.from('kein Bild'.repeat(50)));
    const i = await uploadFileChunked(env, admin.auth, path.join(fixtures(), 'fake.png'), 'IMAGE');
    expect(i.upload.status).toBe('INVALID');
  });

  it('Abschnitts-Upload ist fortsetzbar und prüft den Offset', async () => {
    const data = Buffer.alloc(3 * 1024 * 1024 + 10, 1);
    const created = (await send('POST', '/admin/uploads', admin.auth, { kind: 'AUDIO', filename: 'x.flac', size: data.length })).json();
    const id = created.upload.id;
    const chunk = created.chunkSize;
    const put = (off: number, len: number) =>
      env.app.inject({
        method: 'PUT',
        url: `${API}/admin/uploads/${id}/content`,
        headers: { ...admin.auth, 'content-type': 'application/octet-stream', 'upload-offset': String(off) },
        payload: data.subarray(off, off + len),
      });
    expect((await put(0, chunk)).statusCode).toBe(200);
    const wrong = await put(0, chunk);
    expect(wrong.statusCode).toBe(409);
    expect(wrong.json().error.details.receivedSize).toBe(chunk);
    const status = await get(`/admin/uploads/${id}`, admin.auth);
    expect(status.json().upload.receivedSize).toBe(chunk);
    expect((await put(chunk, chunk * 2)).statusCode).toBe(413);
    expect((await send('POST', `/admin/uploads/${id}/complete`, admin.auth)).statusCode).toBe(409);
    expect((await send('DELETE', `/admin/uploads/${id}`, admin.auth)).json().upload.status).toBe('ABORTED');
  });
});

describe('Gleichnamige Songs und Suche', () => {
  it('erlaubt gleichnamige Songs/Alben bei verschiedenen Künstlern und findet sie über den Künstlernamen', async () => {
    const m = env.config.MUSIC_DIR;
    for (const artist of ['Linkin Park', 'Andere Band']) {
      const dir = path.join(m, artist, 'Alben', '2003 - Meteora', '01 - Numb');
      await fs.mkdir(dir, { recursive: true });
      makeAudio(path.join(dir, 'audio.flac'), { tags: { title: 'Numb', artist } });
    }
    const featDir = path.join(m, 'Linkin Park', 'Singles', '2004 - Numb Encore');
    await fs.mkdir(featDir, { recursive: true });
    makeAudio(path.join(featDir, 'audio.mp3'), { format: 'mp3', tags: { title: 'Numb/Encore', artist: 'Linkin Park feat. Jay-Z' } });
    const summary = await runLibraryScan(env.db, env.config);
    expect(summary.errors).toBe(0);

    const numb = await get('/search?q=numb', alice.auth);
    const tracks = numb.json().tracks.items as Array<{ title: string; artists: Array<{ name: string }>; release: { title: string; albumArtist: { name: string } } }>;
    expect(tracks.filter((t) => t.title === 'Numb')).toHaveLength(2);
    expect(new Set(tracks.filter((t) => t.title === 'Numb').map((t) => t.release.albumArtist.name))).toEqual(new Set(['Linkin Park', 'Andere Band']));
    expect(numb.json().releases.items.length).toBeGreaterThanOrEqual(1);

    const byArtist = await get('/search?q=linkin', alice.auth);
    expect(byArtist.json().tracks.items.map((t: { title: string }) => t.title)).toEqual(expect.arrayContaining(['Numb', 'Numb/Encore']));
    expect(byArtist.json().artists.items[0].name).toBe('Linkin Park');

    const byFeature = await get('/search?q=jay-z', alice.auth);
    expect(byFeature.json().tracks.items.map((t: { title: string }) => t.title)).toContain('Numb/Encore');

    const oneLetter = await get('/search?q=n', alice.auth);
    expect(oneLetter.json().tracks.items.length).toBeGreaterThan(0);

    const multi = await get('/search?q=andere%20numb', alice.auth);
    expect(multi.json().tracks.items).toHaveLength(1);

    const empty = await get('/search?q=xyzxyz', alice.auth);
    expect(empty.json().tracks.items).toHaveLength(0);

    const paged = await get('/search/tracks?q=numb&limit=1&offset=0', alice.auth);
    expect(paged.json().items).toHaveLength(1);
    expect(paged.json().nextOffset).toBe(1);
  });
});

describe('Bibliotheksscan', () => {
  it('wiederholte Scans erzeugen keine Duplikate; Verschiebungen und fehlende Dateien werden erkannt', async () => {
    const m = env.config.MUSIC_DIR;
    const dir = path.join(m, 'Scan Band', 'EPs', '2025 - Scan EP');
    await fs.mkdir(path.join(dir, '01 - Eins'), { recursive: true });
    await fs.mkdir(path.join(dir, '02 - Zwei'), { recursive: true });
    makePng(path.join(dir, 'cover.jpg'.replace('.jpg', '.png')), 'blue');
    makeAudio(path.join(dir, '01 - Eins', 'audio.flac'), { freq: 330 });
    makeAudio(path.join(dir, '02 - Zwei', 'audio.flac'), { freq: 660 });
    makePng(path.join(dir, '02 - Zwei', 'cover.png'), 'yellow');
    await fs.writeFile(path.join(dir, '02 - Zwei', 'kaputt.mp3'), 'kein mp3');
    makePng(path.join(m, 'Scan Band', 'artist.png'), 'orange');

    const s1 = await runLibraryScan(env.db, env.config);
    expect(s1.errors).toBe(1); // kaputte Datei einzeln gemeldet, Scan läuft weiter
    const count1 = await env.db.track.count();
    const release = await env.db.release.findFirstOrThrow({ where: { title: 'Scan EP' }, include: { albumArtist: true } });
    expect(release.type).toBe('EP');
    expect(release.coverImageId).toBeTruthy();
    expect(release.albumArtist.imageId).toBeTruthy();
    const tracks = await env.db.track.findMany({ where: { releaseId: release.id }, orderBy: { trackNumber: 'asc' } });
    expect(tracks.map((t) => t.title)).toEqual(['Eins', 'Zwei']);
    expect(tracks[0]!.coverImageId).toBeNull();
    expect(tracks[1]!.coverImageId).toBeTruthy();
    expect(tracks[0]!.needsReview).toBe(false);

    const s2 = await runLibraryScan(env.db, env.config);
    expect(s2.added).toBe(0);
    expect(await env.db.track.count()).toBe(count1);
    expect(await env.db.artist.count({ where: { name: 'Scan Band' } })).toBe(1);

    // Favorit + Playlist auf Track "Eins"
    await send('PUT', `/library/favorites/${tracks[0]!.id}`, alice.auth);
    // Datei verschieben → gleicher Track, neuer Pfad
    await fs.rename(path.join(dir, '01 - Eins'), path.join(dir, '01 - Eins (neu)'));
    const s3 = await runLibraryScan(env.db, env.config);
    expect(s3.moved).toBe(1);
    expect(s3.added).toBe(0);
    const moved = await env.db.track.findUniqueOrThrow({ where: { id: tracks[0]!.id } });
    expect(moved.audioRelPath).toContain('01 - Eins (neu)');
    expect(moved.available).toBe(true);

    // Datei entfernen → nicht verfügbar, Favorit bleibt erhalten
    await fs.rename(path.join(dir, '01 - Eins (neu)', 'audio.flac'), path.join(env.root, 'weg.flac'));
    const s4 = await runLibraryScan(env.db, env.config);
    expect(s4.missing).toBe(1);
    expect((await env.db.track.findUniqueOrThrow({ where: { id: tracks[0]!.id } })).available).toBe(false);
    expect(await env.db.favoriteTrack.count({ where: { trackId: tracks[0]!.id } })).toBe(1);
    const issues = await get('/admin/issues?kind=MISSING_FILE', admin.auth);
    expect(issues.json().items.length).toBeGreaterThanOrEqual(1);

    // Zurücklegen → wieder verfügbar
    await fs.rename(path.join(env.root, 'weg.flac'), path.join(dir, '01 - Eins (neu)', 'audio.flac'));
    const s5 = await runLibraryScan(env.db, env.config);
    expect(s5.restored).toBe(1);
  });

  it('überschreibt manuell gepflegte Metadaten nicht', async () => {
    const t = await env.db.track.findFirstOrThrow({ where: { title: 'Zwei' } });
    const res = await send('PATCH', `/admin/tracks/${t.id}`, admin.auth, { title: 'Zwei (bearbeitet)' });
    expect(res.statusCode).toBe(200);
    const file = path.join(env.config.MUSIC_DIR, t.audioRelPath);
    const now = new Date(Date.now() + 5000);
    await fs.utimes(file, now, now); // Datei „geändert“
    const s = await runLibraryScan(env.db, env.config);
    expect(s.updated).toBe(1);
    expect((await env.db.track.findUniqueOrThrow({ where: { id: t.id } })).title).toBe('Zwei (bearbeitet)');
  });
});

describe('Streaming', () => {
  it('unterstützt Range-Anfragen und lehnt ungültige Signaturen ab', async () => {
    const t = await env.db.track.findFirstOrThrow({ where: { available: true } });
    const r = await send('POST', `/tracks/${t.id}/stream-url`, alice.auth, { quality: 'original' });
    expect(r.statusCode).toBe(200);
    const { url } = r.json() as { url: string };
    expect(url).not.toContain(alice.token);
    const full = await env.app.inject({ method: 'GET', url });
    expect(full.statusCode).toBe(200);
    expect(full.headers['accept-ranges']).toBe('bytes');
    const size = Number(full.headers['content-length']);
    const part = await env.app.inject({ method: 'GET', url, headers: { range: 'bytes=10-19' } });
    expect(part.statusCode).toBe(206);
    expect(part.headers['content-range']).toBe(`bytes 10-19/${size}`);
    expect(part.rawPayload.length).toBe(10);
    const tail = await env.app.inject({ method: 'GET', url, headers: { range: 'bytes=-5' } });
    expect(tail.rawPayload.length).toBe(5);
    const bad = await env.app.inject({ method: 'GET', url, headers: { range: `bytes=${size + 10}-` } });
    expect(bad.statusCode).toBe(416);
    const tampered = await env.app.inject({ method: 'GET', url: url.replace(/sig=[^&]+/, 'sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA') });
    expect(tampered.statusCode).toBe(403);
    const otherTrack = await env.db.track.findFirstOrThrow({ where: { id: { not: t.id } } });
    const swapped = await env.app.inject({ method: 'GET', url: url.replace(t.id, otherTrack.id) });
    expect(swapped.statusCode).toBe(403);
  });
  it('liefert per X-Accel-Redirect aus, wenn konfiguriert', async () => {
    env.config.MEDIA_ACCEL_REDIRECT = true;
    try {
      const t = await env.db.track.findFirstOrThrow({ where: { available: true, audioRelPath: { contains: ' ' } } });
      const { url } = (await send('POST', `/tracks/${t.id}/stream-url`, alice.auth, {})).json() as { url: string };
      const res = await env.app.inject({ method: 'GET', url });
      expect(res.headers['x-accel-redirect']).toBe('/_protected/music/' + t.audioRelPath.split('/').map(encodeURIComponent).join('/'));
      expect(res.rawPayload.length).toBe(0);
    } finally {
      env.config.MEDIA_ACCEL_REDIRECT = false;
    }
  });
  it('Streaming-URL wird nach Abmelden ungültig', async () => {
    const u = await makeUser(env, 'streamer');
    const t = await env.db.track.findFirstOrThrow({ where: { available: true } });
    const { url } = (await send('POST', `/tracks/${t.id}/stream-url`, u.auth, {})).json() as { url: string };
    await send('POST', '/auth/logout', u.auth);
    expect((await env.app.inject({ method: 'GET', url })).statusCode).toBe(403);
  });
});

describe('Private Nutzerdaten', () => {
  it('Playlists sind privat, Reihenfolge und Favoriten bleiben gespeichert', async () => {
    const tracks = await env.db.track.findMany({ take: 3, orderBy: { createdAt: 'asc' } });
    const created = await send('POST', '/playlists', alice.auth, { name: 'Alices Mix', trackIds: tracks.map((t) => t.id) });
    expect(created.statusCode).toBe(200);
    const pid = created.json().playlist.id;
    expect((await get(`/playlists/${pid}`, bob.auth)).statusCode).toBe(404);
    expect((await send('DELETE', `/playlists/${pid}`, bob.auth)).statusCode).toBe(404);
    expect((await get('/playlists', bob.auth)).json().items.find((p: { id: string }) => p.id === pid)).toBeUndefined();
    expect((await get('/search/playlists?q=alices', bob.auth)).json().items).toHaveLength(0);
    expect((await get('/search/playlists?q=alices', alice.auth)).json().items).toHaveLength(1);

    const detail = (await get(`/playlists/${pid}`, alice.auth)).json();
    const entryIds = detail.entries.map((e: { entryId: string }) => e.entryId) as string[];
    const reversed = [...entryIds].reverse();
    expect((await send('PUT', `/playlists/${pid}/order`, alice.auth, { entryIds: reversed })).statusCode).toBe(200);
    const after = (await get(`/playlists/${pid}`, alice.auth)).json();
    expect(after.entries.map((e: { entryId: string }) => e.entryId)).toEqual(reversed);
    // Eintrag entfernen → Positionen lückenlos
    await send('DELETE', `/playlists/${pid}/entries/${reversed[0]}`, alice.auth);
    const after2 = (await get(`/playlists/${pid}`, alice.auth)).json();
    expect(after2.entries.map((e: { position: number }) => e.position)).toEqual([0, 1]);

    await send('PUT', `/library/favorites/${tracks[1]!.id}`, alice.auth);
    const favA = (await get('/library/favorites/ids', alice.auth)).json().ids as string[];
    const favB = (await get('/library/favorites/ids', bob.auth)).json().ids as string[];
    expect(favA).toContain(tracks[1]!.id);
    expect(favB).not.toContain(tracks[1]!.id);

    await send('POST', '/library/history', alice.auth, { trackId: tracks[2]!.id });
    const homeA = (await get('/home', alice.auth)).json();
    const homeB = (await get('/home', bob.auth)).json();
    expect(homeA.recentlyPlayed.map((t: { id: string }) => t.id)).toContain(tracks[2]!.id);
    expect(homeB.recentlyPlayed).toHaveLength(0);
    expect(homeA.newReleases.length).toBeGreaterThan(0);
  });
});
