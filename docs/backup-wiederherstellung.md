# Backup und Wiederherstellung

Zu sichern sind drei Dinge:

1. **Datenbank** (Benutzer, Playlists, Favoriten, Hörverlauf, Metadaten, manuelle Korrekturen)
2. **Originalmusik** `/srv/music` (inkl. Covern und Künstlerbildern)
3. **Konfiguration** `/srv/nodeapps/demonify/shared/.env`, Nginx-Site, systemd-Unit

Nicht nötig: `/srv/nodeapps/demonify/data/cache` (Transkodierungen, Covervarianten – werden neu erzeugt)
und `data/uploads` (unfertige Uploads).

## Sicherung

```bash
sudo BACKUP_DIR=/mnt/backup/demonify /srv/nodeapps/demonify/current/deploy/scripts/backup.sh
```

Automatisch täglich um 3:17 Uhr (root-Crontab):

```bash
echo '17 3 * * * BACKUP_DIR=/mnt/backup/demonify /srv/nodeapps/demonify/current/deploy/scripts/backup.sh >> /var/log/demonify-backup.log 2>&1' | sudo crontab -
```

Achtung: `crontab -` ersetzt die root-Crontab. Bestehende Einträge vorher mit `sudo crontab -l` prüfen und ggf. per `sudo crontab -e` ergänzen.

Die `.env` enthält Secrets – Backups verschlüsselt bzw. zugriffsgeschützt aufbewahren und möglichst
zusätzlich außerhalb des Servers lagern (z. B. `rsync`/`restic` auf ein anderes System).

## Wiederherstellung

1. Server wie in [installation-debian12.md](installation-debian12.md) einrichten (ohne Admin anzulegen).
2. Konfiguration zurückspielen:

```bash
sudo tar -xzf /mnt/backup/demonify/config/config-<ZEIT>.tar.gz -C /
```

3. Musik zurückspielen:

```bash
sudo rsync -a /mnt/backup/demonify/music/ /srv/music/ && sudo chown -R demonify:demonify /srv/music
```

4. Datenbank zurückspielen (Dienst vorher stoppen):

```bash
sudo systemctl stop demonify
```

```bash
sudo -u postgres pg_restore --clean --if-exists -d demonify /mnt/backup/demonify/db/demonify-<ZEIT>.dump
```

5. Deployment ausführen (Migrationen werden automatisch angewendet) und prüfen:

```bash
sudo /srv/nodeapps/demonify-src/deploy/scripts/deploy.sh
```

6. Optional einen Bibliotheksscan starten – er erkennt Abweichungen zwischen Datenbank und Dateien,
   ohne manuelle Metadaten zu überschreiben.

Da Secrets (`AUTH_TOKEN_SECRET`) mitgesichert werden, bleiben Anmeldungen gültig. Werden sie geändert,
müssen sich alle Benutzer neu anmelden; Downloads auf den Geräten bleiben erhalten.
