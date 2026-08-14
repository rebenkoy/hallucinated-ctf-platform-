"""vuln-services CTF hub — a deliberately minimal Flask GUI.

Does four things and no more:
  1. shows challenge tiles + descriptions (from challenges.toml)
  2. checks submitted flags (static, constant-time compare)
  3. stores per-user progress (sqlite)
  4. login + password auth (self-register; passwords stored PLAINTEXT so an
     admin can recover them — intentional for a one-week course, NOT secure)

Run locally only. The services this hub points at are intentionally vulnerable.
"""

import os
import hmac
import json
import hashlib
import sqlite3
import tomllib
import functools
import datetime
import urllib.request
from pathlib import Path

from flask import (
    Flask, g, session, request, redirect, url_for, render_template, flash, abort,
)
import markdown as md

BASE = Path(__file__).resolve().parent
DATA_DIR = BASE / "data"
DATA_DIR.mkdir(exist_ok=True)
DB_PATH = DATA_DIR / "ctf.sqlite"
CHALLENGES_PATH = BASE / "challenges.toml"
LISTENER_URL = os.environ.get("LISTENER_URL", "http://listener:80")
# public repo holding the (sanitized) challenge source; tiles deep-link into it
TASKS_REPO_URL = os.environ.get("TASKS_REPO_URL", "https://github.com/rebenkoy/les-simple-ctf")

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-insecure-change-me")


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


# ---------------------------------------------------------------------------
# challenge manifest
# ---------------------------------------------------------------------------
def load_challenges():
    with open(CHALLENGES_PATH, "rb") as f:
        data = tomllib.load(f)
    chals = data.get("challenge", [])
    chals.sort(key=lambda c: c.get("order", 0))
    return chals


CHALLENGES = load_challenges()
CHALLENGE_BY_ID = {c["id"]: c for c in CHALLENGES}


def listener_id(uid):
    """Stable, unguessable per-player token for the listener bucket."""
    return hashlib.sha256(f"listener:{uid}".encode()).hexdigest()[:10]


def source_url(c):
    """Deep link to this challenge's source in the public tasks repo, or None."""
    name = c.get("source")
    return f"{TASKS_REPO_URL}/tree/master/{name}" if name else None


# ---------------------------------------------------------------------------
# database
# ---------------------------------------------------------------------------
def get_db():
    db = getattr(g, "_db", None)
    if db is None:
        db = g._db = sqlite3.connect(DB_PATH)
        db.row_factory = sqlite3.Row
    return db


@app.teardown_appcontext
def close_db(_exc):
    db = getattr(g, "_db", None)
    if db is not None:
        db.close()


