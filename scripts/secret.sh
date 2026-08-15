#!/bin/sh
# Print one secret field for a challenge, read from the live manifest.
#
# Usage: scripts/secret.sh <challenge-id> <field>     e.g. secret.sh sqli-union flag
#
# Each active challenge is a dir active-challenges/<id>/ holding <field>.txt files
# (flag.txt, and for forensics admin_pass.txt / secret_host.txt). These are written by
# the per-challenge setup scripts (solutions/<dir>/setup.sh) via `just setup` and are
# gitignored. Bring-up recipes fetch flags/secrets through this helper.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cid=${1:?usage: secret.sh <challenge-id> <field>}
field=${2:?usage: secret.sh <challenge-id> <field>}
f="$here/active-challenges/$cid/$field.txt"

[ -f "$f" ] || {
  echo "secret.sh: $f missing — run 'just setup' (needs the private solutions repo)" >&2
  exit 1
}
val=$(cat "$f")
[ -n "$val" ] || {
  echo "secret.sh: challenge '$cid' has an empty '$field'" >&2
  exit 1
}
printf '%s\n' "$val"
