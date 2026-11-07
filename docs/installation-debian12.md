# Installation auf Debian 12

Zielumgebung: Debian 12 (bookworm), App unter `/srv/nodeapps/demonify`, Musik unter `/srv/music`,
Backend intern auf `127.0.0.1:1340`, öffentlich nur über Nginx/HTTPS. Die Skripte sind wiederholbar und
verändern weder vorhandene Musik noch Secrets, Datenbanken oder fremde Nginx-Sites.

> Nichts davon wurde auf deinem Server ausgeführt – es fehlte der Zugang. Platzhalter wie `<SERVER-IP>` musst du ersetzen.

## 1. Voraussetzungen

- Rootserver mit Debian 12, öffentliche IPv4 `<SERVER-IP>`, Ports 80 und 443 offen
- DNS-Eintrag `demonify.thedemonlord333.me` → `<SERVER-IP>` (siehe [cloudflare.md](cloudflare.md)), zunächst **DNS only**

## 2. Repository holen und Grundeinrichtung

```bash
sudo apt-get update && sudo apt-get install -y git
```

```bash
sudo git clone https://github.com/TheDemonLord333/demonify.git /srv/nodeapps/demonify-src
```

```bash
sudo /srv/nodeapps/demonify-src/deploy/scripts/install-debian.sh
```

Das Skript installiert nginx, PostgreSQL (nur lokal), FFmpeg, certbot, rsync und Node.js 24 LTS (NodeSource),
legt den Dienstbenutzer `demonify` (ohne Login-Shell, ohne Root-Rechte) an, erstellt Verzeichnisse,
DB-Benutzer/-Datenbank, `/srv/nodeapps/demonify/shared/.env` mit **neu erzeugten** Secrets (nur falls nicht vorhanden),
die systemd-Unit und zunächst eine HTTP-Bootstrap-Site für die Zertifikatsausstellung.

Prüfe danach `/srv/nodeapps/demonify/shared/.env` (Rechte `640 root:demonify`). Existierte der DB-Benutzer bereits,
trägst du das Passwort bei `DATABASE_URL` selbst ein.

Vorhandene Musik: der Dienst braucht Lese-/Schreibrechte (Uploads), Nginx Leserechte über die Gruppe:

```bash
sudo chown -R demonify:demonify /srv/music && sudo chmod -R u+rwX,g+rX,o-rwx /srv/music
```

## 3. HTTPS-Zertifikat (Let's Encrypt) – Reihenfolge beachten

1. DNS zeigt auf den Server (bei Cloudflare: **DNS only**, graue Wolke).
2. Bootstrap-Site ist aktiv (macht `install-debian.sh` automatisch, nur ACME auf Port 80).
3. Zertifikat ausstellen:

```bash
sudo certbot certonly --webroot -w /var/www/letsencrypt -d demonify.thedemonlord333.me --email <DEINE-EMAIL> --agree-tos --no-eff-email
```

4. Produktive Site aktivieren (ersetzt nur die eigene Datei `demonify.conf`):

```bash
sudo install -m 0644 /srv/nodeapps/demonify-src/deploy/nginx/demonify.conf /etc/nginx/sites-available/demonify.conf
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

5. Automatische Erneuerung: Debians certbot-Paket bringt `certbot.timer` mit. Nginx nach Erneuerung neu laden:

```bash
echo -e '#!/bin/sh\nsystemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh && sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

```bash
sudo certbot renew --dry-run
```

## 4. Deployment

```bash
sudo /srv/nodeapps/demonify-src/deploy/scripts/deploy.sh
```

Baut Backend und Verwaltung in `/srv/nodeapps/demonify/releases/<Zeit>`, führt `prisma migrate deploy` aus,
schaltet `/srv/nodeapps/demonify/current` um, startet `demonify.service` neu und prüft `/api/v1/health`.

## 5. Erstes Admin-Konto (kein Standardpasswort)

```bash
sudo /srv/nodeapps/demonify/current/deploy/scripts/demonify-cli.sh create-admin --username <ADMINNAME>
```

Das Passwort (mind. 10 Zeichen) wird interaktiv abgefragt. Weitere Befehle: `scan`, `reset-password --username <name>`, `cleanup-uploads`.

## 6. Musikbibliothek einlesen

```bash
sudo /srv/nodeapps/demonify/current/deploy/scripts/demonify-cli.sh scan
```

Oder in der Verwaltung: „Aufträge & Probleme“ → „Bibliotheksscan starten“.

## 7. Kontrolle

```bash
systemctl status demonify --no-pager
```

```bash
journalctl -u demonify -n 100 --no-pager
```

```bash
curl -s https://demonify.thedemonlord333.me/api/v1/health
```

Erwartet: `{"status":"ok","database":"ok"}`.

## Hinweise

- PostgreSQL lauscht unter Debian standardmäßig nur auf `localhost` – so lassen.
- `TRUST_PROXY=127.0.0.1,::1`: Nur der lokale Nginx gilt als Proxy. Nginx setzt `X-Forwarded-For` auf die echte Client-IP
  und übernimmt keine fremde Kette. Bei aktiviertem Cloudflare-Proxy siehe [cloudflare.md](cloudflare.md) (`real_ip`).
- Nginx in Debian 12 ist Version 1.22 – deshalb `listen 443 ssl http2;` statt `http2 on;`.
- Medien werden nie als Verzeichnis ausgeliefert: `/_protected/...` ist `internal` und nur per `X-Accel-Redirect` nach Prüfung erreichbar.
