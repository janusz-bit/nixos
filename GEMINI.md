# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS**, **Nix Flakes**, and **Home Manager**. Your task is to assist in maintaining, refactoring, and developing this repository (dotfiles).

# NixOS Configuration Flake

## Project Overview
This repository contains a centralized, declarative NixOS system configuration architecture using Nix Flakes. The project defines environments and manages state across multiple hardware architectures, specifically supporting `x86_64-linux` and `aarch64-linux` platforms. The codebase structures Nix modules dynamically using `flake-parts` and `vic/import-tree`.

Integrated technologies handling the system's core capabilities include:
* **Home Manager**: Manages user-specific environments and dotfiles.
* **Agenix**: Handles encrypted system secrets (SSH-key based, age-encrypted).
* **Cachix**: External Nix binary cache (`janusz-bit.cachix.org`).
* **Disko**: Automates disk partitioning and formatting (encrypted Btrfs).
* **NixOS-WSL**: Provides configurations for Windows Subsystem for Linux.
* **nvf**: Declarative Neovim configuration framework.
* **nixos-avf**: NixOS support for Android Virtualization Framework.
* **nixos-raspberrypi**: RPi-specific hardware support.
* **nix-cachyos-kernel**: CachyOS kernel packages.
* **github-actions-nix**: Auto-generates GitHub Actions workflows.
* **Pre-commit Hooks**: Enforces formatting (`nixfmt-tree`) and workflow sync.

## System Architectures & Host Deployments
The `modules/hosts/` directory contains isolated definitions targeting different deployment vectors. Each host is built upon a shared foundation but customized for its specific role.

### 1. `base` (The Foundation)
A shared set of modules included in every system deployment.
* Sets up the core CLI experience: `bash` is set as the login shell (to avoid compatibility issues like broken recovery environments), but automatically `exec`s `fish` for interactive sessions. Includes custom aliases (`eza`, `bat`, `fastfetch`), the `done` fish plugin for long-command notifications.
* Configures fundamental services: Git defaults, SSH security (key-only authentication), Agenix secrets handling, core Nix settings, `vulnix` vulnerability scanning.
* Shared packages: `micro`, `nil`, `nixd`, `nixfmt-tree`, `uv`, `toybox`, `statix`, `cachix`, `agenix`, `nix-update`, `tlrc`, `fzf`, `hw-probe`, `htop`, `cloudflared`, `gemini-cli`, `opencode`.
* `nix-ld` enabled to support dynamically linked binaries (e.g., from `uv`).
* `nix-index-database` with `comma` integration.
* `direnv` enabled.
* Default editor: `micro`.
* **OpenCode**: Declarative configuration via `environment.etc` + `systemd.tmpfiles.rules` symlink. Config at `modules/configs/opencode/opencode.json` (Ollama provider with `kimi-k2.6:cloud` model, `superpowers`, `caveman-opencode-plugin`, and `opencode-skillful` plugins). Installed on all hosts through the `base/opencode` module.

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
An `x86_64-linux` deployment for a **Lenovo LOQ-15IRX10** laptop (Nvidia GPU, Polish locale).
* **Kernel**: CachyOS kernel (`linuxPackages-cachyos-latest-lto-x86_64-v3`) via the `nix-cachyos-kernel` input.
* **Storage**: Disko-managed encrypted Btrfs with LUKS. Working hibernation configured (`/dev/mapper/swap`).
* **Bootloader**: Limine, with a Windows EFI dual-boot entry.
* **Desktop**: KDE Plasma 6 (Wayland) with SDDM, plus **Niri** compositor (`programs.niri.enable`).
* **Audio**: Pipewire (with ALSA 32-bit and PulseAudio compat).
* **Scheduler**: `scx` with `scx_lavd` (`--performance`); `ananicy-cpp` with CachyOS rules.
* **Specialisations** (boot-time profiles):
  * `power-save` – TLP + `powersave` governor + scx `--powersave`.
  * `reverse-sync` – Nvidia Prime Reverse Sync.
  * `sync-mode` – Nvidia Prime Sync.
* **Gaming**: Steam (with Proton-CachyOS-v3 and proton-ge-bin), Heroic, GameMode, OBS Studio (CUDA), Mullvad VPN, Wooting keyboard support.
* **Containers**: Podman with Docker compatibility, DNS enabled.
* **AI Tools**: Ollama (CUDA backend), `uv`, `repomix`, Node.js, Python 3.
* **Apps**: Zed, Brave, Firefox, LibreOffice, Vesktop, Signal, Element, Tor Browser, qBittorrent-enhanced, Bitwarden, Trilium, Joplin, Nextcloud client, PrismLauncher, VLC, Haruna, Elisa, Alacritty, sbctl, bootdev-cli.
* **Sync**: Syncthing (user data in `~/Sync`).
* **Overlays applied**: `nix-cachyos-kernel`, `bootdev-cli-overlay`, `brave-debloater`, `trilium`.
* **Locale**: Polish (`pl_PL.UTF-8`), timezone `Europe/Warsaw`, keymap `pl2`.
* **State version**: `25.11`.

