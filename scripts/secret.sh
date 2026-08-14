#!/bin/sh
# Print one secret field for a challenge, read from the single gitignored store.
#
# Usage: scripts/secret.sh <challenge-id> <field>     e.g. secret.sh sqli-union flag
#
# The store is infra/web/challenges.toml (copied from challenges.toml.example and
# filled in by the instructor). Flags and the two forensics secrets live ONLY there,
# never in tracked source — bring-up recipes and build scripts fetch them via this.
# Pure POSIX sh + awk so it needs no interpreter beyond what the host already has.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
store="$here/infra/web/challenges.toml"
[ -f "$store" ] || {
  echo "secret.sh: $store missing — cp challenges.toml.example challenges.toml and fill it in" >&2
  exit 1
}
cid=${1:?usage: secret.sh <challenge-id> <field>}
field=${2:?usage: secret.sh <challenge-id> <field>}

val=$(awk -v cid="$cid" -v field="$field" '
  # toggle triple-quoted (""") blocks so keys inside descriptions are ignored
  { n = gsub(/"""/, "&"); if (n % 2 == 1) instr = !instr }
  instr == 1 { next }
  /^id[[:space:]]*=/ { cur = $0; sub(/^id[[:space:]]*=[[:space:]]*"/, "", cur); sub(/".*/, "", cur) }
  cur == cid && $0 ~ ("^" field "[[:space:]]*=") {
    v = $0; sub("^" field "[[:space:]]*=[[:space:]]*\"", "", v); sub(/".*/, "", v)
    print v; exit
  }
' "$store")

[ -n "$val" ] || {
  echo "secret.sh: challenge '$cid' has no non-empty '$field' in challenges.toml" >&2
  exit 1
}
printf '%s\n' "$val"
