compose := "docker compose -f infra/docker-compose.yml"

# list available tasks
default:
    @just --list

# one-shot provisioning on a fresh machine: pick a domain + wildcard cert, clone the tasks +
# solutions repos, then run every per-challenge setup (solutions/<dir>/setup.sh) — each writes
# its flag.txt + symlinks meta/readme into active-challenges/; forensics also build pcaps.
# Needs the PRIVATE solutions repo (it holds the flag values). Services end up at https://<name>.<domain>.
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
    # 3. clone the challenge + solution repos into place
    [ -d challenges ] || git clone git@github.com:rebenkoy/les-simple-ctf.git challenges
    [ -d solutions ] || git clone git@github.com:rebenkoy/les-simple-ctf-sols.git solutions
    # 4. activate every challenge (writes active-challenges/<id>/)
    ls solutions/*/setup.sh >/dev/null 2>&1 || { echo "setup: no solutions/*/setup.sh — is the private solutions repo cloned?" >&2; exit 1; }
    for s in solutions/*/setup.sh; do echo ">>> $s"; sh "$s"; done
    echo "setup: done. Now 'just up' + 'just challenge <id>'. Services live at https://<name>.$DOMAIN"

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

# forensics live service: the plaintext Secret Store (sniff-secretstore).
# Injects the flag + the sniffable admin password from the manifest.
sniff-up:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    export FLAG="$(scripts/secret.sh sniff-secretstore flag)"
    export ADMIN_PASS="$(scripts/secret.sh sniff-secretstore admin_pass)"
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
