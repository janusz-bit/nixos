# Instructions for AI Assistant

You are an advanced DevOps engineer and an expert in **NixOS** and **Nix Flakes**. Your task is to assist in maintaining, refactoring, and developing this repository (dotfiles).

# Refinement (`/refine`, Prime Agent)
`/refine` is a built-in Prime Agent command (skill: `packages/coding-agent/skills/refine`), NOT a system-deployment tool. It does not apply NixOS changes.
* Use it when you notice a repeated failure, a reusable tactic, a delegation role, or a behavior policy worth persisting.
* From IPython: `await refine.status()`, `await refine.run()`, `await refine.run("focused instruction")` (session-local) or `await refine.run("...", global_=True)` (cross-session global store).
* Refinement runs when the current turn ends; the harness applies prompt/memory/skill/subagent-spec updates and rebuilds the system prompt. One request per turn.
* System/NixOS changes themselves (packages, services, rebuilds) are still made by editing the flake and running `nixos-rebuild` (aliases: `update`, `update-local`) — never via `/refine`.

# NixOS Configuration Flake

## Project Overview
This repository contains a centralized, declarative NixOS system configuration architecture using Nix Flakes. The project defines environments and manages state across multiple hardware architectures, specifically supporting `x86_64-linux` and `aarch64-linux` platforms. The codebase structures Nix modules dynamically using `flake-parts` and `vic/import-tree`. The repository does **not** use Home Manager: user environments and dotfiles are declared directly in the NixOS modules (the `home-manager` input and the dead `flake.homeModules.configuration` block were removed).

Integrated technologies handling the system's core capabilities include:
* **Agenix**: Handles encrypted system secrets (SSH-key based, age-encrypted).
* **Cachix**: External Nix binary cache (`janusz-bit.cachix.org`).
* **Disko**: Automates disk partitioning and formatting (encrypted Btrfs with LUKS).
* **NixOS-WSL**: Provides configurations for Windows Subsystem for Linux.
* **nvf**: Declarative Neovim configuration framework.
* **nixos-avf**: NixOS support for Android Virtualization Framework.
* **nixos-hardware**: Common hardware modules (`github:NixOS/nixos-hardware/master`).
* **chaotic (Chaotic-Nyx)**: Bleeding-edge packages and binary cache (`github:chaotic-cx/nyx/nyxpkgs-unstable`). Provides `proton-cachyos_x86_64_v3`, `proton-ge-custom`, `mangohud_git`, `pkgsx86_64_v3` etc. (the CachyOS **kernel** now comes from the separate `nix-cachyos-kernel` input, not chaotic); its `nixosModules.default` adds the nyx overlay, registry and the `nyx-cache.chaotic.cx` substituter. Applied to the `nixos` host only.
* **nix-cachyos-kernel**: CachyOS kernel packages (`github:xddxdd/nix-cachyos-kernel`, branch `release` = builds covered by a binary cache). Its overlay (`inputs.nix-cachyos-kernel.overlays.default`) supplies `pkgs.cachyosKernels`; the `nixos` host runs `linuxPackages-cachyos-bore-lto-x86_64-v3` (i5-13450HX supports x86-64-v3, not AVX-512). MUST NOT set `inputs.nixpkgs.follows` — it needs its own nixpkgs for patch compatibility.
* **github-actions-nix**: Auto-generates GitHub Actions workflows (`github:synapdeck/github-actions-nix`).
* **hermes-agent**: Hermes AI agent NixOS module (`github:NousResearch/hermes-agent`). Now unpinned (tracks upstream); a comment in `flake.nix` records the previous pin (`3f2a389c...`) made because `topup.ts` introduced a broken `@hermes/shared/charge-settlement` import in `nix/tui.nix`.
* **llm-agents (numtide/llm-agents.nix)**: Centralized Nix packages for AI coding agents and development tools (`github:numtide/llm-agents.nix`). Supplies `prime-agent` and DeepSeek Harness (`dsh`) via `inputs.llm-agents.packages.${system}.{prime-agent,dsh}`.
* **Gitea**: Self-hosted Git service with web UI and SSH access (`git.janusz-bit.com`).
* **TriliumNext**: Note-taking server (`services.trilium-server` from nixpkgs; the local `overrideAttrs` fix for the better-sqlite3 prebuilds bug is gone — upstream now deletes the prebuilt `linuxmusl-*.node`, see the “Zamknięte” section of `temporary-fixes.md`) and desktop client (`trilium-desktop` from nixpkgs).
* **Pre-commit Hooks**: Enforces secret scanning (`gitleaks`), formatting (`nixfmt`), linting (`statix`, `deadnix`) and workflow sync. The same checks run in CI via `checks.<system>.pre-commit` (built by the `lint` workflow).

## System Architectures & Host Deployments
The `modules/hosts/` directory contains isolated definitions targeting different deployment vectors. Each host is built upon a shared foundation but customized for its specific role.

