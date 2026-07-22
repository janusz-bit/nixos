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
* **github-actions-nix**: Auto-generates GitHub Actions workflows (`github:synapdeck/github-actions-nix`).
* **hermes-agent**: Hermes AI agent NixOS module (`github:NousResearch/hermes-agent`).
* **Gitea**: Self-hosted Git service with web UI and SSH access (`git.janusz-bit.com`).
* **TriliumNext**: Note-taking server and desktop client (pinned to specific commit `44f5be88b776078fe268dc9877411cb144df3a46`).
* **Pre-commit Hooks**: Enforces formatting (`nixfmt-tree`) and workflow sync.

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
* **OpenCode**: Declarative configuration inline in `modules/overlays/opencode.nix` (Nix overlay generating `opencode.json` + `web-search-mcp.py` at build time). Default model: `google/gemini-3.1-pro-preview`. Provider `ollama` (OpenAI-compatible, `http://localhost:11434/v1`) with model `orinth:35b`. Local `web_search_and_fetch` MCP server via `uv run` (Ollama web_search/web_fetch API). Installed on all hosts through the `base/opencode` module.
* **Nix settings** (`modules/nix-settings.nix`): Weekly GC (delete older than 7d), auto-optimise-store, trusted-users = `@wheel`.
* **Git** (`modules/hosts/base/git.nix`): user.name = `janusz-bit`, user.email = `janusz-bit@proton.me`, init.defaultBranch = `main`, `gh:` and `github:` rewritten to `https://github.com/`. `gh` CLI installed.
* **SSH** (`modules/hosts/base/ssh.nix`): Key-only authentication, `ssh.startAgent = false`, `gnupg.agent.enable = true`. Cloudflared SSH proxy configured (`ssh.*` host pattern uses `cloudflared access ssh --hostname %h`).
* **Agenix** (`modules/hosts/base/agenix.nix`): Exports `CACHIX_AUTH_TOKEN`, `GITHUB_TOKEN`, `OLLAMA_API_KEY`, `GOOGLE_API_KEY` via `environment.shellInit` from age-encrypted secrets.
* **Firewall**: Enabled, allows TCP port 22.

#### Shell Aliases (all hosts)
| Alias | Command |
|---|---|
| `update` | `sudo nixos-rebuild switch --sudo --flake <remote-flake>#<target> --refresh` |
| `update-boot` | `sudo nixos-rebuild boot --sudo --flake <remote-flake>#<target> --refresh` |
| `update-local` | `sudo nixos-rebuild switch --sudo --flake <local-flake>#<target>` |
| `update-local-boot` | `sudo nixos-rebuild boot --sudo --flake <local-flake>#<target>` |
| `push` | Build toplevel and push closure to Cachix via `nix build ... \| cachix push ...` |
| `update-my-pkgs` | `nix run <flake>#update-my-pkgs` |
| `ls`, `la`, `ll`, `lt`, `l.` | `eza` variants |
| `..`, `...`, `....` | Directory navigation |
| `cat` | `bat` |
| `hw` | `hwinfo --short` |

### 2. `nixos` (Main Workstation)
An `x86_64-linux` deployment for a **Lenovo LOQ-15IRX10** laptop (Nvidia GPU, Polish locale). Default user: `dinosaur`.
* **Kernel**: CachyOS kernel (`linuxPackages-cachyos-latest-lto-x86_64-v3`) via the `nix-cachyos-kernel` input.
* **Storage**: Disko-managed encrypted Btrfs with LUKS on `/dev/nvme1n1`. Partitions: 6G ESP (vfat `/boot`), 36G LUKS swap, rest LUKS+Btrfs (`/root`, `/home`, `/nix` subvolumes, `compress=zstd`, `noatime`). Working hibernation configured (`/dev/mapper/swap`).
* **Bootloader**: Limine, with a Windows EFI dual-boot entry. `efi.canTouchEfiVariables = true`.
* **binfmt emulation**: `aarch64-linux` emulated systems enabled (`boot.binfmt.emulatedSystems`).
* **Supported filesystems**: `btrfs` explicitly listed.
* **Desktop**: KDE Plasma 6 (Wayland) with SDDM, plus **Niri** compositor (`programs.niri.enable`).
* **Audio**: Pipewire (with ALSA 32-bit and PulseAudio compat).
* **Scheduler**: `scx` with `scx_lavd` (`--performance`); `ananicy-cpp` with CachyOS rules.
* **Specialisations** (boot-time profiles):
  * `power-save` – TLP + `powersave` governor + scx `--powersave`.
  * `reverse-sync` – Nvidia Prime Reverse Sync.
  * `sync-mode` – Nvidia Prime Sync.
