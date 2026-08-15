compose := "docker compose -f infra/docker-compose.yml"

# list available tasks
default:
    @just --list

# one-shot provisioning on a fresh machine: pick a domain + wildcard cert, clone the PUBLIC
# tasks repo, then assemble active-challenges/ with a freshly-generated random flag per
# challenge. No private repo needed — flags are random per deployment (printed at the end;
# also readable from active-challenges/*/flag.txt). Services end up at https://<name>.<domain>.
setup:
    #!/usr/bin/env sh
    set -eu
    # 1. domain — reuse infra/.env if set, else prompt (default ctf.test)
    if [ -f infra/.env ] && grep -q '^DOMAIN=' infra/.env; then
        DOMAIN=$(sed -n 's/^DOMAIN=//p' infra/.env | head -1)
    else
        DOMAIN="${DOMAIN:-ctf.test}"
        if [ -t 0 ]; then printf 'Domain [%s]: ' "$DOMAIN"; read ans || true; [ -n "${ans:-}" ] && DOMAIN="$ans"; fi
        mkdir -p infra; touch infra/.env
        printf 'DOMAIN=%s\n' "$DOMAIN" >> infra/.env
    fi
    echo "setup: domain = $DOMAIN"
    # 2. wildcard cert — use a provided pair, else self-sign *.$DOMAIN
    if [ -t 0 ] && [ ! -f infra/traefik/certs/wildcard.crt ]; then
        printf 'Path to wildcard fullchain.pem (blank = self-signed): '; read cf || true
        if [ -n "${cf:-}" ]; then
            printf 'Path to wildcard privkey.pem: '; read kf || true
            mkdir -p infra/traefik/certs
            cp "$cf" infra/traefik/certs/wildcard.crt
            cp "$kf" infra/traefik/certs/wildcard.key
        fi
    fi
    [ -f infra/traefik/certs/wildcard.crt ] || scripts/gen-cert.sh "$DOMAIN"
    # 3. clone the PUBLIC tasks repo (challenge source + handouts). No auth, no private repo.
    [ -d challenges ] || git clone https://github.com/rebenkoy/les-simple-ctf.git challenges
    # 4. assemble active-challenges/: random flag per challenge + symlinked meta/readme
    scripts/activate.sh
    echo "setup: done — generated flags (also in active-challenges/*/flag.txt):"
    for f in active-challenges/*/flag.txt; do printf '  %-26s %s\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"; done
    echo "Now 'just up' + 'just challenge <id>'. Services live at https://<name>.$DOMAIN"

# build + start the CTF hub + Traefik + shared infra (detached). Injects the stored-XSS flag
# into the admin bot from the live manifest; aborts if it isn't provisioned (run 'just setup').
up:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    scripts/gen-routes.sh "${DOMAIN:-ctf.test}"
    export FLAG_XSS_STORED="$(scripts/secret.sh xss-stored flag)"
    {{compose}} up -d --build

# bring up one challenge service; its FLAG is injected from the manifest (unused by xss-stored,
# whose flag rides the admin bot). Routed by Traefik at https://<id>.<domain>. e.g. `just challenge sqli-union`
challenge id:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    export FLAG="$(scripts/secret.sh {{id}} flag)"
    docker compose -f challenges/{{id}}/docker-compose.yml up -d --build

# stop one challenge service
challenge-down id:
    docker compose -f challenges/{{id}}/docker-compose.yml down

# forensics live service: the plaintext Secret Store (sniff-secretstore). FLAG is the random
# one from the manifest; ADMIN_PASS must match the password frozen in the published pcap, so
# the operator supplies it (from the private ANSWER-KEY): `ADMIN_PASS=... just sniff-up`.
sniff-up:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    export FLAG="$(scripts/secret.sh sniff-secretstore flag)"
    export ADMIN_PASS="${ADMIN_PASS:?set ADMIN_PASS to the pcap login password (see ANSWER-KEY)}"
    docker compose -f challenges/sniff-http-secretstore/server/docker-compose.yml up -d --build

# forensics live service: the Hidden Vault (hidden-vault). Deploy on a host that resolves
# to the secret domain (see the private solutions repo); the flag is injected from the manifest.
vault-up:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    export FLAG="$(scripts/secret.sh hidden-vault flag)"
    docker compose -f challenges/sni-hidden-vault/vault/docker-compose.yml up -d --build

# stop and remove the stack
down:
    {{compose}} down

# restart the web service (re-reads the active-challenges manifest)
reload:
    {{compose}} restart web

# follow logs — `just logs web` for one service
logs service="":
    {{compose}} logs -f {{service}}

# show container status
ps:
    {{compose}} ps

# wipe ALL progress + accounts for a fresh course run
reset:
    {{compose}} down
    rm -rf infra/web/data
    mkdir -p infra/web/data
