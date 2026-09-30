#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base=https://localhost:8443
http() { curl --cacert certs/localhost.crt --connect-timeout 10 --max-time 60 "$@"; }
echo 'TEST: installed instance through Apache TLS and load balancer'
http -fsS "$base/status.php" | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["installed"] and not s["maintenance"] and not s["needsDbUpgrade"]'
echo 'TEST: both load balancer backends receive traffic'
for n in $(seq 1 20); do
  http -fsS -D - -o /dev/null "$base/status.php" | tr -d '\r' | sed -n 's/^[Xx]-[Uu]pstream: //p'
done | sort -u > "$work/upstreams"
[[ $(wc -l < "$work/upstreams") -eq 2 ]]
echo 'TEST: login through the complete request path'
http -fsS -u "admin:$ADMIN_PASSWORD" -H 'OCS-APIRequest: true' "$base/ocs/v2.php/cloud/user?format=json" |
  python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["ocs"]["meta"]["status"] == "ok" and s["ocs"]["data"]["id"] == "admin"'
echo 'TEST: rejected unauthenticated private file access'
code=$(http -sS -o /dev/null -w '%{http_code}' "$base/remote.php/dav/files/admin/")
[[ "$code" == 401 ]]
echo 'TEST: explicitly upload through app1, download through app2'
# Internal PHP HTTP client forces different nodes rather than trusting round robin.
file="ci-shared-$(date +%s).txt"
payload="Group C shared storage test $file"
docker compose exec -T -e DAV_PASS="$ADMIN_PASSWORD" -e DAV_FILE="$file" -e DAV_BODY="$payload" app1 php -r '
$u="http://app1/remote.php/dav/files/admin/".getenv("DAV_FILE");
$c=stream_context_create(["http"=>["method"=>"PUT","header"=>"Authorization: Basic ".base64_encode("admin:".getenv("DAV_PASS"))."\r\nContent-Type: text/plain\r\n","content"=>getenv("DAV_BODY")]]);
if(file_get_contents($u,false,$c)===false) exit(1);'
docker compose exec -T -e DAV_PASS="$ADMIN_PASSWORD" -e DAV_FILE="$file" -e DAV_BODY="$payload" app2 php -r '
$c=stream_context_create(["http"=>["header"=>"Authorization: Basic ".base64_encode("admin:".getenv("DAV_PASS"))]]);
$r=file_get_contents("http://app2/remote.php/dav/files/admin/".getenv("DAV_FILE"),false,$c);
if($r!==getenv("DAV_BODY")) exit(1);'
echo 'TEST: file available through HTTPS'
[[ $(http -fsS -u "admin:$ADMIN_PASSWORD" "$base/remote.php/dav/files/admin/$file") == "$payload" ]]
for node in app1 app2; do
  [[ $(docker compose exec -T -u www-data "$node" php occ config:system:get memcache.locking | tr -d '\r') == '\OC\Memcache\Redis' ]]
  [[ $(docker compose exec -T "$node" php -r 'echo ini_get("session.save_handler");') == redis ]]
done
[[ $(docker compose exec -T redis redis-cli ping | tr -d '\r') == PONG ]]
echo 'TEST: a separate user cannot read the admin file'
docker compose exec -T -u www-data -e OC_PASS="$ADMIN_PASSWORD" app1 php occ user:add --password-from-env ci_reader
code=$(http -sS -u "ci_reader:$ADMIN_PASSWORD" -o /dev/null -w '%{http_code}' "$base/remote.php/dav/files/admin/$file")
[[ "$code" == 403 || "$code" == 404 ]]
docker compose exec -T -u www-data app1 php occ user:delete ci_reader
echo 'TEST: cron entrypoint and one background job execution'
docker compose exec -T -u www-data cron php -f /var/www/html/cron.php
echo 'TEST: restart app2 without losing uploaded file' 
docker compose restart app2
for attempt in $(seq 1 60); do
  if docker compose exec -T app2 php -r 'exit(@file_get_contents("http://localhost/status.php") === false ? 1 : 0);'; then break; fi
  [[ "$attempt" != 60 ]] || exit 1
  sleep 3
done
docker compose exec -T -e DAV_PASS="$ADMIN_PASSWORD" -e DAV_FILE="$file" -e DAV_BODY="$payload" app2 php -r '
$c=stream_context_create(["http"=>["header"=>"Authorization: Basic ".base64_encode("admin:".getenv("DAV_PASS"))]]);
if(file_get_contents("http://app2/remote.php/dav/files/admin/".getenv("DAV_FILE"),false,$c)!==getenv("DAV_BODY")) exit(1);'
# Database restore is isolated from the live test database.
echo 'TEST: database backup and restore into a separate temporary database'
docker compose exec -T db pg_dump -U nextcloud -d nextcloud -Fc > "$work/db.dump"
docker compose exec -T db createdb -U nextcloud ci_restore
docker compose exec -T db pg_restore -U nextcloud -d ci_restore --no-owner < "$work/db.dump"
[[ $(docker compose exec -T db psql -U nextcloud -d ci_restore -Atc "SELECT count(*) FROM oc_users WHERE uid='admin';" | tr -d '\r') == 1 ]]
docker compose exec -T db dropdb -U nextcloud ci_restore
echo 'TEST: archived user file can be extracted with original contents'
docker compose exec -T app1 tar -C /var/www/html/data/admin/files -cf - "$file" > "$work/files.tar"
tar -xf "$work/files.tar" -C "$work"
[[ $(cat "$work/$file") == "$payload" ]]
http -fsS -u "admin:$ADMIN_PASSWORD" -X DELETE "$base/remote.php/dav/files/admin/$file" >/dev/null
echo 'All integration checks passed.'
