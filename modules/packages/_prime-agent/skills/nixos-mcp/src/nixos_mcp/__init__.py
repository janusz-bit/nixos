"""NixOS integration: tools auto-discovered from the local mcp-nixos stdio server.

Usage in the kernel:

    import nixos_mcp
    r = await nixos_mcp.nix(action="search", query="flakes")
"""

from __future__ import annotations

import os
from contextlib import AsyncExitStack

from rlm import McpIntegration

__all__ = ["NixosMcp", "nixos_mcp"]


class NixosMcp(McpIntegration):
    # Credential/config key is unused: mcp-nixos is a local stdio server with
    # no auth. The mcpServers mechanism only supports HTTP servers, so this
    # integration overrides `_open_session` with a stdio transport instead.
    server = "nixos-mcp"

    async def _open_session(self, stack: AsyncExitStack):
        from mcp import ClientSession, StdioServerParameters  # noqa: PLC0415
        from mcp.client.stdio import stdio_client  # noqa: PLC0415

        # The prime-agent wrapper exports MCP_NIXOS_EXE pointing at the
        # nixpkgs mcp-nixos binary (no PATH dependency).
        exe = os.environ.get("MCP_NIXOS_EXE", "").strip() or "mcp-nixos"
        params = StdioServerParameters(command=exe, args=[])
        read, write, *_ = await stack.enter_async_context(stdio_client(params))
        session = await stack.enter_async_context(ClientSession(read, write))
        await session.initialize()
        return session


nixos_mcp = NixosMcp()


# Names the kernel bootstrap probes to decide if a module is a callable skill.
# Don't forward them, or `getattr(module, "run")` returns an MCP tool stub and
# the module gets wrapped as callable, breaking `await nixos_mcp.<tool>()`.
_RESERVED = {"run", "__wrapped__", "__call__"}


def __getattr__(name: str):
    # Forward bare module-level access (e.g. nixos_mcp.nix) to the instance,
    # so `import nixos_mcp; await nixos_mcp.nix(...)` works without the dot.
    if name.startswith("_") or name in _RESERVED:
        raise AttributeError(name)
    return getattr(nixos_mcp, name)
