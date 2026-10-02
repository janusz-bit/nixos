{ customTop, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Akcje przypięte do commitów (tag można przesunąć — a akcje widzą
      # CACHIX_AUTH_TOKEN i w cachyos-kernel-update mają contents: write).
      # Bump: `git ls-remote https://github.com/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`.
      actions = {
        checkout = "actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"; # v5
        installNix = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"; # v31
        cachix = "cachix/cachix-action@18cf96c7c98e048e10a83abd92116114cd8504be"; # v14
      };

      # Wspolne kroki dla wszystkich workflowow budujacych
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
            name = "${customTop.cache.cachix.name}";
            authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
          };
        }
      ];

      # Workflow aktualizujacy i budujacy CachyOS kernel
      mkCachyOSKernelUpdateWorkflow =
        { name, runsOn }:
        {
          inherit name;
          runName = "Update & Build CachyOS Kernel by @\${{ github.actor }}";
          on = {
            # Na razie wylaczone — daily cron zakomentowany
            # schedule = [ { cron = "0 2 * * *"; } ];
            workflowDispatch = { };
          };
          permissions.contents = "write";
          # Recznie odpalany workflow — bez sensu dwa rownolegle buildy kernela
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

      # Fabryka workflowow
      mkBuildWorkflow =
        {
          name,
          buildTarget,
          runsOn,
          runName ? "Build ${name} by @\${{ github.actor }}",
          command ? null,
          # `tags = false` dla ciezkich buildow. Build toplevela `nixos` trwa
          # 3-5 h i w wiekszosci pada na infrastrukturze CI (cache.nixos.org,
          # limity api.github.com), wiec nie odpalamy go przy kazdym tagu —
          # zostaje PR + reczny workflow_dispatch.
          tags ? true,
          # Tanie sprawdzenia (lint, ewaluacja) odpalaja sie tez na kazdy
          # push do master — commity trafiaja tam bezposrednio.
          onMaster ? false,
        }:
        {
          inherit name runName;
          # Least privilege: buildy tylko czytaja repo.
          permissions.contents = "read";
          # Ten sam workflow dla tego samego refa nie odpala sie dwa razy.
          # cancelInProgress = false — nie zabijamy buildow w trakcie.
          concurrency = {
            group = "build-${name}-\${{ github.ref }}";
            cancelInProgress = false;
          };
          on = {
            push =
              if tags || onMaster then
                (if tags then { tags = [ "v*" ]; } else { })
                // (if onMaster then { branches = [ "master" ]; } else { })
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

      # Ewaluacja wszystkich hostów NixOS (sekundy zamiast godzin buildu) —
      # łapie błędy ewaluacji przy każdym pushu do master.
      evalHosts = [
        "nixos"
        "raspberry-pi-4"
        "wsl"
      ];

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
        # Automatycznie generujemy workflowy dla wszystkich wpisow w 'configs'
        workflows =
          builtins.mapAttrs
            (
              name: cfg:
              mkBuildWorkflow {
                inherit name;
                runsOn = archToRunner."${cfg.arch}";
                buildTarget =
                  cfg.buildTarget or "nixosConfigurations.${name}.config.system.build.${cfg.target or "toplevel"}";
                command = cfg.command or null;
                runName = cfg.runName or "Build ${name} by @\${{ github.actor }}";
                tags = cfg.tags or true;
                onMaster = cfg.onMaster or false;
              }
            )
            {
              nixos = {
                arch = "x86_64-linux";
                # Ciezki build (~400 pakietow, 3-5 h) — tylko PR i dispatch.
                tags = false;
              };
              raspberry-pi-4 = {
                arch = "aarch64-linux";
              };
              raspberry-pi-4-sd-image = {
                arch = "aarch64-linux";
                buildTarget = "packages.aarch64-linux.raspberry-pi-4-sd-image";
              };
              wsl = {
                arch = "x86_64-linux";
              };
              eval = {
                arch = "x86_64-linux";
                runName = "Evaluate hosts by @\${{ github.actor }}";
                onMaster = true;
                command = builtins.concatStringsSep "\n" (
                  map (
                    host:
                    "nix eval --raw .#nixosConfigurations.${host}.config.system.build.toplevel.drvPath --show-trace --accept-flake-config"
                  ) evalHosts
                );
              };
              lint = {
                arch = "x86_64-linux";
                buildTarget = "checks.x86_64-linux.pre-commit";
                onMaster = true;
              };
            }
          // {
            cachyos-kernel-update = mkCachyOSKernelUpdateWorkflow {
              name = "cachyos-kernel-update";
              runsOn = archToRunner."x86_64-linux";
            };
          };
      };
    };
}
