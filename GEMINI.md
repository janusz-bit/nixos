# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS**, **Nix Flakes**, and **Home Manager**. Your task is to assist in maintaining, refactoring, and developing this repository (dotfiles).

# NixOS Configuration Flake

## Project Overview
This repository contains a centralized, declarative NixOS system configuration architecture using Nix Flakes. The project defines environments and manages state across multiple hardware architectures, specifically supporting `x86_64-linux` and `aarch64-linux` platforms. The codebase structures Nix modules dynamically using `flake-parts` and `vic/import-tree`.

Integrated technologies handling the system's core capabilities include:
* **Home Manager**: Manages user-specific environments and dotfiles.
* **Agenix**: Handles encrypted system secrets (SSH-key based, age-encrypted).
* **Cachix**: External Nix binary cache (`janusz-bit.cachix.org`).
* **Disko**: Automates disk partitioning and formatting (encrypted Btrfs with LUKS).
* **NixOS-WSL**: Provides configurations for Windows Subsystem for Linux.
* **nvf**: Declarative Neovim configuration framework.
* **nixos-avf**: NixOS support for Android Virtualization Framework.
* **nixos-raspberrypi**: RPi-specific hardware support (`github:nvmd/nixos-raspberrypi`).
* **nixos-hardware**: Common hardware modules (`github:NixOS/nixos-hardware/master`).
* **nix-cachyos-kernel**: CachyOS kernel packages (`github:xddxdd/nix-cachyos-kernel/release`).
* **chaotic (Chaotic-Nyx)**: Bleeding-edge packages and binary cache (`github:chaotic-cx/nyx/nyxpkgs-unstable`). Provides `proton-cachyos_x86_64_v3`, `proton-ge-custom`, `mangohud_git`, `linux_cachyos` etc.; its `nixosModules.default` adds the nyx overlay, registry and the `nyx-cache.chaotic.cx` substituter. Applied to the `nixos` host only.
* **github-actions-nix**: Auto-generates GitHub Actions workflows (`github:synapdeck/github-actions-nix`).
* **hermes-agent**: Hermes AI agent NixOS module (`github:NousResearch/hermes-agent`). Now unpinned (tracks upstream); a comment in `flake.nix` records the previous pin (`3f2a389c...`) made because `topup.ts` introduced a broken `@hermes/shared/charge-settlement` import in `nix/tui.nix`.
* **Gitea**: Self-hosted Git service with web UI and SSH access (`git.janusz-bit.com`).
* **TriliumNext**: Note-taking server and desktop client (pinned to specific commit `744646d07bff459d1db305b1c0a8ea0c99b9c27c`).
* **Pre-commit Hooks**: Enforces formatting (`nixfmt`), linting (`statix`, `deadnix`) and workflow sync. The same checks run in CI via `checks.<system>.pre-commit` (built by the `lint` workflow).

## System Architectures & Host Deployments
The `modules/hosts/` directory contains isolated definitions targeting different deployment vectors. Each host is built upon a shared foundation but customized for its specific role.