* **Gaming**: Steam (with Proton-CachyOS-v3 and proton-ge-bin), Heroic, Lutris, GameMode, OBS Studio (CUDA), Mullvad VPN, Wooting keyboard support. `protonup-qt` for Proton management.
* **AppImage support** (`modules/hosts/nixos/appimage-run.nix`): `programs.appimage` enabled with binfmt registration. Custom extra packages: `icu`, `libxcrypt-legacy`, `python312`, `python312Packages.torch`.
* **Containers**: Podman with Docker compatibility, DNS enabled.
* **AI Tools** (`modules/hosts/nixos/ai.nix`): Ollama (CUDA backend via `ollama-cuda`), Open WebUI (no auth, connects to local Ollama at `127.0.0.1:11434`), `uv`, `repomix`, Node.js, Python 3 with pip.
* **Apps**: Zed, Brave, Firefox, LibreOffice, Vesktop, Signal, Element, Tor Browser, qBittorrent-enhanced, Trilium, Joplin, Nextcloud client, PrismLauncher, Lutris, VLC, Haruna, Elisa, Alacritty, sbctl, bootdev-cli, ungoogled-chromium, KDE Partition Manager, KDE QRCA, KDE KCalc, `sqlite`, `protonup-qt`.
* **Compilers & build tools**: `cmake`, `ninja`, `clang`, `clang-tools`, `lldb`, `boost`, `wine64`, `pkgs.pkgsCross.mingwW64.buildPackages.gcc` (MinGW cross-compiler).
* **Gitea CLI**: `tea` installed (for interacting with `git.janusz-bit.com`).
* **Sync**: Syncthing (user data in `~/Sync`).
* **Overlays applied**: `nix-cachyos-kernel`, `brave-debloater`, `trilium`.
* **Other services**: Avahi (mDNS), Flatpak, Btrfs autoScrub, CUPS printing, Bluetooth.
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
* **Nextcloud 33**: PostgreSQL backend (locally created, tuned: 128MB shared_buffers, 4MB work_mem, 32MB maintenance_work_mem, 256MB effective_cache_size), Redis cache, 2GB upload limit, accessible **only via Cloudflare Tunnel** (no open ports, HSTS enabled). Trusted proxies: `127.0.0.1`, `::1`.
* **Hermes Agent** (`modules/hosts/raspberry-pi-4/hermes.nix`): AI agent service (`services.hermes-agent`) on port 8642. Uses `glm-5.2:cloud` model via Ollama Cloud, `ddgs` as the web backend. `require_approval = false`. `agent.reasoning_effort = "xhigh"` (maps to `max` for ollama-cloud). `auxiliary.vision` configured with `gemma4:31b` model via Ollama Cloud. `restart = "always"`, `restartSec = 5`. Extra packages: `uv`, `nodejs_22`, `ripgrep`, `ffmpeg`, `python311`. Extra dependency groups: `all`, `messaging`, `matrix`. Configured MCP servers: `trilium-notes` (HTTP at `127.0.0.1:8081/mcp` with Bearer token) and `nixos` (`uvx mcp-nixos`). Environment loaded from `hermes-env.age` (sops-nix). Sudo NOPASSWD for user `hermes` (ALL). Service hardening overrides: `NoNewPrivileges = false` (enables sudo), `UMask = 0027` (group-readable files for `nixos` user in `hermes` group), `ExecStartPre` cleans stale lock/pid/state files. User `hermes` in groups: `users`, `keys`, `wheel`, `systemd-journal`, `disk`. User `nixos` added to `hermes` group.
* **Open WebUI** (`modules/hosts/raspberry-pi-4/open-webui.nix`): Open-source AI chat interface on port 8080 (localhost only). Connects to Hermes Agent via OpenAI-compatible API at `127.0.0.1:8642/v1` (`ENABLE_OPENAI_API = "true"`). Ollama API disabled (`ENABLE_OLLAMA_API = "false"`). Auth required (`WEBUI_AUTH = "True"`). `ENABLE_PERSISTENT_CONFIG = "False"` (env vars override DB-stored values). Shared API key with Hermes Agent via `hermes-env.age`.
* **Ollama**: Local LLM backend (`services.ollama.enable`), EnvironmentFile from `hermes-env.age`.
* **Gitea** (`modules/hosts/raspberry-pi-4/gitea.nix`): Self-hosted Git service on port 3000 (localhost only). SQLite database. Domain `git.janusz-bit.com`. Registration disabled. Cookie secure enabled. SSH access via system SSH (port 22, `START_SSH_SERVER = false`). `tea` (Gitea CLI) installed in system packages.
* **Cloudflared**: Tunnel to expose services externally:
  * `${customTop.site.full}` -> Nextcloud (localhost:80)
  * `chat.${customTop.site.full}` -> Open WebUI (localhost:8080)
  * `notes.${customTop.site.full}` -> Trilium (localhost:8081)
  * `ssh.${customTop.site.full}` -> SSH (localhost:22)
  * `git.${customTop.site.full}` -> Gitea (localhost:3000)
