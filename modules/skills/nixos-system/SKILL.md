---
name: nixos-system
description: This machine runs NixOS, configured declaratively by the flake in /etc/nixos (github:janusz-bit/nixos, no Home Manager) — it is NOT a conventional FHS Linux distribution. Use this skill before installing or looking up software, running downloaded or prebuilt binaries, compiling code, writing scripts or shebangs, installing pip/npm/cargo packages globally, editing anything under /etc, changing systemd units, users, firewall, drivers or kernel modules, reaching for sudo, or whenever a command, shared library or header is "not found". Covers nix shell / comma / nix-ld, how system changes are made and activated, privilege limits, secrets, and the facts of the current host.
---

# Working on this NixOS machine

The whole system — packages, `/etc`, systemd units, users, firewall, kernel,
drivers — is the build output of the flake in `/etc/nixos`
(`github:janusz-bit/nixos`). Imperative changes are either impossible
(read-only store) or silently lost on the next rebuild. The exact facts of the
host you are on are in **This host** at the end of this file.

## Ground rules

1. **Never install system-wide imperatively.** No `apt`/`dnf`/`pacman` (they
   don't exist), no `nix-env -i`, no `nix profile install`, no `sudo pip`,
   no `curl … | sh` installers. Run a tool ad hoc (below) or add it to the flake.
2. **Never edit generated files.** Anything under `/nix/store`, `/etc/static`,
   and every file that is a symlink into them (most of `/etc`, every systemd
   unit) is managed by Nix. Check with `readlink -f <file>`; change the Nix
   option that produces it instead.
3. **No FHS paths.** Only `/bin/sh` and `/usr/bin/env` exist. There is no
   `/usr/lib`, `/usr/include`, `/usr/local`, `/bin/bash` or `/usr/bin/python3`.
4. **You cannot use sudo.** It asks for a password and your shell has no tty.
   Hand privileged commands to the user (see *Changing the system*).
5. **Never read, print or copy secrets** (`/run/agenix/*`, `~/.ssh/id_*`,
   `/var/lib/sbctl`, tokens in env or config files).
6. **Mind build cost.** A `nix build` / `nix shell` that misses the binary
   cache compiles locally — hours for CUDA packages or the kernel on the
   laptop, and the RPi is slow at everything. `nix build --dry-run <installable>`
   lists "will be built" vs "will be fetched"; ask before a large local build.

## Where things are

| What | Where |
|---|---|
| System-wide binaries | `/run/current-system/sw/bin` (on `PATH`) |
| Per-user packages from the config | `/etc/profiles/per-user/$USER/bin` |
| User-installed tools (uv, npm, pipx) | `~/.local/bin` — on `PATH`, writable |
| Running system | `/run/current-system` → `/nix/store/…-nixos-system-…` |
| GPU driver libs (`libcuda`, …) | `/run/opengl-driver/lib` |
| Decrypted secrets | `/run/agenix/` — do not touch |
| Mutable state | `/var/lib/<service>`, `$HOME` |
| Config source | `/etc/nixos` (git repo; has its own `AGENTS.md`) |

Store paths contain hashes that change on every update: never hardcode a
`/nix/store/…` path in scripts, configs or instructions. In shell use
`command -v foo`; in Nix use `lib.getExe pkgs.foo` / `"${pkgs.foo}/bin/foo"`.
Shebangs: `#!/usr/bin/env bash` (or `python3`, …), never `#!/bin/bash`.

## Getting a program

| Need | Do |
|---|---|
| Is it installed? | `command -v foo` |
| Which package ships binary `foo`? | `nix-locate --minimal --at-root --whole-name /bin/foo` (offline DB) |
| Which package ships a file/lib? | `nix-locate --minimal --whole-name libfoo.so.1` |
| Does attribute `foo` exist, which version? | `nix eval nixpkgs#foo.version` (avoid slow `nix search`) |
| Run once | `nix run nixpkgs#foo -- args` or `nix shell nixpkgs#foo nixpkgs#bar -c cmd args` |
| Run once by binary name | `, foo args` (comma; interactive picker if several packages match — prefer `nix shell` in scripts) |
| Permanently | add it to the flake (see *Changing the system*) |

`nixpkgs` in the flake registry and `NIX_PATH` is pinned to the system's own
nixpkgs revision, so `nixpkgs#…` and `nix-shell -p …` reuse the store and the
binary cache — no channel download, versions match the system.

## Language toolchains

- **Python:** use `uv` — `uv venv`, `uv add`, `uv run --with requests script.py`,
  `uvx tool`, `uv tool install tool` (→ `~/.local/bin`). Never `pip install` into
  the system or `--user`. Manylinux wheels work through nix-ld only when their
  native deps are in the nix-ld library list (see *This host*); otherwise use a
  nixpkgs build: `nix-shell -p 'python3.withPackages (ps: [ ps.numpy ps.opencv4 ])'`.
  CUDA wheels (torch, …) also need the driver: `LD_LIBRARY_PATH=/run/opengl-driver/lib`.
- **Node:** `npx`, project-local `npm install`, or `npm install -g --prefix ~/.local <pkg>`
  (plain `npm -g` fails: its prefix is in the read-only store).
- **C/C++/Rust/Go builds needing system libraries:** there are no headers or
  `.pc` files globally. Use `nix-shell -p pkg-config openssl zlib --run 'cargo build'`
  — `nix-shell -p` runs setup hooks (sets `PKG_CONFIG_PATH`, `NIX_CFLAGS_COMPILE`,
  …); `nix shell` only extends `PATH` and is not enough for compiling.
  Projects with a `flake.nix` / `shell.nix`: `nix develop` / `nix-shell`
  (direnv is enabled: `.envrc` with `use flake` loads it automatically).

## Prebuilt / downloaded binaries

- Dynamically linked binaries run through **nix-ld** (`/lib64/ld-linux-x86-64.so.2`
  is its shim), but they find only the libraries in the nix-ld list.
  `error while loading shared libraries: libX.so.N` → find the package with
  `nix-locate --minimal --whole-name libX.so.N`, then either run it with
  `LD_LIBRARY_PATH="$(nix build --no-link --print-out-paths nixpkgs#<pkg>.out)/lib" ./binary`
  (do not override `NIX_LD_LIBRARY_PATH` — it carries the default list), or
  propose adding the package to `programs.nix-ld.libraries` in the flake.
- Prefer the nixpkgs package over a downloaded binary whenever one exists.
- `steam-run <binary>` gives a broad FHS-like runtime; `appimage-run file.AppImage`
  runs AppImages (laptop only — check with `command -v`).
- Inspect with `file`, `ldd`; `patchelf` via `nix shell nixpkgs#patchelf`.

## Inspecting the system

- Version / generation: `nixos-version`, `readlink /run/current-system`.
- Effective value of any option (fast, no root):
  `nix eval /etc/nixos#nixosConfigurations.<target>.config.<option.path>`
  (`--raw` for strings, `--json` for structures). Option docs: `man configuration.nix`.
- Services: `systemctl status <unit>`, `systemctl cat <unit>` (the generated unit),
  `journalctl -u <unit> -b`, `systemctl list-units --type=service --state=running`.
- Store: `nix path-info -rSh <path>` (closure size), `nix why-depends <a> <b>`,
  `nix store diff-closures /run/current-system ./result`.
- Pinned inputs: `nix flake metadata /etc/nixos`. Package versions come from
  `flake.lock`, not from upstream "latest".

## Changing the system

1. Edit the flake in `/etc/nixos` — read its `AGENTS.md` first (module map,
   verification steps, git rules). Claude Code for that repo is meant to run as
   `claude-nixos` (dev shell with pre-commit hooks).
2. The kind of change decides the option, never a manual edit:

   | Instead of | Use in the flake |
   |---|---|
   | installing a package | `environment.systemPackages` (or `users.users.<u>.packages`) |
   | editing `/etc/foo` | the module option that renders it, or `environment.etc."foo"` |
   | `systemctl edit` / `enable`, unit files, cron | `systemd.services.<n>` / `systemd.timers.<n>` (no cron) |
   | `iptables`, `ufw` | `networking.firewall.*` |
   | `useradd`, `usermod -aG` | `users.users.<u>` / `extraGroups` |
   | `modprobe` at boot, `/etc/modprobe.d` | `boot.kernelModules`, `boot.extraModprobeConfig` |
   | `sysctl -w` | `boot.kernel.sysctl` |
   | patching an installed program | an overlay or `.overrideAttrs` |

3. Verify without root: `nix eval --raw /etc/nixos#nixosConfigurations.<target>.config.system.build.toplevel.drvPath`,
   then `nixos-rebuild build --flake /etc/nixos#<target>` for package/service changes.
4. Activation needs root — the **user** runs it in their own terminal:
   `update-local` (switch from `/etc/nixos`) or `update` (switch from GitHub
   `master`, i.e. only after a push); `*-boot` variants apply on next boot.
   Not via Claude Code's `!` prefix (no tty for the sudo password). Afterwards
   check units with `systemctl status` / `journalctl`.
5. Rollback: the previous generation in the boot menu, or (user, root)
   `sudo nixos-rebuild switch --rollback`. Never run `nix-collect-garbage -d`
   — it deletes rollback generations (GC is already automatic).

Things outside Nix: `$HOME` dotfiles are not managed (no Home Manager) and may
be edited directly — unless the file is a symlink into `/nix/store` or `/etc`.
`/etc/nixos` and `/etc/ai` (runtime skill drop-in for Prime Agent) are mutable.

## Privileges and security

- `sudo` requires a password; `nix.settings.trusted-users` is root only, so
  `--option substituters`, unsigned imports and similar need root too.
- Containers: rootless `podman` (where enabled, `docker` is podman's
  compatibility wrapper); the user is deliberately not in the `podman` group —
  do not add it.
- Secrets are agenix files decrypted to `/run/agenix/` at activation. Tools get
  them per process through wrappers defined in the flake; never export them
  globally, never write secret values into `.nix` files (the store is
  world-readable).

## Common symptoms

| Symptom | Cause → fix |
|---|---|
| `bash: foo: command not found` | not installed → `nix-locate`, then `nix shell` / `,` |
| `/bin/bash: bad interpreter` | FHS shebang → `#!/usr/bin/env bash` |
| `Read-only file system` under `/nix/store` or `/etc` | generated file → change the Nix option |
| `error while loading shared libraries` | missing nix-ld lib → see *Prebuilt binaries* |
| `fatal error: foo.h: No such file` / `pkg-config` can't find | → `nix-shell -p pkg-config foo` |
| `npm ERR! EACCES` on `-g` | → `--prefix ~/.local` or `npx` |
| `systemctl enable` / `edit` fails or reverts | units are generated → `systemd.*` in the flake |
| change "lost" after reboot | made imperatively → put it in the flake |
| alias like `update-local` missing in the Bash tool | aliases and fish functions are interactive-only → give the command to the user |