### 1. `base` (The Foundation)
A shared set of modules included in every system deployment (`modules/hosts/base/default.nix`).
* Sets up the core CLI experience: `bash` is set as the login shell (to avoid compatibility issues like broken recovery environments), but automatically `exec`s `fish` for interactive sessions. Includes custom aliases (`eza`, `bat`, `fastfetch`), the `done` fish plugin for long-command notifications.
* Configures fundamental services: Git defaults, SSH security (key-only authentication), Agenix secrets handling, core Nix settings, `vulnix` vulnerability scanning.
* Shared packages (`modules/hosts/base/configuration.nix`): `micro-full`, `nil`, `nixd`, `nixfmt-tree`, `uv`, `toybox`, `statix`, `kdePackages.kleopatra`, `cachix`, `agenix`, `nix-update`, `tlrc`, `fzf`, `hw-probe`, `htop`, `cloudflared`, `gemini-cli`, `vulnix`.
* Shell packages (`modules/hosts/base/shell.nix`): `fish`, `fishPlugins.done`, `eza`, `bat`, `hw-probe`, `fastfetch`.
* `nix-ld` enabled to support dynamically linked binaries (e.g., from `uv`).
* `nix-index-database` with `comma` integration.
* `direnv` enabled.
* `environment.localBinInPath = true` (recommended for `uv`-installed binaries in `~/.local/bin`).
* Default editor: `micro`.
* **OpenCode**: Declarative configuration inline in `modules/overlays/opencode.nix` (Nix overlay generating `opencode.json` + `web-search-mcp.py` at build time). Default model: `llmgateway/claude-sonnet-4-6`. Plugins: `superpowers` (`superpowers@git+https://github.com/obra/superpowers.git`) and `caveman-opencode-plugin`; `websearch` permission set to `allow`. Provider `llmgateway` (OpenAI-compatible, `https://api.llmgateway.io/v1`, apiKey from `{env:LLMGATEWAY_API_KEY}`) with models `claude-sonnet-4-6`, `gpt-5.5`, `gemini-3.1-pro`, `qwen3.8-max`, `kimi-k3`, `glm-5.2`. Provider `ollama` (OpenAI-compatible, `http://localhost:11434/v1`) with model `ornith:35b`. Provider `ollama-cloud` (OpenAI-compatible, `https://ollama.com/v1`, apiKey from `{env:OLLAMA_API_KEY}`) with model `glm-5.2:cloud`. Provider `opencode` (OpenCode Cloud, `https://api.opencode.ai/v1`, apiKey from `{env:OPENCODE_GO_API_KEY}`) with models `glm-5.2`, `kimi-k3`. Local MCP servers: `web_search_and_fetch` via `uv run` (Ollama web_search/web_fetch API) and `nixos` via `pkgs.mcp-nixos` (`lib.getExe`; NixOS/Home Manager/nixpkgs/flakes/wiki search tools). The `opencode-config` overlay is applied in `base/configuration.nix`, so the wrapped `opencode` is available on all hosts.
* **Nix settings** (`modules/nix-settings.nix`): Weekly GC (delete older than 7d), auto-optimise-store, trusted-users = `@wheel`.
* **Git** (`modules/hosts/base/git.nix`): user.name = `janusz-bit`, user.email = `janusz-bit@proton.me`, init.defaultBranch = `main`, `gh:` and `github:` rewritten to `https://github.com/`. `gh` CLI installed.
* **SSH** (`modules/hosts/base/ssh.nix`): Key-only authentication, `ssh.startAgent = false`, `gnupg.agent.enable = true`. Cloudflared SSH proxy configured (`ssh.*` host pattern uses `cloudflared access ssh --hostname %h`).
* **Agenix** (`modules/hosts/base/agenix.nix`): Exports `CACHIX_AUTH_TOKEN`, `GITHUB_TOKEN`, `OLLAMA_API_KEY`, `GOOGLE_API_KEY`, `OPENCODE_GO_API_KEY` (from `opencode.age`), and `NIX_CONFIG` (access-tokens for `github.com`) via `environment.shellInit` from age-encrypted secrets; additionally sources the `llmgateway-api-key.age` env-file (exports `LLMGATEWAY_API_KEY`).
* **DNS**: Quad9 nameservers (`9.9.9.9`, `149.112.112.112`, `2620:fe::fe`, `2620:fe::9`) configured in base.
* **ZFS**: `boot.zfs.forceImportRoot = false` explicitly set in base to silence the 26.11 evaluation warning (ZFS module pulled in by default even when not in use).
* **Firewall**: Enabled, allows TCP port 22.

#### Shell Aliases (all hosts)
| Alias | Command |
|---|---|
| `update` | `sudo nixos-rebuild switch --sudo --flake <remote-flake>#<target> --refresh` |
| `update-boot` | `sudo nixos-rebuild boot --sudo --flake <remote-flake>#<target> --refresh` |
| `update-local` | `sudo nixos-rebuild switch --sudo --flake <local-flake>#<target>` |
| `update-local-boot` | `sudo nixos-rebuild boot --sudo --flake <local-flake>#<target>` |
| `push` | Build toplevel and push closure to Cachix via `nix build ... \| cachix push ...` |
| `update-my-pkgs` | `nix run <flake>#update-flake` |
| `ls`, `la`, `ll`, `lt`, `l.` | `eza` variants |
| `..`, `...`, `....` | Directory navigation |
| `cat` | `bat` |
| `hw` | `hwinfo --short` |

