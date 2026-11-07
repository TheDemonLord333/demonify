# Updates

## Server (Backend + Verwaltung)

```bash
cd /srv/nodeapps/demonify-src && sudo git pull
```

```bash
sudo /srv/nodeapps/demonify-src/deploy/scripts/deploy.sh
```

Das Skript baut ein neues Release, wendet Datenbankmigrationen an (`prisma migrate deploy`), schaltet um und
prüft den Health-Endpunkt. Musik, `.env`, Uploads und Cache bleiben unberührt; die letzten 5 Releases bleiben erhalten.

Rücksprung auf das vorherige Release (nur wenn keine neue Migration dazukam):

```bash
ls -1dt /srv/nodeapps/demonify/releases/*/
```

```bash
sudo ln -sfn /srv/nodeapps/demonify/releases/<VORHERIGES> /srv/nodeapps/demonify/current && sudo systemctl restart demonify
```

Vor größeren Updates ein Backup ziehen (siehe [backup-wiederherstellung.md](backup-wiederherstellung.md)).

Wurde die Nginx- oder systemd-Datei im Repository geändert, diese bewusst übernehmen:

```bash
sudo install -m 0644 deploy/nginx/demonify.conf /etc/nginx/sites-available/demonify.conf && sudo nginx -t && sudo systemctl reload nginx
```

```bash
sudo install -m 0644 deploy/systemd/demonify.service /etc/systemd/system/demonify.service && sudo systemctl daemon-reload && sudo systemctl restart demonify
```

Systempakete (Debian, Node.js, PostgreSQL-Minor, FFmpeg) regelmäßig aktualisieren:

```bash
sudo apt-get update && sudo apt-get upgrade
```

## App

Version in `demonify/pubspec.yaml` erhöhen (`version: 1.1.0+2`), dann wie in [android-ios-build.md](android-ios-build.md) bauen.
Abhängigkeiten prüfen:

```bash
flutter pub outdated
```

`pubspec.lock` wird versioniert – Updates bewusst mit `flutter pub upgrade` durchführen und testen.

## Datenbankschema ändern (Entwicklung)

```bash
cd backend && npx prisma migrate dev --name <beschreibung>
```

Die erzeugte Migration unter `backend/prisma/migrations/` committen; auf dem Server wendet `deploy.sh` sie an.
