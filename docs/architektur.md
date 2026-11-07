# Architektur

```
App (Flutter)  ─┐                       ┌─ /admin/      Verwaltung (statisch, React)
Verwaltung (Web)├─ HTTPS ─ Nginx ───────┼─ /api/        → Fastify 127.0.0.1:1340 ─ PostgreSQL (lokal)
spätere Web-App ┘                       ├─ /            Startseite (reserviert für Musik-Web)
                                        └─ /_protected/ internal → /srv/music, Cache (nur per X-Accel-Redirect)
```

Die App greift ausschließlich über `/api/v1` zu – nie direkt auf Datenbank oder Dateisystem.
Authentifizierung, Datenmodelle und APIs sind so gebaut, dass die spätere Musik-Webversion (Cookie-Login wie die Verwaltung) sie direkt nutzen kann.

## Backend (`backend/src`)

| Bereich | Datei(en) |
|---|---|
| Konfiguration (Umgebungsvariablen, Pflicht-Secrets) | `config.ts` |
| Auth: Argon2id, Access-Token (15 min, HMAC), rotierende Refresh-Tokens mit Wiederverwendungserkennung, Web-Cookies + CSRF | `services/auth.ts`, `plugins/auth.ts`, `routes/auth.ts` |
| Katalog, Suche (pg_trgm), Bibliothek, Playlists | `routes/*.ts` |
| Streaming: signierte, ressourcengebundene URLs (6 h), Range, X-Accel-Redirect | `routes/stream.ts` |
| Bibliotheksscan | `services/scanner.ts`, `services/layout.ts` |
| Uploads (Abschnitte, Prüfung per ffprobe/libvips) + Ablage | `services/uploads.ts`, `services/commit.ts` |
| Hintergrundaufträge (Scan, Transkodierung, Bereinigung) mit Parallelitätsgrenzen | `services/jobs.ts`, `services/transcoder.ts` |
| Verwaltung (nur ADMIN, serverseitig geprüft) | `routes/admin/*` |
| CLI | `cli/index.ts` |

Fehlerformat überall: `{"error":{"code":"…","message":"…","details":…}}`. Unbekannte Routen → JSON-404.
Authentifizierte Antworten: `Cache-Control: no-store`; Medien `private`. CORS nur für ausdrücklich konfigurierte Origins.
Logs enthalten weder Passwörter noch Tokens (Header geschwärzt, Signaturparameter gekürzt).

## Verbindliche Ablage

```
/srv/music/<Künstler>/<Alben|EPs|Singles>/<JJJJ - Titel>/[<NN - Titel>/]audio.<ext>, cover.<ext>
/srv/music/<Künstler>/artist.jpg
```

- Uploads: Album/EP-Tracks immer in Unterordnern; eine Single mit genau einem Track direkt im Veröffentlichungsordner,
  mehrere Single-Tracks in Unterordnern. Mehrere Discs: `D-NN - Titel` (z. B. `2-03 - Titel`); der Scan versteht zusätzlich `Disc 2/`.
- Sampler: Albumkünstler `Various Artists`, Trackordner `NN - Künstler - Titel`.
- Namensgleiche Veröffentlichungen/Tracks: eindeutiger Ordner mit ID-Zusatz `[abcd1234]` (Vergleich ohne Groß-/Kleinschreibung),
  nie Zusammenführung. Dateien werden exklusiv angelegt (`COPYFILE_EXCL` + `link`) und nie überschrieben.
- Dateinamen werden bereinigt (verbotene Zeichen, reservierte Windows-Namen, Länge).
- Datenbank speichert relative Pfade; Originale bleiben unverändert. Transkodierungen, eingebettete Cover und Covervarianten liegen im Cache (`DATA_DIR/cache`).
- Umbenennungen in der Verwaltung ändern nur die Datenbank, nicht die Ordner (kein Verschieben großer Dateien).

## Cover

Veröffentlichung: `cover.*` im Veröffentlichungsordner → eingebettetes Cover des ersten Tracks.
Song: `cover.*` im Trackordner → eingebettetes Cover (nur wenn es sich vom Veröffentlichungscover unterscheidet).
API liefert pro Track `coverImageId` (effektiv: Songcover → Veröffentlichungscover) und `hasOwnCover`; fehlt beides → Demonify-Platzhalter.
Manuell gesetzte Cover/Metadaten sind gesperrt (`coverLocked`/`metaLocked`) und werden vom Scan nicht überschrieben.

## Bibliotheksscan

Idempotent: bekannte Dateien über Pfad + Größe + mtime, verschobene Dateien über Inhalts-Fingerabdruck
(Größe + erste/letzte MiB), fehlende Dateien → „nicht verfügbar“ (Playlists/Verlauf bleiben), fehlerhafte Dateien
einzeln als Problem gemeldet, unvollständige Metadaten zur Korrektur markiert. Gleichzeitige Scans verhindert ein PostgreSQL-Advisory-Lock.

