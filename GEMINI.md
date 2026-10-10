# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS** and **Nix Flakes**. You maintain, refactor and develop this repository (NixOS dotfiles). Details live in module comments — read the module before changing it; this file is the map and the rules.

## Refinement (`/refine`, Prime Agent)
`/refine` is a built-in Prime Agent command (skill `packages/coding-agent/skills/refine`) for persisting tactics, policies and memory. It never deploys NixOS changes. From IPython: `await refine.status()`, `await refine.run("…")`, `await refine.run("…", global_=True)`. System changes are made only by editing this flake and running `nixos-rebuild` (aliases `update`, `update-local`).

## Repository map
- `flake.nix` — inputs + `nixConfig` caches; outputs = `flake-parts` + `import-tree ./modules` (every `.nix` under `modules/` is a flake-parts module; paths containing a `_`-prefixed segment are ignored, e.g. `_secrets/`, `_hardware-configuration/`, `packages/_waywallen/`). No Home Manager.
- `modules/args.nix` — `customTop` (repo, e-mail, domain `janusz-bit.com`, LAN `192.168.100.0/24`, binary caches, `secretsDir`).
- `modules/options.nix` — `customBot.{flakeTarget, enableFastfetch, defaultUser, triliumMcpUrl}`.
- `modules/hosts/base/` — shared NixOS base (`self.modules.nixos.base`), plus `fail2ban.nix` (imported by `nixos` and `raspberry-pi-4` only).
- `modules/hosts/{nixos,raspberry-pi-4,wsl}/` — hosts.
- `modules/hardware/` — LOQ-15IRX10, Lenovo tweaks, x86-64-v3 system features, `facter.json`. `M27Q.icm` is referenced by KWin (`~/.config/kwinoutputconfig.json` → `/etc/nixos/modules/hardware/M27Q.icm`) — do not move it.
- `modules/agenix/agenix.nix` + `modules/_secrets/` — secrets (see below).
- `modules/overlays/opencode.nix` — `opencode` wrapped with an inline, `builtins.toJSON`-generated `opencode.json` (providers, pinned plugins, MCP servers).
- `modules/packages/` — overlay `local-packages` (`helium`, `waywallen`, `waywallen-kde-plugin`, `bootdev-cli`; also exposed as `packages.<system>.*` for `nix-update`), scripts (`flake-update`, `flake-release`, `repo-sync`), RPi SD image.
- `modules/installer/` — everything for installing host `nixos`: `install.nix` (packages `install-system`, `install-system-offline`, `post-install`), `iso.nix` (`nixos-iso`, fully offline bootable installer ISO).
- `modules/skills/` — declarative skills: Prime Agent (`skills`) and Claude Code (`claudeSkills`; `nixos-system` = NixOS specifics + a host section generated from `config`).
- `modules/github-actions.nix` — generates `.github/workflows/*.yml`.
- `modules/hosts/raspberry-pi-4/_hermes-agent/` — vendored copy of upstream `nix/nixosModules.nix` (MIT) whose activation runs as the service user; the header lists the changes and the sync procedure (`temporary-fixes.md`).
- `modules/checks/hermes-activation.nix` — NixOS VM test: the vendored Hermes activation never writes as root through agent-owned paths (symlink-attack matrix). Run: `nix build .#checks.<system>.hermes-activation` (needs kvm; ~3 min on the RPi).
- `modules/checks/tuning.nix` — NixOS VM test (x86_64 only, the host's own CachyOS kernel): `nixos-tuning` is applied with the host's values and each CachyOS-derived change has an effect (A/B THP 409 vs 511, zram 100% vs 50%, sysrq 244 vs 16, stop timeout, oomd kill/omit). Run: `nix build -L .#checks.x86_64-linux.tuning` (needs kvm; ~2.5 min).
- `temporary-fixes.md` — tracker of upstream workarounds (active / closed).
- `.claude/` — Claude Code project config: `settings.json` (permissions: read-only nix/git commands allowed, `git push` and `sudo` ask for confirmation, secrets and Secure Boot/disk writes denied) and `hooks/post-edit.sh` (nixfmt after every `.nix` edit; after `modules/github-actions.nix` also pre-commit refresh + workflow sync).

## Hosts
| Host | Arch | User | Notes |
|---|---|---|---|
| `nixos` (= `default`) | x86_64 | `dinosaur` | Lenovo LOQ-15IRX10 laptop, Plasma 6 (Wayland, no X server), stateVersion 25.11 |
| `raspberry-pi-4` | aarch64 | `nixos` | headless home server behind Cloudflare Tunnel, stateVersion 26.05 |
| `wsl` | x86_64 | `nixos` | NixOS-WSL, stateVersion 25.05 |

### Base (all NixOS hosts)
bash as login shell that `exec`s fish; fish aliases (eza/bat), tmux, `nix-ld`, `nix-index-database` + comma, direnv, Quad9 DNS (`mkDefault`; WSL clears it), firewall on, openssh key-only with `PermitRootLogin = "no"` by default, git config, agenix, Prime Agent config (`/etc/prime-agent/*.json` symlinked into `~/.prime/agent/`), nix: flakes, weekly GC (`mkDefault`), `nix.optimise.automatic`, caches from `customTop.cache`.

### `nixos` (laptop)
- Kernel: `pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3` via `nix-cachyos-kernel.overlays.pinned` (cache hit only with `pinned`; NVIDIA driver version therefore follows that input's nixpkgs). Never set `inputs.nixpkgs.follows` on `nix-cachyos-kernel`.
- Disko (`/dev/disk/by-id/nvme-WD_BLACK_SN850X_4000GB_…`; the other NVMe is Windows): ESP 6G, LUKS swap 36G (hibernation), LUKS+Btrfs `/`, `/home`, `/nix`. Limine with Windows entry and `secureBoot.enable` (sbctl keys in `/var/lib/sbctl`; `autoGenerateKeys` creates them when missing, e.g. on a fresh install — firmware untouched).
- Secure Boot is **enabled** with own keys (enrolled 2026-09-28): PK = sbctl, KEK/db = sbctl + Microsoft + Lenovo defaults, dbx = firmware `dbxDefault` (371 Microsoft SHA-256 hashes).
- **Insyde firmware quirk:** Linux sees only ~12 EFI variables (no `SecureBoot`, `SetupMode`, `PK`/`KEK`/`db`/`dbx`, `BootOrder`), so `sbctl status`/`sbctl enroll-keys`, `bootctl` and `efibootmgr` report nonsense. Reads: kernel log (`journalctl -k -b | grep -i "secure boot"`) or the TPM event log (`sudo tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements | grep -B3 -E 'UnicodeName: (SecureBoot|PK|KEK|db|dbx)$'`). Writes work through efitools. Key (re)enrollment, in Setup Mode: `sudo sbctl enroll-keys --microsoft --firmware-builtin db,KEK --export auth`, then `sudo efi-updatevar -f {db,KEK,PK}.auth {db,KEK,PK}` (PK last). Entering Setup Mode wipes `dbx` — restore it afterwards: `tail -c +5 /sys/firmware/efi/efivars/dbxDefault-8be4df61-93ca-11d2-aa0d-00e098032b8c > dbx.esl`, `sudo sign-efi-sig-list -a -k /var/lib/sbctl/keys/KEK/KEK.key -c /var/lib/sbctl/keys/KEK/KEK.pem dbx dbx.esl dbx.auth`, `sudo efi-updatevar -a -f dbx.auth dbx`. Never use "Erase all Secure Boot settings"/"Reset to Setup Mode" without a reason. Because `BootOrder` is invisible, `limine-install` recreates its NVRAM entry on every rebuild — never write boot entries manually with `efibootmgr`.
- Snapper for `/` and `/home`; `.snapshots` subvolumes are created by tmpfiles `v` rules.
- NVIDIA PRIME offload + Dynamic Boost (`nvidia-powerd`), `nixpkgs.config.cudaCapabilities = [ "12.0" ]` (RTX 5060; CUDA packages are built locally), ollama-cuda.
- Helium Browser (`helium.nix`) is the local package `helium` (`modules/packages/_helium`, official tar.xz, bumped by `flake-update`). Its dlopen dependencies (libpci, nixpkgs Vulkan loader, GTK 3, libpulse, pipewire) are in the binary's RUNPATH; the header says why `ominit/helium-browser-flake` was dropped (GPU not identified, no Intel driver workarounds, Qt6 UI).
- SSH reachable only from `customTop.lan.subnet` (iptables rule; `openFirewall = false`).
- Account `claude-remote` (`remote-agent.nix`) for Claude Code on the RPi: own primary group, no supplementary groups, no sudo, no agenix secrets; only the RPi key `keys.users.claude-rpi` with `from=<LAN>,restrict`. For eval/builds only — activation stays with the user.
- `claude-notify` (`nixos-hermes-notify` in `modules/hosts/raspberry-pi-4/hermes-notify.nix`): text to the Matrix DM through Hermes on the RPi (see `raspberry-pi-4`); `claude-remote` cannot read its key.
- Zed (`packages.nix`): `zeditor` wrapped with `VK_LOADER_DRIVERS_SELECT='intel_icd*'` (only the Mesa ANV ICD is loaded; the NVIDIA ICD would wake the dGPU from D3cold at `vkCreateInstance`); processes started from Zed inherit it (temporary, `temporary-fixes.md`).
- `tuning.nix` (CachyOS-Settings, only items with a shown effect; the header lists what was skipped and why): zram zstd at 100% RAM with zswap disabled (`zswap.enabled=0`; the CachyOS kernel enables it by default → double compression), swappiness 150/page-cluster 0, dirty bytes, THP `max_ptes_none=409`, `DefaultTimeoutStopSec=10s` (system + user), `kernel.sysrq=244`, systemd-oomd on `system.slice` and `user@.service` (80%; KWin/session bus `omit` — drop-ins for KDE units via `systemd.user.units.*.text`, because `systemd.user.services` drop-ins add `Environment=PATH=…`).
- No ananicy-cpp: with cgroup v2 nice only competes inside one cgroup (measured 50/50 across scopes), and its rules made GameMode refuse renice.
- Gaming (`gaming.nix`: Steam + proton-cachyos from chaotic, `ntsync` module, gamemode with renice and power-profiles-daemon `performance` while a game runs, `dbdrun`), podman (rootless use; user is intentionally **not** in group `podman`).
- VFIO passthrough (`vfio.nix` + `win11-vm.xml`, disabled) was removed; restore with `git show 3584010:modules/hosts/nixos/vfio.nix` (removing commit: `git log --diff-filter=D -- modules/hosts/nixos/vfio.nix`). Pitfalls if revived: never pass a `by-path` value (contains `:`) to `KWIN_DRM_DEVICES`; `virtualisation.libvirtd.qemu.ovmf` no longer exists.

### `raspberry-pi-4` (server)
- Imports the full base; overrides: GC daily/3d, `max-jobs = 2`, `documentation.doc.enable = false`, `PermitRootLogin = "prohibit-password"` (admin path: `ssh ssh.janusz-bit.com` as root via cloudflared), no ssh-askpass.
- RPi vendor kernel: the `nixos-hardware` default (`raspberry-pi/common/kernel.nix` itself forces `PREEMPT=y`, `PREEMPT_LAZY=n`); cache hit in `attic.xuyh0120.win/lantian`.
- Hardware: `pwm-fan.nix` (root service, PWM fan on GPIO 14: 0/50/100 % below 48 / from 48 / from 60 °C), `leds-off.nix` (ACT/PWR/Ethernet LEDs off through the `nixos-hardware` DT overlays, `mmc0`/`default-on` through tmpfiles).
- Wi-Fi (`wifi.nix`): NetworkManager `ensureProfiles` profile `home-wifi`, SSID/PSK substituted at runtime from `wifi.age` (`WIFI_SSID=…`/`WIFI_PSK=…`), powersave off, regdom `PL`. Inactive (evaluation warning only) until `wifi.age` is tracked in git.
- Services (all bound to localhost, exposed only through the tunnel `modules/hosts/raspberry-pi-4/cloudflared.nix`): Nextcloud 35 (Postgres, Redis, PHP-FPM `ondemand`), Open WebUI behind nginx (8080 → 3001; CORS limited to `chat.janusz-bit.com`, `SameSite=lax` cookies, sign-up disabled, security headers; it gets only `open-webui-keys.age`, never the Hermes env file), Trilium 8081, Gitea 3000, ttyd on a Unix socket only nginx can open, behind nginx Basic Auth 8083 (dedicated `ttyd-password.age` required by an assertion, rate limit, `--check-origin`), Matrix homeserver continuwuity (`matrix.nix`, 6167 → `matrix.janusz-bit.com`; `server_name` is the bare domain, delegated by `/.well-known/matrix/client` on the Nextcloud vhost; no federation, no open registration), SSH. Local Ollama (`hermes.nix`, default `127.0.0.1:11434`, `EnvironmentFile` = `hermes-env.age`) is not exposed.
- `laptop-run <cmd>` / `ssh laptop` (`modules/hosts/nixos/remote-agent.nix`, key `~nixos/.ssh/id_ed25519_laptop`, laptop host key pinned from `keys.sshHostKeys`, address `customTop.lan.laptop`): runs `<cmd>` on the laptop as `claude-remote` in a snapshot of the current repo (tracked files with uncommitted changes, sent as `git archive` over ssh into `~/work/<repo>`, no `git push`). Works only while the laptop is on and at home; the laptop's fail2ban does not ignore the LAN (5 failed logins ban the RPi).
- `claude-notify "text"` (or text on stdin) → Matrix DM through Hermes, no LLM (`modules/hosts/raspberry-pi-4/hermes-notify.nix`, modules `rpi-hermes-notify` + `nixos-hermes-notify`, key `hermes-notify-key.age`; without the file in git, or without `MATRIX_HOME_ROOM`: evaluation warning, feature off). Laptop → ssh through the tunnel (`ssh.janusz-bit.com`, cloudflared), `nixos` on the RPi → ssh to localhost, `hermes` → receiver directly. The key logs in only as `hermes`, from `127.0.0.1`/`::1`, with `restrict` and the forced command `hermes-notify-receive` (stdin only, max 3500 bytes, 30 messages/hour, `hermes send` to `MATRIX_HOME_ROOM` through the `hermes` wrapper exposed as `services.hermes-agent.cliWrapper`). Key file: laptop `dinosaur` 0400, RPi `hermes:hermes` 0440 (`nixos` reads it through the group); the client pins the RPi host key (`keys.sshHostKeys.raspberry-pi-4`) and ignores `ssh_config` (`-F /dev/null`).
- Hermes Agent (`hermes.nix` + vendored module `_hermes-agent/`): runs as `hermes` without sudo, `wheel`, `disk`, `keys` or Nix trust; sharing with user `nixos` via the 2770/UMask 0007 state dirs. Activation writes into `/var/lib/hermes` only as `hermes` (setpriv) — never as root; entries of `HERMES_HOME` owned by other users (left by the old root/`nixos` CLI) are taken over by copy, original directories are kept as `.foreign-<name>` for the administrator to delete (`sudo rm -r /var/lib/hermes/.hermes/.foreign-*`). The CLI (`hermes`, `hermes-acp`, `hermes-agent`) is a wrapper that runs `sudo -u hermes` against the service `HERMES_HOME` (as `hermes` itself it execs the binary directly); never run the package binary as root or `nixos` (it would execute agent-writable plugins/config). Main model = Claude Code subscription through the `claude-subscription-directsdk` plugin (`extraPlugins`, commit from the Hermes plugin catalog); one-time login on the RPi: `sudo -u hermes -H claude auth login`. Own plugin `mermaid-render` (`_hermes-plugins/mermaid-render/`, enabled in `plugins.enabled`): on Matrix, ```` ```mermaid ```` blocks of a reply are rendered with `mermaid-cli` to PNG in `cache/images/mermaid/` and sent as images (a block that fails to render stays code). Fallbacks: `openai-codex`, then `ollama-cloud`. UI language Polish (`display.language`) from the text-only language-pack plugin `hermes-lang-pl` (`extraPlugins` + `plugins.enabled`; that list replaces the on-disk one on every activation, so plugins are enabled only there). Matrix adapter (`matrix.nix`): bot account token in `hermes-matrix.age` (without it: evaluation warning, server runs, Hermes does not connect), answers only the owner account (`MATRIX_ALLOWED_USERS`), E2EE `required`, notifications to `MATRIX_HOME_ROOM`.

## Secrets (agenix)
- Recipients: `modules/_secrets/secrets.nix` (rules only — `*.age` entries), public keys in `modules/_secrets/keys.nix`. The laptop is a recipient of everything (secrets are edited there). Rekey after changing recipients: `cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519`.
- User secrets (`modules/agenix/agenix.nix`): owner `customBot.defaultUser`, mode `0400`. Service secrets: owned by the service user, or root `0400` when the service reads them via `LoadCredential`/`EnvironmentFile`. Never `group = "users"`.
- Never export secrets globally (shell init, `sessionVariables`). Inject per process: fish wrapper functions in `modules/hosts/base/agenix.nix` (`prime-agent`, `opencode`, `gemini`, `cachix-push`); nix `access-tokens` are rendered into `~/.config/nix/nix.conf` by the user unit `nix-access-tokens`.
- Never write secret values into `.nix` files (they end up in the world-readable store).

## Security invariants — do not regress
- `nix.settings.trusted-users` stays default (root only).
- No passwordless root paths for user or agent accounts (no `podman`/`docker` group, no NOPASSWD sudo for agents).
- `/etc/ai` (runtime skill drop-in) is `0755`, owned by `customBot.defaultUser`.
- Root never writes through paths an unprivileged account controls (no `chown`/`chmod`/`install`/merge as root inside `/var/lib/hermes`; use `setpriv` to the owner or symlink-safe `systemd-tmpfiles`).
- Runtime-fetched code is pinned: opencode plugins (commit/version in `opencode.nix`), GitHub Actions (commit SHAs in `github-actions.nix`), Hermes plugins (commit in `hermes.nix`), MCP servers from nixpkgs rather than `uvx`/`uv run`.
- The RPi is less trusted than the laptop (internet-facing): its key logs into the laptop only as `claude-remote` (no groups, `from=<LAN>,restrict`) — never into `dinosaur` or root; no `nix.buildMachines` to the laptop (it would need `trusted-users`).
- ttyd credentials never on a command line (nginx `auth_basic` with a hash file generated from the agenix secret); ttyd itself is reachable only through nginx (Unix socket `root:nginx 0660`); its password is its own secret, never another service's.

## Binary caches
`customTop.cache` (→ `nix.settings`) and `nixConfig` in `flake.nix` must list the same caches: `janusz-bit.cachix.org`, `attic.xuyh0120.win/lantian` (CachyOS kernel), `cache.numtide.com` (llm-agents). Input `nixConfig` is not inherited. When adding a cache, run the first rebuild with `--accept-flake-config`.

## Development workflow
- Always work inside `nix develop` (installs pre-commit hooks: gitleaks, nixfmt, statix, deadnix, sync-github-actions). Claude Code: start it with the alias `claude-nixos` (host `nixos`, `modules/hosts/nixos/ai.nix`) = `nix develop -c claude` in `/etc/nixos`; outside the dev shell the `.claude/` hooks silently do nothing.
- **Stale hook pitfall:** the `sync-github-actions` hook points at the store path built when the shell was entered. After editing `modules/github-actions.nix`, re-enter `nix develop`, or run `nix run .#sync-github-actions` and commit with `SKIP=sync-github-actions`. Claude Code's `.claude/hooks/post-edit.sh` does this automatically.
- CI workflows (generated): `nixos` (PR + manual only, 3–5 h), `nixos-iso` (PR + manual only, same cost as `nixos` since the ISO now bundles its whole closure), `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl` (tags `v*`, PR), `eval` and `lint` (also on every push to `master`), `cachyos-kernel-update` (manual).
- `flake-update` updates `flake.lock` and local packages (`helium` and `waywallen` in two arch passes, `bootdev-cli`) and commits; `flake-release` tags `vN` and pushes; `repo-sync` commits everything, rebases and pushes.
- **Git (mandatory):** commit every change; style: short lowercase summary prefixed with the area (`nixos: …`, `rpi: …`, `docs: …`). Push to `origin` only after verification (below) — `update` on every host deploys straight from GitHub, so a push is a deployment: host `nixos` after a successful `update-local`; `raspberry-pi-4`/`wsl` (no local switch) after verification steps 1–2. Experimental or large features (new services, wrappers, overlays): a branch + PR (CI `eval` and `lint` run on PRs), merged after testing on the target host.
- **Skills:** store in `modules/skills/<name>/` (`SKILL.md` + `references/`; Python skills also `src/<pkg>/` + `pyproject.toml` and an entry in `pythonSkills`) and register in `modules/skills/default.nix`; programs a skill calls go into `skillPackages` there (installed with the skill, not in a host module). Python skill sources reach the kernel through the `prime-agent` wrapper's `PYTHONPATH`. Prime Agent reads `/etc/ai-skills` and the runtime drop-in `/etc/ai` through `skills` in its `settings.json` (`base/prime-agent.nix`; earlier entry wins a name collision, so declarative skills win); runtime skills without a rebuild go to `/etc/ai/<name>/`. Claude Code skills go into `claudeSkills` → `/etc/claude-code/.claude/skills/<name>` (managed scope: every user and project on hosts importing `ai-skills`; `claude --debug` logs `Loading skills from: managed=…`).
- Temporary upstream workarounds must get an entry in `temporary-fixes.md` with a removal condition.

## Verification (before every commit)
A change is done only when it has been checked as far as possible without root. Report which steps ran and which did not.
1. Evaluate every affected host: `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (`nixos`/`raspberry-pi-4` ~25 s, `wsl` ~8 s; aarch64 evaluates fine on x86_64). On the RPi run steps 1–3 for x86_64 hosts through `laptop-run` when the laptop is on. Changes in `base/`, `args.nix`, `options.nix`, overlays or `flake.nix` affect all three hosts.
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

- Module layout: every `.nix` file under `modules/` is a flake-parts module (import-tree). A new NixOS module is exported as `flake.modules.nixos.<prefix>-<name>` (`base-*`, `nixos-*`, `rpi-*`, `wsl-*`) and imported explicitly in the host's `default.nix`. Anything that is not a flake-parts module (package definitions, hardware configs, vendored code, patches) **MUST** live under a `_`-prefixed path, otherwise import-tree imports it and evaluation breaks.
- Shell scripts: `pkgs.writeShellApplication` with `runtimeInputs` (shellcheck runs at build time). **NEVER** use `writeShellScriptBin`/`writeScript` for new scripts with logic; migrate old ones when you touch them anyway. Longer scripts go into a sibling `.sh` file loaded with `builtins.readFile` (import-tree only imports `.nix`). `excludeShellChecks` only with a comment explaining why (pattern: `laptop-run` in `remote-agent.nix`).
- Executables in units, wrappers and generated config: `lib.getExe pkg` / `lib.getExe' pkg "name"` instead of `${pkg}/bin/name` in new code.
- Generated config files: `builtins.toJSON` or `pkgs.formats.<json|yaml|ini|toml>`. **NEVER** build JSON/YAML/INI by string concatenation. Every value interpolated into shell **MUST** go through `lib.escapeShellArg`.
- Repo-wide constants (domain, LAN, e-mail, caches, repository URL) come from `customTop` (`modules/args.nix`); host-dependent values from `customBot` options (`modules/options.nix`, always with `type` and `description`). **NEVER** duplicate those literals in modules.
- Runtime files and directories: `systemd.tmpfiles` rules or unit `StateDirectory`/`RuntimeDirectory`, not `mkdir`/`chown` in activation scripts.
- Invariants that would otherwise fail at runtime: `assertions` with an actionable message (pattern: `ttyd.nix`). Degraded but valid configuration: `warnings` (pattern: `wifi.nix`).
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
- Every non-trivial module starts with a header comment: what it does, why it exists, how to verify or test it (patterns: `modules/hosts/nixos/tuning.nix`, `modules/hosts/nixos/remote-agent.nix`, `modules/checks/hermes-activation.nix`).
- Every temporary upstream workaround gets an entry in `temporary-fixes.md` (removal condition + upstream link) and a code comment pointing to it.
- **MUST** update AGENTS.md in the same commit when a change adds, removes or renames a module, host, service, secret, CI workflow, command or alias. AGENTS.md is a symlink to `GEMINI.md`: edit `GEMINI.md`. It stays a map; details belong in module headers.
- Non-trivial architecture: write the design down in `docs/` (Markdown with mermaid diagrams) before implementing. Once it is implemented, delete the document or move the lasting facts into the module header; plans and checklists are not kept in the repo.

### Flake inputs and dependencies

- New inputs follow our nixpkgs (`inputs.nixpkgs.follows = "nixpkgs"`) unless their binary cache only matches their own nixpkgs (`nix-cachyos-kernel`, `llm-agents`); then say so in a comment next to the input.
- An input with its own binary cache: add the cache to both `nixConfig` in `flake.nix` and `customTop.cache` (see **Binary caches**).
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

- [ ] Inside `nix develop`; pre-commit passes (gitleaks, nixfmt, statix, deadnix, sync-github-actions)
- [ ] New files are `git add`ed
- [ ] Every affected host evaluates (Verification step 1)
- [ ] Generated values are rendered and inspected (step 2)
- [ ] `nixos-rebuild build` + `nix store diff-closures` for host `nixos` when packages, overlays, the kernel or services changed (step 3)
- [ ] VM tests covering the touched modules pass
- [ ] Workflows regenerated if `modules/github-actions.nix` changed
- [ ] AGENTS.md (`GEMINI.md`) and `temporary-fixes.md` updated
- [ ] No secrets, no commented-out code, no debug traces

**Remember:** prefer the simplest correct declarative solution. Cleverness is welcome only when it removes code or manual steps.

## Commands
```sh
sudo nixos-rebuild switch --flake .#nixos          # or .#raspberry-pi-4 / .#wsl
update / update-boot / update-reboot               # remote flake (github:janusz-bit/nixos), --refresh; update-reboot = boot + reboot on success
update-local / update-local-boot                   # /etc/nixos
push                                               # fish: build toplevel and push closure to cachix
nix run github:janusz-bit/nixos -- [--disk DEV]    # install-system (live ISO), see below
nix run /etc/nixos#post-install [ssh|secure-boot]  # after install: agenix root key, Secure Boot enrollment
nix build .#raspberry-pi-4-sd-image
nix build .#packages.x86_64-linux.nixos-iso           # custom installer ISO for host nixos
```

`install-system` (`packages.default`, `modules/installer/install.nix`) runs from a live ISO (stock ISO: `nix --extra-experimental-features 'nix-command flakes' run …`), wipes the target disk and installs the flake revision it was started from (`nix run .` = local tree); `/etc/nixos` gets a clone of origin. Target: `--disk DEV` or a picker (Enter = disko.nix device); the disko script is prebuilt (`extendModules`) for the device `/run/install-system/disk`, a symlink pointed at the chosen disk right before formatting, so any disk works without evaluating the flake at install time; the system itself is unchanged (mounts use `by-partlabel/disk-main-*`), so it refuses while another disk carries those labels. It needs no keys: limine-install generates sbctl keys, Secure Boot stays off in the firmware and agenix decrypts nothing until `post-install` (same file): `ssh` generates `/root/.ssh/id_ed25519` and writes it into `keys.nix` (then rekey on raspberry-pi-4, the other recipient of every secret), `secure-boot` runs the Insyde enrollment procedure above (asks for Setup Mode, restores dbx).

`nixos-iso` (`modules/installer/iso.nix`) is the bootable-media version of the same flow: a stock `installation-cd-minimal.nix` installer with flakes pre-enabled and `install-system-offline` pre-installed, so booting the ISO and running `install-system [--disk DEV]` as root (no password) is the whole flow — **no network needed at all**. Unlike the online `install-system` (`--flake`, git-clones origin), the offline variant (`install-system-offline`, generated by the same `mkInstallSystem` in `install.nix`) copies `self` straight out of the Nix store into `/etc/nixos` (fresh `git init` + `origin` remote tracking `origin/master`, no shared history — `git fetch origin && git reset --hard origin/master` once back online, before `post-install`, recovers real history) and runs `nixos-install --system <prebuilt toplevel> --no-channel-copy` instead of `--flake`, so no flake evaluation happens on the booted media. The prebuilt `config.system.build.toplevel` for host `nixos` is pulled into the ISO automatically: the offline script text references it, so Nix's store-path reference scanning adds its whole closure as a build dependency, which lands in the ISO squashfs via `environment.systemPackages`. Consequence: the ISO embeds the ENTIRE `nixos` host closure (CachyOS kernel LTO, KDE, gaming, NVIDIA...) — build cost and ISO size are comparable to a full `nixos` host build (hence `tags = false` in `github-actions.nix`, PR/dispatch only); on the laptop, with the closure already in the store, the build takes ~20 min (squashfs zstd-19) and the ISO is ~17 GB (fits a 32 GB stick). Offline `nixos-install` runs with `--option substituters ""` (copies only from the ISO store). Tested end-to-end in QEMU (OVMF, `-nic none`): install onto a non-disko.nix disk, then Limine → LUKS → SDDM; attach the disk as NVMe (`-device nvme`) when booting the installed system — its facter-based initrd has no `virtio_blk`. Picking a disk other than the one in `disko.nix` is offline too (same prebuilt symlink disko script). Legacy `isoImage.isoBaseName` collides with the new `image.baseName` default in `iso-image.nix` (both land at the same priority → "conflicting definition values") — set `image.baseName` directly with `lib.mkForce` instead. Write to USB: `dd` the file under `result/iso/*.iso`, or mount it in Ventoy.
