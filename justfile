compose := "docker compose -f infra/docker-compose.yml"

# list available tasks
default:
    @just --list

# build + start the CTF hub (detached). Injects the stored-XSS flag into the admin bot
# from the single secret store (infra/web/challenges.toml); aborts if it isn't provisioned.
up:
    #!/usr/bin/env sh
    set -eu
    export FLAG_XSS_STORED="$(scripts/secret.sh xss-stored flag)"
    {{compose}} up -d --build

# bring up one challenge service; its FLAG is injected from challenges.toml (unused by
# xss-stored, which gets its flag via the admin bot). e.g. `just challenge sqli-union`
challenge id:
    #!/usr/bin/env sh
    set -eu
    export FLAG="$(scripts/secret.sh {{id}} flag)"
    docker compose -f challenges/{{id}}/docker-compose.yml up -d --build

# stop one challenge service
challenge-down id:
    docker compose -f challenges/{{id}}/docker-compose.yml down

# forensics live service: the plaintext Secret Store (sniff-secretstore).
# Injects the flag + the sniffable admin password from challenges.toml.
sniff-up:
    #!/usr/bin/env sh
    set -eu
    export FLAG="$(scripts/secret.sh sniff-secretstore flag)"
    export ADMIN_PASS="$(scripts/secret.sh sniff-secretstore admin_pass)"
    docker compose -f challenges/sniff-http-secretstore/server/docker-compose.yml up -d --build

# forensics live service: the Hidden Vault (hidden-vault). Deploy on a host that resolves
# to the secret domain (see the private solutions repo); the flag is injected from challenges.toml.
vault-up:
    #!/usr/bin/env sh
    set -eu
    export FLAG="$(scripts/secret.sh hidden-vault flag)"
    docker compose -f challenges/sni-hidden-vault/vault/docker-compose.yml up -d --build

# stop and remove the stack
down:
    {{compose}} down

# restart the web service (reloads challenges.toml)
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