* **Trilium**: Note-taking server on port 8081 (overlay applied).
* **Fan control**: Custom Python-based systemd service (`pwm-fan`) for GPIO PWM fan control based on CPU temperature (GPIO BCM pin 14, thresholds: 60C=100%, 48C=50%, else 0%).
* **LED control** (`modules/hosts/raspberry-pi-4/leds-off.nix`): All LEDs disabled via DT overlays (`hardware.raspberry-pi."4".leds` — eth, act, pwr) and systemd-tmpfiles rules (mmc0, default-on).
* **Overlays applied**: `trilium`, `hermes-agent` (patches stale `npmDepsHash` in upstream hermes-agent's `nix/lib.nix` via `applyPatches` + `substituteInPlace`).
* **State version**: `26.05`.

### 4. `wsl` (Windows Subsystem for Linux)
A minimal `x86_64-linux` environment bridging NixOS into a Windows host.
* Uses `NixOS-WSL` module (`wsl.enable`, `useWindowsDriver`, `startMenuLaunchers`).
* Default user: `nixos`.
* `fastfetch` disabled.
* `zed-editor-fhs` installed.
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
* **`modules/default.nix`**: Integration module. Defines `systems` (`x86_64-linux`, `aarch64-linux`), `devShells`, formatter (`nixfmt-tree`), pre-commit hooks (`nixfmt`, `sync-github-actions`), and exposes `update-flake` and `flake-release` packages in the dev shell.
* **`modules/github-actions.nix`**: CI/CD factory that auto-generates GitHub Actions workflows. Generates 7 workflows: `nixos`, `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl`, `droid` (build on tag push/PR), `cachyos-kernel-update` (daily cron at 2am). Maps `x86_64-linux` to `ubuntu-latest`, `aarch64-linux` to `ubuntu-24.04-arm`.
* **`modules/hardware/`**: Hardware-specific profiling. Stores Lenovo LOQ-15IRX10 patches, `x86-64-v3` CPU optimization, `M27Q.icm` color profile, and a `facter.json` inventory.
* **`modules/agenix/` & `modules/_secrets/`**: Cryptographic secrets. Age-encrypted files (GitHub token, Cachix token, Cloudflare tunnel, Nextcloud adminpass, Hermes env/API key, Ollama API key, Google API key, LibreChat env, Open WebUI env, notes, attic token) stored safely in the repo, decryptable only by target machines. Secrets defined in `modules/_secrets/secrets.nix` with per-host SSH public keys. `hermes-env`, `hermes-api-key`, `hermes-webui-env`, and `librechat-env` target only `nixos` and `raspberry-pi-4` (not `droid-android`).
* **`modules/overlays/`**: Nixpkgs patches. `brave-debloater` (extensive Brave browser policy hardening: disables AI, rewards, wallet, VPN, tor, telemetry, sync, password manager, autofill, etc.; sets AdGuard DNS-over-HTTPS), `trilium` (pinned to specific TriliumNext commit), `hermes-agent` (patches stale `npmDepsHash` in upstream hermes-agent source via `applyPatches`).
* **`modules/packages/`**: Custom packages and scripts.
  * `proton-cachyos-v3` (custom Proton build from CachyOS, x86_64-linux only)
  * `my-neovim` (nvf-based Neovim with gruvbox, LSP, Telescope, which-key, lualine, treesitter, nix/python/clang)
  * `update-flake` (updates flake.lock + bootdev-cli + proton-cachyos-v3, commits)
  * `flake-release` (commits, auto-increments git tag, pushes)
  * `install-system` (default package; runs disko, clones repo, nixos-install)
  * `raspberry-pi-4-sd-image` (aarch64 SD card image build)
  * `bootdev-cli` (pinned to v1.29.6)
* **`modules/templates/`**: Project scaffolds. `nix flake init -t .` bootstraps a new `_project.nix` template.
* **`modules/configs/opencode/`**: OpenCode legacy config directory (now generated inline by `modules/overlays/opencode.nix` overlay).

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

## Dev Shell Tools
Running `nix develop` provides:
* `update-flake` – updates `flake.lock`, commits it, then updates `bootdev-cli` and `proton-cachyos-v3` packages via `nix-update`.
* `flake-release` – commits, auto-increments the git tag, pushes to GitHub.
* Pre-commit hooks auto-installed: `nixfmt` formatter, `sync-github-actions` (syncs generated workflow YAML to `.github/workflows/`).

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
* **Formatting**: `nixfmt-tree` (enforced via pre-commit and CI).
* **Pre-commit hooks**: formatter + `sync-github-actions` (keeps workflow YAML in sync with the Nix-generated definitions).
* **Dev shell**: Always use `nix develop` to ensure pre-commit hooks and required tools are bootstrapped automatically.
* **Secrets**: Never write API keys, passwords, or tokens directly in `.nix` files (they end up in the world-readable `/nix/store`). Always use Agenix with `environmentFiles` from age-encrypted secrets.