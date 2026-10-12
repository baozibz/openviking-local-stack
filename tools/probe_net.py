import ssl, urllib.request, urllib.error

ctx = ssl.create_default_context()
ctx_unverified = ssl._create_unverified_context()
PROXY = "http://127.0.0.1:7890"

targets = [
    ("github-release", "https://github.com/ollama/ollama/releases/download/v0.40.3/ollama-windows-amd64.zip"),
    ("ollama-com", "https://ollama.com/"),
    ("ghproxy", "https://gh-proxy.com/https://github.com/ollama/ollama/releases/download/v0.40.3/ollama-windows-amd64.zip"),
    ("registry-ollama", "https://registry.ollama.ai/v2/"),
    ("pypi", "https://pypi.org/simple/"),
]

def probe(name, url, proxy, context, method="GET"):
    if proxy:
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({"http": proxy, "https": proxy}),
            urllib.request.HTTPSHandler(context=context))
    else:
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}, method="HEAD")
    try:
        with opener.open(req, timeout=20) as r:
            print("OK   %-16s proxy=%-5s code=%s len=%s" % (name, bool(proxy), r.status, r.headers.get("Content-Length")), flush=True)
            return True
    except Exception as e:
        print("FAIL %-16s proxy=%-5s %s" % (name, bool(proxy), str(e)[:110]), flush=True)
        return False

for name, url in targets:
    for proxy in (None, PROXY):
        for ctxname, context in (("verify", ctx), ("unverified", ctx_unverified)):
            if probe(name + "[" + ctxname + "]", url, proxy, context, method="HEAD" if name != "pypi" else "GET"):
                break
        else:
            continue
        break
