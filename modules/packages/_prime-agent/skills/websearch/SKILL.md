---
name: websearch
description: Web search and page extraction via DuckDuckGo (ddgs). No API key or /login needed. Use for searching the web, recent news, or fetching a page's content.
---

# Web Search (DuckDuckGo / ddgs)

Overrides the built-in Serper-based websearch skill. No API key, no `/login`
— it works out of the box.

## Usage

Call the prepared `websearch` import directly in the IPython kernel:

```python
print(await websearch("latest Prime Agent release"))
```

Optional: `limit` (default 5), `timelimit` (`d`/`w`/`m`/`y`).

More control via the module's helpers:

```python
import websearch
r = await websearch.search("nixos flakes", limit=10)     # list of {title, href, body}
r = await websearch.news("NixOS release", timelimit="d") # news, past 24h by default
md = await websearch.extract("https://example.com")      # page content as markdown
help(websearch.run)
```