#### GPU Aliases (`nixos` host only, via `modules/hosts/nixos/gpu.nix`)
| Alias | Command |
|---|---|
| `update-passthrough` | `sudo nixos-rebuild switch --sudo --specialisation gpu-passthrough --flake <remote-flake>#nixos --refresh` (reboot required to take effect) |
| `update-passthrough-local` | Same as above with local `/etc/nixos` flake |
| `gpu-status` | `gpu status` (drivers of both PCI functions + boot mode) |
| `gpu-vfio` | `gpu vfio` (runtime: rebind GPU to vfio-pci) |
| `gpu-host` | `gpu host` (runtime: rebind GPU back to nvidia) |

### 2. `nixos` (Main Workstation)
An `x86_64-linux` deployment for a **Lenovo LOQ-15IRX10** laptop (Nvidia GPU, Polish locale). Default user: `dinosaur`.
* **Kernel**: CachyOS kernel (`linuxPackages-cachyos-latest-lto-x86_64-v3`) via the `nix-cachyos-kernel` input.
* **Storage**: Disko-managed encrypted Btrfs with LUKS on `/dev/nvme1n1`. Partitions: 6G ESP (vfat `/boot`), 36G LUKS swap, rest LUKS+Btrfs (`/root`, `/home`, `/nix` subvolumes, `compress=zstd`, `noatime`). Working hibernation configured (`/dev/mapper/swap`).
* **Bootloader**: Limine, with a Windows EFI dual-boot entry. `efi.canTouchEfiVariables = true`.
* **binfmt emulation**: `aarch64-linux` emulated systems enabled (`boot.binfmt.emulatedSystems`).
* **Supported filesystems**: `btrfs` explicitly listed.
* **Desktop**: KDE Plasma 6 (Wayland) with SDDM (Wayland, autoNumlock). A **Niri** module exists (`nixos/niri.nix`) but is currently commented out/disabled.
* **Audio**: Pipewire (with ALSA 32-bit and PulseAudio compat).
* **Scheduler**: `scx` with `scx_lavd` (`--performance`).
* **Specialisations** (boot-time profiles):
  * `power-save` – full TLP settings (incl. battery conservation mode), thermald, UPower (percentage policy, hibernate on critical), `powersave` governor, WiFi powersave, power-saving kernel params, logind lid/idle suspend, scx `--powersave`.
  * `reverse-sync` – Nvidia Prime Reverse Sync.
  * `sync-mode` – Nvidia Prime Sync.
  * `gpu-passthrough` – PCI passthrough (VFIO) for the dGPU: `intel_iommu=on` + `vfio-pci.ids=10de:2d59,10de:22eb` kernel params, `vfio_pci`/`vfio`/`vfio_iommu_type1`/`i915` initrd modules, `nvidia*` modules blacklisted, `hardware.facter.detected.graphics.enable = false` (prevents facter from injecting `nvidia` into initrd before vfio), X server on iGPU (`modesetting`), libvirtd (qemu_kvm, runAsRoot, swtpm), spiceUSBRedirection, virt-manager, user in `libvirtd` group. See https://wiki.nixos.org/wiki/PCI_passthrough.
