---
name: nixos-mcp
description: Query NixOS, Home Manager, Darwin, FlakeHub, flakes, Nixvim, Wiki, nix.dev, Noogle, NixHub and Nix package version history via the local mcp-nixos MCP server. Use for anything touching nixpkgs, NixOS/home-manager options, flakes, or Nix package lookup.
---

# NixOS MCP (mcp-nixos)

Local stdio MCP server (`mcp-nixos` from nixpkgs, path injected via
`MCP_NIXOS_EXE`). No login, no credentials, works offline-capable.

## Usage

Tools are auto-discovered from the server; call them from the IPython kernel.
Always `await` — results are already-parsed Python (str/dict):

```python
import nixos_mcp

# 1. Discover tools / argument schemas (don't hardcode)
for t in await nixos_mcp.list_tools():
    print(t["name"], "-", t["description"][:80])
help(nixos_mcp.nix)          # schema populated after list_tools()

# 2. Search nixpkgs packages
r = await nixos_mcp.nix(action="search", query="flakes")

# 3. NixOS option lookup
r = await nixos_mcp.nix(action="search", query="services.openssh", type="options")

# 4. Package details / home-manager / wiki / flake inputs / version history
r = await nixos_mcp.nix(action="info", query="hello", type="package")
r = await nixos_mcp.nix(action="search", query="git", source="home-manager")
r = await nixos_mcp.nix(action="search", query="flakes", source="wiki")
r = await nixos_mcp.nix_versions(package="mcp-nixos")
```

Tools: `nix` (actions: search, info, stats, browse, channels, flake-inputs,
cache, store) and `nix_versions` (NixHub.io history; required arg: `package`).
