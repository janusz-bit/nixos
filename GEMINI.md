# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS** and **Nix Flakes**. You maintain, refactor and develop this repository (NixOS dotfiles). Details live in module comments — read the module before changing it; this file is the map and the rules.

## Refinement (`/refine`, Prime Agent)
`/refine` is a built-in Prime Agent command (skill `packages/coding-agent/skills/refine`) for persisting tactics, policies and memory. It never deploys NixOS changes. From IPython: `await refine.status()`, `await refine.run("…")`, `await refine.run("…", global_=True)`. System changes are made only by editing this flake and running `nixos-rebuild` (aliases `update`, `update-local`).

## Repository map
Generated reference — read it before grepping: `docs/reference/hosts.md` (each host's modules, diagrams), `docs/reference/modules.md` (every module with its header summary), `docs/reference/options.md`. Human overview and the add-a-host procedure: `README.md`.

- `flake.nix` — inputs + `nixConfig` (the only binary-cache list); outputs = `flake-parts` + `import-tree ./modules`: every `.nix` under `modules/` is a flake-parts module, paths with a `_`-prefixed segment are ignored (`_secrets/`, `packages/_helium/`, `raspberry-pi-4/_hardware-configuration.nix`). No Home Manager.
- `modules/default.nix` — systems, flake-parts modules, formatter, pre-commit hooks, dev shell. `modules/options.nix` declares and `modules/args.nix` sets the read-only option `customTop` (typed, `config.customTop` in flake-parts modules and, through `base-options`, in NixOS modules): owner- and repo-specific values (GitHub owner, e-mail, tailnet, repository, user names, locale and time zone, LAN, `nixConfig`, own cachix, `secretsDir`, `keys`). Literals that stay outside it because they are read outside the module system: `flake.nix` inputs and `nixConfig`, `modules/_secrets/keys.nix`.
- `modules/hosts/registry.nix` — `hosts.<name> = { system; modules; buildOnTags; }` → `nixosConfigurations.<name>`, `networking.hostName` and `customBot.flakeTarget` = `<name>` (a host setting another hostname fails evaluation), CI workflows, docs.
- `modules/hosts/base/` — what every host imports (aggregate `base`): `options.nix` (`customBot.*`, NixOS `customTop`), `nix.nix`, `rebuild.nix` (update aliases), `configuration.nix`, shell, git, ssh, Prime Agent; opt-in (imported by `nixos` and `raspberry-pi-4`, not WSL, which is no agenix recipient): `agenix.nix` (`base-agenix`: user secrets from `secrets.nix`, per-process wrappers, `push`), `fail2ban.nix` (`base-fail2ban`), `ssh-lan.nix` (`base-ssh-lan`: SSH only from the home LAN) and `lockdown.nix` (`base-lockdown`: emergency `lockdown on|off|status`).
- `modules/hosts/<host>/` — what makes a machine itself: registry entry + identity in `default.nix`, disk, boot, host-only services. `modules/hosts/t3code-laptop.nix` and `modules/hosts/tailscale.nix` link two hosts and export one module per host.
- `modules/desktop/`, `modules/gaming/` — workstation features any x86_64 desktop host may import (aggregates `desktop`, `gaming`). GPU-dependent settings inside them follow `hardware.nvidia.*` from the hardware module; `desktop-kernel` and Proton-CachyOS need an x86-64-v3 CPU (import `hardware-x86-64-v3`).
- `modules/hardware/<machine>/` — drivers, quirks and the facter report of one machine; `lenovo.nix`, `x86-64-v3.nix` shared pieces. `M27Q.icm` is referenced by KWin (`~/.config/kwinoutputconfig.json` → `/etc/nixos/modules/hardware/M27Q.icm`) — do not move it.
- `modules/installer/` — `install-system` for the host named by `installHost` (`nixos`), `post-install` for any host; `modules/packages/` — local packages (overlay `local-packages`, also `packages.<system>.*`) and `flake-update`/`flake-release`/`repo-sync`/`package-import`; `modules/ai/` — skills and models of the coding agents (Prime Agent, Claude Code, Codex, opencode) as NixOS options `ai.*`: catalogs (`skills.nix`, `models.nix`), the import logic into each agent (`harness.nix`), per-host choice in `hosts/<host>/ai.nix`; `modules/skills/` — the skill directories themselves (`SKILL.md`); `modules/github-actions.nix`, `modules/docs.nix` — generators.
- `modules/checks/` — NixOS VM tests: `tuning` (x86_64 only, the host's CachyOS kernel, A/B effects of `desktop-tuning`; `nix build -L .#checks.x86_64-linux.tuning`, kvm, ~2.5 min), `lockdown` (`base-lockdown` closes ports and stops services but keeps SSH, across firewall reload, target restart and reboot; `nix build -L .#checks.<system>.lockdown`, kvm, ~1 min on the laptop).
- `temporary-fixes.md` — upstream workarounds (active / closed). `.claude/` — `settings.json` (nix eval/build, `nixos-rebuild build` and read-only git allowed; `git push`, `sudo` ask; secrets, Secure Boot and disk writes denied) and `hooks/post-edit.sh` (nixfmt after every `.nix` edit).

## Hosts
| Host | Arch | User | Notes |
|---|---|---|---|
| `nixos` (= `default`) | x86_64 | `dinosaur` | Lenovo LOQ-15IRX10 laptop, Plasma 6 (Wayland, no X server), stateVersion 25.11 |
| `raspberry-pi-4` | aarch64 | `nixos` | headless home server, services only in the tailnet (Tailscale Serve), stateVersion 26.05 |
| `wsl` | x86_64 | `nixos` | NixOS-WSL, stateVersion 25.05 |

Base (every host): bash exec'ing fish, tmux, nix-ld, comma, direnv, Quad9 DNS (`mkDefault`; WSL clears it), firewall on, key-only SSH (`PermitRootLogin = "no"` by default), Prime Agent config, flakes, weekly GC (`mkDefault`), `nix.optimise.automatic`.

### `nixos` (laptop)
- `base` + `desktop` + `gaming` + `hardware-LOQ-15IRX10` + `nixos-{boot,disko,snapper}` + `base-agenix`, `base-ssh-lan`, `nixos-ai`, `base-fail2ban`, `base-lockdown`, `nixos-tailscale`, `nixos-t3code-laptop`.
- Kernel (`desktop/kernel.nix`) via `nix-cachyos-kernel.overlays.pinned` (built with that input's nixpkgs, so it rebuilds only when the input changes; the NVIDIA driver and, while the host nixpkgs expects kmodigest certificates the pinned kernel lacks, `aggregateModules` follow that input's nixpkgs — `temporary-fixes.md`). No binary cache serves it: a new kernel compiles locally or in CI `cachyos-kernel-update` (pushed to own cachix). Never set `inputs.nixpkgs.follows` on `nix-cachyos-kernel`.
- Secure Boot is **enabled** with own keys (enrolled 2026-09-28): PK = sbctl, KEK/db = sbctl + Microsoft + Lenovo defaults, dbx = firmware `dbxDefault` (371 Microsoft SHA-256 hashes). **Insyde firmware quirk:** Linux sees only ~12 EFI variables (no `SecureBoot`, `SetupMode`, `PK`/`KEK`/`db`/`dbx`, `BootOrder`), so `sbctl status`/`sbctl enroll-keys`, `bootctl` and `efibootmgr` report nonsense. Read the state from the kernel log (`journalctl -k -b | grep -i "secure boot"`) or the TPM event log (`sudo tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements | grep -B3 -E 'UnicodeName: (SecureBoot|PK|KEK|db|dbx)$'`). (Re)enroll keys only with `nix run /etc/nixos#post-install secure-boot` (efitools; restores the dbx that Setup Mode wipes). Never use "Erase all Secure Boot settings"/"Reset to Setup Mode" without a reason; never write boot entries with `efibootmgr` (`limine-install` recreates its NVRAM entry on every rebuild).
- Browser extensions and policies live in `desktop/browsers.nix` (Chromium policies read by Helium and ungoogled-chromium), login apps in `desktop/autostart.nix` (except Brulion: `programs.brulion.autostart` of its own flake's module, `desktop/brulion.nix`) — not in the browser or System Settings.
- Local LLM: `llama`, `llama-server`, … in PATH are stock nixpkgs llama.cpp (CUDA with NVIDIA, `desktop/ai.nix`). Never set `GGML_CUDA_ENABLE_UNIFIED_MEMORY` (it hides VRAM overflow and pages over PCIe).
- Strata (`strata`, local package `packages/_strata`, NVIDIA only via `desktop/ai.nix`): MoE engine that keeps experts in RAM/SSD, e.g. `strata launch --family coder --model IQ1_M` (Qwen3.8-Flash-Next GSQ-RCO Coder); default endpoint 127.0.0.1:8080, where provider `strata` in `ai/models.nix` points. The release CUDA engine is patched, so it reports "unsigned"; self-update is cut off by the wrapper (`strata update` fails — bump the package with `nix-update --commit -F strata`, its engine pin by hand). Models and run configs live in `~/.local/share/strata/` (`--data-dir` moves new downloads). opencode2 and Prime Agent get it as provider `strata` (`ai.models.qwen3-8-flash-next-coder-iq1_m`, 128K context, which fits 8 GB VRAM only with `--kv q4_0`; `ai.models.qwen3-8-flash-next-gyro-gyro-m`, `--family gyro`, the default and title model of opencode2); start it with `--context 128k --kv q4_0 --no-api-key` and never use `strata connect opencode --write` (writes the opencode v1 format over the managed `opencode.json` symlink; translate its output into `ai.opencode.settings` in schema v2).
- Unsloth Studio (local package `packages/_unsloth-desktop`, `desktop/ai.nix`): `unsloth-desktop` (the app) and `unsloth` (the CLI of its venv in `~/.unsloth/studio`, e.g. `unsloth studio setup`) run in one FHS environment (CA bundle, node, gcc); run `unsloth` from a directory under `$HOME` (bwrap cannot enter most of `/etc`). The bundled installer no longer links `~/.local/bin/unsloth`; such a link (left by an older install or `curl … install.sh | sh`) shadows the wrapper, and the uv Python behind it fails TLS with `CERTIFICATE_VERIFY_FAILED` — remove it.
- `claude-usage` (skill `claude-usage`, `ai/skills.nix`): remaining Claude subscription limits (5 h session, weekly, per model, extra usage) from the internal `api.anthropic.com/api/oauth/usage` endpoint behind Claude Code's `/usage`, authenticated with the Claude Code OAuth token from `~/.claude/.credentials.json`; `--json` prints the raw response. The endpoint is undocumented and may change.
- REA (local package `packages/_rea-agents`, npm tarball on Node 26, skill `reverse-engineer-anything` through `ai.skills`, which installs it): `rea` CLI and MCP server (`rea mcp`) for reverse engineering binaries, JavaScript/Electron apps, APKs and websites. The flake does not register the MCP server; per agent once: `rea setup --client claude_code --no-skill` (also `codex`, `opencode`; `--dry-run --json` first), which records `/run/current-system/sw/bin/rea` only because `bin/rea` is a symlink to `rea.mjs` (a wrapper would make it record a `/nix/store` path that GC removes). Never `npx rea-agents setup` (records the npx cache) or `rea update` (bump with `nix-update --commit -F rea-agents`, as `flake-update` does; dependencies come from the tarball's `npm-shrinkwrap.json`). Without `--no-skill` setup copies the skill into `~/.claude/skills` and `~/.agents/skills`, shadowing the managed one. Native engines (Ghidra via `GHIDRA_INSTALL_DIR`, JADX, IDA) are not part of the config; Frida instrumentation is unavailable (install scripts are off); `rea doctor` reports NixOS as `unsupported_host` (it looks for apt/dnf/pacman), which only affects Hopper auto-install.
- VFIO passthrough was removed (3247976); restore with `git show 3584010:modules/hosts/nixos/vfio.nix` and `git show 3584010:modules/hosts/nixos/win11-vm.xml`. Pitfalls if revived: never pass a `by-path` value (contains `:`) to `KWIN_DRM_DEVICES`; `virtualisation.libvirtd.qemu.ovmf` no longer exists.

### `raspberry-pi-4` (server)
- `base` (inside the aggregate: the SD image composes it outside the registry) + `base-agenix` + `base-fail2ban` + `base-ssh-lan` + `base-lockdown` + `rpi-ai` + `hardware-raspberry-pi-4` (+ `-fan`) + `rpi-*` modules (incl. `rpi-tailscale`, `rpi-t3code`, `rpi-t3code-laptop`); overrides in `resources.nix` (GC daily/3d, `max-jobs = 2`) and `ssh.nix` (`PermitRootLogin = "prohibit-password"`: admin path `ssh root@raspberry-pi-4`; port 22 also open on `tailscale0`).
- Kernel: the vendor kernel `linuxPackages_rpi4` of input `nixos-raspberrypi` (`hardware/raspberry-pi-4`), built with that input's nixpkgs and served by `nixos-raspberrypi.cachix.org`, so a host nixpkgs bump no longer recompiles it; the rest of the board profile (device tree overlays, firmware) still comes from `nixos-hardware`. Never set `inputs.nixpkgs.follows` on `nixos-raspberrypi` (the cache would miss). After a bump of that input, check the kernel is in its cache (command in the module header) before `update` on the RPi. Pitfall: that kernel has no kmodigest certificate (`modules.cer`), so a second kernel module package (`boot.extraModulePackages`, ZFS) fails in `aggregateModules` with `cannot stat …/modules.cer`; the SD image (`sd-image.nix`) therefore turns off the ZFS its installer profile enables.
- An assertion in `nextcloud.nix` keeps Nextcloud's PHP >= 8.4.27 (PHP2Shell).
- Nothing on the RPi is published to the internet (no Cloudflare Tunnel, no ttyd). Web services listen on localhost only (nginx `defaultListenAddresses`, `network.nix`) and reach the tailnet only through Tailscale Serve on `https://raspberry-pi-4.<customTop.tailnet.domain>:<port>`: each module adds `customBot.tailscaleServe.<https port> = { port; users; }` (`users`: only these accounts and root may connect to the backend locally, iptables owner rule) and unit `tailscale-serve` (`hosts/tailscale.nix`) resets Serve and applies exactly that map after every login. Ports: 443 T3 Code, 8443 Nextcloud (`trusted_proxies` = localhost, tailscaled sets X-Forwarded-For), 3000 Gitea (git over SSH: `gitea@raspberry-pi-4.<tailnet>`). sshd accepts the home LAN (`base-ssh-lan`; fail2ban ignores the LAN) and `tailscale0` (`rpi-ssh`). Ollama (`ollama.nix`) stays local.
- headscale cannot work behind a Cloudflare Tunnel (the Tailscale ts2021 control protocol needs a non-WebSocket `Upgrade`, juanfont/headscale#1468) and the home line is behind CGNAT without IPv6. Hosted Tailscale works (outbound only): laptop and RPi (`hosts/tailscale.nix`); one-time `sudo tailscale up --netfilter-mode=nodivert` per host (RPi also `--accept-dns=false`), unit `tailscale-prefs` re-applies these flags after every login.
- T3 Code (`t3code.nix`): `t3 serve` as system account `t3code` (no groups, sudo or secrets) on 127.0.0.1:3773, reachable only from the tailnet through Tailscale Serve (`https://<RPi>.<tailnet>.ts.net`, port 443). `t3code pair` prints a 5-minute pairing link + QR for that address; `t3code <command>` runs any `t3` command as `t3code`; agent login `sudo -u t3code -H claude auth login`. Tailnet login and admin console settings: the `hosts/tailscale.nix` header.
- T3 Code on the RPi sends sessions to the laptop (`hosts/t3code-laptop.nix`): the laptop's T3 desktop is served on `https://nixos.<tailnet>` (443 -> 127.0.0.1:3773, local connections only from root and `dinosaur`), the RPi gets the name from `networking.hosts` (`customTop.tailnet.laptop`; no MagicDNS there) and only `t3code` may open new connections over `tailscale0`. The tailnet policy (admin console) deliberately allows every device to every device, so the hosts hold the boundary (RPi `OUTPUT` owner rule, laptop `nixos-fw` with `nodivert`); the link is paired in T3 with an access level.
- `lockdown on` (`base-lockdown`) keeps tailscaled on the RPi, which carries SSH from the tailnet (stopping it would also cut the session that ran the command), and stops the Serve backends (nginx, Gitea, T3 Code), so the other tailnet ports answer 502. A CVE in tailscaled itself: stop `tailscaled` from the LAN. On the laptop lockdown stops tailscaled.
- Wi-Fi (`network.nix`): profile `home-wifi` from `wifi.age`, powersave off, regdom `PL`. Pitfall: with no secret agent, NetworkManager blocks the profile until reboot after a "no secrets" failure (`autoconnect-retries` does not cover it), so timer `home-wifi-reconnect` reactivates it every 5 min.

## Secrets (agenix)
- Recipients: `modules/_secrets/secrets.nix` (rules only — `*.age` entries), public keys in `modules/_secrets/keys.nix`. The laptop is a recipient of everything (secrets are edited there). Rekey after changing recipients: `cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519`.
- User secrets (`modules/hosts/base/secrets.nix`, through `base-agenix`; laptop and RPi only): owner `customBot.defaultUser`, mode `0400`. Service secrets: owned by the service user, or root `0400` when the service reads them via `LoadCredential`/`EnvironmentFile`. Never `group = "users"`.
- Never export secrets globally (shell init, `sessionVariables`). Inject per process: fish wrapper functions in `modules/hosts/base/agenix.nix` (`prime-agent`, `opencode`, `gemini`, `cachix-push`); nix `access-tokens` are rendered into `~/.config/nix/nix.conf` by the user unit `nix-access-tokens`.
- Never write secret values into `.nix` files (they end up in the world-readable store).
- Backups only, declared in no host: `brulion-android-keystore.age` (the release signing key of the Brulion Android app, env format with the CI secret names of `github:janusz-bit/brulion`), `brulion-fdroid-key.age` (the F-Droid signing key of Brulion) and `nextcloud-adminpass.age` (password of the existing Nextcloud `admin`; nixpkgs no longer creates an admin, see `rpi-nextcloud`). Restore: `sudo agenix -d <name>.age -i /root/.ssh/id_ed25519` in `modules/_secrets/`.

## Security invariants — do not regress
- `nix.settings.trusted-users` stays default (root only).
- No passwordless root paths for user or agent accounts (no `podman`/`docker` group, no NOPASSWD sudo for agents).
- `/etc/ai` (runtime skill drop-in) is `0755`, owned by `customBot.defaultUser`.
- Root never writes through paths an unprivileged account controls (no `chown`/`chmod`/`install`/merge as root inside a service account's state directory; use `setpriv` to the owner or symlink-safe `systemd-tmpfiles`).
- Runtime-fetched code is pinned: GitHub Actions (commit SHAs in `github-actions.nix`), MCP servers from nixpkgs rather than `uvx`/`uv run`.
- The RPi is less trusted than the laptop (it serves the whole tailnet: Nextcloud, Gitea, T3 Code): none of its keys log into the laptop, neither into `dinosaur` nor root; the one deliberate path to `dinosaur` is the paired T3 link from the RPi account `t3code` (`hosts/t3code-laptop.nix`: no other RPi account opens tailnet connections, access level chosen at pairing) — do not widen it; no `nix.buildMachines` to the laptop (it would need `trusted-users`).
- Tailscale (laptop, RPi): `netfilter-mode=nodivert` (the default `on` accepts all of `tailscale0` before `nixos-fw`), on the RPi also `accept-dns=false`; never `trustedInterfaces = [ "tailscale0" ]`, `tailscale set --operator` (it could enable Funnel) or Funnel. Only root (tailscaled) and `t3code` reach T3 locally (iptables owner rule; local connections to the node's own tailnet addresses are rejected).

## Binary caches
`nixConfig` in `flake.nix` is the only cache list: `janusz-bit.cachix.org`, `nixos-raspberrypi.cachix.org` (RPi vendor kernel; trusted on every host like any `nixConfig` cache). Hosts get the same lists in `nix.settings` through `customTop.nixConfig` (`modules/args.nix` imports `flake.nix`); `customTop.cachix` (own cache: `push`, CI) finds its key there. Input `nixConfig` is not inherited. When adding a cache, run the first rebuild with `--accept-flake-config`. Packages from `llm-agents` (prime-agent, opencode2, chatgpt) have no cache and build locally. `devenv.cachix.org` comes from `desktop-devenv` (`modules/desktop/devenv.nix`, part of the `desktop` aggregate) for devenv projects only, deliberately outside `nixConfig`.

## Development workflow
- Always work inside `nix develop` (installs pre-commit hooks: gitleaks, nixfmt, statix, deadnix, sync-github-actions, sync-docs). Claude Code: start it with the alias `claude-nixos` (`modules/desktop/ai.nix`) = `nix develop -c claude` in `/etc/nixos`; outside the dev shell the `.claude/` hooks silently do nothing.
- **Generated files:** `.github/workflows/*.yml` (`sync-github-actions`, from `modules/github-actions.nix` + host registry) and `docs/reference/*.md` (`sync-docs`, from `modules/docs.nix`). The pre-commit hooks run `nix run .#<generator>` on the working tree (no stale store path from shell entry); if a hook modifies files, `git add` them and commit again. Never edit generated files by hand.
- CI workflows (generated): `nixos` (PR + manual only, 3–5 h), `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl` (tags `v*`, PR), `eval` and `lint` (also on every push to `master`), `cachyos-kernel-update` (manual).
- `flake-update` updates `flake.lock` and local packages (`helium` and `waywallen` in two arch passes, `bootdev-cli`, `unsloth-desktop` — beta tags, so `--version=unstable` —, `opencharts` — no upstream tags, so `--version=branch` —, `strata` — its engine and llama.cpp pins are bumped by hand —, `rea-agents`; each package commits itself through `nix-update --commit`); `flake-release` tags `vN` and pushes; `repo-sync` commits everything, rebases and pushes; `package-import <attr>` copies a package directory from the pinned nixpkgs into `modules/packages/_<attr>/`, registers it in `localPackages` (it then replaces the nixpkgs one on every host) and stages it without committing.
- **Git (mandatory):** commit every change; style: short lowercase summary prefixed with the area (`nixos: …`, `rpi: …`, `docs: …`). Push to `origin` only after verification (below) — `update` on every host deploys straight from GitHub, so a push is a deployment: host `nixos` after a successful `update-local`; `raspberry-pi-4`/`wsl` (no local switch) after verification steps 1–2. Certain changes — every applicable verification step passed and nothing is left to test on the target host (refactors with unchanged derivations, docs, fixes already verified) — are committed on `master` and pushed directly, without a branch or PR. Experimental, large or uncertain changes (new services, wrappers, overlays): a branch + PR (CI `eval` and `lint` run on PRs), merged after testing on the target host.
- **Skills and models (`ai.*`):** like `programs.<x>.enable` in nixpkgs, a host only chooses and `modules/ai/` does the importing. Choice: `ai.skills.<name>.enable`, `ai.skillPacks.<name>.enable`, `ai.models.<name>.enable` in `hosts/<host>/ai.nix` (`base-ai` for what every host has, `nixos-ai`, `rpi-ai`). Catalogs (entries, not enabled): skills in `modules/ai/skills.nix` — the skill itself lives in `modules/skills/<name>/` (`SKILL.md` + `references/`; Python skills also `src/<pkg>/` + `pyproject.toml` and `python = true`); `agents` narrows a skill that one agent alone can run (Prime Agent's Python kernel, Claude Code hooks); `packages` are programs a skill calls (installed with the skill, not in a host module); providers and models in `modules/ai/models.nix` (one neutral schema, `ai/options.nix`). Import logic: `modules/ai/harness.nix` links enabled skills into the system skill directories (Prime Agent `/etc/ai-skills`, Claude Code managed `/etc/claude-code/.claude/skills`, Codex `/etc/codex/skills`, opencode2 `/etc/opencode/skills`; Antigravity has none), writes `prime-agent/models.json` and the managed `opencode/opencode.json` from enabled models (other opencode2 fields: `ai.opencode.settings` on the host), and gives the `prime-agent` wrapper the `PYTHONPATH` of Python skills. Prime Agent reads `/etc/ai-skills` and the runtime drop-in `/etc/ai` through `skills` in its `settings.json` (`base/prime-agent.nix`; earlier entry wins a name collision, so declarative skills win); runtime skills without a rebuild go to `/etc/ai/<name>/`. External skill packs (a repo whose `<dir>/<name>/SKILL.md` are skills, e.g. Qt Development Skills): a `flake = false` input in `flake.nix` + `nix flake lock`, then an entry in `ai.skillPacks` (`modules/ai/skills.nix`) and `enable` on the host; `flake-update` updates them with the other inputs (one pack: `nix flake update <input>`), and a name collision fails evaluation.
- Temporary upstream workarounds must get an entry in `temporary-fixes.md` with a removal condition.

## Verification (before every commit)
A change is done only when it has been checked as far as possible without root. Report which steps ran and which did not.
1. Evaluate every affected host: `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (`nixos`/`raspberry-pi-4` ~25 s, `wsl` ~8 s; aarch64 evaluates fine on x86_64). Changes in `hosts/base/`, `hosts/registry.nix`, `args.nix`, `options.nix`, `packages/` (overlay `local-packages`) or `flake.nix` affect all three hosts.
2. Generated configuration (`builtins.toJSON`, environment variables, systemd units, nginx config, Tailscale Serve map, wrapper scripts): evaluate and show the rendered value, e.g. `nix eval --raw .#nixosConfigurations.<host>.config.systemd.services.<svc>.environment.<VAR>`. Escaping and interpolation bugs pass step 1 and fail only at runtime.
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

- Module layout: every `.nix` file under `modules/` is a flake-parts module (import-tree). A NixOS module is exported as `flake.modules.nixos.<group>-<name>`, the group taken from its directory: `ai-*` (`ai/`), `base-*` (`hosts/base/`), `nixos-*`/`rpi-*`/`wsl-*` (`hosts/<host>/`, `rpi` = `raspberry-pi-4`), `desktop-*`, `gaming-*`, `hardware-<machine>[-<part>]`, `installer-*`; a directory's `default.nix` exports the bare aggregate (`base`, `nixos`, `hardware-LOQ-15IRX10`). Exceptions: shared hardware pieces (`hardware-lenovo`, `hardware-x86-64-v3`), and the cross-host `hosts/*.nix`, which export `nixos-<x>` + `rpi-<x>`. Scope: `hosts/<host>/` holds what makes that machine itself (identity, disk, boot, host-only services), `hardware/` what depends on the devices, `desktop/` and `gaming/` features any workstation may import, `hosts/base/` only what every host needs. Import modules explicitly in the host's `default.nix`. Anything that is not a flake-parts module (package definitions, hardware configs, vendored code, patches) **MUST** live under a `_`-prefixed path, otherwise import-tree imports it and evaluation breaks.
- Shell scripts: `pkgs.writeShellApplication` with `runtimeInputs` (shellcheck runs at build time). **NEVER** use `writeShellScriptBin`/`writeScript` for new scripts with logic; migrate old ones when you touch them anyway. Short scripts stay inline in the module; longer scripts and their helper files (shell, jq) go into a `_<feature>/` directory next to the module (import-tree skips `_` paths), loaded with `builtins.readFile` or a path literal — never loose `.sh`/`.jq` files next to the modules (pattern: `installer/install.nix` + `_install/`). `excludeShellChecks` only with a comment explaining why.
- Executables in units, wrappers and generated config: `lib.getExe pkg` / `lib.getExe' pkg "name"` instead of `${pkg}/bin/name` in new code.
- Generated config files: `builtins.toJSON` or `pkgs.formats.<json|yaml|ini|toml>`. **NEVER** build JSON/YAML/INI by string concatenation. Every value interpolated into shell **MUST** go through `lib.escapeShellArg`.
- Repo-wide constants (tailnet, user names, locale, LAN, e-mail, caches, repository URL) come from `config.customTop` (values in `modules/args.nix`, declaration in `modules/options.nix`; inside a NixOS module `config` is the NixOS one, which carries the same value through `base-options` — a NixOS configuration outside `base` imports `base-options` itself); host-dependent values from `customBot` options (`modules/hosts/base/options.nix`, always with `type` and `description`). **NEVER** duplicate those literals in modules.
- Runtime files and directories: `systemd.tmpfiles` rules or unit `StateDirectory`/`RuntimeDirectory`, not `mkdir`/`chown` in activation scripts.
- Invariants that would otherwise fail at runtime: `assertions` with an actionable message (pattern: `nextcloud.nix`). Degraded but valid configuration: `warnings` (pattern: `raspberry-pi-4/network.nix`).
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
- Paths: relative path literals (`./file`); a file in another module directory is `"${self}/modules/<dir>/<file>"`, not `../`. **NEVER** other string paths into the repo, `/home/…` or `/etc/nixos/…` in Nix code (exception: files consumed at runtime by programs outside Nix, documented where they are referenced, e.g. `M27Q.icm`).
- Three or more assignments with the same prefix in one attrset (`foo.a = …; foo.b = …;`) are nested into `foo = { … };` (statix `repeated_keys`).
- **NEVER** use emoji, or unicode that emulates emoji (e.g. ✓, ✗), in Nix code, scripts, comments or commit messages.
- **NEVER** commit commented-out code. The only exception is a disabled import with a pointer to its re-enable procedure.
- **NEVER** commit `builtins.trace`, `lib.traceVal` or debug `echo` lines.
- Vendored code keeps upstream style so it can be re-synced; changes there stay minimal and are listed in its header.

### Comments and documentation

- Comments explain **why**: upstream bug, measured effect, security reason, non-obvious Nix or module-system behaviour (priorities, `attrNamesToTrue` sorting, store-path reference scanning, `nixConfig` not inherited from inputs). Assume the reader knows NixOS well but not every nixpkgs internal.
- **MUST** avoid redundant comments which are tautological or restate the attribute name.
- **MUST** avoid comments which leak what this file contains, or leak the user's prompt.
- Match the language of the surrounding comments (most modules are commented in Polish). AGENTS.md, `SKILL.md` files and commit messages are in English.
- Every non-trivial module starts with a header comment at the top of the file: what it does, why it exists, how to verify or test it. Its first paragraph is the module's description in `docs/reference/modules.md`, so make it a self-contained summary (patterns: `modules/desktop/tuning.nix`, `modules/hosts/tailscale.nix`, `modules/checks/lockdown.nix`).
- Every temporary upstream workaround gets an entry in `temporary-fixes.md` (removal condition + upstream link) and a code comment pointing to it.
- **MUST** update AGENTS.md in the same commit when a change adds, removes or renames a host, service, secret, CI workflow, command or alias, or changes a rule, invariant or pitfall. The per-module catalog is generated (`docs/reference/`), so a new or renamed module needs a good header, not an AGENTS.md entry. AGENTS.md is a symlink to `GEMINI.md`: edit `GEMINI.md`. It stays a map; details belong in module headers.
- Non-trivial architecture: write the design down in `docs/design/` (Markdown with mermaid diagrams) before implementing. Once it is implemented, delete the document or move the lasting facts into the module header; plans and checklists are not kept in the repo. `docs/reference/` is generated (see Development workflow).

### Flake inputs and dependencies

- New inputs follow our nixpkgs (`inputs.nixpkgs.follows = "nixpkgs"`) unless they are built against their own nixpkgs (`nix-cachyos-kernel`, `llm-agents`); then say so in a comment next to the input.
- An input with its own binary cache: add the cache to `nixConfig` in `flake.nix` (see **Binary caches**).
- Adding or removing an input: `nix flake lock` (does not bump other inputs). Updating one input: `nix flake update <input>`. Full updates only through `flake-update`.
- Every fetcher has a real hash. **NEVER** commit `lib.fakeHash`.
- Flakes see only git-tracked files: `git add` new files before `nix eval`/`nix build`, otherwise they are silently missing.

### Local packages (`modules/packages/_<name>/default.nix`)

- `callPackage` style with `mkDerivation (finalAttrs: { … })` / `buildGoModule (finalAttrs: { … })`; sources from `fetchFromGitHub` with `tag = "v${finalAttrs.version}"` where upstream tags releases.
- `passthru.updateScript = nix-update-script { };` plus an entry in `flake-update` (`modules/packages/_scripts/flake-update.sh`) when the package should be bumped automatically.
- Make the package updateable by `nix-update`: `version = "…";` and `src` (with `tag = "v${finalAttrs.version}"`) must be attributes of the derivation returned as the package, never of a derivation hidden behind a wrapper (`writeShellApplication`) — only then nix-update finds their positions and replaces the hashes (a wrapper without them fails with `expected a set but found null`). Other pinned downloads are top-level attributes of that derivation too; what nix-update cannot derive from the tag (a release asset with its own numbering, a git rev from `setup.py`) stays a literal there and is bumped by hand, documented next to it and in `flake-update` (pattern: `_strata`, `--custom-dep` to refresh its hash) — never by a wrapper script.
- `versionCheckHook` + `doInstallCheck = true` when the binary supports `--version`.
- Complete `meta`: `description`, `homepage`, `license`, `mainProgram`, `platforms`; prebuilt binaries add `sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];`.
- Register the package in `localPackages` (`modules/packages/packages.nix`), which exports both the overlay and `packages.<system>.<name>`.
- Patch sources with `substituteInPlace --replace-fail` (fails loudly when upstream changes); `--replace-warn` only as a documented temporary fix.
- Reference example: `modules/packages/_bootdev-cli/default.nix`.

### Services and security

- New services you write: dedicated user or `DynamicUser`, `NoNewPrivileges`, `ProtectSystem = "strict"`, `ProtectHome`, `PrivateTmp`, minimal `ReadWritePaths`; secrets through `LoadCredential` or `EnvironmentFile` from agenix.
- RPi services bind to `127.0.0.1` or a Unix socket and are exposed only to the tailnet through Tailscale Serve (`customBot.tailscaleServe`). Firewall exposure is always explicit (`openFirewall` set deliberately).
- A service the network reaches other than through a port open in the firewall (Tailscale Serve, its own outbound connections, radio) adds itself to `customBot.lockdownServices` in its module, so `lockdown on` stops it; open firewall ports `lockdown` closes by itself.
- **NEVER** read or print decrypted secrets (`/run/agenix*`). **NEVER** put secret values in `.nix` files, unit `Environment=`, command lines (visible in `ps`) or logs.
- **NEVER** weaken the firewall, SSH, sudo, `trusted-users` or a unit's sandboxing to make something work. Find the narrow fix, or stop and ask.

### Evaluation and build cost

- The RPi is slow (`max-jobs = 2`): evaluate only the hosts a change affects. never build x86_64 hosts locally on the RPi.
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
lockdown on / off / status                         # nixos, RPi: cut off everything but SSH (CVE without a fix yet) / restore; persists across reboot and update
nix run github:janusz-bit/nixos -- [--disk DEV]    # install-system (live ISO), see below
nix run /etc/nixos#post-install [ssh|secure-boot]  # after install: agenix root key, Secure Boot enrollment
nix build .#raspberry-pi-4-sd-image
```

`install-system` (`modules/installer/install.nix`) wipes the chosen disk (`--disk` or a picker) and installs the flake revision it was started from; it needs no keys (agenix decrypts nothing and Secure Boot stays off until `post-install`). `post-install ssh` (any host; named by `uname -n`) writes the root key (`hosts.<host>`) into `keys.nix` or prints the line to add; then re-encrypt the secrets on another recipient. `post-install secure-boot` is for the laptop's Insyde firmware only. Flow: `install.nix` header.
