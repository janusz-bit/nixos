{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Wspolne kroki dla wszystkich workflowow budujacych
      mkBaseSteps = [
        {
          name = "Checkout repository";
          uses = "actions/checkout@v5";
        }
        {
          name = "Install Nix";
          uses = "cachix/install-nix-action@v31";
          with_ = {
            nix_path = "nixpkgs=channel:nixos-unstable";
            extra_nix_config = ''
              experimental-features = nix-command flakes
              access-tokens = github.com=''${{ secrets.GITHUB_TOKEN }}
              extra-substituters = ${config.customTop.cache.cachix.url}
              extra-trusted-public-keys = ${config.customTop.cache.cachix.pubKey}
            '';
          };
        }
        {
          name = "Setup Cachix";
          uses = "cachix/cachix-action@v14";
          with_ = {
            name = config.customTop.cache.cachix.name;
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
            schedule = [ { cron = "0 2 * * *"; } ];
            workflowDispatch = { };
          };
          permissions.contents = "write";
          jobs.update-and-build = {
            inherit runsOn;
            steps = mkBaseSteps ++ [
              {
                name = "Update nix-cachyos-kernel flake input";
                run = "nix flake lock --update-input nix-cachyos-kernel";
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
          kernelTarget ? null,
        }:
        {
          inherit name runName;
          on = {
            push.tags = [ "v*" ];
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs =
            let
              buildJob = {
                inherit runsOn;
                steps = mkBaseSteps ++ [
                  {
                    name = name;
                    run = "nix build \".#${buildTarget}\" --show-trace --accept-flake-config";
                  }
                ];
              };
            in
            if kernelTarget != null then
              {
                build-kernel = {
                  inherit runsOn;
                  steps = mkBaseSteps ++ [
                    {
                      name = "Build Kernel";
                      run = "nix build \".#${kernelTarget}^*\" --show-trace --accept-flake-config";
                    }
                  ];
                };
                build = buildJob // {
                  needs = "build-kernel";
                };
              }
            else
              { build = buildJob; };
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
                kernelTarget =
                  cfg.kernelTarget or (
                    if name == "nixos" || name == "raspberry-pi-4" then
                      "nixosConfigurations.${name}.config.boot.kernelPackages.kernel"
                    else
                      null
                  );
              }
            )
            {
              nixos = {
                arch = "x86_64-linux";
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
              droid = {
                arch = "aarch64-linux";
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
