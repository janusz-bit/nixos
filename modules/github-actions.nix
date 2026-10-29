# Generator workflowów GitHub Actions (github-actions-nix): build toplevelu
# każdego hosta z rejestru, obrazy (SD RPi, ISO instalatora), ewaluacja
# wszystkich hostów, lint (pre-commit) i ręczna aktualizacja kernela CachyOS.
#
# .github/workflows/*.yml to wynik tego pliku: `nix run .#sync-github-actions`
# (też hook pre-commit przy każdym commicie) nadpisuje je i usuwa workflowy,
# których już nie ma. Nowy host w rejestrze nie wymaga zmian tutaj.
#
# Akcje są przypięte do SHA commitów, nie tagów: tag można przesunąć na inny
# kod, a akcje widzą CACHIX_AUTH_TOKEN, w cachyos-kernel-update także
# `contents: write` (push flake.lock).
#
# Sprawdzenie: `nix run .#sync-github-actions && git status --short .github/workflows`
# (pusto = workflowy w repo zgodne z generatorem).
{
  config,
  lib,
  ...
}:
let
  # Rejestr hostów (modules/hosts/registry.nix) i customTop (modules/args.nix);
  # perSystem ma własne `config`.
  inherit (config) hosts customTop;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Nowy SHA: `git ls-remote https://github.com/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`.
      actions = {
        checkout = "actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"; # v5
        installNix = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"; # v31
        cachix = "cachix/cachix-action@18cf96c7c98e048e10a83abd92116114cd8504be"; # v14
      };

      archToRunner = {
        x86_64-linux = "ubuntu-latest";
        aarch64-linux = "ubuntu-24.04-arm";
      };

      baseSteps = [
        {
          name = "Checkout repository";
          uses = actions.checkout;
        }
        {
          name = "Install Nix";
          uses = actions.installNix;
          with_.extra_nix_config = ''
            experimental-features = nix-command flakes
            access-tokens = github.com=''${{ secrets.GITHUB_TOKEN }}
            extra-substituters = ${customTop.cachix.url}
            extra-trusted-public-keys = ${customTop.cachix.pubKey}
            build-fallback = true
          '';
        }
        {
          name = "Setup Cachix";
          uses = actions.cachix;
          with_ = {
            inherit (customTop.cachix) name;
            authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
          };
        }
      ];

      mkWorkflow =
        name:
        {
          arch,
          buildTarget ? "nixosConfigurations.${name}.config.system.build.toplevel",
          runName ? "Build ${name} by @\${{ github.actor }}",
          command ? "nix build \".#${buildTarget}\" --show-trace --accept-flake-config",
          # false: buildy 3-5 h (host nixos, ISO z całym jego closure) padają
          # głównie na infrastrukturze CI (cache.nixos.org, limity
          # api.github.com), więc ruszają tylko przy PR i ręcznie, nie przy v*.
          tags ? true,
          # Tanie sprawdzenia także na każdy push do master (commity trafiają
          # tam wprost).
          onMaster ? false,
        }:
        {
          inherit name runName;
          # Least privilege: buildy tylko czytają repo.
          permissions.contents = "read";
          concurrency.group = "build-${name}-\${{ github.ref }}";
          on = {
            push = lib.mkIf (tags || onMaster) {
              tags = lib.mkIf tags [ "v*" ];
              branches = lib.mkIf onMaster [ "master" ];
            };
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs.build = {
            runsOn = archToRunner.${arch};
            steps = baseSteps ++ [
              {
                inherit name;
                run = command;
              }
            ];
          };
        };
    in
    {
      packages = {
        github-actions = config.githubActions.workflowsDir;

        sync-github-actions = pkgs.writeShellApplication {
          name = "sync-github-actions";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.findutils
          ];
          text = ''
            workflows=${lib.escapeShellArg config.githubActions.workflowsDir}
            echo "Syncing workflows from $workflows to .github/workflows/..."
            mkdir -p .github/workflows
            # Usun stare workflowy, ktore nie sa juz generowane (np. po refactorze),
            # zeby nie zostaly osierocone pliki w .github/workflows/.
            find .github/workflows -name '*.yml' -delete
            cp -f "$workflows"/*.yml .github/workflows/
            chmod +w .github/workflows/*.yml
            echo "Done! Workflows are now in sync."
          '';
        };
      };

      githubActions = {
        enable = true;
        workflows =
          lib.mapAttrs mkWorkflow (
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
                tags = false;
              };
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
            cachyos-kernel-update = {
              name = "cachyos-kernel-update";
              runName = "Update & Build CachyOS Kernel by @\${{ github.actor }}";
              on.workflowDispatch = { };
              permissions.contents = "write";
              # Ręcznie odpalany: dwa równoległe buildy kernela nie mają sensu.
              concurrency.group = "cachyos-kernel-update";
              jobs.update-and-build = {
                runsOn = archToRunner.x86_64-linux;
                steps = baseSteps ++ [
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
          };
      };
    };
}