* **GPU management** (`modules/hosts/nixos/gpu.nix` + `gpu.sh`): `gpu` command (wrapped shell script, runtime deps `pciutils`/`libvirt`/`kmod`/`coreutils`/`gnugrep` pinned in PATH; `sudo` intentionally left to the setuid wrapper) for the RTX 5060 Laptop GPU (VGA `0000:01:00.0` 10de:2d59 + audio `0000:01:00.1` 10de:22eb): `gpu status` (drivers + boot mode), `gpu vfio` (runtime rebind to vfio-pci), `gpu host` (runtime rebind back to nvidia), `gpu attach <vm>` / `gpu detach <vm>` (virsh hotplug of both PCI functions). Host-only aliases: `update-passthrough` (`nixos-rebuild switch --specialisation gpu-passthrough`, remote), `update-passthrough-local` (local `/etc/nixos`), `gpu-status` / `gpu-vfio` / `gpu-host`. Aliases defined via `environment.shellAliases`, auto-propagated to fish by nixpkgs.
* **Gaming** (`modules/hosts/nixos/gaming.nix`): Steam (with Proton-CachyOS x86-64-v3 and proton-ge-bin as extraCompatPackages — Proton now comes from the chaotic-nyx overlay/binary cache, gamescope session, protontricks), Heroic, Lutris, GameMode (renice -10, softrealtime, `performance` governor while gaming, screensaver inhibited), Gamescope (`capSysNice`), MangoHud, OBS Studio (CUDA), Mullvad VPN, Wooting keyboard support. `protonup-qt` for Proton management. Gaming sysctls: `vm.max_map_count=2147483642`, `kernel.split_lock_mitigate=0`.
* **AppImage support** (`modules/hosts/nixos/appimage-run.nix`): `programs.appimage` enabled with binfmt registration. Custom extra packages: `icu`, `libxcrypt-legacy`, `python312`, `python312Packages.torch`.
* **Containers**: Podman with Docker compatibility, DNS enabled.
* **AI Tools** (`modules/hosts/nixos/ai.nix`): Ollama (temporarily uses the `ollama` package from the `nixpkgs-stable` input), Open WebUI currently **disabled** (`enable = false`), `uv`, `repomix`, Node.js, Python 3 with pip.
* **Apps**: Zed, Brave, Firefox, LibreOffice (`libreoffice-qt`), Vesktop, Signal, Element, Tor Browser, qBittorrent-enhanced, Trilium, Joplin, Nextcloud client, PrismLauncher, Lutris, VLC, Haruna, Elisa, Kdenlive, Alacritty, sbctl, bootdev-cli, ungoogled-chromium, foliate (ebook reader), OpenCode, Prime Agent (self-improving AI coding agent), losange, KDE Partition Manager, KDE QRCA, KDE KCalc, `sqlite`, `protonup-qt`.
* **Compilers & build tools**: `cmake`, `ninja`, `clang`, `clang-tools`, `lldb`, `boost`, `wine64`, `pkgs.pkgsCross.mingwW64.buildPackages.gcc` (MinGW cross-compiler).
* **Gitea CLI**: `tea` installed (for interacting with `git.janusz-bit.com`).
* **Sync**: Syncthing (user data in `~/Sync`).
* **Overlays applied**: `nix-cachyos-kernel` (kernel overlay), `brave-debloater` (browser policies), `prime-agent` (exposes the custom Prime Agent package from `modules/packages/_prime-agent`), `chaotic-nyx` (bleeding-edge packages: proton-cachyos_x86_64-v3 etc., via `chaotic.nixosModules.default`).
* **Other services**: Avahi (mDNS), Flatpak, Btrfs autoScrub, CUPS printing (splix driver, Samsung ML-2160 preconfigured), Bluetooth, rtkit.
* **Security**: fail2ban (max 5 retries, LAN whitelisted).
* **Locale**: Polish (`pl_PL.UTF-8`), timezone `Europe/Warsaw`, keymap `pl2`.
* **State version**: `25.11`.
* **Hardware** (`modules/hardware/LOQ-15IRX10.nix`): Nvidia Prime offload (intelBusId `PCI:0:2:0`, nvidiaBusId `PCI:1:0:0`), `nixos-hardware` modules for Intel CPU/GPU, Nvidia GPU, laptop, SSD. `facter.json` report. `x86-64-v3` architecture optimization (`modules/hardware/architectures/x86-64-v3.nix`).

