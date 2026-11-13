# Normalisierung und Eindeutigkeit von Namen

Umsetzung: `backend/src/lib/normalize.ts`. Gespeichert werden getrennt:

- `Artist.name` – Anzeige-Schreibweise (bereinigt, sonst wie eingegeben)
- `Artist.nameKey` – normalisierter Schlüssel mit **UNIQUE-Constraint** in PostgreSQL
- `Artist.searchText` – Suchtext (zusätzlich ohne Diakritika)

## Regeln für `nameKey`

1. Unicode **NFKC** (Kompatibilitätsformen vereinheitlichen, z. B. Vollbreite „Ｄｅｍｏｎ“ → „Demon“, Ligatur „ﬁ“ → „fi“).
2. Alle Leerraumzeichen (inkl. geschütztem Leerzeichen, Tabulator) → normales Leerzeichen.
3. Unsichtbare Formatzeichen entfernen (Zero-Width-Space/-Joiner, Wortverbinder, BOM, weiches Trennzeichen).
4. Führende/nachfolgende Leerzeichen entfernen, Folgen zu einem Leerzeichen zusammenfassen.
5. Vollständige Groß-/Kleinschreibungsfaltung: `toUpperCase()` → `toLowerCase()` (dadurch „ß“ = „SS“ = „ss“).
6. Erneut NFKC.

Diakritika bleiben erhalten: **„Björk“ und „Bjork“ sind verschiedene Künstler.** Solche Fälle werden nur als
Ähnlichkeitshinweis angezeigt (pg_trgm-Ähnlichkeit auf dem diakritikfreien Suchtext) und nie automatisch zusammengeführt.

Beispiele, die **nicht** doppelt angelegt werden können: `The Demon Lord`, `the demon lord`, `  THE   DEMON LORD `, `Ｔｈｅ Demon Lord`.

## Ablauf beim Anlegen

1. Live-Vorschläge ab dem ersten Buchstaben (Wortanfänge, ab 2 Zeichen auch Teilwörter).
2. „Neuen Künstler erstellen“ übernimmt den eingetippten Namen.
3. Vor dem Speichern: Prüfung `GET /api/v1/admin/artists/check` (exakter normalisierter Treffer + ähnliche Namen).
4. Speichern: Die Datenbank-Constraint entscheidet verbindlich. Bei gleichzeitigen Anlegeversuchen erhält der
   zweite `409 ARTIST_EXISTS` mit dem vorhandenen Künstler, den die Oberfläche direkt zur Auswahl anbietet.

## Was bewusst mehrfach vorkommen darf

Songtitel und Veröffentlichungstitel – auch beim selben Künstler. Beziehungen laufen ausschließlich über IDs;
die Suche zeigt Künstler und Veröffentlichung zur Unterscheidung an. Dateiduplikate werden beim Scan über
Pfad bzw. Inhalts-Fingerabdruck erkannt, nicht über Titel.

## Benutzernamen

Gleiche Regeln (`usernameKey`, eindeutig). Erlaubt: 3–32 Zeichen aus Buchstaben, Ziffern, `.`, `_`, `-` – also nie `@`.

## E-Mail-Adressen

Anzeige: NFKC, unsichtbare Zeichen entfernt, getrimmt. Schlüssel `emailKey`: zusätzlich Kleinschreibung (eindeutig,
nur bestätigte Adressen). Dieselbe Funktion (`normalizeEmail`) gilt beim Erfassen, Anmelden, Ändern und Zurücksetzen.
Ein gemeinsames Eingabefeld wird so aufgelöst: enthält es `@` → E-Mail, sonst Anmeldename.
