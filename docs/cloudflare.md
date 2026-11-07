# Cloudflare: DNS und HTTPS

Diese Schritte musst du im Cloudflare-Dashboard selbst ausführen – es bestand kein Zugriff.

## Empfehlung (Standard): **DNS only** + Let's Encrypt

Für eine private Musikplattform ist **DNS only** (graue Wolke) der empfohlene Standard:

- Cloudflares Self-Serve-Bedingungen (Abschnitt 2.8 der Service-spezifischen Bedingungen) erlauben das Ausliefern
  von Video oder eines unverhältnismäßigen Anteils an Audio/Bildern über das CDN nur mit dafür vorgesehenen
  kostenpflichtigen Diensten. Ein kostenloser Proxy deckt beliebige Musikübertragung also nicht ab.
- Upload-Limit pro Anfrage bei Free/Pro: 100 MB, Proxy-Read-Timeout: 125 s (HTTP 524) – nur bei Enterprise änderbar.
- Ohne Proxy gelten nur die Grenzen deines Servers; Let's Encrypt funktioniert direkt (HTTP-01).

## DNS-Einträge

| Typ | Name | Inhalt | Proxy |
|---|---|---|---|
| A | `demonify` | `<öffentliche IPv4 des Rootservers>` | DNS only |
| AAAA | `demonify` | `<IPv6>` – **nur** wenn IPv6 am Server tatsächlich funktioniert | DNS only |

- **Keine** separaten Einträge für `/api` oder `/admin` – das sind Pfade, keine Hostnamen.
- Danach das Zertifikat wie in [installation-debian12.md](installation-debian12.md) ausstellen.

Prüfen:

```bash
dig +short demonify.thedemonlord333.me
```

## Optional: Cloudflare-Proxy aktivieren (orange Wolke)

Nur wenn du die oben genannten Bedingungen für deinen Tarif geprüft hast:

1. **SSL/TLS → Modus „Full (strict)“** – der Server hat bereits ein gültiges Let's-Encrypt-Zertifikat
   (alternativ ein Cloudflare-Origin-Zertifikat in `demonify.conf` eintragen). Niemals „Flexible“.
2. **Keine „Cache Everything“-Regel** für `/api/*` oder Medien. Die API sendet `Cache-Control: no-store`,
   Medien/Bilder `private` – authentifizierte Daten werden so nicht zwischen Benutzern gecacht.
   Zusätzlich eine Cache-Regel „Bypass cache“ für `demonify.thedemonlord333.me/api/*` anlegen.
3. **Uploads:** Die Abschnittsgröße ist auf 8 MB voreingestellt (`UPLOAD_CHUNK_MB`) und bleibt damit unter
   der 100-MB-Grenze; ein erhöhtes Nginx-Limit hebt Cloudflare-Grenzen nicht auf. Lange Commit-Anfragen
   großer Alben müssen unter 125 s bleiben – bei sehr großen Alben in mehreren Durchgängen hochladen
   (Veröffentlichung später „vorhandene auswählen“).
4. **Echte Client-IP für Login-Rate-Limits:** in `demonify.conf` (Server-Block) ergänzen und die aktuellen
   Cloudflare-IP-Bereiche (https://www.cloudflare.com/ips/) eintragen:

   ```nginx
   real_ip_header CF-Connecting-IP;
   set_real_ip_from <Cloudflare-IPv4-Bereich>;   # je Bereich eine Zeile
   ```

5. **Streaming:** Range-Anfragen funktionieren durch den Proxy; die Bedingungen zu Audio-Inhalten gelten dennoch.

## Quellen (Stand der Prüfung)

- Cloudflare Connection limits: https://developers.cloudflare.com/fundamentals/reference/connection-limits/
- Error 413: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-413/
- Service-spezifische Bedingungen (Abschnitt CDN/2.8): https://www.cloudflare.com/service-specific-terms-application-services/

Bitte vor Aktivierung des Proxys die aktuellen Bedingungen deines Tarifs selbst prüfen; sie können sich ändern.