### 1. `base` (The Foundation)
A shared foundation defined in `modules/hosts/base/default.nix` (8 modules: `base-configuration`, `base-shell`, `base-git`, `nix-settings`, `base-ssh`, `base-agenix`, `base-prime-agent`, `options`). `nixos`, `wsl` and `droid` import the whole `base` module; `raspberry-pi-4` imports only 6 of them (`modules/hosts/raspberry-pi-4/default.nix` skips `nix-settings` and `base-ssh`, so it sets its own `nix.gc`/`nix.settings` locally and does not get the base SSH agent/cloudflared proxy settings).
* Sets up the core CLI experience: `bash` is set as the login shell (to avoid compatibility issues like broken recovery environments), but automatically `exec`s `fish` for interactive sessions. Includes custom aliases (`eza`, `bat`), the `done` fish plugin for long-command notifications, and a `fish_greeting` function that runs `fastfetch` (`fastfetch` is a package gated by `customBot.enableFastfetch`, not an alias).
* Configures fundamental services: Git defaults, SSH security (key-only authentication), Agenix secrets handling, core Nix settings, `vulnix` vulnerability scanning.
* Shared packages (`modules/hosts/base/configuration.nix`): `micro-full`, `nil`, `nixd`, `nixfmt-tree`, `uv`, `toybox`, `statix`, `kdePackages.kleopatra`, `cachix`, `agenix`, `prime-agent` and `dsh` (both from `inputs.llm-agents`), `nix-update`, `tlrc`, `fzf`, `hw-probe`, `htop`, `cloudflared`, `vulnix`.
* Shell packages (`modules/hosts/base/shell.nix`): `fish`, `fishPlugins.done`, `eza`, `bat`, `fastfetch`, `p7zip` (`hw-probe` comes from the shared package list in `base/configuration.nix`). The same file enables `programs.tmux` with a shared config (vi key mode, mouse, 100k history) for every host that imports `base-shell`.
* `nix-ld` enabled to support dynamically linked binaries (e.g., from `uv`).
* `nix-index-database` with `comma` integration.
* `direnv` enabled.
* `environment.localBinInPath = true` (recommended for `uv`-installed binaries in `~/.local/bin`).
* Default editor: `micro`.
* **OpenCode**: Declarative configuration inline in `modules/overlays/opencode.nix` (Nix overlay generating `opencode.json` + `web-search-mcp.py` at build time). Default model: `ollama-cloud/glm-5.3-flash:cloud`. Plugins: `superpowers` (`superpowers@git+https://github.com/obra/superpowers.git`) and `caveman-opencode-plugin`; `websearch` permission set to `allow`; `external_directory` rule `"/nix/store/**": "allow"` so tools never prompt for `/nix/store` paths. Provider `llmgateway` (OpenAI-compatible, `https://api.llmgateway.io/v1`, apiKey from `{env:LLMGATEWAY_API_KEY}`) with models `claude-sonnet-4-6`, `gpt-5.5`, `gemini-3.1-pro`, `qwen3.8-max`, `kimi-k3`, `glm-5.2`. Provider `ollama` (OpenAI-compatible, `http://localhost:11434/v1`) with model `ornith:35b`. Provider `ollama-cloud` (OpenAI-compatible, `https://ollama.com/v1`, apiKey from `{env:OLLAMA_API_KEY}`) with models `glm-5.3-flash:cloud` (multimodal: `attachment: true`, `tool_call: true`, `modalities.input` `text, image, video` — reads images and videos) and `deepseek-v4.1-flash:cloud` (thinking + vision + tools, 1M context; `attachment: true`, `tool_call: true`, `modalities.input` `text, image`, no video). Important: opencode replaces media parts with an `ERROR: ... does not support X input` text part when the model's `modalities.input` lacks the media kind (config-defined models default to all-false, so `text` must be listed explicitly). Provider `opencode` (OpenCode Cloud, `https://api.opencode.ai/v1`, apiKey from `{env:OPENCODE_GO_API_KEY}`) with models `glm-5.2`, `kimi-k3`. Provider `llamacpp` (local llama.cpp server, `http://localhost:8080/v1`) with model `qwen3.8-27b`. Local MCP servers: `web_search_and_fetch` via `uv run` (Ollama web_search/web_fetch API) and `nixos` via `pkgs.mcp-nixos` (`lib.getExe`; NixOS/Home Manager/nixpkgs/flakes/wiki search tools). The `opencode-config` overlay is applied in `base/configuration.nix`, so the wrapped `opencode` is available on all hosts.
* **Prime Agent config** (`modules/hosts/base/prime-agent.nix`): deklaratywna
  konfiguracja prime-agenta — `models.json` (providery `ollama` lokalny,
  `http://localhost:11434/v1`, models `ornith:35b` oraz `kimi-k3:cloud` (thinking + vision + tools), z `compat.supportsDeveloperRole/supportsReasoningEffort = false`;
  oraz `ollama-cloud`, `https://ollama.com/v1`, models `deepseek-v4.1-flash:cloud`
  (thinking + vision + tools, 1M kontekstu; dodany bez zmiany defaultu) oraz
  `glm-5.3-flash:cloud` z `reasoning = true` i `input = ["text", "image"]`
  (czytanie zdjęć; schemat
  prime-agenta nie dopuszcza modalności `video` — filmy deklaruje się wyłącznie
  w opencode), klucz z env `OLLAMA_API_KEY` z agenix; oraz `openrouter`,
  `https://openrouter.ai/api/v1`, model `deepseek/deepseek-v4.1-flash`
  (reasoning + vision + tools, 1M kontekstu, 384k max output, cost
  $0.15/$0.60/$0.003 za 1M tokenów), klucz z env `OPENROUTER_API_KEY` z agenix
  (sekret `openrouter-api-key.age`, `agenix -e modules/_secrets/openrouter-api-key.age`)) i `settings.json`
  (`defaultProvider = "ollama-cloud"`, `defaultModel = "glm-5.3-flash:cloud"`, `telemetry.enabled = false` plus env `PRIME_AGENT_TELEMETRY=0` / `DO_NOT_TRACK=1` as a second layer).
  Pliki generowane do `/etc/prime-agent/` i symlinkowane przez tmpfiles do
  `~/.prime/agent/` użytkownika `customBot.defaultUser`. Trade-off: zmiany
  settings.json z TUI nie przetrwają rebuildu, a przy obecnym symlinku nie da
  się ich w ogóle zapisać (zapis trafia w read-only store path; write-and-replace
  podmienia symlink aż do następnej rundy tmpfiles po rebuildzie).
