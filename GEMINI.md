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
- `modules/packages/` — overlay `local-packages` (`waywallen`, `waywallen-kde-plugin`, `bootdev-cli`; also exposed as `packages.<system>.*` for `nix-update`), scripts (`flake-update`, `flake-release`, `repo-sync`), `install-system`, `post-install`, `nixos-iso` (bootable installer ISO), RPi SD image.
- `modules/skills/` — declarative Prime Agent skills.
- `modules/github-actions.nix` — generates `.github/workflows/*.yml`.
- `temporary-fixes.md` — tracker of upstream workarounds (active / closed).

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
- Helium Browser (`helium.nix`) comes from the flake input `helium-browser` (`github:ominit/helium-browser-flake`, follows our `nixpkgs`); version bumps arrive with `nix flake update`.
- SSH reachable only from `customTop.lan.subnet` (iptables rule; `openFirewall = false`).
- zram (zstd) with zswap disabled (`zswap.enabled=0`; the CachyOS kernel enables it by default → double compression).
- Gaming (`gaming.nix`: Steam + proton-cachyos from chaotic, `ntsync` module, gamemode with renice and power-profiles-daemon `performance` while a game runs, `dbdrun`), podman (rootless use; user is intentionally **not** in group `podman`).
- VFIO (`vfio.nix`) is **disabled** (commented import in `nixos/default.nix`). If re-enabled: never pass a `by-path` value (contains `:`) to `KWIN_DRM_DEVICES` (KWin splits on `:` and crashes); `virtualisation.libvirtd.qemu.ovmf` no longer exists; use `virsh -c qemu:///system`; ISOs go to `/var/lib/libvirt/images/`.

### `raspberry-pi-4` (server)
- Imports the full base; overrides: GC daily/3d, `max-jobs = 2`, `documentation.doc.enable = false`, `PermitRootLogin = "prohibit-password"` (admin path: `ssh ssh.janusz-bit.com` as root via cloudflared), no ssh-askpass.
- RPi vendor kernel with `PREEMPT_LAZY n` (`temporary-fixes.md`).
- Services (all bound to localhost, exposed only through the tunnel `modules/hosts/raspberry-pi-4/cloudflared.nix`): Nextcloud 35 (Postgres, Redis, PHP-FPM `ondemand`), Open WebUI behind nginx (8080 → 3001), Trilium 8081, Gitea 3000, ttyd 8082 behind nginx Basic Auth 8083, SSH.
- Hermes Agent (`hermes.nix`): runs as `hermes` without sudo, `wheel`, `disk`, `keys` or Nix trust; sharing with user `nixos` via the upstream 2770/UMask 0007 state dirs. Main model = Claude Code subscription through the `claude-subscription-directsdk` plugin (`extraPlugins`, commit from the Hermes plugin catalog); one-time login on the RPi: `sudo -u hermes -H claude auth login`. Fallbacks: `openai-codex`, then `ollama-cloud`.

## Secrets (agenix)
- Recipients: `modules/_secrets/secrets.nix` (rules only — `*.age` entries), public keys in `modules/_secrets/keys.nix`. The laptop is a recipient of everything (secrets are edited there). Rekey after changing recipients: `cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519`.
- User secrets (`modules/agenix/agenix.nix`): owner `customBot.defaultUser`, mode `0400`. Service secrets: owned by the service user, or root `0400` when the service reads them via `LoadCredential`/`EnvironmentFile`. Never `group = "users"`.
- Never export secrets globally (shell init, `sessionVariables`). Inject per process: fish wrapper functions in `modules/hosts/base/agenix.nix` (`prime-agent`, `opencode`, `gemini`, `cachix-push`); nix `access-tokens` are rendered into `~/.config/nix/nix.conf` by the user unit `nix-access-tokens`.
- Never write secret values into `.nix` files (they end up in the world-readable store).

## Security invariants — do not regress
- `nix.settings.trusted-users` stays default (root only).
- No passwordless root paths for user or agent accounts (no `podman`/`docker` group, no NOPASSWD sudo for agents).
- `/etc/ai` (runtime skill drop-in) is `0755`, owned by `customBot.defaultUser`.
- Runtime-fetched code is pinned: opencode plugins (commit/version in `opencode.nix`), GitHub Actions (commit SHAs in `github-actions.nix`), Hermes plugins (commit in `hermes.nix`), MCP servers from nixpkgs rather than `uvx`/`uv run`.
- ttyd credentials never on a command line (nginx `auth_basic` with a hash file generated from the agenix secret).

