import os, time, json, urllib.request, ssl

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
FLAG = os.environ.get("FLAG_XSS_STORED", "")
BASE = f"https://xss-stored.{DOMAIN}"
_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def _hit(path):
    try:
        urllib.request.urlopen(BASE + path, timeout=5, context=_ctx).read()
    except Exception:
        pass


def act(driver):
    try:
        ids = json.loads(urllib.request.urlopen(BASE + "/pending", timeout=5, context=_ctx).read())
    except Exception:
        ids = []
    driver.get(BASE + "/")
    driver.add_cookie({"name": "flag", "value": FLAG})
    driver.get(BASE + "/admin")   # renders pending messages → stored XSS fires
    time.sleep(3)
    for mid in ids:               # mark each looked-at exactly once
        _hit(f"/seen/{mid}")
    _hit("/heartbeat")
