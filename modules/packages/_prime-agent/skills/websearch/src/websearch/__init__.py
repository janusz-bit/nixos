"""Web search via DuckDuckGo (ddgs). No API key required.

Usage in the kernel:

    print(await websearch("latest Prime Agent release"))
    md = await websearch.extract("https://example.com")
"""

from __future__ import annotations

import asyncio
from typing import Any

__all__ = ["run", "search", "news", "extract"]


def _format(results: list[dict[str, Any]]) -> str:
    if not results:
        return "No results found."
    out = []
    for i, r in enumerate(results, 1):
        title = str(r.get("title", "")).strip()
        url = str(r.get("href") or r.get("url") or "").strip()
        body = str(r.get("body", "")).strip()
        out.append(f"{i}. {title}\n   {url}\n   {body}")
    return "\n\n".join(out)


async def search(
    query: str,
    limit: int = 5,
    region: str | None = None,
    timelimit: str | None = None,
) -> list[dict[str, Any]]:
    """Web search; returns a list of dicts with title/href/body."""
    from ddgs import DDGS  # noqa: PLC0415

    kwargs: dict[str, Any] = {"max_results": limit}
    if region:
        kwargs["region"] = region
    if timelimit:
        kwargs["timelimit"] = timelimit
    return await asyncio.to_thread(DDGS().text, query, **kwargs)


async def news(query: str, limit: int = 5, timelimit: str | None = "d") -> list[dict[str, Any]]:
    """News search (timelimit: d/w/m/y; default past 24h)."""
    from ddgs import DDGS  # noqa: PLC0415

    kwargs: dict[str, Any] = {"max_results": limit}
    if timelimit:
        kwargs["timelimit"] = timelimit
    return await asyncio.to_thread(DDGS().news, query, **kwargs)


async def extract(url: str) -> str:
    """Fetch a page and return its content as markdown text."""
    from ddgs import DDGS  # noqa: PLC0415

    r = await asyncio.to_thread(DDGS().extract, url, "text_markdown")
    if isinstance(r, dict):
        return str(r.get("content", ""))
    return str(r)


async def run(query: str, limit: int = 5, timelimit: str | None = None) -> str:
    """Search the web with DuckDuckGo and return formatted results."""
    results = await search(query, limit=limit, timelimit=timelimit)
    return _format(results)
