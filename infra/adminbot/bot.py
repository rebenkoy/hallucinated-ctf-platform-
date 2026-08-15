import os, time, glob, importlib.util, traceback
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service

CYCLE = int(os.environ.get("CYCLE_MINUTES", "2"))
PLUGIN_DIR = os.path.join(os.path.dirname(__file__), "plugins")


def load_plugins():
    mods = []
    for path in sorted(glob.glob(os.path.join(PLUGIN_DIR, "*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        if hasattr(mod, "act"):
            mods.append((name, mod))
    return mods


def make_driver():
    opts = Options()
    opts.binary_location = "/usr/bin/chromium"
    for a in ("--headless=new", "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu",
              "--ignore-certificate-errors"):   # accept the self-signed wildcard behind Traefik
        opts.add_argument(a)
    d = webdriver.Chrome(service=Service("/usr/bin/chromedriver"), options=opts)
    d.set_page_load_timeout(30)
    return d


def cycle():
    plugins = load_plugins()
    print(f"[bot] cycle: {len(plugins)} plugin(s)", flush=True)
    for name, mod in plugins:
        driver = make_driver()
        try:
            mod.act(driver)
            print(f"[bot]  {name}: ok", flush=True)
        except Exception:
            print(f"[bot]  {name}: FAILED\n{traceback.format_exc()}", flush=True)
        finally:
            driver.quit()


if __name__ == "__main__":
    while True:
        cycle()
        time.sleep(CYCLE * 60)
