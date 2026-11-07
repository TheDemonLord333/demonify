# Demonify

Private Musikplattform für Familie und Freunde – Spotify-nahe Bedienung, eigene Marke, eigener Server.

| Teil | Ort | Stack |
|---|---|---|
| App (Android, iOS; Windows vorbereitet) | [`demonify/`](demonify/) | Flutter 3.47 · Dart 3.13 · Riverpod 3 · go_router · media_kit (libmpv/FFmpeg) · audio_service · audio_session |
| API-Server | [`backend/`](backend/) | Node.js 24 LTS · TypeScript · Fastify 5 · Prisma 7 · PostgreSQL · FFmpeg/ffprobe · sharp |
| Verwaltungswebseite | [`admin-web/`](admin-web/) | React 19 · TypeScript · Vite 8 (Basis `/admin/`) |
| Deployment | [`deploy/`](deploy/) | Nginx · systemd · Let's Encrypt · Skripte |
| Dokumentation | [`docs/`](docs/) | |

Öffentliche Adressen:

- `https://demonify.thedemonlord333.me/` – Startseite (reserviert für die spätere Musik-Webversion)
- `https://demonify.thedemonlord333.me/admin/` – Verwaltung
- `https://demonify.thedemonlord333.me/api/v1/` – API (OpenAPI: `/api/v1/docs`, JSON: `/api/v1/openapi.json`)

## Funktionen (Kurzüberblick)

- **App:** Login (Benutzername/Passwort, konfigurierbare Serveradresse, Einladungen einlösen), Start, Live-Suche ab dem ersten Buchstaben, Bibliothek (Playlists, Künstler, Alben/EPs/Singles, Lieblingssongs, Downloads, Sortierung/Filter), Künstler-, Veröffentlichungs- und Playlistseiten, zentraler Player mit Mini-Player, Vollbild-Player, Warteschlange (umsortieren/entfernen), Shuffle, Wiederholung, Hintergrundwiedergabe, Sperrbildschirm/Bluetooth, Offline-Downloads, **10-Band-Equalizer** (Einstellungen → Klang), Einstellungen, Verwaltung für Admins.
- **Server:** Benutzer/Rollen, Argon2id, kurzlebige Access-Tokens + rotierende Refresh-Tokens, Web-Cookies mit CSRF-Schutz, Einladungen, Katalog mit normalisiert eindeutigen Künstlernamen, Bibliotheksscan (CLI + Admin-Aktion), wiederaufnehmbare Abschnitts-Uploads mit automatischer Ablage, signierte Streaming-URLs mit Range-Support (Nginx X-Accel-Redirect), AAC-Transkodierung als Hintergrundauftrag, Playlists, Favoriten, Hörverlauf, PostgreSQL-Suche (pg_trgm).
- **Verwaltung (Web + App, gleiche API):** Künstler (Live-Vorschläge, Anlegen, Umbenennen, Profilbild mit Zuschnitt), Upload-Assistent, Veröffentlichungen/Tracks bearbeiten, Reihenfolge, Song-/Veröffentlichungscover, Benutzer & Einladungen, Aufträge, Probleme und nicht verfügbare Dateien.

## Dokumentation

- [Installation auf Debian 12](docs/installation-debian12.md)
- [Cloudflare, DNS und HTTPS](docs/cloudflare.md)
- [Entwicklung unter Windows und macOS](docs/entwicklung.md)
- [Android- und iOS-Builds](docs/android-ios-build.md)
- [Backup und Wiederherstellung](docs/backup-wiederherstellung.md)
- [Updates](docs/updates.md)
- [Architektur, Ablage, Audio & Equalizer](docs/architektur.md)
- [Normalisierung von Namen](docs/normalisierung.md)
- [Prüfprotokoll & bekannte Einschränkungen](docs/pruefung.md)

## Schnellstart (Entwicklung)

```bash
cd backend && cp .env.example .env   # Werte anpassen (DATABASE_URL, Secrets, Pfade, NODE_ENV=development)
npm ci && npx prisma migrate deploy && npm run dev
```

```bash
cd admin-web && npm ci && npm run dev   # http://localhost:5173/admin/
```

```bash
cd demonify && flutter pub get && flutter run --dart-define=DEMONIFY_API_BASE=http://<IP-des-Rechners>:1340/api/v1/
```

Das App-Icon stammt aus `Neon horned demon headphone icon.png` (Original im Hauptverzeichnis, Arbeitskopie `demonify/assets/icon/app_icon.png`).
