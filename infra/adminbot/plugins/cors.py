import os, time, json, urllib.request, ssl

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
GRADER = f"https://grader.{DOMAIN}"
STORE = f"https://store.{DOMAIN}"
_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE   # self-signed wildcard behind Traefik


def act(driver):
    try:
        ids = json.loads(urllib.request.urlopen(GRADER + "/pending", timeout=5, context=_ctx).read())
    except Exception:
        ids = []
    driver.get(STORE + "/")
    driver.add_cookie({"name": "session", "value": "admin", "sameSite": "Lax"})
    for sid in ids[-10:]:
        try:
            driver.get(f"{GRADER}/{sid}")
            time.sleep(2)
            urllib.request.urlopen(f"{GRADER}/{sid}/done", timeout=5, context=_ctx).read()
        except Exception:
            pass
