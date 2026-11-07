#!/usr/bin/env bash
# Demonify – Build & Deployment einer neuen Version (als root auf dem Server, aus einem Git-Checkout).
#   sudo ./deploy/scripts/deploy.sh
# Legt ein neues Release unter /srv/nodeapps/demonify/releases/<Zeit> an, führt Migrationen aus,
# schaltet den Symlink "current" um und startet den Dienst neu. Musik, .env und Daten bleiben unberührt.
set -euo pipefail

APP_DIR=/srv/nodeapps/demonify
APP_USER=demonify
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RELEASE="$APP_DIR/releases/$STAMP"
KEEP=5

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen."; exit 1; }
[[ -f "$APP_DIR/shared/.env" ]] || { echo "$APP_DIR/shared/.env fehlt – zuerst install-debian.sh ausführen."; exit 1; }
# .env muss sowohl für systemd als auch für bash lesbar sein (Werte mit Leerzeichen in Anführungszeichen)
if grep -nE '^[A-Za-z_][A-Za-z0-9_]*=[^"'"'"'#]*[[:space:]][^#]*$' "$APP_DIR/shared/.env" | grep -vE '=[^[:space:]]*[[:space:]]*$'; then
  echo "Fehler: Obige Zeile(n) in $APP_DIR/shared/.env enthalten Leerzeichen ohne Anführungszeichen, z. B. LOGIN_RATE_LIMIT_WINDOW=\"5 minutes\"."
  exit 1
fi

echo "==> Quellcode nach $RELEASE"
install -d -o root -g "$APP_USER" -m 0750 "$RELEASE"
rsync -a --delete \
  --exclude '.git' --exclude 'demonify/' --exclude 'node_modules' --exclude 'dist' \
  --exclude '.env' --exclude 'backend/src/generated' \
  "$REPO_DIR/" "$RELEASE/"

echo "==> Backend bauen"
cd "$RELEASE/backend"
npm ci --no-audit --no-fund
npm run build

echo "==> Verwaltungswebseite bauen"
cd "$RELEASE/admin-web"
npm ci --no-audit --no-fund
npm run build
rm -rf node_modules

echo "==> Datenbankmigrationen"
cd "$RELEASE/backend"
( set -a; . "$APP_DIR/shared/.env"; set +a; npx prisma migrate deploy )
# Entwicklungsabhängigkeiten erst nach der Migration entfernen
npm prune --omit=dev --no-audit --no-fund

chown -R root:"$APP_USER" "$RELEASE"
chmod -R g+rX,o-rwx "$RELEASE"

echo "==> Umschalten und Neustart"
ln -sfn "$RELEASE" "$APP_DIR/current.new" && mv -Tf "$APP_DIR/current.new" "$APP_DIR/current"
systemctl restart demonify.service
for i in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:1340/api/v1/health >/dev/null; then echo "   Health-Check ok"; break; fi
  sleep 1
  [[ $i -eq 20 ]] && { echo "Health-Check fehlgeschlagen – journalctl -u demonify -n 100"; exit 1; }
done
nginx -t && systemctl reload nginx

echo "==> Alte Releases aufräumen (behalte $KEEP)"
ls -1dt "$APP_DIR"/releases/*/ | tail -n +$((KEEP + 1)) | xargs -r rm -rf
echo "Deployment $STAMP abgeschlossen."