* **Nix settings** (`modules/nix-settings.nix`): Weekly GC (delete older than 7d), auto-optimise-store, trusted-users = `@wheel`.
* **Git** (`modules/hosts/base/git.nix`): user.name = `janusz-bit`, user.email = `janusz-bit@proton.me`, init.defaultBranch = `main`, `gh:` and `github:` rewritten to `https://github.com/`. `gh` CLI installed.
* **SSH** (`modules/hosts/base/ssh.nix`): Key-only authentication, `ssh.startAgent = false`, `gnupg.agent.enable = true`. Cloudflared SSH proxy configured (`ssh.*` host pattern uses `cloudflared access ssh --hostname %h`).
* **Agenix** (`modules/hosts/base/agenix.nix`): NO global env exports (formerly `environment.shellInit` — removed because secrets leaked via `import-environment` to the entire KDE session and every spawned AI agent). Secrets are injected per-process: fish wrapper functions (`prime-agent`, `opencode`, `gemini`, `cachix-push`) shipped in the system profile via `share/fish/vendor_functions.d` (`programs.fish.vendor.functions`; a tmpfiles rule migrates away the old `~/.config/fish/functions` symlinks) and read the agenix secret paths; `nix` access-tokens are rendered into `~/.config/nix/nix.conf` (0600) by the user oneshot `nix-access-tokens`. To add a new consumer, add a wrapper — never an export in a shell profile.
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
| `update-my-pkgs` | `nix run <flake>#flake-update` |
| `ls`, `la`, `ll`, `lt`, `l.` | `eza` variants |
| `..`, `...`, `....` | Directory navigation |
| `cat` | `bat` |
| `grep` | `grep --color=auto` |
| `hw` | `hwinfo --short` |

