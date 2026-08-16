import os, time, json, urllib.request, ssl

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
BASE = f"https://csrf.{DOMAIN}"
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
    driver.add_cookie({"name": "role", "value": "admin"})
    for pid in ids:                 # open each hosted page once, then mark it seen
        try:
            driver.get(f"{BASE}/hosted/{pid}")
            time.sleep(2)
        except Exception:
            pass
        _hit(f"/seen/{pid}")
    _hit("/heartbeat")
