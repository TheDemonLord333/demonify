/**
 * Normalisierungsregeln (dokumentiert in docs/normalisierung.md).
 *
 * nameKey (eindeutiger Künstlerschlüssel):
 *   1. Unicode NFKC (Kompatibilitätszerlegung + Komposition: "ﬁ" → "fi", Vollbreite → ASCII)
 *   2. Alle Unicode-Leerraumzeichen (inkl. NBSP) → normales Leerzeichen
 *   3. Unsichtbare Formatzeichen (Zero-Width-Space/Joiner, BOM, Soft Hyphen) entfernen
 *   4. Führende/nachfolgende Leerzeichen entfernen, Folgen von Leerzeichen zu einem zusammenfassen
 *   5. Vollständige Groß-/Kleinschreibungs-Faltung: toUpperCase → toLowerCase ("ß" → "ss")
 *   6. Erneut NFKC
 *   Diakritika bleiben erhalten: "Björk" und "Bjork" sind verschiedene Namen (→ nur Ähnlichkeitshinweis).
 *
 * searchText (Suche): nameKey-Regeln + Diakritika entfernt (NFKD, Combining Marks löschen).
 */
const INVISIBLE = /[\u00AD\u200B-\u200D\u2060\uFEFF]/gu;
const WHITESPACE = /[\s\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+/gu;

export function cleanDisplayName(input: string): string {
  return input.normalize('NFKC').replace(INVISIBLE, '').replace(WHITESPACE, ' ').trim();
}

export function nameKey(input: string): string {
  const cleaned = cleanDisplayName(input);
  return cleaned.toUpperCase().toLowerCase().normalize('NFKC');
}

export function foldDiacritics(input: string): string {
  return input.normalize('NFKD').replace(/\p{M}+/gu, '').normalize('NFC');
}

export function searchText(...parts: Array<string | null | undefined>): string {
  return parts
    .filter((p): p is string => typeof p === 'string' && p.length > 0)
    .map((p) => foldDiacritics(nameKey(p)))
    .join(' ')
    .trim();
}

/** Eingabe aus dem Suchfeld identisch normalisieren */
export function normalizeQuery(q: string): string {
  return foldDiacritics(nameKey(q));
}

/** LIKE-Sonderzeichen maskieren */
export function escapeLike(s: string): string {
  return s.replace(/[\\%_]/g, (m) => `\\${m}`);
}

export function usernameKey(input: string): string {
  return nameKey(input);
}