## Binary caches
`customTop.cache` (→ `nix.settings`) and `nixConfig` in `flake.nix` must list the same caches: `janusz-bit.cachix.org`, `attic.xuyh0120.win/lantian` (CachyOS kernel), `cache.numtide.com` (llm-agents). Input `nixConfig` is not inherited. When adding a cache, run the first rebuild with `--accept-flake-config`.

## Development workflow
- Always work inside `nix develop` (installs pre-commit hooks: gitleaks, nixfmt, statix, deadnix, sync-github-actions).
- **Stale hook pitfall:** the `sync-github-actions` hook points at the store path built when the shell was entered. After editing `modules/github-actions.nix`, re-enter `nix develop`, or run `nix run .#sync-github-actions` and commit with `SKIP=sync-github-actions`.
- CI workflows (generated): `nixos` (PR + manual only, 3–5 h), `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `nixos-iso`, `wsl` (tags `v*`, PR), `eval` and `lint` (also on every push to `master`), `cachyos-kernel-update` (manual).
- `flake-update` updates `flake.lock` and local packages (`waywallen` in two arch passes, `bootdev-cli`) and commits; `flake-release` tags `vN` and pushes; `repo-sync` commits everything, rebases and pushes.
- **Git (mandatory):** finish every change with a commit and a push to `origin`. Commit style: short lowercase summary prefixed with the area (`nixos: …`, `rpi: …`, `docs: …`).
- **Skills:** store in `modules/skills/<name>/` (`SKILL.md` + `references/`; Python skills also `src/<pkg>/` + `pyproject.toml` and an entry in `pythonSkills`) and register in `modules/skills/default.nix`. Python skill sources reach the kernel through the `prime-agent` wrapper's `PYTHONPATH`. Runtime skills without a rebuild go to `/etc/ai/<name>/` (auto-linked by `prime-agent-skills-import`).
- Temporary upstream workarounds must get an entry in `temporary-fixes.md` with a removal condition.

## Commands
```sh
sudo nixos-rebuild switch --flake .#nixos          # or .#raspberry-pi-4 / .#wsl
update / update-boot                               # remote flake (github:janusz-bit/nixos), --refresh
update-local / update-local-boot                   # /etc/nixos
push                                               # fish: build toplevel and push closure to cachix
nix run github:janusz-bit/nixos -- [--disk DEV]    # install-system (live ISO), see below
nix run /etc/nixos#post-install [ssh|secure-boot]  # after install: agenix root key, Secure Boot enrollment
nix build .#raspberry-pi-4-sd-image
nix build .#packages.x86_64-linux.nixos-iso           # custom installer ISO for host nixos
```

`install-system` (`packages.default`, `modules/packages/install.nix`) runs from a live ISO (stock ISO: `nix --extra-experimental-features 'nix-command flakes' run …`), wipes the target disk and installs the flake revision it was started from (`nix run .` = local tree); `/etc/nixos` gets a clone of origin. Target: `--disk DEV` or a picker (Enter = disko.nix device); another disk gets its disko script via `extendModules` (like `disko-install --disk`), the system itself is unchanged (mounts use `by-partlabel/disk-main-*`), so it refuses while another disk carries those labels. It needs no keys: limine-install generates sbctl keys, Secure Boot stays off in the firmware and agenix decrypts nothing until `post-install` (`modules/packages/post-install.nix`): `ssh` generates `/root/.ssh/id_ed25519` and writes it into `keys.nix` (then rekey on raspberry-pi-4, the other recipient of every secret), `secure-boot` runs the Insyde enrollment procedure above (asks for Setup Mode, restores dbx).

`nixos-iso` (`modules/packages/iso.nix`) is the bootable-media version of the same flow: a stock `installation-cd-minimal.nix` installer with flakes pre-enabled and `install-system` pre-installed, so booting the ISO and running `install-system [--disk DEV]` as root (no password) is the whole flow — no `nix run github:...` or `--extra-experimental-features` needed. It still needs network (install-system clones the repo from GitHub and `nixos-install`s it). Legacy `isoImage.isoBaseName` collides with the new `image.baseName` default in `iso-image.nix` (both land at the same priority → "conflicting definition values") — set `image.baseName` directly with `lib.mkForce` instead. Write to USB: `dd` the file under `result/iso/*.iso`, or mount it in Ventoy.
