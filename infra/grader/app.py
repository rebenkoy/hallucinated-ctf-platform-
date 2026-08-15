import secrets
from flask import Flask, request, redirect, render_template, jsonify, Response

app = Flask(__name__)
SUBS = {}    # id -> {"html": str, "graded": bool}
ORDER = []   # submission ids, oldest first


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/submit", methods=["POST"])
def submit():
    html = request.form.get("html", "")
    if not html.strip():
        return redirect("/")
    sid = secrets.token_hex(4)
    SUBS[sid] = {"html": html, "graded": False}
    ORDER.append(sid)
    while len(ORDER) > 50:
        SUBS.pop(ORDER.pop(0), None)
    return redirect("/?id=" + sid)


@app.route("/pending")
def pending():
    return jsonify([sid for sid in ORDER if not SUBS[sid]["graded"]])


@app.route("/queue.json")
def queue():
    return jsonify([{"id": sid, "graded": SUBS[sid]["graded"]} for sid in reversed(ORDER)])


@app.route("/<sid>/done")
def done(sid):
    if sid in SUBS:
        SUBS[sid]["graded"] = True
    return Response("", status=204)


@app.route("/<sid>")
def view(sid):
    s = SUBS.get(sid)
    if not s:
        return Response("not found", status=404)
    return Response(s["html"], mimetype="text/html")