## App (`demonify/lib`)

```
core/      Konfiguration, Theme/Design-Tokens, API-Client (Timeouts, Token-Erneuerung), sicherer Speicher, Widgets
features/  auth, home, search, library, catalog, playlists, player (+equalizer), downloads, settings, admin, shell
l10n/      zentrale Texte (app_de.arb)
```

Zustand: Riverpod 3. Darstellung, Zustand, Datenzugriff, Downloads und Audio sind getrennt.
Lokale Download-Daten (`features/downloads/download_models.dart`) sind bewusst vom Servermodell getrennt.

### Audio

- **Engine: media_kit (libmpv + FFmpeg)** – eine Engine für Android, iOS und später Windows. Spielt alle Bibliotheksformate
  (MP3, FLAC, AAC/M4A, Ogg/Opus, WAV) auch auf iOS, unterstützt HTTP-Range-Seeking.
- **audio_service:** Hintergrundwiedergabe, Benachrichtigung, Sperrbildschirm/Control Center, Bluetooth-/Headset-Tasten.
- **audio_session:** Audiofokus, Anrufe/Unterbrechungen (Pause + Fortsetzen), Ducking, Kopfhörer abgezogen → Pause.
- Quellenwahl: lokaler Download hat immer Vorrang (auch ohne Netz), sonst kurzlebige signierte Streaming-URL.
- Warteschlange, Position, Shuffle und Wiederholung werden pro Benutzer gespeichert und beim Start ohne automatisches Abspielen wiederhergestellt.

### Equalizer (Einstellungen → Klang)

Geprüft wurden: just_audio (Equalizer nur Android, kein iOS), native Lösungen (Android `DynamicsProcessing`/`Equalizer`
am Audio-Session-ID, iOS `AVAudioUnitEQ`/`MTAudioProcessingTap` – würde einen eigenen nativen Player pro Plattform erfordern)
und media_kit. Entscheidung: **FFmpeg-Filter `equalizer` in libmpv**. Die media_kit-Audiobuilds für Android
(`libmpv-android-audio-build` v1.1.8) und iOS (`libmpv-darwin-build` v0.6.0) wurden geprüft: beide enthalten
`--enable-filter=equalizer`. Damit gilt auf beiden Plattformen dieselbe, echte Signalverarbeitung:

- 10 Peaking-Bänder (Bandbreite 1 Oktave): 31, 62, 125, 250, 500 Hz, 1, 2, 4, 8, 16 kHz; −12 … +12 dB.
- Voreinstellungen: Neutral, Bass Boost, Rock, Pop, Elektronisch, Gesang; benutzerdefiniert (automatisch gespeichert); „Zurücksetzen“.
- Headroom: automatische Vorverstärkung = −(stärkste Anhebung) oder manuell −12 … 0 dB (über die mpv-Lautstärke, kubische Skala berücksichtigt).
- Änderungen werden entprellt (60 ms) während der Wiedergabe angewendet; mpv baut dabei die Filterkette neu auf
  (kurze, in der Regel unhörbare Umschaltung).
- Wirkt auf Streaming und Offline-Wiedergabe; Dateien bleiben unverändert. Gespeichert pro Benutzer und Gerät.
- Bluetooth/AirPlay: Der Klang wird im Gerät berechnet und dann übertragen → EQ wirkt. Künftiges Casting (Wiedergabe auf dem Zielgerät) → EQ wirkt nicht; die App weist darauf hin.
- Nimmt die Engine den Filter nicht an, zeigt die App einen Hinweis statt wirkungsloser Regler.

Einschränkung: Die Wirksamkeit auf echten Android-/iOS-Geräten konnte in der Entwicklungsumgebung nicht gehört werden
(keine Geräte/SDKs); geprüft wurden Filtersyntax (FFmpeg), Build-Konfiguration der Bibliotheken und die App-Logik per Tests.

## Offline-Downloads und Grenzen

Downloads liegen im privaten App-Speicher (`Application Support/users/<Benutzer-ID>/downloads`), getrennt pro Benutzer;
die App liest nur den Ordner des angemeldeten Benutzers. Beim Abmelden kann der Benutzer sie löschen.
Ehrliche Grenze: Wird ein Konto später serverseitig gesperrt oder ein Song entfernt, kann der Server bereits
heruntergeladene Dateien auf einem Gerät **nicht** fernlöschen. Beim nächsten Online-Start schlägt die
Sitzungsprüfung fehl (Abmeldung); die Dateien bleiben aber bis zum Löschen (Abmelden-Dialog, Downloadverwaltung,
App-Deinstallation) im App-Speicher. Ein gerootetes/jailbroken Gerät kann auf diese Dateien zugreifen.
