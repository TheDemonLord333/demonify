import { describe, expect, it } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { nameKey, searchText, cleanDisplayName } from '../src/lib/normalize.js';
import { sanitizeSegment, resolveInside, createUniqueDir } from '../src/lib/fsnames.js';
import { parseLocation, trackFolderName, releaseFolderName } from '../src/services/layout.js';
import { splitArtists } from '../src/lib/media.js';
import { signToken, verifyToken } from '../src/lib/tokens.js';

describe('Normalisierung von Künstlernamen', () => {
  it('ignoriert Groß-/Kleinschreibung, Randleerzeichen und Mehrfachleerzeichen', () => {
    expect(nameKey('  The   Demon  Lord ')).toBe(nameKey('the demon lord'));
    expect(nameKey('THEDEMONLORD333')).toBe(nameKey('TheDemonLord333'));
  });
  it('wendet Unicode-NFKC und vollständige Faltung an', () => {
    expect(nameKey('Ｄｅｍｏｎ')).toBe(nameKey('demon')); // Vollbreite
    expect(nameKey('Straße')).toBe(nameKey('STRASSE')); // ß → ss
    expect(nameKey('Café')).toBe(nameKey('Café')); // kombinierend vs. vorkomponiert
    expect(nameKey('A B')).toBe(nameKey('a b')); // geschütztes Leerzeichen
    expect(nameKey('A​B')).toBe(nameKey('ab')); // Zero-Width-Space
  });
  it('unterscheidet Diakritika (nur Ähnlichkeitshinweis, keine Zusammenführung)', () => {
    expect(nameKey('Björk')).not.toBe(nameKey('Bjork'));
    expect(searchText('Björk')).toBe(searchText('Bjork'));
  });
  it('behält Anzeige-Schreibweise getrennt', () => {
    expect(cleanDisplayName('  AC/DC  ')).toBe('AC/DC');
  });
});

describe('Dateisystemnamen', () => {
  it('bereinigt verbotene Zeichen und reservierte Namen', () => {
    expect(sanitizeSegment('AC/DC')).toBe('AC DC');
    expect(sanitizeSegment('What?: <Yes>|*')).toBe('What Yes');
    expect(sanitizeSegment('CON')).toBe('_CON');
    expect(sanitizeSegment('...')).toBe('Unbenannt');
    expect(sanitizeSegment(' trailing. ')).toBe('trailing');
  });
  it('verhindert Pfad-Traversal', () => {
    expect(() => resolveInside('/srv/music', '../etc/passwd')).toThrow();
    expect(() => resolveInside('/srv/music', '/etc/passwd')).toThrow();
    expect(() => resolveInside('/srv/music', 'a/../../b')).toThrow();
    expect(resolveInside('/srv/music', 'A/B/audio.flac')).toBe('/srv/music/A/B/audio.flac');
  });
  it('legt bei Namenskollision einen Ordner mit stabilem ID-Zusatz an', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'dmf-unit-'));
    const a = await createUniqueDir(dir, '2026 - Numb', 'aaaaaaaa-0000-0000-0000-000000000000');
    const b = await createUniqueDir(dir, '2026 - Numb', 'bbbbbbbb-0000-0000-0000-000000000000');
    const c = await createUniqueDir(dir, '2026 - NUMB', 'cccccccc-0000-0000-0000-000000000000');
    expect(path.basename(a)).toBe('2026 - Numb');
    expect(path.basename(b)).toBe('2026 - Numb [bbbbbbbb]');
    expect(path.basename(c)).toBe('2026 - NUMB [cccccccc]');
    await fs.rm(dir, { recursive: true });
  });
});

describe('Ablagestruktur', () => {
  it('erkennt Album-Tracks in Unterordnern', () => {
    const l = parseLocation('TheDemonLord333/Alben/2026 - Albumtitel/02 - Zweiter Song/audio.mp3');
    expect(l).toMatchObject({ structured: true, type: 'ALBUM', releaseYear: 2026, releaseTitle: 'Albumtitel', trackNumber: 2, trackTitle: 'Zweiter Song' });
    expect(l.trackFolderRel).toBe('TheDemonLord333/Alben/2026 - Albumtitel/02 - Zweiter Song');
    expect(l.releaseFolderRel).toBe('TheDemonLord333/Alben/2026 - Albumtitel');
  });
  it('erkennt Singles ohne Track-Unterordner', () => {
    const l = parseLocation('TheDemonLord333/Singles/2026 - Singletitel/audio.mp3');
    expect(l).toMatchObject({ type: 'SINGLE', releaseTitle: 'Singletitel', trackFolderRel: null, trackTitle: null });
  });
  it('erkennt Sampler-Tracks und Disc-Nummern', () => {
    const l = parseLocation('Various Artists/Alben/2026 - Samplername/01 - Künstler - Songtitel/audio.flac');
    expect(l).toMatchObject({ trackArtist: 'Künstler', trackTitle: 'Songtitel', trackNumber: 1 });
    const d = parseLocation('X/Alben/2020 - Doppel/2-03 - Titel/audio.flac');
    expect(d).toMatchObject({ discNumber: 2, trackNumber: 3 });
    const d2 = parseLocation('X/Alben/2020 - Doppel/Disc 2/05 - Titel/audio.flac');
    expect(d2).toMatchObject({ discNumber: 2, trackNumber: 5 });
  });
  it('entfernt ID-Zusätze aus Ordnernamen', () => {
    const l = parseLocation('X/EPs/2026 - Numb [abcd1234]/01 - Numb [12345678]/audio.flac');
    expect(l).toMatchObject({ type: 'EP', releaseTitle: 'Numb', trackTitle: 'Numb' });
  });
  it('erzeugt Ordnernamen', () => {
    expect(releaseFolderName(2026, 'A/B')).toBe('2026 - A B');
    expect(trackFolderName({ disc: 1, track: 3, title: 'Song', multiDisc: false })).toBe('03 - Song');
    expect(trackFolderName({ disc: 2, track: 3, title: 'Song', multiDisc: true })).toBe('2-03 - Song');
    expect(trackFolderName({ disc: 1, track: 1, title: 'Song', multiDisc: false, artistPrefix: 'Künstler' })).toBe('01 - Künstler - Song');
  });
  it('trennt Features', () => {
    expect(splitArtists('A feat. B & C')).toEqual({ primary: ['A'], featured: ['B', 'C'] });
    expect(splitArtists('A; B', 'Song (feat. C)')).toEqual({ primary: ['A', 'B'], featured: ['C'] });
  });
});

describe('Tokens', () => {
  it('lehnt abgelaufene und manipulierte Tokens ab', () => {
    const secret = 'x'.repeat(40);
    const t = signToken({ sub: 'u', exp: Math.floor(Date.now() / 1000) + 60 }, secret);
    expect(verifyToken(t, secret)).not.toBeNull();
    expect(verifyToken(t, 'y'.repeat(40))).toBeNull();
    expect(verifyToken(t.slice(0, -2) + 'AA', secret)).toBeNull();
    const expired = signToken({ sub: 'u', exp: Math.floor(Date.now() / 1000) - 1 }, secret);
    expect(verifyToken(expired, secret)).toBeNull();
  });
});
