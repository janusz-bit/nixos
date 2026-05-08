# NixOS Configuration Flake

## Project Overview
This repository contains a centralized, declarative NixOS system configuration architecture using Nix Flakes. The project defines environments and manages states across multiple hardware architectures, specifically supporting `x86_64-linux` and `aarch64-linux` platforms. The codebase structures Nix modules dynamically utilizing `flake-parts` and `vic/import-tree`. 

Integrated technologies handling the system's core capabilities include:
* **Home Manager**: Manages user-specific environments and dotfiles.
* **Agenix**: Handles encrypted system secrets.
* **Attic**: Self-hosted Nix binary cache.
* **Disko**: Automates disk partitioning and formatting.
* **NixOS-WSL**: Provides configurations for the Windows Subsystem for Linux.
* **Pre-commit Hooks**: Enforces CI/CD and repository consistency constraints.

## System Architectures & Hosts
The repository contains isolated host definitions targeting different deployment vectors:
* **NixOS (Default)**: An `x86_64-linux` system deployment implementing specific hardware configuration for a Lenovo LOQ-15IRX10 laptop.
* **Raspberry Pi 4**: An `aarch64-linux` platform deployment.
* **WSL**: Configurations mapped for Windows Subsystem for Linux integration.

## Building and Running
System deployments are executed via standard NixOS flake reconstruction commands.

To build and switch the configuration for a given host:
* `sudo nixos-rebuild switch --flake .#nixos`
* `sudo nixos-rebuild switch --flake .#raspberry-pi-4`

To build and push the configuration to the Attic binary cache:
* `push` (shell alias)

The repository also exposes an automated installation script via `packages.install-system`, accessible as the flake's default package.

## Development Conventions
* **Formatting Enforcement**: Code formatting is strictly unified using `nixfmt-tree`.
* **Pre-commit Validation**: Development relies heavily on local git hooks. The pre-commit pipeline is configured to run the formatter and synchronize GitHub Actions state (`sync-github-actions`).
* **Environment Initialization**: Generating a shell context (via `nix develop`) automatically bootstraps the required pre-commit installation scripts into the shell hook alongside necessary formatter packages.
