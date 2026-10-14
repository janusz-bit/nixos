# Generator workflowów GitHub Actions (github-actions-nix): build toplevelu
# każdego hosta z rejestru, obrazy (SD RPi, ISO instalatora), ewaluacja
# wszystkich hostów, lint (pre-commit) i ręczna aktualizacja kernela CachyOS.
#
# .github/workflows/*.yml to wynik tego pliku: nigdy nie edytuje się ich
# ręcznie. `nix run .#sync-github-actions` kopiuje wygenerowany katalog do
# repo i usuwa workflowy, których już nie ma; hook pre-commit robi to sam
# przy każdym commicie (ręczna edycja zostaje nadpisana).
# Workflowy buildów hostów powstają z rejestru (modules/hosts/registry.nix),
# więc nowy host dostaje swój workflow bez zmian tutaj.
#
# Akcje są przypięte do SHA commitów, nie tagów: tag można przesunąć na inny
# kod, a akcje widzą CACHIX_AUTH_TOKEN, w cachyos-kernel-update także
# `contents: write` (push flake.lock). Ciężkie buildy (host z
# buildOnTags = false i ISO z całym closure hosta nixos, 3-5 h) nie ruszają
# przy tagach v*, tylko przy PR i ręcznie.
#
# Sprawdzenie: `nix run .#sync-github-actions && git status --short .github/workflows`
# (pusto = workflowy w repo zgodne z generatorem).
{
  config,
  customTop,
  lib,
  ...
}:
let
  # Rejestr hostów (modules/hosts/registry.nix); perSystem ma własne `config`.
  inherit (config) hosts;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Bump SHA: `git ls-remote https://github.com/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`.
      actions = {
        checkout = "actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"; # v5
        installNix = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"; # v31
        cachix = "cachix/cachix-action@18cf96c7c98e048e10a83abd92116114cd8504be"; # v14
      };

      # Wspólne kroki dla wszystkich workflowów budujących
      mkBaseSteps = [
        {
          name = "Checkout repository";
          uses = actions.checkout;
        }
        {
          name = "Install Nix";
          uses = actions.installNix;
          with_ = {
            extra_nix_config = ''
              experimental-features = nix-command flakes
              access-tokens = github.com=''${{ secrets.GITHUB_TOKEN }}
              extra-substituters = ${customTop.cache.cachix.url}
              extra-trusted-public-keys = ${customTop.cache.cachix.pubKey}
              build-fallback = true
            '';
          };
        }
        {
          name = "Setup Cachix";
          uses = actions.cachix;
          with_ = {
            name = customTop.cache.cachix.name;
            authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
          };
        }
      ];

      # Workflow aktualizujący i budujący kernel CachyOS
      mkCachyOSKernelUpdateWorkflow =
        { name, runsOn }:
        {
          inherit name;
          runName = "Update & Build CachyOS Kernel by @\${{ github.actor }}";
          on.workflowDispatch = { };
          permissions.contents = "write";
          # Ręcznie odpalany workflow — bez sensu dwa równoległe buildy kernela
          concurrency = {
            group = "cachyos-kernel-update";
            cancelInProgress = false;
          };
          jobs.update-and-build = {
            inherit runsOn;
            steps = mkBaseSteps ++ [
              {
                name = "Update nix-cachyos-kernel flake input";
                run = "nix flake update nix-cachyos-kernel";
              }
              {
                name = "Build Kernel";
                run = "nix build \".#nixosConfigurations.nixos.config.boot.kernelPackages.kernel^*\" --show-trace --accept-flake-config";
              }
              {
                name = "Commit updated flake.lock";
                run = ''
                  git config user.name "github-actions[bot]"
                  git config user.email "github-actions[bot]@users.noreply.github.com"
                  git add flake.lock
                  git diff --cached --quiet || git commit -m "flake.lock: update nix-cachyos-kernel"
                  git push
                '';
              }
            ];
          };
        };

      # Fabryka workflowów
      mkBuildWorkflow =
        {
          name,
          runsOn,
          buildTarget ? "nixosConfigurations.${name}.config.system.build.toplevel",
          runName ? "Build ${name} by @\${{ github.actor }}",
          command ? null,
          # `tags = false` dla ciężkich buildów. Build toplevela `nixos` trwa
          # 3-5 h i w większości pada na infrastrukturze CI (cache.nixos.org,
          # limity api.github.com), więc nie odpalamy go przy każdym tagu —
          # zostaje PR + ręczny workflow_dispatch.
          tags ? true,
          # Tanie sprawdzenia (lint, ewaluacja) odpalają się też na każdy
          # push do master — commity trafiają tam bezpośrednio.
          onMaster ? false,
        }:
        {
          inherit name runName;
          # Least privilege: buildy tylko czytają repo.
          permissions.contents = "read";
          # Ten sam workflow dla tego samego refa nie odpala się dwa razy.
          # cancelInProgress = false — nie zabijamy buildów w trakcie.
          concurrency = {
            group = "build-${name}-\${{ github.ref }}";
            cancelInProgress = false;
          };
          on = {
            push =
              if tags || onMaster then
                lib.optionalAttrs tags { tags = [ "v*" ]; }
                // lib.optionalAttrs onMaster { branches = [ "master" ]; }
              else
                null;
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs.build = {
            inherit runsOn;
            steps = mkBaseSteps ++ [
              {
                inherit name;
                run =
                  if command == null then
                    "nix build \".#${buildTarget}\" --show-trace --accept-flake-config"
                  else
                    command;
              }
            ];
          };
        };

      # Mapa architektur na GitHub Runners
      archToRunner = {
        "x86_64-linux" = "ubuntu-latest";
        "aarch64-linux" = "ubuntu-24.04-arm";
      };

    in
    {
      packages.github-actions = config.githubActions.workflowsDir;

      packages.sync-github-actions = pkgs.writeShellApplication {
        name = "sync-github-actions";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          WORKFLOWS_DIR="${config.githubActions.workflowsDir}"
          echo "Syncing workflows from $WORKFLOWS_DIR to .github/workflows/..."
          mkdir -p .github/workflows
          # Usun stare workflowy, ktore nie sa juz generowane (np. po refactorze),
          # zeby nie zostaly osierocone pliki w .github/workflows/.
          find .github/workflows -name '*.yml' -delete
          cp -f "$WORKFLOWS_DIR"/*.yml .github/workflows/
          chmod +w .github/workflows/*.yml
          echo "Done! Workflows are now in sync."
        '';
      };

      githubActions = {
        enable = true;
        # Build toplevela każdego hosta z rejestru, obrazy i tanie sprawdzenia.
        workflows =
          lib.mapAttrs
            (
              name: cfg:
              mkBuildWorkflow (
                {
                  inherit name;
                  runsOn = archToRunner.${cfg.arch};
                }
                // removeAttrs cfg [ "arch" ]
              )
            )
            (
              lib.mapAttrs (_: host: {
                arch = host.system;
                tags = host.buildOnTags;
              }) hosts
              // {
                raspberry-pi-4-sd-image = {
                  arch = "aarch64-linux";
                  buildTarget = "packages.aarch64-linux.raspberry-pi-4-sd-image";
                };
                nixos-iso = {
                  arch = "x86_64-linux";
                  buildTarget = "packages.x86_64-linux.nixos-iso";
                  # ISO w pełni offline (modules/installer) zawiera cały
                  # closure hosta nixos — ten sam koszt (3-5 h) co build
                  # hosta, więc nie na każdy tag.
                  tags = false;
                };
                # Ewaluacja wszystkich hostów (sekundy zamiast godzin buildu)
                # łapie błędy ewaluacji przy każdym pushu do master.
                eval = {
                  arch = "x86_64-linux";
                  runName = "Evaluate hosts by @\${{ github.actor }}";
                  onMaster = true;
                  command = lib.concatMapStringsSep "\n" (
                    host:
                    "nix eval --raw .#nixosConfigurations.${host}.config.system.build.toplevel.drvPath --show-trace --accept-flake-config"
                  ) (lib.attrNames hosts);
                };
                lint = {
                  arch = "x86_64-linux";
                  buildTarget = "checks.x86_64-linux.pre-commit";
                  onMaster = true;
                };
              }
            )
          // {
            cachyos-kernel-update = mkCachyOSKernelUpdateWorkflow {
              name = "cachyos-kernel-update";
              runsOn = archToRunner."x86_64-linux";
            };
          };
      };
    };
}
