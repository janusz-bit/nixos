# Nyx Cache Off + hermes-desktop + OpenCode /nix/store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disable the Chaotic-Nyx binary cache on the `nixos` host, install `hermes-desktop`, and let OpenCode access `/nix/store` without approval prompts.

**Architecture:** Three independent, small edits across existing Nix modules of a flake-parts/import-tree repo, followed by an AGENTS.md doc sync. The `nixos` host applies `inputs.chaotic.nixosModules.default` in `modules/hosts/nixos/default.nix`; packages live in `modules/hosts/nixos/packages.nix`; the OpenCode wrapper config is generated in `modules/overlays/opencode.nix`.

**Tech Stack:** Nix (nixfmt formatting), flake-parts, hermes-agent flake package output, OpenCode JSON config.

## Global Constraints

- Never put secrets in `.nix` files (world-readable `/nix/store`) — not touched here, but must not regress.
- Formatting is enforced: `nixfmt` (via `nix fmt` / pre-commit), `statix`, `deadnix` (no unused lambda args), workflow sync. Run the checks before committing code files.
- Host `nixos` is `x86_64-linux`; packages must resolve for `pkgs.system` of the module, not a hardcoded arch.
- AGENTS.md is the repo's living documentation — every functional change to host config or overlays gets its section updated.

---

### Task 1: Disable Chaotic-Nyx binary cache on `nixos` host

**Files:**
- Modify: `modules/hosts/nixos/default.nix:37-40`

**Interfaces:**
- Consumes: `chaotic.nyx.cache.enable` NixOS option from `inputs.chaotic.nixosModules.default` (module `modules/nixos/nyx-cache.nix` of the nyx flake; defaults to `true`).
- Produces: host config where `nix.settings.substituters` / `trusted-public-keys` no longer contain `nyx-cache.chaotic.cx`. Overlay (packages) unaffected.

- [ ] **Step 1: Edit the inline module in `modules/hosts/nixos/default.nix`**

Replace:

```nix
        (_: {
          customBot.flakeTarget = "nixos";
          customBot.defaultUser = "dinosaur";
        })
```

with:

```nix
        (_: {
          customBot.flakeTarget = "nixos";
          customBot.defaultUser = "dinosaur";
          # Nadal używamy overlaya (pakiety), ale bez binary cache nyx.
          chaotic.nyx.cache.enable = false;
        })
```

- [ ] **Step 2: Format and lint**

Run: `nix fmt modules/hosts/nixos/default.nix` (from `/etc/nixos`) and `statix check modules/hosts/nixos/default.nix` / `deadnix modules/hosts/nixos/default.nix`
Expected: no changes needed by formatter; no lint findings.

- [ ] **Step 3: Verify substitution settings change**

Run: `nix eval /etc/nixos#nixosConfigurations.nixos.config.nix.settings.substituters --json`
Expected: no entry containing `nyx-cache.chaotic.cx` (before the change it contains `https://nyx-cache.chaotic.cx/`).

- [ ] **Step 4: Commit**

```bash
git add modules/hosts/nixos/default.nix
git commit -m "nixos: disable chaotic nyx binary cache (overlay stays)"
```

---

### Task 2: Install `hermes-desktop` on `nixos` host

**Files:**
- Modify: `modules/hosts/nixos/packages.nix:1-6` (function signature) and `:66` (package list)

**Interfaces:**
- Consumes: `inputs.hermes-agent.packages.<system>.desktop` — Electron wrapper (`nix/desktop.nix` of the hermes-agent flake) with `mainProgram = "hermes-desktop"`; resolves the `hermes` CLI through `HERMES_DESKTOP_HERMES` to the flake's `#default` package.
- Produces: `hermes-desktop` in `environment.systemPackages` of the `nixos` host; XDG launcher `hermes.desktop`; app state in `~/.hermes` of user `dinosaur`.

- [ ] **Step 1: Add `inputs`/`pkgs` plumbing and the package entry in `modules/hosts/nixos/packages.nix`**

The file already has `{ inputs, ... }:` at the top but the module lambda currently takes only `{ pkgs, config, ... }`. Change:

```nix
{ inputs, ... }:
{
  flake.modules.nixos.nixos-packages =
    { pkgs, config, ... }:
```

to:

```nix
{ inputs, ... }:
{
  flake.modules.nixos.nixos-packages =
    {
      pkgs,
      config,
      inputs,
      ...
    }:
```

Then add to the end of `environment.systemPackages` list (after `antigravity-cli`):

```nix
        antigravity-cli
        inputs.hermes-agent.packages.${pkgs.system}.desktop
      ];
```

- [ ] **Step 2: Format and lint**

Run: `nix fmt modules/hosts/nixos/packages.nix` and `statix check modules/hosts/nixos/packages.nix` / `deadnix modules/hosts/nixos/packages.nix`
Expected: clean.

- [ ] **Step 3: Verify the package evaluates**

Run: `nix eval /etc/nixos#nixosConfigurations.nixos.config.environment.systemPackages --json --apply 'map (p: p.pname or p.name)' | grep -o hermes`
Expected: at least one `hermes` match (e.g. `hermes-desktop-<version>`).

