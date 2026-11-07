#!/usr/bin/env bash
# Verwaltungsbefehle auf dem Server ausführen (als Dienstbenutzer, mit Produktionskonfiguration):
#   sudo /srv/nodeapps/demonify/current/deploy/scripts/demonify-cli.sh create-admin --username <name>
#   sudo .../demonify-cli.sh scan
#   sudo .../demonify-cli.sh reset-password --username <name>
#   sudo .../demonify-cli.sh cleanup-uploads
set -euo pipefail
APP_DIR=/srv/nodeapps/demonify
cd "$APP_DIR/current/backend"
exec sudo -u demonify --preserve-env=PATH bash -c 'set -a; . /srv/nodeapps/demonify/shared/.env; set +a; exec node dist/src/cli/index.js "$@"' demonify-cli "$@"
