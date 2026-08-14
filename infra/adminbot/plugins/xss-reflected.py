import time, json, urllib.request

BASE = "http://host.docker.internal:8093"


def act(driver):
    try:
        urls = json.loads(urllib.request.urlopen(BASE + "/reports.json", timeout=5).read())
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
