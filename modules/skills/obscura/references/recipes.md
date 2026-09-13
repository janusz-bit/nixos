# Obscura — full recipes

## 1) Helper for the IPython kernel

```python
import subprocess, json

def ob(*args, timeout=180):
    """Run obscura; returns stdout. Raises with stderr on failure."""
    r = subprocess.run(["obscura", *args], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"obscura {args}: {r.stderr[:500]}")
    return r.stdout

def ob_json(*args, **kw):
    return json.loads(ob(*args, **kw))
```

## 2) scrape with JS eval (returns one JSON line per URL)

```python
out = ob("scrape", "--eval",
         "JSON.stringify({title: document.title, h1: document.querySelector('h1')?.innerText})",
         "https://example.com", "https://news.ycombinator.com",
         "--format", "json")
for line in out.strip().splitlines():
    print(json.loads(line))
```

## 3) playwright-core over CDP (node script template)

```javascript
// save as /tmp/ob.js; run: cd <dir-with-node_modules> && node ob.js
const { chromium } = require("playwright-core");
(async () => {
  const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
  const ctx = b.contexts()[0] || await b.newContext();
  const pg = await ctx.newPage();
  await pg.goto(process.argv[2], { timeout: 45000, waitUntil: "domcontentloaded" });
  await pg.waitForTimeout(3000);
  console.log("title:", await pg.title());
  await pg.screenshot({ path: process.argv[3] || "/tmp/shot.png" });
  await b.close();
})().catch(e => { console.error(e.message); process.exit(1); });
```

## 4) MCP mode

`obscura mcp` speaks MCP over stdio. Minimal Python client: spawn the process and
exchange JSON-RPC frames (initialize, tools/list, tools/call) — no extra deps.

## 5) Politeness & safety

- Prefer `--obey-robots` for crawls; throttle bulk jobs via `--concurrency`.
- `--allow-private-network` disables the SSRF guard — never combine with
  untrusted input URLs.
- For cookies/session work remember `--dump cookies` exposes HttpOnly cookies —
  treat as secrets.
