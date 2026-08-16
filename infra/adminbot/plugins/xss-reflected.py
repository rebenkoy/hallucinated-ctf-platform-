import os, time, json, urllib.request, ssl

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
BASE = f"https://xss-reflected.{DOMAIN}"
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
        reports = json.loads(urllib.request.urlopen(BASE + "/pending", timeout=5, context=_ctx).read())
    except Exception:
        reports = []
    driver.get(BASE + "/")
    driver.add_cookie({"name": "role", "value": "admin"})
    for r in reports:               # visit each reported link once, then mark it seen
        u = r["url"]
        try:
            driver.get(BASE + u if u.startswith("/") else u)
            time.sleep(2)
        except Exception:
            pass
        _hit(f"/seen/{r['id']}")
    _hit("/heartbeat")
