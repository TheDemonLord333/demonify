#!/usr/bin/env bash
# Demonify – einmalige Servereinrichtung auf Debian 12 (als root ausführen).
# Wiederholbar: vorhandene Musik, Datenbanken, Secrets und fremde Nginx-Sites bleiben unangetastet.
set -euo pipefail

APP_DIR=/srv/nodeapps/demonify
MUSIC_DIR=/srv/music
APP_USER=demonify
DB_NAME=demonify
DB_USER=demonify
NODE_MAJOR=24
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (sudo)."; exit 1; }
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == "bookworm" ]] || echo "Warnung: getestet für Debian 12 (bookworm), gefunden: ${PRETTY_NAME:-unbekannt}"

echo "==> Pakete"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg rsync git nginx postgresql ffmpeg certbot openssl

if ! command -v node >/dev/null || [[ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -lt $NODE_MAJOR ]]; then
  echo "==> Node.js $NODE_MAJOR LTS (NodeSource)"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update && apt-get install -y nodejs
fi
node -v

echo "==> Dienstbenutzer und Verzeichnisse"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
install -d -o root -g "$APP_USER" -m 0750 "$APP_DIR" "$APP_DIR/shared" "$APP_DIR/releases"
install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_DIR/data" "$APP_DIR/data/uploads" "$APP_DIR/data/cache"
# Musikverzeichnis: anlegen, falls nicht vorhanden; vorhandene Inhalte werden nicht verändert
if [[ ! -d "$MUSIC_DIR" ]]; then install -d -o "$APP_USER" -g "$APP_USER" -m 2750 "$MUSIC_DIR"; fi
echo "   Hinweis: $MUSIC_DIR muss für $APP_USER les-/schreibbar und für die Gruppe lesbar sein."
echo "   Bestehende Bibliothek ggf.: chown -R $APP_USER:$APP_USER $MUSIC_DIR && chmod -R g+rX $MUSIC_DIR"
# Nginx (www-data) darf Medien nur lesen, ausgeliefert werden sie ausschließlich per X-Accel-Redirect
usermod -a -G "$APP_USER" www-data

echo "==> PostgreSQL (nur lokal)"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
  DB_PASS="$(openssl rand -hex 24)"
  sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';"
  NEW_DB_PASS="$DB_PASS"
fi
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

echo "==> Konfiguration ($APP_DIR/shared/.env)"
ENV_FILE="$APP_DIR/shared/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_DIR/deploy/env.example" "$ENV_FILE"
  sed -i "s#<ZUFALLSWERT_1>#$(openssl rand -base64 48 | tr -d '\n/+=' )#; s#<ZUFALLSWERT_2>#$(openssl rand -base64 48 | tr -d '\n/+=')#" "$ENV_FILE"
  if [[ -n "${NEW_DB_PASS:-}" ]]; then sed -i "s#<DB_PASSWORT>#$NEW_DB_PASS#" "$ENV_FILE"; fi
  chown root:"$APP_USER" "$ENV_FILE"; chmod 0640 "$ENV_FILE"
  echo "   .env angelegt (Secrets generiert)."
  grep -q "<DB_PASSWORT>" "$ENV_FILE" && echo "   ACHTUNG: DB-Benutzer existierte bereits – Passwort in $ENV_FILE manuell eintragen."
else
  echo "   .env existiert – wird nicht verändert."
fi

echo "==> systemd"
install -m 0644 "$REPO_DIR/deploy/systemd/demonify.service" /etc/systemd/system/demonify.service
systemctl daemon-reload
systemctl enable demonify.service >/dev/null

echo "==> Nginx (eigene Site, andere Sites bleiben erhalten)"
install -d -m 0755 /var/www/letsencrypt
if [[ ! -f /etc/letsencrypt/live/demonify.thedemonlord333.me/fullchain.pem ]]; then
  install -m 0644 "$REPO_DIR/deploy/nginx/demonify-bootstrap.conf" /etc/nginx/sites-available/demonify.conf
  echo "   Bootstrap-Site (nur ACME) installiert – Zertifikat anschließend mit certbot ausstellen (siehe Doku)."
else
  install -m 0644 "$REPO_DIR/deploy/nginx/demonify.conf" /etc/nginx/sites-available/demonify.conf
fi
ln -sf /etc/nginx/sites-available/demonify.conf /etc/nginx/sites-enabled/demonify.conf
nginx -t && systemctl reload nginx

echo "Fertig. Nächste Schritte: docs/installation-debian12.md (Zertifikat, Deployment, Admin anlegen)."
