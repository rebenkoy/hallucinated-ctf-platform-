#!/bin/sh
# Generate a self-signed wildcard cert for *.<domain> into infra/traefik/certs/.
# Used as the fallback when the operator doesn't supply their own wildcard cert.
# Runs openssl in a container (the host has none). Idempotent-ish: overwrites.
#
# Usage: scripts/gen-cert.sh [domain]        (default: ctf.test)
set -eu

domain=${1:-ctf.test}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$root/infra/traefik/certs"
mkdir -p "$out"

docker run --rm -v "$out":/certs alpine/openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /certs/wildcard.key -out /certs/wildcard.crt -days 825 \
  -subj "/CN=*.$domain" \
  -addext "subjectAltName=DNS:*.$domain,DNS:$domain" >/dev/null 2>&1

echo "gen-cert: self-signed wildcard for *.$domain -> infra/traefik/certs/wildcard.{crt,key}"
