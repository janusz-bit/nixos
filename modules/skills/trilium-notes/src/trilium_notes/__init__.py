"""Trilium Notes integration: tools auto-discovered from Trilium's built-in
HTTP MCP server (TriliumNext >= 0.105, streamable HTTP + Bearer auth).

Usage in the kernel:

    import trilium_notes

    r = await trilium_notes.search_notes(query="Nix")
    r = await trilium_notes.get_note_content(noteId="gizBJ1qzBFsT")

The ETAPI token lives in agenix (/run/agenix/trilium-etapi, root:users 0440)
and is loaded into TRILIUM_ETAPI_TOKEN for the runtime's bearer-token auth.
"""

from __future__ import annotations

import os

from rlm import McpIntegration

__all__ = ["TriliumMcp", "trilium"]


_TOKEN_ENV = "TRILIUM_ETAPI_TOKEN"
# agenix secret: owner root, group users, mode 0440 (modules/hosts/base/agenix.nix).
_TOKEN_FILE = "/run/agenix/trilium-etapi"


def _load_token() -> None:
    """Seed the bearer-token env var from the agenix secret (idempotent)."""
    if os.environ.get(_TOKEN_ENV, "").strip():
        return
    try:
        with open(_TOKEN_FILE) as fh:
            token = fh.read().strip()
    except OSError:
        return
    if token:
        os.environ[_TOKEN_ENV] = token


_load_token()


class TriliumMcp(McpIntegration):
    """Client of the Trilium Notes MCP server (http://127.0.0.1:8081/mcp)."""

    server = "trilium-notes"
    url = "http://127.0.0.1:8081/mcp"
    bearer_token_env = _TOKEN_ENV


trilium = TriliumMcp()


# Names the kernel bootstrap probes to decide if a module is a callable skill.
# Don't forward them, or `getattr(module, "run")` returns an MCP tool stub and
# the module gets wrapped as callable, breaking `await trilium.<tool>()`.
_RESERVED = {"run", "__wrapped__", "__call__"}


def __getattr__(name: str):
    # Forward bare module-level access (e.g. trilium_notes.search_notes)
    # to the instance, mirroring the nixos-mcp skill.
    if name.startswith("_") or name in _RESERVED:
        raise AttributeError(name)
    return getattr(trilium, name)