### 3. `raspberry-pi-4` (Home Server / Cloud)
A headless `aarch64-linux` deployment for network services. Default user: `nixos`.
* **Kernel**: Custom RPi vendor kernel from `nixos-hardware` via `callPackage` with `argsOverride` injecting `PREEMPT_LAZY n` (workaround for kconfig conflict with nixpkgs `common-config.nix` on kernel >= 6.18). `boot.initrd.allowMissingModules = true` (fix for missing `dw-hdmi` module).
* **Memory optimization**: zRAM (`zstd`), 8GB SSD swap (`/var/lib/swapfile`), `vm.swappiness=100`, tmpfs for `/tmp`.
* **CPU**: `ondemand` governor.
* **Security**: fail2ban (max 5 retries, LAN whitelisted), SSH key-only.
* **Nix GC**: daily, deletes derivations older than 3 days; max 2 build jobs. `documentation.doc.enable = false` (workaround for sphinx/docutils build failure). Trusted users include `hermes`.
* **Networking**: NetworkManager enabled. Timezone `Europe/Warsaw`.
* **User SSH keys**: Authorized keys imported DRY from `secrets.nix` (same public keys used for age encryption).
* **Nextcloud 34**: PostgreSQL backend (locally created, tuned: 128MB shared_buffers, 4MB work_mem, 32MB maintenance_work_mem, 256MB effective_cache_size), Redis cache, 2GB upload limit, PHP-FPM pool tuned for 4GB RAM (`pm = dynamic`, max_children 24, opcache interned strings 16MB), accessible **only via Cloudflare Tunnel** (no open ports, HSTS enabled). Trusted proxies: `127.0.0.1`, `::1`.
* **Hermes Agent** (`modules/hosts/raspberry-pi-4/hermes.nix`): AI agent service (`services.hermes-agent`) on port 8642. Uses `qwen3.8-max` model via LLM Gateway (`https://api.llmgateway.io/v1`, key from `LLMGATEWAY_API_KEY`), `ddgs` as the web backend. `require_approval = false`. `agent.reasoning_effort = "max"`. `auxiliary.vision` configured with `qwen3.8-max` via LLM Gateway. `addToSystemPackages = true`. `restart = "always"`, `restartSec = 5`. Extra packages: `uv`, `nodejs_22`, `ripgrep`, `ffmpeg`, `python311`. Extra dependency groups: `all`, `messaging`, `matrix`. Configured MCP servers: `trilium-notes` (HTTP at `127.0.0.1:8081/mcp` with Bearer token) and `nixos` (`uvx mcp-nixos`). Environment loaded from `hermes-env.age` and `llmgateway-api-key.age` (agenix). Sudo NOPASSWD for user `hermes` (ALL). Service hardening overrides: `NoNewPrivileges = false` (enables sudo), `UMask = 0027` (group-readable files for `nixos` user in `hermes` group), `ExecStartPre` cleans stale lock/pid/state files. User `hermes` in groups: `users`, `keys`, `wheel`, `systemd-journal`, `disk`. User `nixos` added to `hermes` group.
* **Open WebUI** (`modules/hosts/raspberry-pi-4/open-webui.nix`): Open-source AI chat interface on port 3001 (localhost only), fronted by an **nginx reverse proxy on port 8080** (cloudflared ingress target) with static-asset caching (`proxy_cache`, immutable `Cache-Control` headers, gzip, response buffering). Connects to two OpenAI-compatible backends via semicolon-separated multi-endpoint lists (`ENABLE_OPENAI_API = "true"`, `OPENAI_API_BASE_URLS = "http://127.0.0.1:8642/v1;https://api.llmgateway.io/v1"`): index 0 = Hermes Agent (`127.0.0.1:8642/v1`), index 1 = LLM Gateway devpass (`api.llmgateway.io/v1`). Keys paired by index in `OPENAI_API_KEYS` from the age-encrypted `open-webui-keys.age` (appended to the service via a second `systemd.serviceConfig.EnvironmentFile`, kept out of `environment {}` so they never enter the world-readable nix store). Ollama API disabled (`ENABLE_OLLAMA_API = "false"`). Auth required (`WEBUI_AUTH = "True"`). `ENABLE_PERSISTENT_CONFIG = "False"` (env vars override DB-stored values). Stateful Responses API enabled. Session/auth cookies set to `Secure` + `SameSite=none` (required behind Cloudflare Tunnel TLS termination). Shared Hermes API key via `hermes-env.age`.
* **Ollama**: Local LLM backend (`services.ollama.enable`), EnvironmentFile from `hermes-env.age`.
* **Gitea** (`modules/hosts/raspberry-pi-4/gitea.nix`): Self-hosted Git service on port 3000 (localhost only). SQLite database. Domain `git.janusz-bit.com`. Registration disabled. Cookie secure enabled. SSH access via system SSH (port 22, `START_SSH_SERVER = false`). `tea` (Gitea CLI) installed in system packages.
* **Cloudflared**: Tunnel to expose services externally (root and `chat.` hosts get `originRequest` tuning: `connectTimeout = 300s`, keepalive settings, to survive long photo uploads / slow LLM streams):
  * `${customTop.site.full}` -> Nextcloud (localhost:80)
  * `chat.${customTop.site.full}` -> Open WebUI via nginx (localhost:8080)
  * `notes.${customTop.site.full}` -> Trilium (localhost:8081)
  * `ssh.${customTop.site.full}` -> SSH (localhost:22)
  * `git.${customTop.site.full}` -> Gitea (localhost:3000)
