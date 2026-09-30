#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p certs
if [[ ! -f .env ]]; then
  umask 077
  printf 'DB_PASSWORD=%s\nADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" > .env
fi
if [[ ! -f certs/localhost.crt || ! -f certs/localhost.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
    -keyout certs/localhost.key -out certs/localhost.crt \
    -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost'
fi
