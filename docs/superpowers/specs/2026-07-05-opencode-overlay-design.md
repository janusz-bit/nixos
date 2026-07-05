# opencode overlay (fully self-contained package)

## Goal
Bundle the opencode user config (`opencode.json` and `web-search-mcp.py`) into the `opencode` nix package via a flake overlay, mirroring `modules/overlays/brave.nix`. **Everything** lives in the overlay: config files, the MCP-server path patch, and the `OPENCODE_CONFIG` environment variable (baked into the binary wrapper). The NixOS module's only opencode-related responsibilities are applying the overlay and adding `pkgs.opencode` to `environment.systemPackages`. No `environment.etc.*`, no `systemd.tmpfiles.rules`, no `environment.sessionVariables` for opencode. The standalone `modules/hosts/base/opencode.nix` module is deleted; package installation moves into `modules/hosts/base/configuration.nix`.

## Context
- Current state: `modules/hosts/base/opencode.nix` installs `pkgs.opencode` and separately installs `opencode.json` + `web-search-mcp.py` into `/etc/opencode/` via `environment.etc.*.source = self + /modules/configs/opencode/...`. `systemd.tmpfiles.rules` then symlinks `~/.config/opencode/{opencode.json,web-search-mcp.py}` to `/etc/opencode/...`.
- **opencode config discovery (per opencode.ai/docs/config):** the `OPENCODE_CONFIG` environment variable points opencode at a custom config file path; it is loaded at precedence tier 3 (above global `~/.config/opencode/`, below project `opencode.json`). This lets us ship a system-wide config from the nix store without touching `/etc` or `~/.config`.
- `opencode.json` currently contains a hardcoded absolute path `/etc/opencode/web-search-mcp.py` in the MCP server `command`. The overlay patches this to `$out/share/opencode/web-search-mcp.py` at build time via `substituteInPlace`, so the reference resolves to the file inside the same package.
- The upstream `opencode` package already wraps `$out/bin/opencode` (via `make-binary-wrapper-hook`) in its `installPhase` to set `OPENCODE_DISABLE_AUTOUPDATE` and prefix `PATH` with `ripgrep`. The overlay re-wraps the binary in `postInstall` to additionally set `OPENCODE_CONFIG`. `makeWrapper`/`wrapProgram` is idempotent in the sense that a second call rewrites the wrapper script and can append `--set` flags; the previous `--prefix PATH` and `--set OPENCODE_DISABLE_AUTOUPDATE` flags from the upstream `wrapProgram` are preserved because `wrapProgram` edits the existing wrapper in place when the binary is already a wrapper.
- `modules/overlays/brave.nix` is the established pattern: `flake.overlays.<name> = final: prev: { <pkg> = prev.<pkg>.overrideAttrs (old: { postInstall = (old.postInstall or "") + ...; }); }; }`.
- opencode is installed on all hosts via `modules/hosts/base/default.nix` → `base-opencode`. After this change, installation is handled by `base-configuration.nix`, so the overlay must be applied on every host (x86_64 and aarch64). The only `nixpkgs.overlays` today lives in `modules/hosts/nixos/configuration.nix` (host-specific). The overlay therefore has to be registered at the `base` layer.

## Design

### Architecture
A new overlay `opencode-config` wraps `prev.opencode` and, in `postInstall`: (a) copies `opencode.json` and `web-search-mcp.py` from the flake source into `$out/share/opencode/`, (b) patches `opencode.json` in-place to replace `/etc/opencode/web-search-mcp.py` with `$out/share/opencode/web-search-mcp.py`, and (c) re-wraps `$out/bin/opencode` with `--set OPENCODE_CONFIG $out/share/opencode/opencode.json`. The existing `base-configuration.nix` module only applies the overlay and adds `pkgs.opencode` to `environment.systemPackages` — nothing else. No `/etc/opencode/`, no `environment.etc`, no `systemd.tmpfiles.rules`, no `environment.sessionVariables` for opencode. The standalone `modules/hosts/base/opencode.nix` file is deleted, and `modules/hosts/base/default.nix` drops its `self.modules.nixos.base-opencode` import.

### Components

1. **`modules/overlays/opencode.nix`** (new)
   - Defines `flake.overlays.opencode-config = final: prev: { opencode = prev.opencode.overrideAttrs (oldAttrs: { postInstall = (oldAttrs.postInstall or "") + '' ... ''; }); }; }`.
   - Takes `self` as a top-level flake-module arg to reference flake source paths.
   - Inside `postInstall`:
     ```bash
     mkdir -p $out/share/opencode
     install -Dm644 ${self + /modules/configs/opencode/opencode.json} $out/share/opencode/opencode.json
     install -Dm755 ${self + /modules/configs/opencode/web-search-mcp.py} $out/share/opencode/web-search-mcp.py
     substituteInPlace $out/share/opencode/opencode.json \
       --replace-fail "/etc/opencode/web-search-mcp.py" "$out/share/opencode/web-search-mcp.py"
     wrapProgram $out/bin/opencode --set OPENCODE_CONFIG $out/share/opencode/opencode.json
     ```
   - `--replace-fail` ensures the build breaks loudly if the source `opencode.json` ever changes the path string, prompting a spec update.
   - `wrapProgram` is provided by `make-binary-wrapper-hook`, already a `nativeBuildInput` of the upstream package, so it is available in `postInstall`. The upstream `installPhase` already wrapped `$out/bin/opencode`; calling `wrapProgram` again appends the new `--set` flag to the existing wrapper.

