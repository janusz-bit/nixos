{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.github-actions = config.githubActions.workflowsDir;

      packages.sync-github-actions = pkgs.writeShellApplication {
        name = "sync-github-actions";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # Sciezka do wygenerowanych plikow w /nix/store
          WORKFLOWS_DIR="${config.githubActions.workflowsDir}"

          echo "Syncing workflows from $WORKFLOWS_DIR to .github/workflows/..."
          mkdir -p .github/workflows

          # Kopiujemy pliki YAML. Flaga -L zapewnia, ze kopiujemy zawartosc, a nie linki.
          cp -f "$WORKFLOWS_DIR"/*.yml .github/workflows/

          # Nadajemy uprawnienia do zapisu (pliki w /nix/store sa tylko do odczytu)
          chmod +w .github/workflows/*.yml

          echo "Done! Workflows are now in sync."
        '';
      };

      githubActions = {
        enable = true;
        workflows = {
          build-nixos = {
            name = "Build nixos";
            runName = "Build NixOS Configuration (nixos) by @\${{ github.actor }}";
            on = {
              push.tags = [ "v*" ];
              pullRequest.branches = [ "master" ];
              workflowDispatch = { };
            };
            jobs.build = {
              runsOn = "ubuntu-latest";
              steps = [
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
                      extra-substituters =  https://janusz-bit.cachix.org
                      extra-trusted-public-keys =  janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=
                    '';
                  };
                }
                {
                  name = "Setup Cachix";
                  uses = "cachix/cachix-action@v14";
                  with_ = {
                    name = "janusz-bit";
                    authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
                  };
                }
                {
                  name = "Build NixOS Configuration (nixos)";
                  run = "nix build .#nixosConfigurations.nixos.config.system.build.toplevel --show-trace --accept-flake-config";
                }
              ];
            };
          };

          build-raspberry-pi-4 = {
            name = "Build raspberry-pi-4";
            on = {
              push.tags = [ "v*" ];
              pullRequest.branches = [ "master" ];
              workflowDispatch = { };
            };
            jobs.build = {
              runsOn = "ubuntu-24.04-arm";
              steps = [
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
                      extra-substituters = https://janusz-bit.cachix.org
                      extra-trusted-public-keys = janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=
                    '';
                  };
                }
                {
                  name = "Setup Cachix";
                  uses = "cachix/cachix-action@v14";
                  with_ = {
                    name = "janusz-bit";
                    authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
                  };
                }
                {
                  name = "Build NixOS Configuration (raspberry-pi-4)";
                  run = "nix build .#nixosConfigurations.raspberry-pi-4.config.system.build.toplevel --show-trace --accept-flake-config";
                }
              ];
            };
          };
        };
      };
    };
}
