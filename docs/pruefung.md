# Prüfprotokoll und bekannte Einschränkungen

Stand: Implementierung in einer Linux-Entwicklungsumgebung (Node.js 24, PostgreSQL 16, FFmpeg, Flutter 3.47.9, nginx 1.24).
Kein Zugriff auf den Zielserver, Cloudflare, Android-SDK oder Xcode.

## Tatsächlich ausgeführte Prüfungen

| Bereich | Prüfung | Ergebnis |
|---|---|---|
| Backend | `tsc --noEmit` | ohne Fehler |
| Backend | `vitest run` – 45 Unit-/Integrationstests gegen echte PostgreSQL-DB und echte FFmpeg-Audiodateien | 45/45 bestanden |
| Verwaltung | `tsc -b`, `vite build` | ohne Fehler |
| Verwaltung | Playwright im Chromium: Login, Dashboard, Künstler-Live-Vorschläge, Release-Detail, mobiles Layout, kompletter Upload-Assistent (Künstler anlegen → Album → Cover → 2 Audiodateien → Songcover → Bestätigen) | erfolgreich, Ordnerstruktur korrekt, keine JS-Fehler |
| App | `flutter analyze` | keine Befunde |
| App | `flutter test` – 31 Tests: Warteschlange/Shuffle/Wiederholung, Equalizer-Modell/Filterkette, Serveradresse, Player bevorzugt lokale Downloads auch ohne Server, Login-Widget, Layout ohne Überlauf (360 px bei 100 %/150 % Schrift, 1280 px) | 31/31 bestanden |
| Equalizer | FFmpeg-Filterkette (`equalizer=f=…:t=o:w=1:g=…`) mit ffmpeg validiert; media_kit-Audiobuilds für Android (v1.1.8) und iOS (v0.6.0) heruntergeladen und auf `--enable-filter=equalizer` geprüft | vorhanden |
| Nginx | Produktionskonfiguration mit nginx getestet (selbstsigniertes Zertifikat, Testpfade): HTTP→HTTPS, `/api/v1` unverändert durchgereicht, unbekannte API-Route → JSON-404, `/api/foo` → JSON, `/admin/kuenstler` Deep-Link → Verwaltung, Assets, Startseite, `/_protected/` direkt → 404, Streaming per X-Accel mit Range (206, Datei bitgenau identisch), manipulierte Signatur → 403, 8-MB-Abschnitt ok, zu großer Body → JSON-413, Backend aus → JSON-503 | bestanden |
| Deployment | Produktions-Build wie `deploy.sh` (npm ci, build ohne DATABASE_URL, migrate, prune) und Start von Server/CLI aus dem Build | bestanden |

### Abgedeckte Anforderungen (Auswahl, automatisiert)

- Normale Benutzer erhalten 403 auf alle Verwaltungsendpunkte; Rollenentzug wirkt sofort; letzter Admin geschützt.
- Private Daten getrennt (Playlists, Favoriten, Hörverlauf, Playlist-Suche).
- Abgelaufene/manipulierte/fremd signierte Tokens → 401; Refresh-Rotation mit Wiederverwendungserkennung; Abmelden und Sperren widerrufen sofort (auch Streaming-URLs).
- Web-Cookies HttpOnly + SameSite=Strict, CSRF-Pflicht für Änderungen.
- Künstlernamen normalisiert eindeutig (inkl. 5 gleichzeitiger Anlageversuche → genau 1), DB-Constraint greift.
- Gleichnamige Songs/Alben bei verschiedenen Künstlern und beim selben Künstler erlaubt (eigener Ordner mit ID-Zusatz, Original unverändert).
- Upload erzeugt die verbindliche Struktur (Album mit Trackordnern, Einzel-Single flach), Song- und Veröffentlichungscover korrekt, wiederholter Commit ohne Duplikat, manipulierte Audio-/Bilddateien abgelehnt, Abschnitts-Upload fortsetzbar.
- Wiederholte Scans ohne Duplikate; verschobene Dateien erkannt; fehlende Dateien „nicht verfügbar“ ohne Verlust von Favoriten; manuelle Metadaten bleiben erhalten; fehlerhafte Datei bricht Scan nicht ab.
- Range-Anfragen (Teilbereich, Suffix, 416), X-Accel-Pfad.
- Live-Suche: ab 1 Buchstaben, über Künstlernamen und Features, mehrere Wörter, Pagination, leere Ergebnisse.

