---
name: obscura
description: Use when plain HTTP requests return a JS-only shell or get bot-blocked, or when a task needs JS-rendered page content, markdown/text/links/cookies extraction, page screenshots, bulk parallel scraping, or browser automation over CDP (playwright-core/puppeteer) or MCP. Headless browser CLI `obscura` (V8 JavaScript, optional stealth fingerprint).
---

# Obscura — headless browser for web scraping and automation

CLI: `obscura` 0.2.2 (nixpkgs `pkgs.obscura`, built with the `render` and
`stealth` features; upstream https://github.com/h4ckf0r0day/obscura, docs
https://docs.obscura.sh). Rust + V8. Commands: `fetch`, `scrape`, `serve`,
`mcp`. Global flags (before the subcommand; most are also accepted after it): `--stealth`
(consistent fingerprint, TLS impersonation, tracker blocking), `--proxy`,
`--user-agent`, `--obey-robots`, `--allow-private-network`, `--storage-dir`,
`--v8-flags`. Check `obscura <command> --help` for the rest.

## Quick usage (IPython kernel via subprocess)

```python
import json, subprocess

def ob(*args, timeout=180):
    r = subprocess.run(["obscura", *args], capture_output=True, text=True, timeout=timeout)
    return r.stdout

# Rendered page, pick a dump format (-q silences per-page script warnings):
html    = ob("fetch", "-q", "--dump", "html",     "https://example.com")
md      = ob("fetch", "-q", "--dump", "markdown", "https://example.com")
text    = ob("fetch", "-q", "--dump", "text",     "https://example.com")
links   = ob("fetch", "-q", "--dump", "links",    "https://example.com")  # "<url>\t<text>" per line
assets  = ob("fetch", "-q", "--dump", "assets",   "https://example.com")  # one JSON object per sub-resource
cookies = ob("fetch", "-q", "--dump", "cookies",  "https://example.com")  # JSON array, incl. HttpOnly
raw     = ob("fetch", "-q", "--dump", "original", "https://example.com/file.bin")  # raw body, no JS layer

# Wait for an element before dumping (it does not extract it; --wait/--timeout tune it),
# print one JS expression instead of the page, or save a screenshot:
page = ob("fetch", "-q", "--selector", "#results", "--dump", "text", "https://example.com")
ttl  = ob("fetch", "-q", "--eval", "document.title", "https://example.com")
ob("fetch", "-q", "--screenshot", "/tmp/page.png", "https://example.com")  # PNG 1280x720

# Bot-resistant fetch (stealth fingerprint; obey robots.txt):
out = ob("--stealth", "--obey-robots", "fetch", "-q", "--dump", "text", "https://hard-target.example")

# Bulk parallel scraping with JS eval: ONE JSON document with a `results` list
res = json.loads(ob("scrape", "-q", "--eval", "document.title",
                    "https://a.example", "https://b.example",
                    "--format", "json", "--concurrency", "10"))
for item in res["results"]:          # keys: url, title, eval, time_ms, worker
    print(item["url"], item["eval"])
```

`fetch --file urls.txt` (or `-` for stdin) is a raw batch mode: every URL is
fetched as `--dump original` and one JSON status line is printed per URL; for
rendered batch output use `scrape`.

## Long-lived CDP server (drive with playwright-core)

```bash
obscura serve --port 9333 &   # CDP on 127.0.0.1:9333 (default port 9222, --host to change)
```

```javascript
// node + playwright-core (no browser download needed; npm install playwright-core
// in a scratch directory, it is not installed system-wide)
const { chromium } = require("playwright-core");
const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
```

`file://` URLs are refused over CDP unless `serve --allow-file-access`.

## MCP mode

`obscura mcp` runs an MCP server on stdio (`--http` for HTTP on
`127.0.0.1:3000`). Tools are `browser_*`: `navigate`, `snapshot`,
`markdown`, `links`, `click`, `fill`, `fill_form`, `evaluate`, `wait_for`,
`screenshot`, `pdf`, tabs, cookies and storage state, etc.; list them with
`tools/list` instead of assuming names.

## Gotchas

- **SSRF guard**: loopback/private addresses are blocked by default
  ("Access to private/internal IP address … is not allowed"). Add
  `--allow-private-network` ONLY for local dev against localhost/LAN.
- **IP-reputation blocks are NOT bypassed by `--stealth`** (it changes the
  fingerprint, not the source IP); captchas tied to the IP persist — use a
  `--proxy`.
- The packaged version follows `flake.lock` (0.2.2 at the time of writing;
  upstream already has newer releases). Compare `obscura --version` with
  upstream releases before assuming a feature exists. Installed together with
  the skill by `modules/skills/default.nix` (`skillPackages`).
