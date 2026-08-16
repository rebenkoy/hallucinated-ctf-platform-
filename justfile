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
    docker compose version >/dev/null 2>&1 || { echo "just: needs Docker Compose v2 (the v1 'docker-compose' rejects these files — top-level 'name:'). Install: apt-get install -y docker-compose-plugin" >&2; exit 1; }
    DC="docker compose"
    scripts/gen-routes.sh "${DOMAIN:-ctf.test}"
    export FLAG_XSS_STORED="$(scripts/secret.sh xss-stored flag)"
    $DC -f infra/docker-compose.yml up -d --build
    # also bring up every standard challenge. Forensics need operator secrets, so start them
    # by hand: `ADMIN_PASS=... just challenge sniff-secretstore` and `SECRET=... just vault-up`.
    for cf in challenges/*/docker-compose.yml; do
        id=$(sed -n 's/^id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$(dirname "$cf")/meta.toml" | head -1)
        [ -n "$id" ] || continue
        case " sniff-secretstore hidden-vault " in *" $id "*) continue ;; esac
        echo ">>> $id"
        FLAG="$(scripts/secret.sh "$id" flag)" $DC -f "$cf" up -d --build
    done

# bring up one challenge by id (its folder may differ from the id, e.g. sniff). FLAG is injected
# from the manifest; Traefik serves it at https://<id>.<domain>. The sniff store also needs the
# pcap password: `ADMIN_PASS=... just challenge sniff-secretstore` (see the private ANSWER-KEY).
challenge id:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    docker compose version >/dev/null 2>&1 || { echo "just: needs Docker Compose v2 (the v1 'docker-compose' rejects these files — top-level 'name:'). Install: apt-get install -y docker-compose-plugin" >&2; exit 1; }
    DC="docker compose"
    dir=$(for m in challenges/*/meta.toml; do grep -q "^id[[:space:]]*=[[:space:]]*\"{{id}}\"" "$m" && { dirname "$m"; break; }; done)
    [ -n "$dir" ] || { echo "challenge: no challenge with id '{{id}}' (is challenges/ present?)" >&2; exit 1; }
    export FLAG="$(scripts/secret.sh {{id}} flag)"
    $DC -f "$dir/docker-compose.yml" up -d --build

# stop one challenge by id
challenge-down id:
    #!/usr/bin/env sh
    set -eu
    docker compose version >/dev/null 2>&1 || { echo "just: needs Docker Compose v2 (the v1 'docker-compose' rejects these files — top-level 'name:'). Install: apt-get install -y docker-compose-plugin" >&2; exit 1; }
    DC="docker compose"
    dir=$(for m in challenges/*/meta.toml; do grep -q "^id[[:space:]]*=[[:space:]]*\"{{id}}\"" "$m" && { dirname "$m"; break; }; done)
    [ -n "$dir" ] || { echo "challenge-down: no challenge with id '{{id}}'" >&2; exit 1; }
    $DC -f "$dir/docker-compose.yml" down

# forensics live service: the Hidden Vault. It answers on the *leaked SNI host* (the pcap
# secret), so the operator supplies it: `SECRET=<host> just vault-up`. This adds a gitignored
# Traefik route for that host (kept out of the repo) and brings the vault up on ctfnet.
vault-up:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    docker compose version >/dev/null 2>&1 || { echo "just: needs Docker Compose v2 (the v1 'docker-compose' rejects these files — top-level 'name:'). Install: apt-get install -y docker-compose-plugin" >&2; exit 1; }
    DC="docker compose"
    SECRET="${SECRET:?set SECRET to the leaked SNI host, e.g. SECRET=<host> just vault-up (see ANSWER-KEY)}"
    export FLAG="$(scripts/secret.sh hidden-vault flag)"
    printf 'http:\n  routers:\n    hidden-vault:\n      rule: "Host(`%s`)"\n      entryPoints: [websecure]\n      tls: {}\n      service: hidden-vault\n  services:\n    hidden-vault:\n      loadBalancer:\n        servers:\n          - url: "http://hidden-vault:80"\n' "$SECRET" > infra/traefik/dynamic/vault.yml
    $DC -f challenges/sni-hidden-vault/docker-compose.yml up -d --build
    echo "vault-up: hidden-vault live; Host($SECRET) routed. Point that host's DNS at the ingress."

# stop and remove EVERYTHING — every challenge container plus the shared infra stack
down:
    #!/usr/bin/env sh
    set -eu
    set -a; [ -f infra/.env ] && . ./infra/.env; set +a
    docker compose version >/dev/null 2>&1 || { echo "just: needs Docker Compose v2 (the v1 'docker-compose' rejects these files — top-level 'name:'). Install: apt-get install -y docker-compose-plugin" >&2; exit 1; }
    DC="docker compose"
    # every challenge (forensics included — they may have been started by hand)
    for cf in challenges/*/docker-compose.yml; do
        echo "<<< $(basename "$(dirname "$cf")")"
        $DC -f "$cf" down
    done
    # shared infra last
    $DC -f infra/docker-compose.yml down

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
