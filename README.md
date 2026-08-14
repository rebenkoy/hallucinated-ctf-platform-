# vuln-services

A practical, web-focused CTF course — the hands-on successor to
[`how-internet-works`](../how-internet-works) and [`linux-quest`](../linux-quest).
Students break a set of **intentionally vulnerable services** and submit the flags they
find to a small web hub that tracks their progress.

> ⚠️ **These services are deliberately insecure by design.** Run everything on
> `localhost` only. **Never expose this to a public network.** Passwords are even stored
> in plaintext (see below) — it is built for a one-week classroom, not the internet.

## Quickstart

```sh
cp infra/web/challenges.toml.example infra/web/challenges.toml   # then fill in the flags
just up                       # build + start the hub (http://localhost:8000)
```

`infra/web/challenges.toml` is **gitignored** and is the single source of truth for flags
(plus the two forensics secrets). Copy the tracked `.example`, paste the real values from the
private solutions repo's `ANSWER-KEY.md`, and you're set — the hub checks flags against it and
`just challenge <id>` injects each flag into its container from it (via `scripts/secret.sh`).

Then open <http://localhost:8000>, **register** an account, and start solving. The tiles
come from `infra/web/challenges.toml`; a self-solvable warm-up challenge is included so you
can learn the submit flow immediately.

## Repositories

This project is published as three independent repos (branch `master`):

| Repo | Visibility | Holds |
|------|-----------|-------|
| [`hallucinated-ctf-platform-`](https://github.com/rebenkoy/hallucinated-ctf-platform-) | public | the platform: hub + shared infra + orchestration (**this repo**) |
| [`les-simple-ctf`](https://github.com/rebenkoy/les-simple-ctf) | public | sanitized challenge source (`challenges/`), no flags/secrets |
| `les-simple-ctf-sols` | **private** | instructor solutions + answer key |

Clone the challenges repo into `challenges/` (gitignored here). No flag or forensics secret is
committed to either public repo; secrets live only in the gitignored `challenges.toml` you fill
from the private answer key.

The two forensics **handout pcaps** are likewise not committed — generate them with the private
solutions repo's builders and drop them into `infra/web/static/files/` (gitignored) before a
course run. See the solutions repo's `ANSWER-KEY.md`.

```sh
just ps          # container status
just logs web    # follow the hub's logs
just reload      # reload challenges.toml after editing it
just down        # stop
just reset       # wipe all accounts + progress for a fresh run
```

### Admin

An admin account is seeded from environment variables (default `admin` / `admin`).
Override before first run by creating `infra/.env`:

```sh
SECRET_KEY=some-random-string
ADMIN_USER=instructor
ADMIN_PASS=pick-something
```

Log in as the admin and visit **Admin** in the nav to see every account. Passwords are
stored plaintext **on purpose** so you can recover a student's forgotten login during the
week — this is a deliberate, non-production trade-off.

## What's here

```
infra/                  # everything that runs
  docker-compose.yml    # the hub (challenge services join its network later)
  web/                  # the Flask hub: tiles, flag-checking, progress, auth
  INFRA.md              # architecture + how to add a challenge
```

The actual vulnerable services (SQLi boxes, a 2-server LAN-sniffing pair, …) are added as
separate per-challenge stacks — see [`infra/INFRA.md`](infra/INFRA.md).
