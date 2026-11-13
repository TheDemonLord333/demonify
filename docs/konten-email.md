# Konten, E-Mail und „Passwort vergessen“

## Abläufe

| Situation | Ablauf |
|---|---|
| Admin legt Konto an (Verwaltung → Benutzer → „Benutzer anlegen“) | Admin vergibt ein **Startpasswort**. Erste Anmeldung → App führt durch die Ersteinrichtung: Anzeigename, eigenes Passwort, E-Mail bestätigen. Bis zum Passwortwechsel liefert der Server für alle anderen Endpunkte `403 PASSWORD_CHANGE_REQUIRED`. Das Startpasswort ist danach ungültig, andere Sitzungen werden beendet. |
| Einladungslink | Anmeldename, Anzeigename, Passwort und E-Mail eingeben. Der Bestätigungslink geht sofort an die Adresse. |
| Bestehendes Konto ohne E-Mail | Anmeldung per Anmeldename funktioniert unverändert. Nach dem Login fragt die App nach der Adresse (Passwort zur Bestätigung) und wartet auf die Bestätigung. |
| Anmeldung | Ein Feld „Anmeldename oder E-Mail“ + Passwort. Per E-Mail nur mit **bestätigter** Adresse. |
| Passwort vergessen (App-Anmeldung oder `/admin/passwort-vergessen`) | Anmeldename oder E-Mail eingeben → immer dieselbe neutrale Antwort. Der Link geht nur an die bestätigte Adresse des passenden Kontos. |
| Link zum Zurücksetzen | Öffnet `https://<Domain>/admin/konto/passwort-zuruecksetzen#token=…` (mobil nutzbar). Neues Passwort → alle Sitzungen und weitere offene Reset-Links ungültig, Bestätigungsmail, danach normale Anmeldung. |
| E-Mail ändern (App → Einstellungen → E-Mail-Adresse) | Neue Adresse + aktuelles Passwort → Bestätigungslink an die neue Adresse; erst danach aktiv. Die alte Adresse erhält einen Hinweis. |
| Kein Zugriff auf die Mail | Admin setzt in der Verwaltung ein neues Startpasswort („Passwort“) → bei der nächsten Anmeldung muss ein eigenes gewählt werden. |
| Anmelde-/Anzeigename ändern | Verwaltung → Benutzer → „Namen“. Getrennt bearbeitbar; Konto-ID, Bibliothek, Playlists und Favoriten bleiben. Anzeigename auch selbst in der App (Einstellungen). |

## Sicherheit

- Eindeutigkeit in der Datenbank: `User.usernameKey` und `User.emailKey` sind `UNIQUE`. `emailKey` enthält nur bestätigte Adressen.
- Normalisierung überall gleich (Erfassen, Anmelden, Ändern, Zurücksetzen): NFKC, unsichtbare Zeichen entfernt, getrimmt; Schlüssel zusätzlich kleingeschrieben.
- Anmeldenamen dürfen kein `@` enthalten → das gemeinsame Eingabefeld ist immer eindeutig (mit `@` = E-Mail).
- Tokens: 256 Bit zufällig, nur als SHA-256-Hash gespeichert, Reset 30 min / Bestätigung 24 h gültig (konfigurierbar), einmalig.
  Verbrauch und Passwortänderung laufen in einer Transaktion (`UPDATE … WHERE "usedAt" IS NULL RETURNING`), parallele Anfragen gewinnen genau einmal.
- Links tragen das Token im Fragment (`#token=…`). Browser senden es nicht an den Server; es landet nicht in Nginx-Protokollen.
  Die Seite schickt es nur im Body der API-Anfrage.
- Begrenzung: „Passwort vergessen“ pro IP (`FORGOT_RATE_LIMIT_MAX`/15 min) und pro Konto (3 Links/Stunde, 1/Minute, stillschweigend). Die Antwort wird nicht vom Mailversand verzögert (gleiches Zeitverhalten).
- E-Mail-Bestätigung erst per Knopfdruck auf der Seite: automatische Link-Vorschauen von Mailprogrammen bestätigen nichts.

## Konfiguration (`/srv/nodeapps/demonify/shared/.env`)

```
PUBLIC_BASE_URL=https://demonify.thedemonlord333.me
MAIL_TRANSPORT=smtp
MAIL_FROM="Demonify <noreply@thedemonlord333.me>"
SMTP_HOST="smtp.example.org"
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER="noreply@thedemonlord333.me"
SMTP_PASSWORD="…"
```

- `PUBLIC_BASE_URL` muss die öffentliche HTTPS-Adresse sein – daraus entstehen die Links in den Mails.
- Port 587 mit STARTTLS (wird erzwungen) oder 465 mit `SMTP_SECURE=true`. Viele Rechenzentren sperren ausgehenden Port 25 – nicht verwenden.
- Absenderdomain: SPF/DKIM beim Mailanbieter einrichten, sonst landen Mails im Spam.
- `MAIL_TRANSPORT=disabled` (Standard): keine E-Mail-Pflicht, kein Selbst-Reset; Admin-Reset bleibt. So sperrt ein fehlender
  Mailserver niemanden aus. Erst nach erfolgreichem Testversand auf `smtp` umstellen.
- Änderungen wirken nach `sudo systemctl restart demonify`.

Testversand nach dem Umstellen: In der Verwaltung oben „E-Mail hinterlegen“ (eigene Adresse) → Mail kommt an → Link öffnen → bestätigen.
Fehler stehen im Journal:

```bash
sudo journalctl -u demonify -n 100 --no-pager | grep -i mail
```

## Entwicklung

`MAIL_TRANSPORT=log` schreibt Mails (inkl. Link) ins Server-Log statt sie zu senden – nur mit `NODE_ENV=development`
(in Produktion verweigert der Server den Start). Automatisierte Tests verwenden `MAIL_TRANSPORT=memory`.

## Nginx / öffentlicher Endpunkt

Keine Änderung nötig: Die Kontoseiten sind Teil der Verwaltungswebseite unter `/admin/` (vorhandener SPA-Fallback
`try_files … /admin/index.html`), die API liegt wie bisher unter `/api/v1/`.
