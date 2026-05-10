# NixOS Configuration Flake

## Project Overview
This repository contains a centralized, declarative NixOS system configuration architecture using Nix Flakes. The project defines environments and manages states across multiple hardware architectures, specifically supporting `x86_64-linux` and `aarch64-linux` platforms. The codebase structures Nix modules dynamically utilizing `flake-parts` and `vic/import-tree`. 

Integrated technologies handling the system's core capabilities include:
* **Home Manager**: Manages user-specific environments and dotfiles.
* **Agenix**: Handles encrypted system secrets.
* **Cachix**: External Nix binary cache.
* **Disko**: Automates disk partitioning and formatting.
* **NixOS-WSL**: Provides configurations for the Windows Subsystem for Linux.
* **Pre-commit Hooks**: Enforces CI/CD and repository consistency constraints.

## System Architectures & Host Deployments
The `modules/hosts/` directory contains isolated definitions targeting different deployment vectors. Each host is built upon a shared foundation but customized for its specific role.

### 1. `base` (The Foundation)
A shared set of modules included in every system deployment.
* Sets up the core CLI experience: `bash` wrapping an optimized `fish` shell with custom aliases (`eza`, `bat`, `fastfetch`).
* Configures fundamental services: Git defaults, SSH security (key-only authentication), Agenix secrets handling, and core Nix settings.

### 2. `nixos` (Main Workstation)
An `x86_64-linux` deployment optimized for a Lenovo LOQ-15IRX10 laptop (Nvidia GPU).
* **Core**: CachyOS kernel (x86-64-v3 optimized), Disko-managed encrypted Btrfs with subvolumes.
* **Profiles**: Boot-time `specialisations` allowing the user to select between battery saving (`power-save`) and GPU sync modes (`sync-mode`, `reverse-sync`).
* **Environment**: KDE Plasma (Wayland via Niri), Pipewire audio, and a robust suite of applications (Steam, Heroic, Vesktop, Tor, Zed).
* **Tools**: Local LLM environment (Ollama), Podman with Docker compatibility.

### 3. `raspberry-pi-4` (Home Server / Cloud)
A headless `aarch64-linux` deployment built for network services and caching.
* **Core**: Highly optimized for limited resources using SSD swap and `zstd` compressed `zramSwap`. Hardened via fail2ban.
* **Nextcloud**: Performance-tuned PostgreSQL and Redis setup, reverse-proxied securely through a Cloudflare Tunnel.
* **Hardware Integration**: Custom Python-based systemd service (`pwm-fan`) for temperature-driven GPIO fan control.

### 4. `wsl` (Windows Subsystem for Linux)
A minimal environment bridging NixOS into a Windows host.
* Utilizes the external `NixOS-WSL` module.
* Enables Start Menu launchers, configures the default user, and injects environment variables for GPU acceleration within the Zed editor.

### 5. `droid-android`
A highly reduced NixOS footprint tailored for Android virtualization (e.g., via `nixos-avf`).
* Includes the core `base` system but strips away visual elements (like `fastfetch`) to ensure lightweight terminal performance on mobile hardware.

## Repository Architecture
The repository uses a highly modular structure powered by `flake-parts` and `import-tree`, which auto-discovers and maps the codebase logically. 

* **`flake.nix`**: The heart of the system. Defines all external inputs (nixpkgs, home-manager, agenix) and passes them to `import-tree` to dynamically load the `modules/` folder.
* **`modules/default.nix`**: The integration module for development environments. It sets up `devShells`, formatters (`nixfmt-tree`), pre-commit hooks, and orchestrates CI pipelines.
* **`modules/github-actions.nix` & `_github-actions-configs.nix`**: CI/CD automation factory. These dynamically generate GitHub Actions workflows to auto-build target architectures (like x86_64 and aarch64) and push the resulting binaries to the Cachix cache.
* **`modules/hardware/`**: Hardware-specific profiling. Stores hardware patches (e.g., Lenovo LOQ specific configurations, `x86-64-v3` CPU optimizations, and `.icm` color profiles).
* **`modules/agenix/` & `modules/_secrets/`**: Cryptographic security. Stores highly secure, SSH-key encrypted secrets (GitHub tokens, credentials) safely within the public repository, decryptable only by target machines at runtime.
* **`modules/overlays/`**: Patches and modifications to the default `nixpkgs` tree. Used to fix broken packages or inject custom/modified software (like a tailored Brave browser).
* **`modules/packages/`**: Custom authored packages and automation scripts (e.g., custom Neovim builder, NixOS installation scripts).
* **`modules/templates/`**: Project scaffolds. Allows running `nix flake init -t .` in a blank directory to quickly scaffold a new project based on the `_project.nix` structure.

## Centralized Configuration (`options.nix`)
The `modules/options.nix` file acts as the central source of truth for global project variables. It exports custom options (`options.custom`) and module arguments (`_module.args.custom`) that are accessible across the entire flake. This ensures consistency and simplifies maintenance by providing a single place to manage:
* **Repository Info**: Source URLs, git repository paths, and identifiers.
* **Domain & Network**: Global domain name mappings.
* **System Defaults**: Universal flags like `enableFastfetch` and the `defaultUser` definition.

## Building and Running
System deployments are executed via standard NixOS flake reconstruction commands.

To build and switch the configuration for a given host:
* `sudo nixos-rebuild switch --flake .#nixos`
* `sudo nixos-rebuild switch --flake .#raspberry-pi-4`

Custom shell aliases are provided to manage deployments and cache pushes (defined in `base/configuration.nix`):
* `update`: rebuilds and switches the current host configuration.
* `update-boot`: rebuilds and sets the configuration for the next boot.
* `push`: builds the top-level configuration and pushes the closure to the Cachix cache.

The repository also exposes an automated installation script via `packages.install-system`, accessible as the flake's default package.

## Development Conventions
* **Formatting Enforcement**: Code formatting is strictly unified using `nixfmt-tree`.
* **Pre-commit Validation**: Development relies heavily on local git hooks. The pre-commit pipeline is configured to run the formatter and synchronize GitHub Actions state (`sync-github-actions`).
* **Environment Initialization**: Generating a shell context (via `nix develop`) automatically bootstraps the required pre-commit installation scripts into the shell hook alongside necessary formatter packages.
