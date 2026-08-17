import time, json, html
from collections import deque
from datetime import datetime, timezone
from flask import Flask, request, Response
from flask_sock import Sock

app = Flask(__name__)
# keep the websocket alive through Traefik's idle timeout
app.config["SOCK_SERVER_OPTIONS"] = {"ping_interval": 25}
sock = Sock(app)
WINDOW = 300
HITS = deque(maxlen=1000)
METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]


def prune():
    cutoff = time.time() - WINDOW
    while HITS and HITS[0]["t"] < cutoff:
        HITS.popleft()


def record(lid):
    HITS.append({
        "t": time.time(),
        "ts": datetime.now(timezone.utc).strftime("%H:%M:%S"),
        "id": lid,                                   # per-player bucket ("" = shared)
        "method": request.method,
        "path": request.full_path.rstrip("?"),
        "query": request.query_string.decode("utf-8", "replace"),
        "body": request.get_data(as_text=True)[:2000],
        "remote": request.remote_addr or "",
    })


@app.route("/__feed")
def feed():
    prune()
    wanted = request.args.get("id")                  # optional per-player filter
    items = [h for h in HITS if wanted is None or h["id"] == wanted]
    return Response(json.dumps(list(reversed(items))), mimetype="application/json")


@sock.route("/ws/<lid>")
def ws_feed(ws, lid):
    # push this player's bucket live — a fresh snapshot whenever it changes (new hit or a
    # hit ages out of the 5-min window). One thread per open Listener tab (gunicorn gthread).
    last = None
    try:
        while True:
            prune()
            items = [h for h in HITS if h["id"] == lid]
            payload = json.dumps(list(reversed(items)))
            if payload != last:
                ws.send(payload)
                last = payload
            time.sleep(1)
    except Exception:
        return  # client went away


@app.route("/__view")
def view():
    prune()
    rows = "".join(
        f"<tr><td>{h['ts']}</td><td>{html.escape(h['id'])}</td><td>{h['method']}</td>"
        f"<td>{html.escape(h['path'])}</td><td>{html.escape(h['body'])}</td>"
        f"<td>{h['remote']}</td></tr>"
        for h in reversed(HITS)
    ) or '<tr><td colspan="6" class="empty">no hits in the last 5 minutes</td></tr>'
    return f"""<!doctype html><meta charset=utf-8>
<meta http-equiv=refresh content=3>
<title>Listener</title>
<style>body{{background:#0e1320;color:#e7ecf5;font-family:ui-monospace,Menlo,monospace;
margin:1.5rem}}h1{{font-size:1.2rem}}table{{width:100%;border-collapse:collapse;font-size:.85rem}}
th,td{{border:1px solid #2b3a57;padding:.4rem .5rem;text-align:left;word-break:break-all}}
th{{color:#93a1bd;background:#0b1020}}td:nth-child(4),td:nth-child(5){{color:#6ee7b7}}
.empty{{color:#93a1bd;text-align:center}}</style>
<h1>HTTP listener <small style="color:#93a1bd">— raw hits, last 5 min</small></h1>
<table><thead><tr><th>time</th><th>id</th><th>method</th><th>path</th><th>body</th><th>from</th></tr></thead>
<tbody>{rows}</tbody></table>"""


@app.route("/l/<lid>", defaults={"path": ""}, methods=METHODS, strict_slashes=False)
@app.route("/l/<lid>/<path:path>", methods=METHODS)
def capture_tagged(lid, path):
    record(lid)
    return Response("", status=200)


@app.route("/", defaults={"path": ""}, methods=METHODS)
@app.route("/<path:path>", methods=METHODS)
def capture(path):
    record("")
    return Response("", status=200)
