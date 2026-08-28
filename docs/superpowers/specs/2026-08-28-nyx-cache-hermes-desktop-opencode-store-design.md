# Design: Nyx cache off, hermes-desktop, OpenCode /nix/store access

Date: 2026-08-28

## Goals

1. Disable the Chaotic-Nyx binary cache for the `nixos` host (keep the overlay).
2. Install `hermes-desktop` (Electron app) on the `nixos` host.
3. Allow OpenCode tools to access `/nix/store` without approval prompts.

## Changes

### 1. `chaotic.nyx.cache.enable = false`

File: `modules/hosts/nixos/default.nix` — inside the inline module next to
`customBot` settings, where `inputs.chaotic.nixosModules.default` is applied.

Effect: the `nyx-cache` module no longer writes
`https://nyx-cache.chaotic.cx/` into `nix.settings.substituters` nor its key
into `trusted-public-keys`. The Chaotic-Nyx overlay (packages: CachyOS kernel,
proton-cachyos, mangohud_git, …) stays enabled.

### 2. `hermes-desktop` package

File: `modules/hosts/nixos/packages.nix` — add
`inputs.hermes-agent.packages.${pkgs.system}.desktop` to
`environment.systemPackages`.

The desktop package is a passthru of the hermes-agent flake's `#default`
package: an Electron wrapper that launches `hermes` via
`HERMES_DESKTOP_HERMES` (fully wrapped binary with venv, skills, plugins,
runtime PATH). State lives in `~/.hermes` of user `dinosaur`.

No Home Manager module and no system service: the repo does not use
Home Manager on the `nixos` host, and `self.modules.nixos.hermes` is the
RPi-specific service module (sudo NOPASSWD, port 8642, user `hermes`) — not
appropriate here. The desktop app runs its own backend when started.

### 3. OpenCode: `/nix/store` always accessible

File: `modules/overlays/opencode.nix` — extend the `permission` block:

```json
"external_directory": {
  "/nix/store/**": "allow"
}
```

OpenCode's `external_directory` permission gates any tool touching paths
outside the working directory (`read`, `edit`, `glob`, `grep`, many `bash`
commands). Default is `ask`; this rule makes `/nix/store` always allowed,
so reading store paths (docs, sources, configs of installed packages) never
prompts.

### 4. Documentation

Update `AGENTS.md`: host `nixos` section (Nyx cache off, hermes-desktop app)
and OpenCode overlay description (external_directory rule).

## Verification

- `nix fmt` (pre-commit hook uses nixfmt-tree).
- JSON of generated `opencode.json` parses (`python3 -m json.tool`).
- `nix build .#nixos.config.system.build.toplevel --dry-run` (or `nix flake check`
  restricted) evaluates both changes.
- `nix eval` the host config: `nix.settings.substituters` no longer contains
  `nyx-cache.chaotic.cx`.