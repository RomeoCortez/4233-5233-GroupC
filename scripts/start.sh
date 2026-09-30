#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# One node performs first installation; only then may app2 touch shared files.
docker compose up -d db redis app1
for attempt in $(seq 1 120); do
  if docker compose exec -T -u www-data app1 php occ status --output=json 2>/dev/null |
    python3 -c 'import sys,json; s=json.load(sys.stdin); sys.exit(0 if s.get("installed") and not s.get("maintenance") and not s.get("needsDbUpgrade") else 1)' 2>/dev/null; then
    break
  fi
  if [[ "$attempt" == 120 ]]; then docker compose logs app1; exit 1; fi
  sleep 5
done
docker compose exec -T -u www-data app1 php occ background:cron
docker compose up -d app2 cron lb edge
# app2 entrypoint must finish before tests start.
for node in app1 app2; do
  ready=false
  for attempt in $(seq 1 60); do
    if docker compose exec -T "$node" php -r 'exit(@file_get_contents("http://localhost/status.php") === false ? 1 : 0);'; then
      ready=true; break
    fi
    sleep 3
  done
  [[ "$ready" == true ]] || { docker compose logs "$node"; exit 1; }
done
for attempt in $(seq 1 60); do
  if curl --cacert certs/localhost.crt -fsS https://localhost:8443/status.php >/dev/null; then exit 0; fi
  sleep 2
done
docker compose logs
exit 1