2. **`modules/hosts/base/configuration.nix`** (edit)
   - Add `nixpkgs.overlays = [ self.overlays.opencode-config ];` to the `base-configuration` module (currently has none).
   - Append `pkgs.opencode` to `environment.systemPackages`:
     ```nix
     environment.systemPackages = (sharedPackages pkgs) ++ [ pkgs.opencode ];
     ```
   - **No `environment.etc`, no `systemd.tmpfiles.rules`, no `environment.sessionVariables` for opencode.** Everything opencode-specific lives in the overlay.
   - `self` is already in the outer arg destructuring (`{ inputs, self, customTop, ... }`); the inner module receives `{ pkgs, config, ... }` and closes over the outer `self`.

3. **`modules/hosts/base/opencode.nix`** (delete)
   - Removed entirely. Its responsibilities (install package, `environment.etc`, `tmpfiles`) are all eliminated or absorbed by `base-configuration.nix`.

4. **`modules/hosts/base/default.nix`** (edit)
   - Remove the line `self.modules.nixos.base-opencode` from the `imports` list.

### Data flow
`modules/configs/opencode/{opencode.json,web-search-mcp.py}`
  → (overlay `opencode-config` reads via `self + /modules/configs/opencode/...`)
  → installed to `pkgs.opencode/share/opencode/{opencode.json,web-search-mcp.py}`
  → `opencode.json` patched in-place: `/etc/opencode/web-search-mcp.py` → `$out/share/opencode/web-search-mcp.py`
  → `wrapProgram` sets `OPENCODE_CONFIG=$out/share/opencode/opencode.json` on `$out/bin/opencode`
  → at runtime opencode reads config from the store path via the env var; MCP `command` invokes `uv run <store-path>/share/opencode/web-search-mcp.py`.

### Why `base-configuration.nix` and not `nixos-configuration.nix`
opencode is installed through the `base` module on every host (`nixos`, `raspberry-pi-4`, `wsl`, `droid`). If the overlay were only in `nixos-configuration.nix`, the other three hosts would get the un-overlaid `opencode` package which lacks `share/opencode/` inside the store, and `OPENCODE_CONFIG` would point at a non-existent path. Registering the overlay in `base-configuration.nix` guarantees all hosts use the wrapped package and the env var resolves.

### Edge cases / risks
- **`postInstall` ordering:** brave.nix pattern uses `(oldAttrs.postInstall or "") + ''...''` — same here. The original opencode `postInstall` installs shell completions, so preserving it is required.
- **`substituteInPlace` and `wrapProgram` availability:** both are stdenv/make-binary-wrapper setup hooks; available in `postInstall` exactly like in `brave.nix`'s `postInstall`. `make-binary-wrapper-hook` is already a `nativeBuildInput` of the upstream opencode package.
- **`wrapProgram` re-wrapping:** the upstream `installPhase` already wrapped `$out/bin/opencode` with `--prefix PATH` (ripgrep) and `--set OPENCODE_DISABLE_AUTOUPDATE`. `wrapProgram` called a second time in `postInstall` edits the same wrapper script and appends the new `--set OPENCODE_CONFIG` flag while preserving the existing flags. (If it turned out to overwrite instead of append, the fallback is to pass all three flags explicitly in the overlay's `wrapProgram` call — to be verified at implementation time.)
- **`--replace-fail` fragility:** if the source `opencode.json` ever changes `/etc/opencode/web-search-mcp.py` to something else, the build fails loudly. This is desirable — it forces a conscious spec update.
- **Self-referential `${pkgs.opencode}`:** inside the overlay's `postInstall` shell code, `$out` is used (the path being built), not `${final.opencode}` (which would be self-referential and cause infinite recursion). The NixOS module only references `pkgs.opencode` in `environment.systemPackages`, which is safe.
- **`OPENCODE_CONFIG` precedence:** tier 3 (custom config). Project-level `opencode.json` (tier 4) and `.opencode/` dirs (tier 5) still override it, so per-project customization is not blocked.
- **Overlay re-application:** `nixpkgs.overlays` is merged across modules; adding it in `base-configuration.nix` does not conflict with the existing list in `nixos-configuration.nix`.
- **Home Manager `flake.homeModules.configuration`:** the sibling home module does not need opencode. If Home Manager users want the same config, the package's `wrapProgram` already sets `OPENCODE_CONFIG` for anyone invoking `$out/bin/opencode`, so Home Manager users get it for free. No change to the home module.

## Verification
- `nix flake check` passes.
- Build a host config (e.g. `nix build .#nixos`) and confirm:
  - The built `opencode` store path contains `share/opencode/opencode.json` and `share/opencode/web-search-mcp.py`.
  - `opencode.json` in the store has `/etc/opencode/web-search-mcp.py` replaced by `<store-path>/share/opencode/web-search-mcp.py`.
  - `$out/bin/opencode` is a wrapper script and contains `OPENCODE_CONFIG` set to the store path of the packaged `opencode.json`.
  - The upstream `--prefix PATH` (ripgrep) and `--set OPENCODE_DISABLE_AUTOUPDATE` flags are still present in the wrapper.
- `modules/hosts/base/opencode.nix` no longer exists; `modules/hosts/base/default.nix` no longer imports it.
- No `environment.etc."opencode/..."`, no `systemd.tmpfiles.rules`, no `environment.sessionVariables.OPENCODE_CONFIG` anywhere in the flake.
- No `/etc/opencode/` on the host.

## Out of scope
- Modifying `opencode.json` contents (beyond the build-time path patch) or the MCP server script logic.
- Applying the overlay anywhere other than `base-configuration.nix`.
- Touching the Home Manager `flake.homeModules.configuration` block.
- Per-user `~/.config/opencode/` setup (the wrapped binary sets `OPENCODE_CONFIG` system-wide).