def init_db():
    db = sqlite3.connect(DB_PATH)
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            username   TEXT UNIQUE NOT NULL,
            password   TEXT NOT NULL,          -- PLAINTEXT, on purpose
            is_admin   INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS solves (
            user_id      INTEGER NOT NULL,
            challenge_id TEXT NOT NULL,
            ts           TEXT NOT NULL,
            PRIMARY KEY (user_id, challenge_id)
        );
        """
    )
    # seed / refresh the admin account from the environment
    admin_user = os.environ.get("ADMIN_USER", "admin")
    admin_pass = os.environ.get("ADMIN_PASS", "admin")
    row = db.execute("SELECT id FROM users WHERE username = ?", (admin_user,)).fetchone()
    if row is None:
        db.execute(
            "INSERT INTO users (username, password, is_admin, created_at) VALUES (?, ?, 1, ?)",
            (admin_user, admin_pass, now_iso()),
        )
    else:
        db.execute(
            "UPDATE users SET password = ?, is_admin = 1 WHERE username = ?",
            (admin_pass, admin_user),
        )
    db.commit()
    db.close()


init_db()


# ---------------------------------------------------------------------------
# auth helpers
# ---------------------------------------------------------------------------
def current_user():
    uid = session.get("uid")
    if uid is None:
        return None
    return get_db().execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()


@app.context_processor
def inject_user():
    return {"current_user": current_user()}


def login_required(f):
    @functools.wraps(f)
    def wrapper(*a, **k):
        if session.get("uid") is None:
            return redirect(url_for("login"))
        return f(*a, **k)

    return wrapper


def admin_required(f):
    @functools.wraps(f)
    def wrapper(*a, **k):
        u = current_user()
        if u is None:
            return redirect(url_for("login"))
        if not u["is_admin"]:
            abort(403)
        return f(*a, **k)

    return wrapper


# ---------------------------------------------------------------------------
# routes: auth
# ---------------------------------------------------------------------------
@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        if not username or not password:
            flash("Username and password are both required.", "error")
            return redirect(url_for("register"))
        db = get_db()
        try:
            db.execute(
                "INSERT INTO users (username, password, is_admin, created_at) VALUES (?, ?, 0, ?)",
                (username, password, now_iso()),
            )
            db.commit()
        except sqlite3.IntegrityError:
            flash("That username is already taken.", "error")
            return redirect(url_for("register"))
        row = db.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
        session["uid"] = row["id"]
        flash(f"Welcome, {username}!", "ok")
        return redirect(url_for("index"))
    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        row = get_db().execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
        if row is None or not hmac.compare_digest(row["password"], password):
            flash("Invalid username or password.", "error")
            return redirect(url_for("login"))
        session["uid"] = row["id"]
        return redirect(url_for("index"))
    return render_template("login.html")


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------------------
# routes: challenges
# ---------------------------------------------------------------------------
@app.route("/")
@login_required
def index():
    solved = {
        r["challenge_id"]
        for r in get_db().execute(
            "SELECT challenge_id FROM solves WHERE user_id = ?", (session["uid"],)
        )
    }
    # group challenges by category, keeping category order by first appearance
    groups = {}
    for c in CHALLENGES:
        groups.setdefault(c.get("category", "Uncategorized"), []).append(c)
    return render_template(
        "index.html",
        groups=groups,
        solved=solved,
        total=len(CHALLENGES),
    )


@app.route("/challenge/<cid>")
@login_required
def challenge(cid):
    c = CHALLENGE_BY_ID.get(cid)
    if c is None:
        abort(404)
    solved = (
        get_db()
        .execute(
            "SELECT 1 FROM solves WHERE user_id = ? AND challenge_id = ?",
            (session["uid"], cid),
        )
        .fetchone()
        is not None
    )
    desc_html = md.markdown(
        c.get("description", ""), extensions=["fenced_code", "tables"]
    )
    return render_template(
        "challenge.html", c=c, desc_html=desc_html, solved=solved,
        source_url=source_url(c),
    )


@app.route("/challenge/<cid>/submit", methods=["POST"])
@login_required
def submit(cid):
    c = CHALLENGE_BY_ID.get(cid)
    if c is None:
        abort(404)
    attempt = request.form.get("flag", "").strip()
    if hmac.compare_digest(attempt, c.get("flag", "")):
        db = get_db()
        db.execute(
            "INSERT OR IGNORE INTO solves (user_id, challenge_id, ts) VALUES (?, ?, ?)",
            (session["uid"], cid, now_iso()),
        )
        db.commit()
        flash(f"Correct! “{c['title']}” solved.", "ok")
    else:
        flash("Incorrect flag. Try again.", "error")
    return redirect(url_for("challenge", cid=cid))


@app.route("/listener")
@login_required
def listener():
    # each player gets a private bucket keyed by an unguessable token
    return redirect(url_for("listener_bucket", lid=listener_id(session["uid"])))


@app.route("/listener/<lid>")
@login_required
def listener_bucket(lid):
    # exfil sink for the client-side challenges — read this player's bucket
    hits, error = [], None
    try:
        with urllib.request.urlopen(f"{LISTENER_URL}/__feed?id={lid}", timeout=3) as r:
            hits = json.load(r)
    except Exception as ex:
        error = f"listener unavailable ({ex})"
    return render_template(
        "listener.html",
        hits=hits,
        error=error,
        lid=lid,
        is_mine=(lid == listener_id(session["uid"])),
    )


@app.route("/scoreboard")
@login_required
def scoreboard():
    rows = get_db().execute(
        """
        SELECT u.username, COUNT(s.challenge_id) AS solves
        FROM users u
        LEFT JOIN solves s ON s.user_id = u.id
        WHERE u.is_admin = 0
        GROUP BY u.id
        ORDER BY solves DESC, u.username ASC
        """
    ).fetchall()
    return render_template("scoreboard.html", rows=rows, total=len(CHALLENGES))


# ---------------------------------------------------------------------------
# routes: admin (credential recovery)
# ---------------------------------------------------------------------------
@app.route("/admin/users")
@admin_required
def admin_users():
    rows = get_db().execute(
        """
        SELECT u.id, u.username, u.password, u.is_admin, u.created_at,
               COUNT(s.challenge_id) AS solves
        FROM users u
        LEFT JOIN solves s ON s.user_id = u.id
        GROUP BY u.id
        ORDER BY u.is_admin DESC, u.created_at ASC
        """
    ).fetchall()
    return render_template("admin.html", rows=rows, total=len(CHALLENGES))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
