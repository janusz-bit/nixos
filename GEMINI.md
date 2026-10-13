# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS** and **Nix Flakes**. You maintain, refactor and develop this repository (NixOS dotfiles). Details live in module comments — read the module before changing it; this file is the map and the rules.

## Refinement (`/refine`, Prime Agent)
`/refine` is a built-in Prime Agent command (skill `packages/coding-agent/skills/refine`) for persisting tactics, policies and memory. It never deploys NixOS changes. From IPython: `await refine.status()`, `await refine.run("…")`, `await refine.run("…", global_=True)`. System changes are made only by editing this flake and running `nixos-rebuild` (aliases `update`, `update-local`).

## Repository map
Generated reference — read it before grepping: `docs/reference/hosts.md` (each host's modules, diagrams), `docs/reference/modules.md` (every module with its header summary), `docs/reference/options.md`. Human overview and the add-a-host procedure: `README.md`.

- `flake.nix` — inputs + `nixConfig` (the only binary-cache list); outputs = `flake-parts` + `import-tree ./modules`: every `.nix` under `modules/` is a flake-parts module, paths with a `_`-prefixed segment are ignored (`_secrets/`, `_hermes-agent/`, `packages/_helium/`, `raspberry-pi-4/_hardware-configuration.nix`). No Home Manager.
- `modules/default.nix` — systems, flake-parts modules, formatter, pre-commit hooks, dev shell. `modules/args.nix` — `customTop`: repo-wide constants (repo, e-mail, domain, LAN, `nixConfig`, own cachix, `secretsDir`, `keys`).
- `modules/hosts/registry.nix` — `hosts.<name> = { system; modules; buildOnTags; }` → `nixosConfigurations.<name>`, `customBot.flakeTarget`, CI workflows, docs.
- `modules/hosts/base/` — what every host imports (aggregate `base`): `options.nix` (`customBot.*`), `nix.nix`, `rebuild.nix` (update aliases), `configuration.nix`, `secrets.nix` + `agenix.nix` (user secrets, per-process wrappers), shell, git, ssh, Prime Agent; opt-in `fail2ban.nix` (`base-fail2ban`).
- `modules/hosts/<host>/` — what makes a machine itself: registry entry + identity in `default.nix`, disk, boot, host-only services. `modules/hosts/{remote-agent,claude-notify}.nix` link two hosts and export one module per host.
- `modules/desktop/`, `modules/gaming/` — workstation features any x86_64 desktop host may import (aggregates `desktop`, `gaming`). GPU-dependent settings inside them follow `hardware.nvidia.*` from the hardware module; `desktop-kernel` and Proton-CachyOS need an x86-64-v3 CPU (import `hardware-x86-64-v3`).
- `modules/hardware/<machine>/` — drivers, quirks and the facter report of one machine; `lenovo.nix`, `x86-64-v3.nix` shared pieces. `M27Q.icm` is referenced by KWin (`~/.config/kwinoutputconfig.json` → `/etc/nixos/modules/hardware/M27Q.icm`) — do not move it.
- `modules/installer/` — `install-system` (+ offline variant) and `nixos-iso` for the host named by `installHost` (`nixos`), `post-install` for any host; `modules/packages/` — local packages (overlay `local-packages`, also `packages.<system>.*`) and `flake-update`/`flake-release`/`repo-sync`; `modules/overlays/opencode.nix`; `modules/skills/` — Prime Agent and Claude Code skills; `modules/github-actions.nix`, `modules/docs.nix` — generators.
- `modules/hosts/raspberry-pi-4/_hermes-agent/` — vendored copy of upstream `nix/nixosModules.nix` (MIT) whose activation runs as the service user; the header lists the changes and the sync procedure (`temporary-fixes.md`).
- `modules/checks/` — NixOS VM tests: `hermes-activation` (the vendored activation never writes as root through agent-owned paths; `nix build .#checks.<system>.hermes-activation`, kvm, ~3 min on the RPi), `tuning` (x86_64 only, the host's CachyOS kernel, A/B effects of `desktop-tuning`; `nix build -L .#checks.x86_64-linux.tuning`, kvm, ~2.5 min).
- `temporary-fixes.md` — upstream workarounds (active / closed). `.claude/` — `settings.json` (nix eval/build, `nixos-rebuild build` and read-only git allowed; `git push`, `sudo` ask; secrets, Secure Boot and disk writes denied) and `hooks/post-edit.sh` (nixfmt after every `.nix` edit).

## Hosts
| Host | Arch | User | Notes |
|---|---|---|---|
| `nixos` (= `default`) | x86_64 | `dinosaur` | Lenovo LOQ-15IRX10 laptop, Plasma 6 (Wayland, no X server), stateVersion 25.11 |
| `raspberry-pi-4` | aarch64 | `nixos` | headless home server behind Cloudflare Tunnel, stateVersion 26.05 |
| `wsl` | x86_64 | `nixos` | NixOS-WSL, stateVersion 25.05 |

Base (every host): bash exec'ing fish, tmux, nix-ld, comma, direnv, Quad9 DNS (`mkDefault`; WSL clears it), firewall on, key-only SSH (`PermitRootLogin = "no"` by default), agenix, Prime Agent config, flakes, weekly GC (`mkDefault`), `nix.optimise.automatic`.

### `nixos` (laptop)
- `base` + `desktop` + `gaming` + `hardware-LOQ-15IRX10` + `nixos-{boot,disko,snapper,ssh}` + `ai-skills`, `base-fail2ban`, `nixos-remote-agent`, `nixos-claude-notify`.
- Kernel (`desktop/kernel.nix`) via `nix-cachyos-kernel.overlays.pinned` (cache hit only with `pinned`; the NVIDIA driver follows that input's nixpkgs). Never set `inputs.nixpkgs.follows` on `nix-cachyos-kernel`.
- Secure Boot is **enabled** with own keys (enrolled 2026-09-28): PK = sbctl, KEK/db = sbctl + Microsoft + Lenovo defaults, dbx = firmware `dbxDefault` (371 Microsoft SHA-256 hashes). **Insyde firmware quirk:** Linux sees only ~12 EFI variables (no `SecureBoot`, `SetupMode`, `PK`/`KEK`/`db`/`dbx`, `BootOrder`), so `sbctl status`/`sbctl enroll-keys`, `bootctl` and `efibootmgr` report nonsense. Read the state from the kernel log (`journalctl -k -b | grep -i "secure boot"`) or the TPM event log (`sudo tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements | grep -B3 -E 'UnicodeName: (SecureBoot|PK|KEK|db|dbx)$'`). (Re)enroll keys only with `nix run /etc/nixos#post-install secure-boot` (efitools; restores the dbx that Setup Mode wipes). Never use "Erase all Secure Boot settings"/"Reset to Setup Mode" without a reason; never write boot entries with `efibootmgr` (`limine-install` recreates its NVRAM entry on every rebuild).
- Browser extensions and policies live in `desktop/browsers.nix` (Chromium policies read by Helium and ungoogled-chromium), login apps in `desktop/autostart.nix` — not in the browser or System Settings.
- Account `claude-remote` (`hosts/remote-agent.nix`): login for Claude Code on the RPi — own group, no supplementary groups, no sudo, no secrets, only `keys.users.claude-rpi` with `from=<LAN>,restrict`; eval/builds only.
- VFIO passthrough was removed (3247976); restore with `git show 3584010:modules/hosts/nixos/vfio.nix` and `git show 3584010:modules/hosts/nixos/win11-vm.xml`. Pitfalls if revived: never pass a `by-path` value (contains `:`) to `KWIN_DRM_DEVICES`; `virtualisation.libvirtd.qemu.ovmf` no longer exists.

### `raspberry-pi-4` (server)
- `base` (inside the aggregate: the SD image composes it outside the registry) + `base-fail2ban` + `ai-skills` + `hardware-raspberry-pi-4` (+ `-fan`) + `rpi-*` modules (incl. `rpi-remote-agent`, `rpi-claude-notify` from `hosts/*.nix`); overrides in `resources.nix` (GC daily/3d, `max-jobs = 2`) and `ssh.nix` (`PermitRootLogin = "prohibit-password"`: admin path `ssh ssh.<domain>` as root through cloudflared).
- Kernel: the `nixos-hardware` vendor kernel (it forces `PREEMPT=y`, `PREEMPT_LAZY=n`), cached in `attic.xuyh0120.win/lantian`.
- Web services are published only through the Cloudflare Tunnel (`cloudflared.nix`; its header maps hostnames to ports): Nextcloud, Open WebUI (gets only `open-webui-keys.age`, never the Hermes env file), Trilium, Gitea, ttyd (Unix socket behind nginx Basic Auth), Matrix (continuwuity, no federation, no registration), plus `ssh.<domain>`. They listen on localhost, except Nextcloud's nginx on :80 (closed in the firewall); sshd keeps the default `openFirewall` (port 22 open on the LAN, fail2ban ignores the LAN). Ollama (`hermes.nix`) stays local.
- Wi-Fi (`network.nix`): profile `home-wifi` from `wifi.age`, powersave off, regdom `PL`.
- Hermes Agent (`hermes.nix` + `_hermes-agent/` + `matrix.nix`): its header holds the trust model, plugins and one-time login (`sudo -u hermes -H claude auth login`).
- `laptop-run <cmd>` / `ssh laptop` (`hosts/remote-agent.nix`): runs `<cmd>` on the laptop as `claude-remote` in a `git archive` snapshot of the current repo (tracked files incl. uncommitted changes) in `~/work/<repo>`; only while the laptop is on and at home; 5 failed logins and the laptop's fail2ban bans the RPi.
- `claude-notify "text"` (`hosts/claude-notify.nix`, client in `_claude-notify/`): Markdown message to the Matrix DM through Hermes, no LLM. The key `hermes-notify-key.age` logs in only as `hermes`, from localhost, with `restrict` and a forced receive command; on both hosts Claude Code gets skill `hermes-notify` and managed hooks. Details and limits: the module header.

## Secrets (agenix)
- Recipients: `modules/_secrets/secrets.nix` (rules only — `*.age` entries), public keys in `modules/_secrets/keys.nix`. The laptop is a recipient of everything (secrets are edited there). Rekey after changing recipients: `cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519`.
- User secrets (`modules/hosts/base/secrets.nix`): owner `customBot.defaultUser`, mode `0400`. Service secrets: owned by the service user, or root `0400` when the service reads them via `LoadCredential`/`EnvironmentFile`. Never `group = "users"`.
- Never export secrets globally (shell init, `sessionVariables`). Inject per process: fish wrapper functions in `modules/hosts/base/agenix.nix` (`prime-agent`, `opencode`, `gemini`, `cachix-push`); nix `access-tokens` are rendered into `~/.config/nix/nix.conf` by the user unit `nix-access-tokens`.
- Never write secret values into `.nix` files (they end up in the world-readable store).

## Security invariants — do not regress
- `nix.settings.trusted-users` stays default (root only).
- No passwordless root paths for user or agent accounts (no `podman`/`docker` group, no NOPASSWD sudo for agents).
- `/etc/ai` (runtime skill drop-in) is `0755`, owned by `customBot.defaultUser`.
- The Hermes CLI runs only through the `hermes` wrapper (`sudo -u hermes`); never run the package binary as root or as the interactive user — `HERMES_HOME` (plugins, `.env`, MCP commands) is agent-writable.
- Root never writes through paths an unprivileged account controls (no `chown`/`chmod`/`install`/merge as root inside `/var/lib/hermes`; use `setpriv` to the owner or symlink-safe `systemd-tmpfiles`).
- Runtime-fetched code is pinned: opencode plugins (commit/version in `opencode.nix`), GitHub Actions (commit SHAs in `github-actions.nix`), Hermes plugins (commit in `hermes.nix`), MCP servers from nixpkgs rather than `uvx`/`uv run`.
- The RPi is less trusted than the laptop (internet-facing): its key logs into the laptop only as `claude-remote` (no groups, `from=<LAN>,restrict`) — never into `dinosaur` or root; no `nix.buildMachines` to the laptop (it would need `trusted-users`).
- ttyd credentials never on a command line (nginx `auth_basic` with a hash file generated from the agenix secret); ttyd itself is reachable only through nginx (Unix socket `root:nginx 0660`); its password is its own secret, never another service's.

## Binary caches
`nixConfig` in `flake.nix` is the only cache list: `janusz-bit.cachix.org`, `attic.xuyh0120.win/lantian` (CachyOS kernel), `cache.numtide.com` (llm-agents). Hosts get the same lists in `nix.settings` through `customTop.nixConfig` (`modules/args.nix` imports `flake.nix`); `customTop.cache.cachix` (own cache: `push`, CI) finds its key there. Input `nixConfig` is not inherited. When adding a cache, run the first rebuild with `--accept-flake-config`. `devenv.cachix.org` comes from `desktop-devenv` (`modules/desktop/devenv.nix`, part of the `desktop` aggregate) for devenv projects only, deliberately outside `nixConfig`.

## Development workflow
- Always work inside `nix develop` (installs pre-commit hooks: gitleaks, nixfmt, statix, deadnix, sync-github-actions, sync-docs). Claude Code: start it with the alias `claude-nixos` (`modules/desktop/ai.nix`) = `nix develop -c claude` in `/etc/nixos`; outside the dev shell the `.claude/` hooks silently do nothing.
- **Generated files:** `.github/workflows/*.yml` (`sync-github-actions`, from `modules/github-actions.nix` + host registry) and `docs/reference/*.md` (`sync-docs`, from `modules/docs.nix`). The pre-commit hooks run `nix run .#<generator>` on the working tree (no stale store path from shell entry); if a hook modifies files, `git add` them and commit again. Never edit generated files by hand.
- CI workflows (generated): `nixos` (PR + manual only, 3–5 h), `nixos-iso` (PR + manual only, same cost as `nixos` since the ISO now bundles its whole closure), `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl` (tags `v*`, PR), `eval` and `lint` (also on every push to `master`), `cachyos-kernel-update` (manual).
- `flake-update` updates `flake.lock` and local packages (`helium` and `waywallen` in two arch passes, `bootdev-cli`) and commits; `flake-release` tags `vN` and pushes; `repo-sync` commits everything, rebases and pushes.
- **Git (mandatory):** commit every change; style: short lowercase summary prefixed with the area (`nixos: …`, `rpi: …`, `docs: …`). Push to `origin` only after verification (below) — `update` on every host deploys straight from GitHub, so a push is a deployment: host `nixos` after a successful `update-local`; `raspberry-pi-4`/`wsl` (no local switch) after verification steps 1–2. Experimental or large features (new services, wrappers, overlays): a branch + PR (CI `eval` and `lint` run on PRs), merged after testing on the target host.
- **Skills:** store in `modules/skills/<name>/` (`SKILL.md` + `references/`; Python skills also `src/<pkg>/` + `pyproject.toml` and an entry in `pythonSkills`) and register in `modules/skills/default.nix`; programs a skill calls go into `skillPackages` there (installed with the skill, not in a host module). Python skill sources reach the kernel through the `prime-agent` wrapper's `PYTHONPATH`. Prime Agent reads `/etc/ai-skills` and the runtime drop-in `/etc/ai` through `skills` in its `settings.json` (`base/prime-agent.nix`; earlier entry wins a name collision, so declarative skills win); runtime skills without a rebuild go to `/etc/ai/<name>/`. Claude Code skills go into `claudeSkills` → `/etc/claude-code/.claude/skills/<name>` (managed scope: every user and project on hosts importing `ai-skills`; `claude --debug` logs `Loading skills from: managed=…`).
- Temporary upstream workarounds must get an entry in `temporary-fixes.md` with a removal condition.

## Verification (before every commit)
A change is done only when it has been checked as far as possible without root. Report which steps ran and which did not.
1. Evaluate every affected host: `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (`nixos`/`raspberry-pi-4` ~25 s, `wsl` ~8 s; aarch64 evaluates fine on x86_64). On the RPi run steps 1–3 for x86_64 hosts through `laptop-run` when the laptop is on. Changes in `hosts/base/`, `hosts/registry.nix`, `args.nix`, `overlays/`, `packages/` (overlay `local-packages`) or `flake.nix` affect all three hosts.
2. Generated configuration (`builtins.toJSON`, environment variables, systemd units, nginx/cloudflared config, wrapper scripts): evaluate and show the rendered value, e.g. `nix eval --raw .#nixosConfigurations.<host>.config.systemd.services.<svc>.environment.<VAR>`. Escaping and interpolation bugs pass step 1 and fail only at runtime.
3. Host `nixos`, when packages, overlays, the kernel or services change: `nixos-rebuild build --flake .#nixos`, then `nix store diff-closures /run/current-system ./result`. Stop and ask before a build that would compile CUDA packages or the kernel locally (hours).
4. Activation needs root and is done by the user in their own terminal (`update-local`), who reports the result. Not via `!`: it runs a non-interactive bash without shell aliases and without a tty for the sudo password. Then check the affected units (`systemctl status …`, `journalctl -u … -b`).

## Code quality rules

These rules MUST be followed by every AI coding agent and contributor. They extend **Secrets**, **Security invariants**, **Development workflow** and **Verification** above; where two rules overlap, the stricter one wins.

### Core principles

All changes you make MUST be minimal, declarative and reproducible.

"Minimal, declarative and reproducible" means:

- the whole system state is described by this flake: no imperative changes (`nix-env`, `nix profile install`, editing `/etc`, `systemctl enable`, files dropped into `$HOME`) that the next rebuild silently undoes or that exist on one machine only
- reuse before adding: a NixOS module option (`services.*`, `programs.*`, `hardware.*`) first, a nixpkgs package second, an existing flake input third, a local package in `modules/packages/_<name>/` last; a new flake input only when none of these fit, with the reason in a comment
- no code beyond what the change needs: no speculative options, toggles or abstractions "for later", no wrapper for something a module option already does, no dead `let` bindings (i.e. no technical debt)
- the narrowest scope: a host module when one host needs it, `modules/hosts/base/` only when every NixOS host needs it
- pure evaluation: flake-only, no `--impure`, no `<nixpkgs>` lookups, no unhashed fetchers

If a change is not minimal, declarative and verified before handing off to the user, you will be fined $100. You have permission to do another pass over the change if you believe it is not.

### Preferred tools and patterns

- Module layout: every `.nix` file under `modules/` is a flake-parts module (import-tree). A NixOS module is exported as `flake.modules.nixos.<group>-<name>`, the group taken from its directory: `base-*` (`hosts/base/`), `nixos-*`/`rpi-*`/`wsl-*` (`hosts/<host>/`, `rpi` = `raspberry-pi-4`), `desktop-*`, `gaming-*`, `hardware-<machine>[-<part>]`, `installer-*`; a directory's `default.nix` exports the bare aggregate (`base`, `nixos`, `hardware-LOQ-15IRX10`). Exceptions: `ai-skills` (`skills/default.nix`), shared hardware pieces (`hardware-lenovo`, `hardware-x86-64-v3`), and the cross-host `hosts/*.nix`, which export `nixos-<x>` + `rpi-<x>`. Scope: `hosts/<host>/` holds what makes that machine itself (identity, disk, boot, host-only services), `hardware/` what depends on the devices, `desktop/` and `gaming/` features any workstation may import, `hosts/base/` only what every host needs. Import modules explicitly in the host's `default.nix`. Anything that is not a flake-parts module (package definitions, hardware configs, vendored code, patches) **MUST** live under a `_`-prefixed path, otherwise import-tree imports it and evaluation breaks.
- Shell scripts: `pkgs.writeShellApplication` with `runtimeInputs` (shellcheck runs at build time). **NEVER** use `writeShellScriptBin`/`writeScript` for new scripts with logic; migrate old ones when you touch them anyway. Short scripts stay inline in the module; longer scripts and their helper files (shell, jq) go into a `_<feature>/` directory next to the module (import-tree skips `_` paths), loaded with `builtins.readFile` or a path literal — never loose `.sh`/`.jq` files next to the modules (pattern: `claude-notify.nix` + `_claude-notify/`, like `hermes.nix` + `_hermes-plugins/`). `excludeShellChecks` only with a comment explaining why (pattern: `laptop-run` in `remote-agent.nix`).
- Executables in units, wrappers and generated config: `lib.getExe pkg` / `lib.getExe' pkg "name"` instead of `${pkg}/bin/name` in new code.
- Generated config files: `builtins.toJSON` or `pkgs.formats.<json|yaml|ini|toml>`. **NEVER** build JSON/YAML/INI by string concatenation. Every value interpolated into shell **MUST** go through `lib.escapeShellArg`.
- Repo-wide constants (domain, LAN, e-mail, caches, repository URL) come from `customTop` (`modules/args.nix`); host-dependent values from `customBot` options (`modules/hosts/base/options.nix`, always with `type` and `description`). **NEVER** duplicate those literals in modules.
- Runtime files and directories: `systemd.tmpfiles` rules or unit `StateDirectory`/`RuntimeDirectory`, not `mkdir`/`chown` in activation scripts.
- Invariants that would otherwise fail at runtime: `assertions` with an actionable message (pattern: `ttyd.nix`). Degraded but valid configuration: `warnings` (pattern: `raspberry-pi-4/network.nix`).
- CI: edit only `modules/github-actions.nix`. `.github/workflows/*.yml` are generated (`nix run .#sync-github-actions`) and **NEVER** edited by hand. Actions are pinned to commit SHAs.
- Formatting: `nix fmt` (nixfmt-tree). Linting: statix and deadnix. All of them run as pre-commit hooks inside `nix develop`.

### Nix code style

- **MUST** pass `nixfmt`, `statix` and `deadnix --no-lambda-pattern-names` with no findings (pre-commit + CI `lint`). **NEVER** disable or skip a lint to get a commit through.
- **MUST** use meaningful, descriptive attribute, binding and module names; a module is named after the feature, not after the change that added it.
- Module arguments: request only what is used; `_:` for a module that uses none.
- **NEVER** use `with lib;`. `with pkgs;` only for plain package lists (`environment.systemPackages`, `runtimeInputs`).
- Prefer `let … in` and `inherit` over `rec { }`; packages use `finalAttrs` instead of `rec`.
- Conditionals inside modules: `lib.mkIf`, `lib.mkMerge`, `lib.optionals`, `lib.optionalString`. **NEVER** wrap a module attrset in `if config.… then { … } else { }` (infinite recursion, lost merging).
- Priorities: `lib.mkDefault` in `base/` for values hosts may override. `lib.mkForce` only with a comment naming the definition it overrides and why.
- Platform: `pkgs.stdenv.hostPlatform.system`, never the deprecated `pkgs.system`.
- Paths: relative path literals (`./file`). **NEVER** string paths into the repo, `/home/…` or `/etc/nixos/…` in Nix code (exception: files consumed at runtime by programs outside Nix, documented where they are referenced, e.g. `M27Q.icm`).
- Three or more assignments with the same prefix in one attrset (`foo.a = …; foo.b = …;`) are nested into `foo = { … };` (statix `repeated_keys`).
- **NEVER** use emoji, or unicode that emulates emoji (e.g. ✓, ✗), in Nix code, scripts, comments or commit messages.
- **NEVER** commit commented-out code. The only exception is a disabled import with a pointer to its re-enable procedure.
- **NEVER** commit `builtins.trace`, `lib.traceVal` or debug `echo` lines.
- Vendored code (`modules/hosts/raspberry-pi-4/_hermes-agent/`) keeps upstream style so it can be re-synced; changes there stay minimal and are listed in its header.

### Comments and documentation

- Comments explain **why**: upstream bug, measured effect, security reason, non-obvious Nix or module-system behaviour (priorities, `attrNamesToTrue` sorting, store-path reference scanning, `nixConfig` not inherited from inputs). Assume the reader knows NixOS well but not every nixpkgs internal.
- **MUST** avoid redundant comments which are tautological or restate the attribute name.
- **MUST** avoid comments which leak what this file contains, or leak the user's prompt.
- Match the language of the surrounding comments (most modules are commented in Polish). AGENTS.md, `SKILL.md` files and commit messages are in English.
- Every non-trivial module starts with a header comment at the top of the file: what it does, why it exists, how to verify or test it. Its first paragraph is the module's description in `docs/reference/modules.md`, so make it a self-contained summary (patterns: `modules/desktop/tuning.nix`, `modules/hosts/remote-agent.nix`, `modules/checks/hermes-activation.nix`).
- Every temporary upstream workaround gets an entry in `temporary-fixes.md` (removal condition + upstream link) and a code comment pointing to it.
- **MUST** update AGENTS.md in the same commit when a change adds, removes or renames a host, service, secret, CI workflow, command or alias, or changes a rule, invariant or pitfall. The per-module catalog is generated (`docs/reference/`), so a new or renamed module needs a good header, not an AGENTS.md entry. AGENTS.md is a symlink to `GEMINI.md`: edit `GEMINI.md`. It stays a map; details belong in module headers.
- Non-trivial architecture: write the design down in `docs/design/` (Markdown with mermaid diagrams) before implementing. Once it is implemented, delete the document or move the lasting facts into the module header; plans and checklists are not kept in the repo. `docs/reference/` is generated (see Development workflow).

### Flake inputs and dependencies

- New inputs follow our nixpkgs (`inputs.nixpkgs.follows = "nixpkgs"`) unless their binary cache only matches their own nixpkgs (`nix-cachyos-kernel`, `llm-agents`); then say so in a comment next to the input.
- An input with its own binary cache: add the cache to `nixConfig` in `flake.nix` (see **Binary caches**).
- Adding or removing an input: `nix flake lock` (does not bump other inputs). Updating one input: `nix flake update <input>`. Full updates only through `flake-update`.
- Every fetcher has a real hash. **NEVER** commit `lib.fakeHash`.
- Flakes see only git-tracked files: `git add` new files before `nix eval`/`nix build`, otherwise they are silently missing.

### Local packages (`modules/packages/_<name>/default.nix`)

- `callPackage` style with `mkDerivation (finalAttrs: { … })` / `buildGoModule (finalAttrs: { … })`; sources from `fetchFromGitHub` with `tag = "v${finalAttrs.version}"` where upstream tags releases.
- `passthru.updateScript = nix-update-script { };` plus an entry in `flake-update` (`modules/packages/scripts.nix`) when the package should be bumped automatically.
- `versionCheckHook` + `doInstallCheck = true` when the binary supports `--version`.
- Complete `meta`: `description`, `homepage`, `license`, `mainProgram`, `platforms`; prebuilt binaries add `sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];`.
- Register the package in `localPackages` (`modules/packages/packages.nix`), which exports both the overlay and `packages.<system>.<name>`.
- Patch sources with `substituteInPlace --replace-fail` (fails loudly when upstream changes); `--replace-warn` only as a documented temporary fix.
- Reference example: `modules/packages/_bootdev-cli/default.nix`.

### Services and security

- New services you write: dedicated user or `DynamicUser`, `NoNewPrivileges`, `ProtectSystem = "strict"`, `ProtectHome`, `PrivateTmp`, minimal `ReadWritePaths`; secrets through `LoadCredential` or `EnvironmentFile` from agenix.
- RPi services bind to `127.0.0.1` or a Unix socket and are exposed only through the Cloudflare tunnel. Firewall exposure is always explicit (`openFirewall` set deliberately).
- **NEVER** read or print decrypted secrets (`/run/agenix*`). **NEVER** put secret values in `.nix` files, unit `Environment=`, command lines (visible in `ps`) or logs.
- **NEVER** weaken the firewall, SSH, sudo, `trusted-users` or a unit's sandboxing to make something work. Find the narrow fix, or stop and ask.

### Evaluation and build cost

- The RPi is slow (`max-jobs = 2`): evaluate only the hosts a change affects. x86_64 builds go through `laptop-run`, never locally on the RPi.
- No import-from-derivation: never `import` or `builtins.readFile` a build output.
- **NEVER** override widely used packages (glibc, openssl, mesa, python3, systemd, the kernel) or `nixpkgs.config` without need: it misses the binary caches and rebuilds everything downstream locally. Stop and ask before any change that compiles the kernel or CUDA packages (Verification step 3).
- Check closure growth with `nix store diff-closures` and justify large increases.

### Testing

- Behaviour that evaluation cannot prove (activation, permissions, kernel/sysctl effects, service startup) gets a NixOS VM test: `pkgs.testers.runNixOSTest` in `modules/checks/<name>.nix`, run with `nix build -L .#checks.<system>.<name>`.
- Tests take expected values from the host configuration instead of duplicating constants, and show the effect A/B where a change claims one (pattern: `modules/checks/tuning.nix`).
- **NEVER** game the tests: do not weaken an assertion, loosen a tolerance, skip a subtest or change a test to match a broken implementation.
- **NEVER** run VM tests or heavy builds in parallel: they compete for RAM and KVM, and failures and timings become meaningless.
- **NEVER** save test logs or write-ups to files unless the user **explicitly** asks; report results in the console.

### Version control

- **MUST** write clear commit messages: `area: short lowercase summary` (`nixos:`, `rpi:`, `base:`, `installer:`, `skills:`, `docs:`), one logical change per commit.
- **NEVER** force-push or rewrite `master`; undo changes with `git revert`.
- **NEVER** commit `result*`, `.direnv`, `.pre-commit-config.yaml`, `.claude/settings.local.json`, credentials or decrypted secrets.
- Release tags `vN` are sequential and never reused; create them only when the user asks (`flake-release`).

### Agent-to-user behavior

- **NEVER** write scratch scripts or notes into the worktree (flakes, `git add -A` and `repo-sync` pick them up); use `$TMPDIR`.
- **NEVER** activate a configuration (`switch`, `boot`, `test`, `update*`): activation is done by the user (Verification step 4).
- **NEVER** claim that something was built, evaluated or tested without real command output; state exactly which steps did not run and why.
- Do not ask for clarification before implementation unless the change is impossible to implement without it.
- When creating several subagents, launch each in a separate parallel tool call, and never let more than one of them build or run VM tests at the same time.
- Before handing off to the user, report the verification steps that ran and their results in a Markdown table.

### Before committing

- [ ] Inside `nix develop`; pre-commit passes (gitleaks, nixfmt, statix, deadnix, sync-github-actions, sync-docs)
- [ ] New files are `git add`ed
- [ ] Every affected host evaluates (Verification step 1)
- [ ] Generated values are rendered and inspected (step 2)
- [ ] `nixos-rebuild build` + `nix store diff-closures` for host `nixos` when packages, overlays, the kernel or services changed (step 3)
- [ ] VM tests covering the touched modules pass
- [ ] Generated files (`.github/workflows`, `docs/reference`) refreshed by the hooks and staged
- [ ] AGENTS.md (`GEMINI.md`) and `temporary-fixes.md` updated
- [ ] No secrets, no commented-out code, no debug traces

**Remember:** prefer the simplest correct declarative solution. Cleverness is welcome only when it removes code or manual steps.

## Commands
```sh
sudo nixos-rebuild switch --flake .#nixos          # or .#raspberry-pi-4 / .#wsl
update / update-boot / update-reboot               # remote flake (github:janusz-bit/nixos), --refresh; update-reboot = boot + reboot on success
update-local / update-local-boot                   # /etc/nixos
push                                               # fish: build toplevel and push closure to cachix
update-my-pkgs                                     # fish: nix run /etc/nixos#flake-update
nix run github:janusz-bit/nixos -- [--disk DEV]    # install-system (live ISO), see below
nix run /etc/nixos#post-install [ssh|secure-boot]  # after install: agenix root key, Secure Boot enrollment
nix build .#raspberry-pi-4-sd-image
nix build .#packages.x86_64-linux.nixos-iso           # custom installer ISO for host nixos
```

`install-system` (`modules/installer/install.nix`) wipes the chosen disk (`--disk` or a picker) and installs the flake revision it was started from; it needs no keys (agenix decrypts nothing and Secure Boot stays off until `post-install`). `post-install ssh` (any host; named by `uname -n`) writes the root key (`hosts.<host>`) and the sshd host key (`sshHostKeys.<host>`) into `keys.nix` or prints the lines to add; then re-encrypt the secrets on another recipient. `post-install secure-boot` is for the laptop's Insyde firmware only. `nixos-iso` (`modules/installer/iso.nix`) embeds the whole `nixos` closure and installs fully offline (`install-system-offline`; `/etc/nixos` gets the flake source without history — run `git fetch origin && git reset --hard origin/master` once online and before `post-install`). Flow: `install.nix` header; cost and QEMU test: `iso.nix` header.
