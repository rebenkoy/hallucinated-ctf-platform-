import os, time

DOMAIN = os.environ.get("DOMAIN", "ctf.test")
FLAG = os.environ.get("FLAG_XSS_STORED", "")
BASE = f"https://xss-stored.{DOMAIN}"


def act(driver):
    driver.get(BASE + "/")
    driver.add_cookie({"name": "flag", "value": FLAG})
    driver.get(BASE + "/admin")
    time.sleep(3)
