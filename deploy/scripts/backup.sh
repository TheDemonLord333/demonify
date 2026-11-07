#!/usr/bin/env bash
# Demonify – Sicherung von Datenbank, Konfiguration und (inkrementell) der Originalmusik.
#   sudo BACKUP_DIR=/mnt/backup/demonify ./deploy/scripts/backup.sh
# Wiederherstellung: siehe docs/backup-wiederherstellung.md
set -euo pipefail
BACKUP_DIR="${BACKUP_DIR:-/var/backups/demonify}"
APP_DIR=/srv/nodeapps/demonify
MUSIC_DIR="${MUSIC_DIR:-/srv/music}"
STAMP="$(date +%Y%m%d-%H%M%S)"
KEEP_DB="${KEEP_DB:-14}"

install -d -m 0700 "$BACKUP_DIR/db" "$BACKUP_DIR/config" "$BACKUP_DIR/music"

echo "==> Datenbank (pg_dump, custom format)"
sudo -u postgres pg_dump -Fc demonify > "$BACKUP_DIR/db/demonify-$STAMP.dump"

echo "==> Konfiguration (.env, Nginx-Site, systemd)"
tar -czf "$BACKUP_DIR/config/config-$STAMP.tar.gz" \
  "$APP_DIR/shared/.env" /etc/nginx/sites-available/demonify.conf /etc/systemd/system/demonify.service 2>/dev/null || true
chmod 0600 "$BACKUP_DIR/config/config-$STAMP.tar.gz"

echo "==> Originalmusik (rsync, löscht im Backup nichts)"
rsync -a "$MUSIC_DIR/" "$BACKUP_DIR/music/"

echo "==> Alte Datenbanksicherungen aufräumen (behalte $KEEP_DB)"
ls -1t "$BACKUP_DIR"/db/*.dump | tail -n +$((KEEP_DB + 1)) | xargs -r rm -f
echo "Sicherung abgeschlossen: $BACKUP_DIR"