## Update: Katalogabgleich, Bibliothek, Konten/E-Mail, Autoplay, Sperrbildschirm-Cover

Automatisiert geprüft (Backend-Integrationstests gegen echtes PostgreSQL, Flutter-Unit-/Widget-Tests):

- **Scan-Abgleich:** gelöschte Datei → Track weg, Album mit Rest bleibt; letzte Datei weg → Veröffentlichung weg; Prüffall
  Testartist/Execute (Kollaboration, beide automatisch erkannt → verschwinden); mitwirkender Künstler bleibt, solange eine
  andere Veröffentlichung auf ihn verweist; manuell angelegter Künstler bleibt; wiederholter Scan ändert nichts;
  nicht lesbarer Unterordner → nichts gelöscht, nur „nicht verfügbar“, danach wiederhergestellt; leeres Musikverzeichnis → Abbruch ohne Löschung.
- **Künstler löschen:** Vorschau, nur Admin, eigene Veröffentlichung → Papierkorb-Ordner, Gastauftritt bleibt verfügbar,
  Hauptkünstler bleibt korrekt, nächster Scan holt nichts zurück.
- **Konten:** Startpasswort (Server sperrt alles außer Ersteinrichtung, gleiches Passwort/kein Anzeigename/falsches
  Startpasswort abgelehnt, altes Passwort danach ungültig); bestehendes Konto ohne E-Mail (Login per Anmeldename,
  Nachtragen, vor Bestätigung kein Login per E-Mail, danach beide Eingaben inkl. Groß-/Kleinschreibung und Leerzeichen);
  E-Mail-Eindeutigkeit; Anmeldename ohne `@`; Einladung mit E-Mail; Admin ändert Anmelde-/Anzeigename getrennt
  (Favoriten bleiben am Konto); manueller Admin-Reset verlangt Passwortwechsel.
- **Passwort vergessen:** gleiche Antwort für unbekannte Konten, unbestätigte Adressen und echte Konten; Mail nur an
  bestätigte Adresse; Limit pro Konto; parallele Einlösung genau einmal erfolgreich; bereits verwendeter, abgelaufener und
  durch einen späteren Reset entwerteter Link → 410; alte Sitzungen beendet; Bestätigungsmail.
- **Browser (Playwright, iPhone-13-Viewport, Backend mit `MAIL_TRANSPORT=log`):** E-Mail bestätigen → Passwort vergessen
  per E-Mail → neues Passwort → derselbe Link erneut abgelehnt → Anmeldung der Verwaltung per E-Mail; keine horizontale Scrollleiste.
- **Bibliothek (Widget-Test):** öffnet ohne Filter mit allen drei Kategorien; Alben/Künstler/Playlists zeigen nur ihre
  Kategorie, aktiver Chip hervorgehoben, erneutes Antippen bzw. × → Gesamtansicht; leere Kategorien mit Hinweis.
- **Autoplay:** Ende Single/Album → ähnlicher Titel (nie der beendete); Song wiederholen und Wiederholen haben Vorrang;
  kein Kandidat → Ende; Pause, Stopp, Wiedergabefehler → kein Autoplay; neue Wiedergabe während der Suche wird nicht überschrieben.
  Server: nur verfügbare Titel, Genre/Künstler, `exclude`, leere Liste ohne Treffer.
- **Sperrbildschirm-Cover (Logik):** lokales Bild sofort; Veröffentlichungscover ohne Songcover; erneuter Versuch nach
  Fehler; verspätetes Bild nach schnellem Titelwechsel nicht beim neuen Titel; begrenzte Versuche.

### Offen: Gerätetest iPhone (Sperrbildschirm-Cover)

Nicht auf einem echten iPhone geprüft. Schritte:

1. App mit leerem Cover-Cache: App löschen und neu installieren (oder Einstellungen → Konto → Abmelden → Downloads löschen, App neu starten).
2. Album mit Songcover (z. B. aus dem Funktionstest unten) abspielen, Gerät sperren → Sperrbildschirm zeigt bei Track 2 das
   Songcover, bei Track 1 das Albumcover. Innerhalb weniger Sekunden, auch wenn die erste Anzeige ohne Bild kam.
