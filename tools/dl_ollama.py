import hashlib, os, ssl, sys, time, urllib.request

GITHUB = "https://github.com/ollama/ollama/releases/download/v0.40.3/ollama-windows-amd64.zip"
PROXY = "http://127.0.0.1:7890"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ollama", "ollama-windows-amd64.zip")
EXPECTED_SIZE = 1468053171

os.makedirs(os.path.dirname(OUT), exist_ok=True)

routes = [
    ("gh-proxy", "https://gh-proxy.com/" + GITHUB, None, ssl.create_default_context()),
    ("github-via-clash-unverified", GITHUB, PROXY, ssl._create_unverified_context()),
]

def download(url, proxy, ctx):
    if proxy:
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({"http": proxy, "https": proxy}),
            urllib.request.HTTPSHandler(context=ctx))
    else:
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with opener.open(req, timeout=90) as r, open(OUT, "wb") as f:
        cl = r.headers.get("Content-Length")
        total = int(cl) if cl else 0
        got, last = 0, 0.0
        while True:
            chunk = r.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)
            got += len(chunk)
            if time.time() - last > 10:
                last = time.time()
                print("  %.0f MB / %.0f MB" % (got / 1048576, total / 1048576), flush=True)
    return got

for name, url, proxy, ctx in routes:
    print("route=%s proxy=%r" % (name, proxy), flush=True)
    try:
        n = download(url, proxy, ctx)
        break
    except Exception as e:
        print("FAILED %s: %s" % (name, str(e)[:140]), flush=True)
        if os.path.exists(OUT):
            os.remove(OUT)
else:
    print("ALL ROUTES FAILED", flush=True)
    sys.exit(1)

h = hashlib.sha256()
with open(OUT, "rb") as f:
    for b in iter(lambda: f.read(1024 * 1024), b""):
        h.update(b)
print("SIZE %d (expected %d, match=%s)" % (os.path.getsize(OUT), EXPECTED_SIZE, os.path.getsize(OUT) == EXPECTED_SIZE), flush=True)
print("SHA256 %s" % h.hexdigest(), flush=True)