* **Trilium**: Note-taking server on port 8081 (flake input `trilium` pinned to specific commit, used as `trilium-server` NixOS module — not an overlay).
* **Fan control**: Custom Python-based systemd service (`pwm-fan`, `rpi-lgpio` package with `RPI_LGPIO_REVISION` override) for GPIO PWM fan control based on CPU temperature (GPIO BCM pin 14, thresholds: 60C=100%, 48C=50%, else 0%).
* **LED control** (`modules/hosts/raspberry-pi-4/leds-off.nix`): All LEDs disabled via DT overlays (`hardware.raspberry-pi."4".leds` — eth, act, pwr) and systemd-tmpfiles rules (mmc0, default-on).
* **Overlays applied**: None host-specific (only `opencode-config` from base).
* **State version**: `26.05`.

### 4. `wsl` (Windows Subsystem for Linux)
A minimal `x86_64-linux` environment bridging NixOS into a Windows host.
* Uses `NixOS-WSL` module (`wsl.enable`, `useWindowsDriver`, `startMenuLaunchers`).
* Default user: `nixos`.
* `fastfetch` disabled.
* `zed-editor-fhs` and `opencode` installed.
* `ZED_ALLOW_EMULATED_GPU = "1"` session variable for Zed GPU emulation.
* Obsidian module available but currently commented out.
* **State version**: `25.05`.

### 5. `droid` (Android Virtualization Framework)
A reduced `aarch64-linux` footprint for Android (via `nixos-avf`).
* Includes `base` modules; `fastfetch` and visual elements disabled.
* Default user: `droid`.
* `ollama` package installed.
* Fixes bogus terminal size (`$COLUMNS=131072`) on Android/AVF at bash init.
* `custom.flakeTarget = "droid"`.
* **State version**: `26.05`.

## Repository Architecture
The repository uses a highly modular structure powered by `flake-parts` and `import-tree`, which auto-discovers and maps the codebase logically.