### 2. `nixos` (Main Workstation)
An `x86_64-linux` deployment for a **Lenovo LOQ-15IRX10** laptop (Nvidia GPU, Polish locale). Default user: `dinosaur`.
* **Kernel**: CachyOS kernel with LTO (`pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3`, BORE scheduler) from the `nix-cachyos-kernel` flake input (overlay applied in `modules/hosts/nixos/configuration.nix`).
* **Storage**: Disko-managed encrypted Btrfs with LUKS on `/dev/nvme1n1`. Partitions: 6G ESP (vfat `/boot`), 36G LUKS swap, rest LUKS+Btrfs (`/root`, `/home`, `/nix` subvolumes, `compress=zstd`, `noatime`). Working hibernation configured (`/dev/mapper/swap`).
* **Bootloader**: Limine, with a Windows EFI dual-boot entry. `efi.canTouchEfiVariables = true`.
* **binfmt emulation**: `aarch64-linux` emulated systems enabled (`boot.binfmt.emulatedSystems`).
* **Supported filesystems**: `btrfs` explicitly listed.
* **Desktop**: KDE Plasma 6 (Wayland) with SDDM (Wayland, autoNumlock). A **Niri** module exists (`modules/hosts/nixos/niri.nix`) but is currently commented out/disabled.
* **Audio**: Pipewire (with ALSA 32-bit and PulseAudio compat).
* **Scheduler**: `scx` (sched-ext) is configured with `scx_lavd` (`--performance`) but currently **disabled** (`enable = false`); `ananicy-cpp` with CachyOS rules is active.
* **Gaming** (`modules/hosts/nixos/gaming.nix`): Steam (with `proton-cachyos_x86_64_v3` as extraCompatPackages — Proton comes from the chaotic-nyx overlay; both `programs.gamescope.enable` and the separate Gamescope session are disabled; protontricks), GameMode, and `low-latency-layer` (Vulkan input-latency reduction). Heroic, Lutris, `protonup-qt`, OBS Studio (CUDA), Mullvad VPN (`services.mullvad-vpn` with GUI) and Wooting keyboard support (`hardware.wooting.enable`) live in `modules/hosts/nixos/packages.nix`. `dbdrun` wrapper (`modules/hosts/nixos/dbd.nix`) for Dead by Daylight (DXVK/Reflex/NVIDIA env + gamemoderun). `GAMEMODERUNEXEC` env var routes Proton through NVIDIA Prime offload.
* **AppImage support** (`modules/hosts/nixos/appimage-run.nix`): `programs.appimage` enabled with binfmt registration (custom extra packages dropped as unused).
* **Containers**: Podman with Docker compatibility, DNS enabled.
* **AI Tools** (`modules/hosts/nixos/ai.nix`): Ollama (`services.ollama`, package from nixpkgs), Open WebUI currently **disabled** (`enable = false`), `repomix`, Node.js, Python 3.13 with `pip` + `unsloth` (pinned to 3.13: python 3.14 is too new for `torchao`, an unsloth dependency); `uv` is not listed here — it comes from the base shared package list.
* **Apps**: Zed, Firefox, LibreOffice (`libreoffice-qt`), Vesktop, Signal, Element, Tor Browser, qBittorrent-enhanced, Trilium, Joplin, Nextcloud client, PrismLauncher, Lutris, VLC, Haruna, Elisa, Kdenlive, Alacritty, sbctl, bootdev-cli, ungoogled-chromium, foliate (ebook reader), OpenCode, Prime Agent (self-improving AI coding agent), DeepSeek Harness (`dsh`), `hermes-desktop` (Electron desktop shell for Hermes Agent from `inputs.hermes-agent.packages.*.desktop`, state in `~/.hermes`), losange, KDE Partition Manager, KDE QRCA, KDE KCalc, `sqlite`, `protonup-qt`, VS Code, VSCodium, `helium` (Helium browser, local package `modules/packages/_helium`, auto-updated via `flake-update`), `freecad-qt6`, `antigravity-ide-fhs`, `antigravity-cli`, `waywallen` (dynamiczne tapety Wayland, lokalny pakiet `modules/packages/_waywallen` + plugin Plasma `waywallen-kde-plugin`). Brave is **not** installed — `# brave` is commented out in `modules/hosts/nixos/packages.nix`; only the `brave-debloater` policy overlay is applied.
* **Compilers & build tools**: `cmake`, `ninja`, `clang`, `clang-tools`, `lldb`, `boost`, `wine64`, `pkgs.pkgsCross.mingwW64.buildPackages.gcc` (MinGW cross-compiler).
* **Gitea CLI**: `tea` installed (for interacting with `git.janusz-bit.com`).
* **Sync**: Syncthing (user data in `~/Sync`).
* **Overlays applied**: `brave-debloater` (browser policies), `nix-cachyos-kernel` (kernel packages), `chaotic-nyx` (bleeding-edge packages: proton-cachyos_x86_64_v3 etc., via `chaotic.nixosModules.default`; `chaotic.nyx.cache.enable = false` — nyx binary cache NOT added to `nix.settings`).
* **Memory optimization**: zRAM (`zstd`, 50% RAM, priority 100 > disk swap -2). NVMe LUKS swap (`/dev/mapper/swap`) preserved for hibernation.
* **Snapshots (`modules/hosts/nixos/snapper.nix`)**: Snapper automated Btrfs snapshots for `/` and `/home` (hourly/daily/weekly retention, user access for `dinosaur`, `snapper-gui`).
* **Lenovo Hardware & Battery (`modules/hardware/lenovo.nix`)**: `ideapad_laptop` kernel module, `services.thermald` for Intel Raptor Lake thermal management, `power-profiles-daemon` with KDE Plasma 6 ACPI `platform_profile` integration, `upower`, Battery Conservation Mode (enforced 80% charge limit on boot via tmpfiles).
* **Other services**: Avahi (mDNS), Flatpak, Btrfs autoScrub, CUPS printing (`printing.enable` + the `splix` driver only — no printer queue is declared anywhere in the repo), Bluetooth, rtkit.
* **Security**: fail2ban (max 5 retries, LAN whitelisted).
* **Locale**: Polish (`pl_PL.UTF-8`), timezone `Europe/Warsaw`, keymap `pl2`.
* **State version**: `25.11`.
* **Hardware** (`modules/hardware/LOQ-15IRX10.nix`): Lenovo hardware optimizations (`modules/hardware/lenovo.nix`), Nvidia Prime offload (intelBusId `PCI:0:2:0`, nvidiaBusId `PCI:1:0:0`), `nixos-hardware` modules for Intel CPU/GPU, Nvidia GPU, laptop, SSD. `facter.json` report. `x86-64-v3` architecture optimization (`modules/hardware/architectures/x86-64-v3.nix`).

