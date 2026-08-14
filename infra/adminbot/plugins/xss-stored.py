import os, time

FLAG = os.environ.get("FLAG_XSS_STORED", "")
BASE = "http://host.docker.internal:8092"


def act(driver):
    driver.get(BASE + "/")
    driver.add_cookie({"name": "flag", "value": FLAG})
    driver.get(BASE + "/admin")
    time.sleep(3)
