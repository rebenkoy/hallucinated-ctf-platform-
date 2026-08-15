import os, time, json, urllib.request, ssl

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
BASE = f"https://xss-reflected.{DOMAIN}"
_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def act(driver):
    try:
        urls = json.loads(urllib.request.urlopen(BASE + "/reports.json", timeout=5, context=_ctx).read())
    except Exception:
        urls = []
    driver.get(BASE + "/")
    driver.add_cookie({"name": "role", "value": "admin"})
    for u in urls[-10:]:
        try:
            driver.get(BASE + u if u.startswith("/") else u)
            time.sleep(2)
        except Exception:
            pass
