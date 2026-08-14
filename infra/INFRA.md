# Infrastructure

## Overview

```
                       host :8000
                          │
                    ┌─────▼─────┐
                    │    web    │   Flask hub (this dir: web/)
                    │           │   • challenge tiles  ← challenges.toml
                    │           │   • flag checking (static, constant-time)
                    │           │   • progress + accounts → data/ctf.sqlite
                    └─────┬─────┘
                          │  network: vuln-services-ctfnet
        ┌─────────────────┼──────────────────────────┐
        │                 │                           │
   (added later)     (added later)              (added later)
   sqli service      xss service          LAN pair: client + server
```

The hub is the only thing that runs today. Each **vulnerable service** is added later as
its own compose stack that joins the shared `vuln-services-ctfnet` network. There is **no
reverse proxy** — the hub is plain HTTP on `:8000`, and each service publishes its own
port (or, for network challenges, stays internal on its own subnet). This keeps HTTP and
raw-TCP/LAN challenges equally easy to model.

## The hub (`web/`)

A single-file Flask app (`app.py`) that does exactly four things: renders challenge tiles,
checks submitted flags, stores progress, and handles login/password auth.

- **Challenges** are read from `challenges.toml` at startup.
- **State** (accounts + solves) lives in `data/ctf.sqlite`, bind-mounted so it survives
  restarts. `just reset` wipes it.
- **Auth**: students self-register; passwords are stored **plaintext** so an admin can
  recover them (`/admin/users`). Deliberate for a short local CTF — not a production
  pattern. The admin account is seeded from `ADMIN_USER` / `ADMIN_PASS`.

## Adding a challenge

### 1. Add a tile (always)

Append a block to `web/challenges.toml`:

```toml
[[challenge]]
id          = "sqli-login"          # unique slug, never reused
title       = "Bypass the Login"
category    = "Web / SQLi"
order       = 2
link        = "http://localhost:9001"   # where the running service lives ("" if none)
description = """Markdown task setup. Don't leak the flag here."""
flag        = "CTF{...}"
```

Then `just reload` (restarts the hub to re-read the manifest — no image rebuild needed,
since `challenges.toml` is bind-mounted).

### 2. Ship the service (if the challenge has one)

Create a sibling stack, e.g. `challenges/sqli-login/docker-compose.yml`, that publishes a
port matching the tile's `link`. Bring it up alongside the hub.

**Connect-and-exploit** (one service):

```yaml
services:
  sqli:
    build: .
    ports: ["9001:80"]
    networks: [ctfnet]
networks:
  ctfnet:
    name: vuln-services-ctfnet
    external: true
```

**LAN sniffing** (2 servers, client + server on a private subnet the student can sniff):

```yaml
services:
  server:
    build: ./server
    networks: [lan]
  client:
    build: ./client          # periodically talks to `server` over the wire
    networks: [lan]
networks:
  lan:
    name: sniff-lan
    # student gets a shell/tap on this subnet to capture the traffic
```

The flag for such a challenge is whatever the student recovers from the captured traffic;
they submit it on the hub tile like any other.