3. Am Sperrbildschirm mehrmals schnell „Weiter“/„Zurück“ tippen → jedes Mal passt das Cover zum angezeigten Titel; kein Bild „springt“ zum falschen Titel.
4. Kurz Flugmodus während eines Titelwechsels, dann wieder online → Cover erscheint nachträglich (Wiederholung).
5. Album herunterladen, App beenden, Flugmodus an, App starten, Download-Titel spielen, sperren → Cover sofort sichtbar.
6. Control Center und (falls vorhanden) CarPlay/Bluetooth-Anzeige prüfen.

Ebenfalls offen auf Geräten: Ersteinrichtung und E-Mail-Bestätigung in der App (Rückkehr aus dem Browser prüft automatisch),
Autoplay hörbar am Ende eines Albums, Bibliotheksfilter. Android-/iOS-Builds wurden in dieser Umgebung nicht erneut erzeugt
(keine neuen Plugins/Abhängigkeiten in der App).

## Nicht geprüft / offene Punkte

- **Android-Build und Geräte-Tests:** Android-SDK-Download war in der Umgebung gesperrt → kein `flutter build apk`. Die Gradle-/Manifest-Konfiguration ist vorbereitet, aber ungetestet.
- **iOS-Build:** kein Xcode verfügbar → nicht gebaut, nicht auf Gerät getestet.
- **Hörbare Prüfung** von Hintergrundwiedergabe, Sperrbildschirm, Bluetooth, Anruf-Unterbrechung, AirPlay und Equalizer-Klang auf echten Geräten: nicht möglich. Konfiguration (audio_service, audio_session, Background Modes, Manifest) ist umgesetzt.
- **Server, DNS, Zertifikat, Cloudflare:** nicht eingerichtet (kein Zugang). Anleitung: [installation-debian12.md](installation-debian12.md), [cloudflare.md](cloudflare.md).
- **Windows:** noch kein `windows/`-Ordner im Projekt; Architektur vorbereitet, Icon-Erzeugung im Pubspec konfiguriert.
- **Equalizer-Umschaltung:** mpv baut die Filterkette bei Änderungen neu auf; auf langsamen Geräten ist ein kurzer Aussetzer möglich.
- **Profilbild-Zuschnitt in der App:** automatischer quadratischer Mittenausschnitt; frei wählbarer Zuschnitt in der Verwaltungswebseite.
- **Umbenennen** von Künstlern/Veröffentlichungen ändert Ordnernamen bewusst nicht (Datenbank ist maßgeblich).
- **Gerätefernlöschung** von Downloads nach serverseitiger Sperrung ist technisch nicht möglich (siehe [architektur.md](architektur.md)).

## Kurzer Funktionstest nach der Installation

1. **Login:** `https://demonify.thedemonlord333.me/admin/` mit dem per CLI angelegten Admin anmelden; in der App ebenfalls anmelden → Tab „Verwaltung“ sichtbar. Mit einem normalen Benutzer: kein Verwaltungs-Tab.
2. **Künstleranlage:** Verwaltung → Künstler → „Künstler anlegen“: „Testband“ anlegen. Erneut „testband“ eingeben → Hinweis „existiert bereits“.
3. **Albumupload:** Upload → Künstler „Tes…“ tippen (Vorschlag erscheint ohne Enter) → auswählen → Album → Titel, Jahr, Cover → zwei Audiodateien → Prüfen → Bestätigen. Auf dem Server prüfen:

```bash
sudo find /srv/music/Testband -maxdepth 4 | sort
```

4. **Songcover:** Beim zweiten Track im Schritt „Prüfen“ ein eigenes Cover wählen. In der App: Album zeigt Veröffentlichungscover, Track 2 sein eigenes Cover in Liste, Mini-Player, Vollbild-Player und auf dem Sperrbildschirm; Track 1 das Albumcover.
5. **Suche:** In der App „t“ tippen → Ergebnisse sofort; „Testband“ → beide Songs werden über den Künstlernamen gefunden.
6. **Wiedergabe:** Song antippen → Mini-Player, Vorspulen (Seeking), Weiter/Zurück, Shuffle/Wiederholung, App in den Hintergrund → Musik läuft weiter, Steuerung über Sperrbildschirm/Bluetooth.
7. **Equalizer:** Einstellungen → Klang → Equalizer → „Bass Boost“ während der Wiedergabe → hörbare Änderung.
8. **Offline:** Album herunterladen → Flugmodus → Song aus „Downloads“ spielen (Quelle „Offline-Datei“ im Player).
