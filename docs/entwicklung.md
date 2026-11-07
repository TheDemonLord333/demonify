# Entwicklung unter Windows und macOS

## Voraussetzungen

| Werkzeug | Version |
|---|---|
| Flutter | 3.47.x stable (Dart 3.13) – Projekt wurde damit erstellt |
| Node.js | 24 LTS |
| PostgreSQL | 15 oder neuer (Debian 12 nutzt 15) |
| FFmpeg inkl. ffprobe | aktuell, im `PATH` |
| Android Studio (Windows) | mit Android SDK, Emulator oder Gerät |
| Xcode (macOS) | aktuelle Version, CocoaPods |

Windows: PostgreSQL über den offiziellen Installer, FFmpeg z. B. per `winget install Gyan.FFmpeg`, Node.js per `winget install OpenJS.NodeJS.LTS`.
macOS: `brew install postgresql@16 ffmpeg node@24`.

## Datenbank anlegen

```bash
psql -U postgres -c "CREATE ROLE demonify LOGIN PASSWORD 'devpass' CREATEDB;"
```

```bash
psql -U postgres -c "CREATE DATABASE demonify OWNER demonify;"
```

```bash
psql -U postgres -c "CREATE DATABASE demonify_test OWNER demonify;"
```

## Backend

```bash
cd backend
```

```bash
cp .env.example .env
```

In `.env` für die Entwicklung anpassen: `NODE_ENV=development`, `DATABASE_URL=postgresql://demonify:devpass@127.0.0.1:5432/demonify`,
zwei verschiedene Secrets (je ≥ 32 Zeichen), `MUSIC_DIR`/`DATA_DIR` auf lokale Ordner, `MEDIA_ACCEL_REDIRECT=false`,
`COOKIE_SECURE=false`, `CORS_ORIGINS=http://localhost:5173`, `HOST=0.0.0.0` (damit Handy/Emulator den Server erreichen).
Optional `DEV_SEED_ENABLED=true` für klar gekennzeichnete Testtöne.

```bash
npm ci
```

```bash
npx prisma migrate deploy
```

```bash
npm run dev
```

Admin anlegen, optional Testtöne erzeugen und scannen:

```bash
npm run cli:dev -- create-admin --username admin
```

```bash
npm run cli:dev -- seed-dev
```

```bash
npm run cli:dev -- scan
```

Prüfungen:

```bash
npm run typecheck
```

```bash
TEST_DATABASE_URL=postgresql://demonify:devpass@127.0.0.1:5432/demonify_test npm test
```

(Unter Windows PowerShell: `$env:TEST_DATABASE_URL="…"; npm test`.)

## Verwaltungswebseite

```bash
cd admin-web
```

```bash
npm ci
```

```bash
npm run dev
```

Aufruf: http://localhost:5173/admin/ – Vite leitet `/api` an `127.0.0.1:1340` weiter.

## Flutter-App

```bash
cd demonify
```

```bash
flutter pub get
```

Android-Emulator (Host-Rechner ist dort `10.0.2.2`):

```bash
flutter run --dart-define=DEMONIFY_API_BASE=http://10.0.2.2:1340/api/v1/
```

Echtes Gerät im WLAN:

```bash
flutter run --dart-define=DEMONIFY_API_BASE=http://<IP-des-Rechners>:1340/api/v1/
```

Gegen den Produktionsserver (Standard, ohne Parameter):

```bash
flutter run
```

Die Serveradresse lässt sich zusätzlich auf dem Login-Bildschirm („Serveradresse ändern“) setzen.
Unverschlüsseltes HTTP ist nur in Android-Debug-Builds bzw. für lokale Netzwerkadressen unter iOS erlaubt.

Prüfungen:

```bash
flutter analyze
```

```bash
flutter test
```

Texte liegen zentral in `lib/l10n/app_de.arb` (nach Änderungen: `flutter gen-l10n`).
Neue Sprache: `app_en.arb` o. Ä. ergänzen.

## Windows-Version (später)

Das Projekt enthält noch keinen `windows/`-Ordner. Architektur und Pakete sind vorbereitet
(media_kit inkl. Equalizer, flutter_secure_storage, file_picker unterstützen Windows; die System-Mediensteuerung
über audio_service ist optional gekapselt). Aktivieren:

```bash
flutter create --platforms=windows --org me.thedemonlord333 .
```

```bash
dart run flutter_launcher_icons
```