* **`flake.nix`**: Entry point. Defines all external inputs and passes them to `import-tree` to dynamically load the `modules/` folder. Declares the `janusz-bit.cachix.org` binary cache.
* **`modules/args.nix`**: Defines `customTop` arguments passed to all modules. Contains: repository info (`github:janusz-bit/nixos`, `/etc/nixos`), email (`janusz-bit@proton.me`), site domain (`janusz-bit.com`), Cachix cache info, `secretsDir`.
* **`modules/options.nix`**: Custom NixOS options (`customBot`): `flakeTarget` (default: `"default"`), `enableFastfetch` (default: `true`), `defaultUser` (default: `"nixos"`).
* **`modules/default.nix`**: Integration module. Defines `systems` (`x86_64-linux`, `aarch64-linux`), `devShells`, formatter (`nixfmt-tree`), pre-commit hooks (`nixfmt`, `statix`, `deadnix`, `sync-github-actions`), and exposes `update-flake` and `flake-release` packages in the dev shell.
* **`modules/github-actions.nix`**: CI/CD factory that auto-generates GitHub Actions workflows. Generates 7 workflows from a config map: `nixos`, `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl`, `droid` (build on tag push `v*` / PR to master), `lint` (builds `checks.x86_64-linux.pre-commit` — nixfmt/statix/deadnix + workflow sync), `cachyos-kernel-update` (manual `workflow_dispatch` only — daily cron currently commented out). The separate `build-kernel` job machinery exists but is currently disabled (kernel built manually, not in CI). Maps `x86_64-linux` to `ubuntu-latest`, `aarch64-linux` to `ubuntu-24.04-arm`. The sync script deletes orphaned workflow files before copying, so a refactor cannot leave stale YAML behind.
* **`modules/hardware/`**: Hardware-specific profiling. Stores Lenovo LOQ-15IRX10 patches, `x86-64-v3` CPU optimization, `M27Q.icm` color profile, and a `facter.json` inventory.
* **`modules/agenix/` & `modules/_secrets/`**: Cryptographic secrets. 15 age-encrypted files (GitHub token, Cachix token, Cloudflare tunnel, Nextcloud adminpass, Hermes env/API key, Ollama API key, Google API key, LLM Gateway API key, OpenCode API key, LibreChat env, Open WebUI env, notes, attic token, `secret1` (shared SSH authorized keys)) stored safely in the repo, decryptable only by target machines. Secrets defined in `modules/_secrets/secrets.nix` with per-host SSH public keys. `hermes-env`, `hermes-api-key`, `hermes-webui-env`, `librechat-env`, and `opencode` target only `nixos` and `raspberry-pi-4` (not `droid-android`); `llmgateway-api-key` targets all hosts; `secret1` is used on `raspberry-pi-4` for user SSH authorized keys.
* **`modules/overlays/`**: Nixpkgs patches (flake-level overlays). `brave.nix` (`brave-debloater`: extensive Brave browser policy hardening — disables AI, rewards, wallet, VPN, tor, telemetry, sync, password manager, autofill, etc.; sets AdGuard DNS-over-HTTPS), `opencode.nix` (`opencode-config`: wraps `opencode` with inline `opencode.json` config + `web-search-mcp.py` MCP server, sets `OPENCODE_CONFIG` env var and `OPENCODE_DISABLE_AUTOUPDATE`). Applied via `self.overlays` in host configs and base.
* **`modules/packages/`**: Custom packages and scripts.
  * `my-neovim` (nvf-based Neovim with gruvbox, LSP, Telescope, which-key, lualine, treesitter, nix/python/clang)
  * `update-flake` (updates flake.lock, syncs workflows, updates `bootdev-cli` via `nix-update`)
  * `flake-release` (commits, auto-increments git tag, pushes)
  * `install-system` (default package; runs disko, clones repo, nixos-install)
  * `raspberry-pi-4-sd-image` (aarch64 SD card image build)
  * `bootdev-cli` (pinned to v1.29.6, Go module)
  * `prime-agent` (v0.7.2, `_prime-agent/`: `buildNpmPackage` z tarballa release; brak skryptu build — dist/ to gotowy bundle; `nodejs_22` wymagany pod prebuildy zeromq/koffi; vendored `package-lock.json` generowany ręcznie (`npm install --package-lock-only`), tarball release go nie zawiera; wrapper seeduje domyślne `~/.prime/agent/models.json` + `settings.json` (LLM Gateway/devpass `https://api.llmgateway.io/v1`: qwen3.8-max jako default, claude-sonnet-4-6, claude-opus-4-8, gpt-5.3-codex, kimi-k2.7-code, qwen3.8-max, deepseek-v4-pro) — apiKey to nazwa zmiennej `LLMGATEWAY_API_KEY`, sekret nie trafia do store; compat `supportsDeveloperPlatforms: false` tylko per-model dla kimi-k2.7-code i qwen3.8-max (pozostałe modele gateway przepuszcza natywnie — zweryfikowane testem na żywym API); seeduje też 2 skille Pythonowe do `~/.prime/agent/skills/` (nadpisywane przy każdym starcie): `nixos-mcp` (integracja MCP z lokalnym serwerem mcp-nixos przez stdio — `McpIntegration` z nadpisanym `_open_session`, bo host wspiera w `mcpServers` tylko HTTP; binarka wstrzyknięta envem `MCP_NIXOS_EXE` przez wrapper) i `websearch` (wyszukiwanie DuckDuckGo przez ddgs, bez klucza API; nadpisuje wbudowany skill Serper — user skills mają priorytet); kernel instaluje skille jako `--editable` do kernel-venv przez uv przy starcie; zależność `prime-agent-runtime` spełniana lokalnym pakietem z dist/ tarballa)
  * Note: Proton-CachyOS x86-64-v3 is no longer built locally (`_proton-bin` derivation removed); it comes from the chaotic-nyx overlay + binary cache.
* **`modules/templates/`**: Project scaffolds. `nix flake init -t .` bootstraps a new `_project.nix` template.

## Centralized Configuration

### `customTop` (`modules/args.nix`)
Global arguments passed to all modules via `_module.args.customTop`:
* `repository`: `github:janusz-bit/nixos`, URL `https://github.com/janusz-bit/nixos.git`, local path `/etc/nixos`
* `email.full`: `janusz-bit@proton.me`
* `site`: `janusz-bit.com`
* `cache.cachix`: `janusz-bit.cachix.org` with public key
* `secretsDir`: `self + /modules/_secrets`

### `customBot` (`modules/options.nix`)
Custom NixOS options:
* `flakeTarget` (default: `"default"`)
* `enableFastfetch` (default: `true`)
* `defaultUser` (default: `"nixos"`)