- [ ] **Step 4: Commit**

```bash
git add modules/hosts/nixos/packages.nix
git commit -m "nixos: add hermes-desktop app"
```

---

### Task 3: OpenCode — allow `/nix/store` via `external_directory`

**Files:**
- Modify: `modules/overlays/opencode.nix:100-102`

**Interfaces:**
- Consumes: OpenCode `permission.external_directory` object syntax (docs: https://opencode.ai/docs/permissions/).
- Produces: generated `opencode.json` (in the wrapped `opencode` package, `$out/share/opencode/opencode.json`) with `permission.external_directory["/nix/store/**"] = "allow"`; all tools touching `/nix/store` paths run without approval.

- [ ] **Step 1: Edit the permission block in `modules/overlays/opencode.nix`**

Replace:

```nix
            "permission": {
              "websearch": "allow"
            },
```

with:

```nix
            "permission": {
              "websearch": "allow",
              "external_directory": {
                "/nix/store/**": "allow"
              }
            },
```

- [ ] **Step 2: Format and lint**

Run: `nix fmt modules/overlays/opencode.nix` and `statix check modules/overlays/opencode.nix` / `deadnix modules/overlays/opencode.nix`
Expected: clean.

- [ ] **Step 3: Verify generated JSON is valid and contains the rule**

Run: `nix build /etc/nixos#nixosConfigurations.nixos.config.environment.systemPackages --json 2>/dev/null || true; nix eval /etc/nixos#nixosConfigurations.nixos.pkgs.opencode.outPath --raw`
then extract and validate:

```bash
out=$(nix eval /etc/nixos#nixosConfigurations.nixos.pkgs.opencode.outPath --raw); python3 -m json.tool "$out/share/opencode/opencode.json" | grep -A3 external_directory
```

Expected: prints the `external_directory` block with `/nix/store/**: allow`; JSON parses cleanly.

- [ ] **Step 4: Commit**

```bash
git add modules/overlays/opencode.nix
git commit -m "opencode: always allow /nix/store via external_directory"
```

---

### Task 4: Update AGENTS.md documentation

**Files:**
- Modify: `AGENTS.md` (sections: `nixos` host bullet list, OpenCode bullet, overlays bullet)

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: documentation matching implemented behavior.

- [ ] **Step 1: Host `nixos` section — update the chaotic bullet and Apps list**

In the `nixos` host bullet mentioning chaotic (`**Overlays applied**: ... chaotic-nyx ...`), change `via chaotic.nixosModules.default)` portion to note the cache is disabled. Find:

```
`nvidia_cachyos` etc., via `chaotic.nixosModules.default`).
```

replace with:

```
`nvidia_cachyos` etc., via `chaotic.nixosModules.default`; `chaotic.nyx.cache.enable = false` — nyx binary cache NOT added to `nix.settings`).
```

Find the Apps list entry `Prime Agent (self-improving AI coding agent), DeepSeek Harness (`dsh`), losange,` and add after `DeepSeek Harness (`dsh`)`:

```
`hermes-desktop` (Electron desktop shell for Hermes Agent from `inputs.hermes-agent.packages.*.desktop`, state in `~/.hermes`),
```

- [ ] **Step 2: OpenCode overlay description**

Find in the `**OpenCode**` base bullet: `websearch` permission set to `allow`.` and replace with:

```
`websearch` permission set to `allow`; `external_directory` rule `"/nix/store/**": "allow"` so tools never prompt for `/nix/store` paths.
```

- [ ] **Step 3: Overlay summary bullet**

Find `* **`modules/overlays/`**: ...` sets `OPENCODE_CONFIG` env var and `OPENCODE_DISABLE_AUTOUPDATE`).` and extend the `opencode.nix` parenthetical with: `, permission.external_directory allows `/nix/store/**``.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: nyx cache off, hermes-desktop, opencode /nix/store allow"
```

---

### Task 5: Full verification

**Files:** none (read-only checks)

**Interfaces:**
- Consumes: all previous tasks applied.
- Produces: confirmation that the whole host still evaluates and hooks pass.

- [ ] **Step 1: Pre-commit style checks on the repo**

Run (from `/etc/nixos`): `nix fmt` then `git status --porcelain` (expect no modified files after fmt) and `statix check .` / `deadnix .`
Expected: clean tree, no lint errors.

- [ ] **Step 2: Evaluate the full host toplevel**

Run: `nix build /etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel --dry-run --accept-flake-config`
Expected: evaluation succeeds; dry-run reports substituter/plan info (may warn about untrusted caches — acceptable) without errors.

- [ ] **Step 3: Sanity-check substituters and desktop entry**

```bash
nix eval /etc/nixos#nixosConfigurations.nixos.config.nix.settings.substituters --json | grep -c nyx-cache || echo "nyx-cache absent: OK"
nix eval /etc/nixos#nixosConfigurations.nixos.pkgs.hermes-desktop.name --raw && echo
```

Expected: first command prints `nyx-cache absent: OK`; second prints `hermes-desktop-<version>`.