---
name: obscura
description: Headless antidetect browser for AI agents (Rust CLI with Chromium-grade JS via V8). Use for fetching and scraping JS-rendered pages, bot-resistant fetching, bulk parallel scraping, extracting markdown/text/links/cookies, screenshots, and browser automation over CDP (playwright-core/puppeteer compatible) or its built-in MCP server. Reach for it when plain HTTP requests return JS shells or get bot-blocked.
---

# Obscura — headless browser for web scraping and automation

CLI: `obscura` (nixpkgs `pkgs.obscura`; upstream https://github.com/h4ckf0r0day/obscura,
docs https://docs.obscura.sh). Rust + V8 (deno_core). Commands: `fetch`, `scrape`,
`serve`, `mcp`. Global flags: `--stealth` (consistent fingerprint), `--proxy`,
`--user-agent`, `--obey-robots`, `--allow-private-network`, `--storage-dir`.

## Quick usage (IPython kernel via subprocess)

```python
import subprocess

def ob(*args, timeout=180):
    r = subprocess.run(["obscura", *args], capture_output=True, text=True, timeout=timeout)
    return r.stdout

# Rendered page, pick a dump format:
html   = ob("fetch", "--dump", "html",      "https://example.com")
md     = ob("fetch", "--dump", "markdown",  "https://example.com")
links  = ob("fetch", "--dump", "links",     "https://example.com")
cookies= ob("fetch", "--dump", "cookies",   "https://example.com")  # JSON, incl. HttpOnly
raw    = ob("fetch", "--dump", "original",  "https://example.com/file.bin")  # bypasses JS layer

# Bot-resistant fetch (stealth fingerprint; obey robots.txt):
out = ob("--stealth", "--obey-robots", "fetch", "https://hard-target.example")

# Bulk parallel scraping with JS eval and JSON output:
out = ob("scrape", "--eval", "document.title",
         "https://a.example", "https://b.example",
         "--format", "json", "--concurrency", "10")
```

## Long-lived CDP server (drive with playwright-core)

```bash
obscura serve --port 9333 &   # CDP endpoint on http://127.0.0.1:9333
```

```javascript
// node + playwright-core (no browser download needed)
const { chromium } = require("playwright-core");
const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
```

`mcp` mode: `obscura mcp` runs an MCP server (stdio) exposing the browser as MCP
tools — usable from any MCP client.

## Gotchas

- **SSRF guard**: loopback/private addresses are blocked by default. Add
  `--allow-private-network` ONLY for local dev against localhost/LAN.
- **IP-level bot walls are NOT bypassed by `--stealth`** (it is fingerprinting
  only). Google captcha from this datacenter IP persists — use a `--proxy` or a
  friendlier engine (e.g. Yandex visual search works from this network).
- nixpkgs ships 0.2.0; upstream moves fast (0.2.2+ at the time of writing).
  Compare `obscura --version` with upstream releases before assuming a feature
  exists. Declarative install lives in `modules/hosts/nixos/ai.nix`.