### 3. `raspberry-pi-4` (Home Server / Cloud)
A headless `aarch64-linux` deployment for network services. Default user: `nixos`.
* **Kernel**: Custom RPi vendor kernel from `nixos-hardware` via `callPackage` with `argsOverride` injecting `PREEMPT_LAZY n` (workaround for kconfig conflict with nixpkgs `common-config.nix` on kernel >= 6.18). `boot.initrd.allowMissingModules = true` (fix for missing `dw-hdmi` module).
* **Memory optimization**: zRAM (`zstd`), 8GB SSD swap (`/var/lib/swapfile`), `vm.swappiness=100`, tmpfs for `/tmp`.
* **CPU**: `ondemand` governor.
* **Security**: fail2ban (max 5 retries, LAN whitelisted), SSH key-only.
* **Nix GC**: daily, deletes derivations older than 3 days; max 2 build jobs. Because this host does not import `nix-settings`, `nix.gc.automatic = true` is set locally in `modules/hosts/raspberry-pi-4/configuration.nix` — without it `nix.gc.dates` is ignored and the collector never runs. `documentation.doc.enable = true` — `python311-doc` builds thanks to the `python-docs-fix` overlay (nixpkgs#499166 workaround, see `temporary-fixes.md`). Trusted users include `hermes`.
* **Networking**: NetworkManager enabled. Timezone `Europe/Warsaw`.
* **User SSH keys**: Authorized keys imported DRY from `secrets.nix` (same public keys used for age encryption).
* **Nextcloud 34**: PostgreSQL backend (locally created, tuned: 128MB shared_buffers, 4MB work_mem, 32MB maintenance_work_mem, 256MB effective_cache_size), Redis cache, 2GB upload limit, PHP-FPM pool tuned for 4GB RAM (`pm = dynamic`, max_children 24, opcache interned strings 16MB), accessible **only via Cloudflare Tunnel** (no open ports, HSTS enabled). Trusted proxies: `127.0.0.1`, `::1`.
* **Hermes Agent** (`modules/hosts/raspberry-pi-4/hermes.nix`): AI agent service (`services.hermes-agent`) on port 8642. Uses `glm-5.3-flash:cloud` model via Ollama Cloud (`https://ollama.com/v1`, key from `OLLAMA_API_KEY`), `ddgs` as the web backend. `require_approval = false`. `agent.reasoning_effort = "max"`. `auxiliary.vision` configured with `glm-5.3-flash:cloud` via Ollama Cloud. `addToSystemPackages = true`. `restart = "always"`, `restartSec = 5`. Extra packages: `uv`, `nodejs_22`, `ripgrep`, `ffmpeg`, `python311`. Extra dependency groups: `all`, `messaging`, `matrix`. Configured MCP servers: `trilium-notes` (HTTP at `127.0.0.1:8081/mcp` with Bearer token) and `nixos` (`uvx mcp-nixos`). Environment loaded from `hermes-env.age` and `llmgateway-api-key.age` (agenix). Sudo NOPASSWD for user `hermes` (ALL). Service hardening overrides: `NoNewPrivileges = false` (enables sudo), `UMask = 0027` (group-readable files for `nixos` user in `hermes` group; exception: `~/.hermes/.env` with `TRILIUM_ETAPI_TOKEN` is forced to `0600` via tmpfiles `Z` rule + `ExecStartPre` chmod, so only user `hermes` reads it), `ExecStartPre` cleans stale lock/pid/state files. User `hermes` in groups: `users`, `keys`, `wheel`, `systemd-journal`, `disk`. User `nixos` added to `hermes` group.
* **Open WebUI** (`modules/hosts/raspberry-pi-4/open-webui.nix`): Open-source AI chat interface on port 3001 (localhost only), fronted by an **nginx reverse proxy on port 8080** (cloudflared ingress target) with static-asset caching (`proxy_cache`, immutable `Cache-Control` headers, gzip, response buffering). Connects to two OpenAI-compatible backends via semicolon-separated multi-endpoint lists (`ENABLE_OPENAI_API = "true"`, `OPENAI_API_BASE_URLS = "http://127.0.0.1:8642/v1;https://api.llmgateway.io/v1"`): index 0 = Hermes Agent (`127.0.0.1:8642/v1`), index 1 = LLM Gateway devpass (`api.llmgateway.io/v1`). Keys paired by index in `OPENAI_API_KEYS` from the age-encrypted `open-webui-keys.age` (appended to the service via a second `systemd.serviceConfig.EnvironmentFile`, kept out of `environment {}` so they never enter the world-readable nix store). Ollama API disabled (`ENABLE_OLLAMA_API = "false"`). Auth required (`WEBUI_AUTH = "True"`). `ENABLE_PERSISTENT_CONFIG = "False"` (env vars override DB-stored values). Stateful Responses API enabled. Session/auth cookies set to `Secure` + `SameSite=none` (required behind Cloudflare Tunnel TLS termination). Shared Hermes API key via `hermes-env.age`.
* **Ollama**: Local LLM backend (`services.ollama.enable`), EnvironmentFile from `hermes-env.age`.
* **Gitea** (`modules/hosts/raspberry-pi-4/gitea.nix`): Self-hosted Git service on port 3000 (localhost only). SQLite database. Domain `git.janusz-bit.com`. Registration disabled. Cookie secure enabled. SSH access via system SSH (port 22, `START_SSH_SERVER = false`). `tea` (Gitea CLI) installed in system packages.
* **ttyd** (`modules/hosts/raspberry-pi-4/ttyd.nix`): Web terminal on port 8082 — binds to loopback only, firewall closed, exposed **only** through the Cloudflare Tunnel (`ttyd.${customTop.site.full}` ingress). Auth: HTTP Basic (user `admin`, password = Nextcloud admin password reusing the existing `nextcloud-adminpass.age` secret via systemd `LoadCredential` — no new secret, nothing sensitive in the nix store). Entrypoint spawns the system `login` program (full PAM session, aliases and PATH), not a bare shell.
* **Cloudflared**: Tunnel to expose services externally (root and `chat.` hosts get `originRequest` tuning: `connectTimeout = 300s`, keepalive settings, to survive long photo uploads / slow LLM streams):
  * `${customTop.site.full}` -> Nextcloud (localhost:80)
  * `chat.${customTop.site.full}` -> Open WebUI via nginx (localhost:8080)
  * `notes.${customTop.site.full}` -> Trilium (localhost:8081)
  * `ssh.${customTop.site.full}` -> SSH (localhost:22)
  * `git.${customTop.site.full}` -> Gitea (localhost:3000)
  * `ttyd.${customTop.site.full}` -> ttyd web terminal (localhost:8082)
* **Trilium**: Note-taking server on port 8081 (`services.trilium-server` from nixpkgs — no dedicated flake input, and no local `overrideAttrs` anymore: upstream `installPhase` already deletes the prebuilt `linuxmusl-*.node`; the closed workaround is tracked in `temporary-fixes.md`). ETAPI token (Bearer) shared between Hermes and Prime Agent via agenix secret `trilium-etapi.age` (`root:users` 0440, `modules/agenix/agenix.nix`); Prime Agent uses it through the declarative `trilium-notes` skill (`modules/skills/trilium-notes` — HTTP MCP `http://127.0.0.1:8081/mcp`, token auto-loaded from `/run/agenix/trilium-etapi`).
* **Fan control**: Custom Python-based systemd service (`pwm-fan`, `rpi-lgpio` package with `RPI_LGPIO_REVISION` override) for GPIO PWM fan control based on CPU temperature (GPIO BCM pin 14, thresholds: 60C=100%, 48C=50%, else 0%).
* **LED control** (`modules/hosts/raspberry-pi-4/leds-off.nix`): All LEDs disabled via DT overlays (`hardware.raspberry-pi."4".leds` — eth, act, pwr) and systemd-tmpfiles rules (mmc0, default-on).
* **Prime Agent CLI**: Self-improving coding agent (RLM) package from `numtide/llm-agents.nix` (`inputs.llm-agents.packages.${system}.prime-agent`), available system-wide as `prime-agent` after rebuild.
* **Overlays applied**: `opencode-config` from base.
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
* `customBot.flakeTarget = "droid"`.
* **State version**: `26.05`.

## Repository Architecture
The repository uses a highly modular structure powered by `flake-parts` and `import-tree`, which auto-discovers and maps the codebase logically.

* **`flake.nix`**: Entry point. Defines all external inputs and passes them to `import-tree` to dynamically load the `modules/` folder. Declares the `janusz-bit.cachix.org` binary cache.
* **`modules/args.nix`**: Defines `customTop` arguments passed to all modules. Contains: repository info (`github:janusz-bit/nixos`, `/etc/nixos`), email (`janusz-bit@proton.me`), site domain (`janusz-bit.com`), Cachix cache info, `secretsDir`.
* **`modules/options.nix`**: Custom NixOS options (`customBot`): `flakeTarget` (default: `"default"`), `enableFastfetch` (default: `true`), `defaultUser` (default: `"nixos"`).
* **`modules/default.nix`**: Integration module. Defines `systems` (`x86_64-linux`, `aarch64-linux`), `devShells`, formatter (`nixfmt-tree`), pre-commit hooks (`gitleaks`, `nixfmt`, `statix`, `deadnix`, `sync-github-actions`), and exposes `flake-update`, `flake-release` and `repo-sync` packages in the dev shell.
* **`modules/github-actions.nix`**: CI/CD factory that auto-generates GitHub Actions workflows. Generates 7 workflows from a config map: `nixos`, `raspberry-pi-4`, `raspberry-pi-4-sd-image`, `wsl`, `droid` (build on tag push `v*` / PR to master), `lint` (builds `checks.x86_64-linux.pre-commit` — gitleaks + nixfmt/statix/deadnix + workflow sync), `cachyos-kernel-update` (manual `workflow_dispatch` only — daily cron currently commented out; updates the `nix-cachyos-kernel` flake input and rebuilds the CachyOS kernel). The `nixos` build is the exception: `tags = false`, so it runs only on PRs to `master` and on manual `workflow_dispatch` — the toplevel build takes 3–5 h and mostly fails on CI infrastructure. Every build workflow gets `permissions.contents = "read"` (least privilege) and a `concurrency` group `build-<name>-${ github.ref }` with `cancelInProgress = false` (same workflow + same ref never runs twice, in-flight builds are not cancelled); `cachyos-kernel-update` has its own `cachyos-kernel-update` concurrency group. The separate `build-kernel` job machinery exists but is currently disabled (kernel built manually, not in CI). Maps `x86_64-linux` to `ubuntu-latest`, `aarch64-linux` to `ubuntu-24.04-arm`. The sync script deletes orphaned workflow files before copying, so a refactor cannot leave stale YAML behind.
* **`modules/hardware/`**: Hardware-specific profiling. Stores Lenovo LOQ-15IRX10 patches, `x86-64-v3` CPU optimization, `M27Q.icm` color profile, and a `facter.json` inventory.
* **`modules/agenix/` & `modules/_secrets/`**: Cryptographic secrets. 15 age-encrypted files (GitHub token, Cachix token, Cloudflare tunnel, Nextcloud adminpass, Trilium ETAPI token, Hermes env/API key, Ollama API key, Google API key, LLM Gateway API key, OpenRouter API key, OpenCode API key, Open WebUI env/keys, notes, `secret1` (shared SSH authorized keys)) stored safely in the repo, decryptable only by target machines. Secrets defined in `modules/_secrets/secrets.nix` with per-host SSH public keys. `hermes-env`, `hermes-api-key`, `opencode` and `open-webui-keys` target only `nixos` and `raspberry-pi-4` (not `droid-android`); `llmgateway-api-key` and `openrouter-api-key` target all hosts; `secret1` is used on `raspberry-pi-4` for user SSH authorized keys. The unused `attic-server-token.age`, `hermes-webui-env.age` and `librechat-env.age` secrets were removed.
* **`modules/overlays/`**: Nixpkgs patches (flake-level overlays). `brave.nix` (`brave-debloater`: extensive Brave browser policy hardening — disables AI, rewards, wallet, VPN, tor, telemetry, sync, password manager, autofill, etc.; sets AdGuard DNS-over-HTTPS), `opencode.nix` (`opencode-config`: wraps `opencode` with inline `opencode.json` config + `web-search-mcp.py` MCP server, sets `OPENCODE_CONFIG` env var and `OPENCODE_DISABLE_AUTOUPDATE`; `permission.external_directory` allows `/nix/store/**`), `python-docs-fix.nix` (`python-docs-fix`: pins docutils 0.21.2 + sphinx 8.2.3 in the cpython docs-builder — nixpkgs#499166 workaround, tracked in `temporary-fixes.md`; applied on `raspberry-pi-4` only). Applied via `self.overlays` in host configs and base.
* **`modules/packages/`**: Custom packages and scripts.
  * `my-neovim` (nvf-based Neovim with gruvbox, LSP, Telescope, which-key, lualine, treesitter, nix/python/clang)
  * `flake-update` (updates flake.lock, syncs workflows, updates `helium`, `waywallen` and `bootdev-cli` via `nix-update`)
  * `flake-release` (commits, auto-increments git tag, pushes)
  * `install-system` (default package; runs disko, clones repo, nixos-install)
  * `raspberry-pi-4-sd-image` (aarch64 SD card image build)
  * `bootdev-cli` (Go module, auto-updated via `nix-update` in `flake-update`; currently v1.32.2)
  * `helium` (Helium browser from `imputnet/helium-linux` release `.deb`s; auto-updated via `nix-update` in `flake-update`, two passes: x86_64 version+hash, then `--version skip` for the aarch64 hash)
  * `waywallen` (dynamiczne tapety Wayland z oficjalnego AppImage v0.3.9 + prebuild pluginu open-wallpaper-engine v0.2.9; auto-updated via `nix-update` in `flake-update`, dwa pasy jak helium — `oweVersion` bumpowany ręcznie)
  * `waywallen-kde-plugin` (plugin tapety dla Plazmy 6 z release waywallen-display v0.3.3)
  * Note: `prime-agent` and DeepSeek Harness (`dsh`) are provided via the `numtide/llm-agents.nix` flake input (local derivations `_prime-agent` and `_deepseek-harness` removed).
  * Note: Proton-CachyOS x86-64-v3 is no longer built locally (`_proton-bin` derivation removed); it comes from the chaotic-nyx overlay + binary cache.
* **`modules/templates/`**: Project scaffolds. `nix flake init -t .` bootstraps a new `_project.nix` template.
* **`docs/`**: Design plans and specs (`docs/superpowers/plans/`, `docs/superpowers/specs/`) — 5 tracked markdown files describing past changes (Prime Agent, nyx cache, Hermes desktop, OpenCode store).
* **`temporary-fixes.md`**: Tracker of temporary upstream workarounds, split into “Aktywne” (with removal conditions and upstream issue links) and “Zamknięte” (closed entries kept for history).

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
16 inputs (`flake.nix`):
* `nixpkgs` — `github:NixOS/nixpkgs/nixos-unstable` (base package set)
* `import-tree` — `github:vic/import-tree` (auto-discovery of `modules/` directory)
* `flake-parts` — `github:hercules-ci/flake-parts` (flake module system)
* `nixos-wsl` — `github:nix-community/NixOS-WSL/main` (WSL support)
* `nvf` — `github:notashelf/nvf` (declarative Neovim config)
* `avf` — `github:nix-community/nixos-avf` (Android Virtualization Framework)
* `nix-index-database` — `github:nix-community/nix-index-database` (follows nixpkgs; for `comma`)
* `chaotic` — `github:chaotic-cx/nyx/nyxpkgs-unstable` (Chaotic-Nyx: bleeding-edge packages + nyx binary cache; nixos host only)
* `nix-cachyos-kernel` — `github:xddxdd/nix-cachyos-kernel/release` (CachyOS kernel packages; no `nixpkgs.follows` on purpose)
* `nixos-hardware` — `github:NixOS/nixos-hardware/master` (hardware modules)
* `agenix` — `github:ryantm/agenix` (follows nixpkgs; secrets management)
* `disko` — `github:nix-community/disko` (follows nixpkgs; disk partitioning)
* `git-hooks-nix` — `github:cachix/git-hooks.nix` (follows nixpkgs; pre-commit hooks)
* `github-actions-nix` — `github:synapdeck/github-actions-nix` (CI workflow generation)
* `hermes-agent` — `github:NousResearch/hermes-agent` (unpinned — see hermes-agent note above)
* `llm-agents` — `github:numtide/llm-agents.nix` (prime-agent + dsh packages)

## Dev Shell Tools
Running `nix develop` provides:
* `flake-update` – updates `flake.lock`, commits it, then updates the pinned local packages via `nix-update`: `helium` and `waywallen` (two passes: x86_64 version+hash, then `--version skip` aarch64 hash) and `bootdev-cli`.
* `flake-release` – commits, auto-increments the git tag, pushes to GitHub.
* `repo-sync` (`modules/packages/scripts.nix`) – `git add -A` + commit, then `git pull --rebase --autostash` and `git push`.
* Pre-commit hooks auto-installed: `gitleaks` (secret scan of the staged diff; NOT a built-in git-hooks-nix hook — defined as a custom hook in `modules/default.nix` with an explicit `entry`), `nixfmt` formatter, `statix` lint, `deadnix` lint (with `noLambdaPatternNames`), `sync-github-actions` (syncs generated workflow YAML to `.github/workflows/`). The sync script deletes stale workflow files first, so no orphaned YAML survives a refactor.

**Pitfall — stale `sync-github-actions` hook.** The hook `entry` points at the store path built when you entered the dev shell (`config.packages.sync-github-actions`). After editing `modules/github-actions.nix`, the already-installed hook keeps copying workflows from the **previous** flake revision and reverts the new `.yml` files — the symptom is `sync-github-actions ... Failed / files were modified by this hook` plus a stale workflow in the commit (this is how the old `cachyos-kernel-update.yml` incident happened). Fix: leave and re-enter `nix develop` to refresh the hooks, or commit with `SKIP=sync-github-actions git commit` after `nix run .#sync-github-actions`. CI is unaffected, because `checks.<system>.pre-commit` builds the hooks from scratch from the current flake.

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
* **Formatting, linting & secret scanning**: `gitleaks` + `nixfmt` + `statix` + `deadnix` (enforced via pre-commit and the CI `lint` workflow building `checks.<system>.pre-commit`).
* **Pre-commit hooks**: gitleaks, formatter, linters + `sync-github-actions` (keeps workflow YAML in sync with the Nix-generated definitions; deletes orphaned files first).
* **Dev shell**: Always use `nix develop` to ensure pre-commit hooks and required tools are bootstrapped automatically.
* **Secrets**: Never write API keys, passwords, or tokens directly in `.nix` files (they end up in the world-readable `/nix/store`). Always use Agenix with `environmentFiles` from age-encrypted secrets.
* **Git workflow (mandatory)**: Any change to tracked files must be finished with a commit (local update) and a push to `origin` (published update) before the work is considered done. Never leave the working tree dirty or unpushed. Commit style: short lowercase summary prefixed with the area, e.g. `nixos: ...`, `docs: ...` (see `git log`).
* **Skills**: Always store new AI-agent skills (SKILL.md format) in `modules/skills/<skill-name>/` (directory with `SKILL.md` + `references/`; python skill packages additionally `src/<pkg>/` + `pyproject.toml` — the kernel bootstrap installs them with `uv pip install --editable`) and register them in the `skills` attrset in `modules/skills/default.nix`. Never create skills ad-hoc in `~/.prime/agent/skills/` or elsewhere — declarative storage is the single source of truth. Apply with `nixos-rebuild switch` (systemd-tmpfiles auto-symlinks each skill into `~/.prime/agent/skills/`; only Prime Agent, not opencode/gemini-cli). For runtime skills WITHOUT a rebuild (added manually or by Prime Agent itself), drop them into `/etc/ai/<skill-name>/` — `prime-agent-skills-import.service` (boot oneshot + systemd.path watcher on `/etc/ai`) auto-symlinks every directory containing `SKILL.md` into `~/.prime/agent/skills/` and cleans up removed skills; declarative skills always win on name conflicts.
* **CI**: Tag push (`v*`) triggers the build workflows — except `nixos`, which runs only on PRs to `master` and on manual `workflow_dispatch` (`tags = false`, because the toplevel build takes 3–5 h and often fails on CI infrastructure). Tags auto-increment sequentially via `flake-release` (latest: `v505`). 7 workflows generated from `modules/github-actions.nix` (6 builds + `lint`).

## Repository Statistics
* 109 tracked files (excluding `.git/`)
* 66 `.nix` files, ~4010 LOC total (`git ls-files '*.nix' | xargs wc -l`)
* 15 age-encrypted secrets (`modules/_secrets/*.age`)
* 7 workflow `.yml` files in `.github/workflows/` (all auto-generated from `modules/github-actions.nix`)
* 5 host configurations: `nixos`, `raspberry-pi-4`, `wsl`, `droid`, `default` (alias for `nixos`)
* 3 Nixpkgs overlays: `brave-debloater`, `opencode-config`, `python-docs-fix`
* Channel: `nixos-unstable`