#!/bin/sh
# Assemble active-challenges/ from the PUBLIC challenges/ tree — no private repo needed.
# For each challenge: generate a random flag (kept stable across re-runs) and symlink its
# meta.toml + readme.md. The hub reads flag.txt to check submissions; `just up`/`challenge`
# inject it into the container. Wipe active-challenges/ (or a single dir) to rotate flags.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
[ -d challenges ] || { echo "activate: challenges/ missing — run 'just setup' (clones it)" >&2; exit 1; }

field() { sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

for meta in challenges/*/meta.toml; do
  dir=$(dirname "$meta")
  id=$(field "$meta" id)
  [ -n "$id" ] || { echo "activate: $meta has no id, skipping" >&2; continue; }
  a="active-challenges/$id"
  mkdir -p "$a"
  if [ ! -s "$a/flag.txt" ]; then
    printf 'CTF{%s}\n' "$(od -An -tx1 -N 12 /dev/urandom | tr -d ' \n')" > "$a/flag.txt"
  fi
  ln -sf "../../$dir/meta.toml" "$a/meta.toml"
  ln -sf "../../$dir/readme.md" "$a/readme.md"
  echo "activate: $id"
done