### 3. `raspberry-pi-4` (Home Server / Cloud)
A headless `aarch64-linux` deployment for network services.
* **Memory optimization**: zRAM (`zstd`), 8GB SSD swap, `vm.swappiness=100`, tmpfs for `/tmp`.
* **CPU**: `ondemand` governor.
* **Security**: fail2ban (max 5 retries, LAN whitelisted), SSH key-only.
* **Nix GC**: daily, deletes derivations older than 3 days; max 2 build jobs.
* **Nextcloud 33**: PostgreSQL backend (locally created), Redis cache, 2GB upload limit, accessible **only via Cloudflare Tunnel** (no open ports, HSTS enabled).
* **Hermes Agent**: AI agent service (`services.hermes-agent`) on port 8642. Uses `kimi-k2.6:cloud` model via Ollama Cloud, and `ddgs` as the web backend. Configured MCP servers: `trilium-notes` and `nixos`.
* **LibreChat**: Open-source AI chat interface (`services.librechat`) on port 2309. Accessible via `chat.${customTop.site.full}`.
* **Ollama**: Lokalny backend LLM (`services.ollama.enable`).
* **Cloudflared**: Tunnel to expose services externally:
  * `chat.${customTop.site.full}` -> LibreChat
  * `${customTop.site.full}` -> Nextcloud
  * `notes.${customTop.site.full}` -> Trilium
  * `ssh.${customTop.site.full}` -> SSH
* **Trilium**: Note-taking server (overlay applied).
* **Fan control**: Custom Python-based systemd service (`pwm-fan`) for GPIO PWM fan control based on CPU temperature.
* **Overlay applied**: `trilium`.

### 4. `wsl` (Windows Subsystem for Linux)
A minimal `x86_64-linux` environment bridging NixOS into a Windows host.
* Uses `NixOS-WSL` module.
* Enables Start Menu integration, sets default user.
* `fastfetch` disabled.
* Obsidian launcher support.

### 5. `droid` (Android Virtualization Framework)
A reduced `aarch64-linux` footprint for Android (via `nixos-avf`).
* Includes `base` modules; `fastfetch` and visual elements disabled.
* Default user: `droid`.
* Fixes bogus terminal size (`$COLUMNS=131072`) on Android/AVF at bash init.
* `custom.flakeTarget = "droid"`.

## Repository Architecture
The repository uses a highly modular structure powered by `flake-parts` and `import-tree`, which auto-discovers and maps the codebase logically.

* **`flake.nix`**: Entry point. Defines all external inputs and passes them to `import-tree` to dynamically load the `modules/` folder. Declares the `janusz-bit.cachix.org` binary cache.
* **`modules/default.nix`**: Integration module. Defines `systems` (`x86_64-linux`, `aarch64-linux`), `devShells`, formatter (`nixfmt-tree`), pre-commit hooks (`nixfmt`, `sync-github-actions`), and exposes `update-flake` and `flake-release` packages in the dev shell.
* **`modules/github-actions.nix` & `_github-actions-configs.nix`**: CI/CD factory that auto-generates GitHub Actions workflows to build target architectures and push binaries to Cachix.
* **`modules/hardware/`**: Hardware-specific profiling. Stores Lenovo LOQ-15IRX10 patches, `x86-64-v3` CPU optimization, `M27Q.icm` color profile, and a `facter.json` inventory.
* **`modules/agenix/` & `modules/_secrets/`**: Cryptographic secrets. Age-encrypted files (GitHub token, Cachix token, Cloudflare tunnel, Nextcloud adminpass, etc.) stored safely in the repo, decryptable only by target machines.
* **`modules/overlays/`**: Nixpkgs patches. `brave-debloater` (Brave browser customization), `trilium` (pinned to a specific commit), `bootdev-cli-overlay`.
* **`modules/packages/`**: Custom packages and scripts. `proton-cachyos-v3` (custom Proton build), `my-neovim` (nvf-based Neovim with gruvbox, LSP, Telescope), `update-flake` (updates flake.lock + packages + commits), `flake-release` (auto-tags and pushes releases), `install-system` (default package).
* **`modules/templates/`**: Project scaffolds. `nix flake init -t .` bootstraps a new `_project.nix` template.

## Centralized Configuration (`options.nix`)
`modules/options.nix` is the single source of truth for global custom arguments (passed via `config.customBot` and `_module.args.customTop`). 
* **Options**: `flakeTarget` (default: `"default"`), `enableFastfetch` (default: `true`), `defaultUser` (default: `"nixos"`).

Note: Repository metadata (repo URL, email, domain, cache) was previously centralized here but has been removed from `options.nix` in recent refactors (now managed via `customTop` arguments).

## Dev Shell Tools
Running `nix develop` provides:
* `update-flake` – updates `flake.lock`, commits it, then updates `bootdev-cli` and `proton-cachyos-v3` packages.
* `flake-release` – commits, auto-increments the git tag, pushes to GitHub.
* Pre-commit hooks auto-installed: `nixfmt` formatter, `sync-github-actions`.

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
```

## Development Conventions
* **Agents**: AI agents are used for repository maintenance; see [AGENTS.md](AGENTS.md) for configuration.
* **Formatting**: `nixfmt-tree` (enforced via pre-commit and CI).
* **Pre-commit hooks**: formatter + `sync-github-actions` (keeps workflow YAML in sync with the Nix-generated definitions).
* **Dev shell**: Always use `nix develop` to ensure pre-commit hooks and required tools are bootstrapped automatically.