## Flake Inputs
* `nixpkgs` — `github:NixOS/nixpkgs/nixos-unstable` (base package set)
* `nixpkgs-stable` — `github:NixOS/nixpkgs/nixos-26.05` (currently used for the `ollama` package on the workstation)
* `import-tree` — `github:vic/import-tree` (auto-discovery of `modules/` directory)
* `flake-parts` — `github:hercules-ci/flake-parts` (flake module system)
* `home-manager` — `github:nix-community/home-manager` (follows nixpkgs)
* `nixos-wsl` — `github:nix-community/NixOS-WSL/main` (WSL support)
* `nvf` — `github:notashelf/nvf` (declarative Neovim config)
* `avf` — `github:nix-community/nixos-avf` (Android Virtualization Framework)
* `nix-index-database` — `github:nix-community/nix-index-database` (follows nixpkgs; for `comma`)
* `nix-cachyos-kernel` — `github:xddxdd/nix-cachyos-kernel/release` (CachyOS kernels + overlay)
* `chaotic` — `github:chaotic-cx/nyx/nyxpkgs-unstable` (Chaotic-Nyx: bleeding-edge packages + nyx binary cache; nixos host only)
* `nixos-hardware` — `github:NixOS/nixos-hardware/master` (hardware modules)
* `nixos-raspberrypi` — `github:nvmd/nixos-raspberrypi` (RPi-specific support)
* `agenix` — `github:ryantm/agenix` (follows nixpkgs; secrets management)
* `disko` — `github:nix-community/disko` (follows nixpkgs; disk partitioning)
* `git-hooks-nix` — `github:cachix/git-hooks.nix` (follows nixpkgs; pre-commit hooks)
* `trilium` — `github:TriliumNext/Trilium/744646d07bff459d1db305b1c0a8ea0c99b9c27c` (follows nixpkgs; pinned commit)
* `github-actions-nix` — `github:synapdeck/github-actions-nix` (CI workflow generation)
* `hermes-agent` — `github:NousResearch/hermes-agent` (unpinned — see hermes-agent note above)

## Dev Shell Tools
Running `nix develop` provides:
* `update-flake` – updates `flake.lock`, commits it, then updates the `bootdev-cli` package via `nix-update`.
* `flake-release` – commits, auto-increments the git tag, pushes to GitHub.
* Pre-commit hooks auto-installed: `nixfmt` formatter, `statix` lint, `deadnix` lint (with `noLambdaPatternNames`), `sync-github-actions` (syncs generated workflow YAML to `.github/workflows/`). The sync script deletes stale workflow files first, so no orphaned YAML survives a refactor.

## Building and Running
```sh
# Build and activate for a given host
sudo nixos-rebuild switch --flake .#nixos
sudo nixos-rebuild switch --flake .#raspberry-pi-4

# Or using the shell aliases (pulls from GitHub)
update        # switch (remote)
update-boot   # boot (remote)
update-local  # switch (local)

# Push build closure to Cachix
push

# Install system (default package)
nix run github:janusz-bit/nixos

# Build SD image for RPi4
nix build .#raspberry-pi-4-sd-image
```

## Development Conventions
* **Agents**: AI agents are used for repository maintenance; see [AGENTS.md](AGENTS.md) for configuration.
* **Formatting & linting**: `nixfmt` + `statix` + `deadnix` (enforced via pre-commit and the CI `lint` workflow building `checks.<system>.pre-commit`).
* **Pre-commit hooks**: formatter, linters + `sync-github-actions` (keeps workflow YAML in sync with the Nix-generated definitions; deletes orphaned files first).
* **Dev shell**: Always use `nix develop` to ensure pre-commit hooks and required tools are bootstrapped automatically.
* **Secrets**: Never write API keys, passwords, or tokens directly in `.nix` files (they end up in the world-readable `/nix/store`). Always use Agenix with `environmentFiles` from age-encrypted secrets.
* **CI**: Tag push (`v*`) triggers build workflows. Tags auto-increment sequentially (v310, v311, ...) via `flake-release`. 7 workflows generated from `modules/github-actions.nix` (6 builds + `lint`).

## Repository Statistics
* 97 tracked files (excluding `.git/`)
* 61 `.nix` files, ~3350 LOC total
* 16 age-encrypted secrets
* 7 workflow `.yml` files in `.github/workflows/` (all auto-generated from `modules/github-actions.nix`)
* 5 host configurations: `nixos`, `raspberry-pi-4`, `wsl`, `droid`, `default` (alias for `nixos`)
* 3 Nixpkgs overlays: `brave-debloater`, `opencode-config`, `prime-agent`
* Channel: `nixos-unstable`