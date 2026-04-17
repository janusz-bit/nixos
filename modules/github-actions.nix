{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Wspolne kroki dla wszystkich workflowow budujacych
      mkBuildSteps =
        { buildTarget, stepName }:
        [
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
            name = stepName;
            run = "nix build .#${buildTarget} --show-trace --accept-flake-config";
          }
        ];

      # Fabryka workflowow
      mkBuildWorkflow =
        {
          name,
          buildTarget,
          runsOn,
          runName ? null,
        }:
        {
          inherit name runName;
          on = {
            push.tags = [ "v*" ];
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs.build = {
            inherit runsOn;
            steps = mkBuildSteps {
              inherit buildTarget;
              stepName = name;
            };
          };
        };

      # Mapa architektur na GitHub Runners
      archToRunner = {
        "x86_64-linux" = "ubuntu-latest";
        "aarch64-linux" = "ubuntu-24.04-arm";
      };

      # Lista konfiguracji do wygenerowania (nazwa = architektura)
      configs = {
        nixos = "x86_64-linux";
        raspberry-pi-4 = "aarch64-linux";
        raspberry-pi-4-sd-image = "aarch64-linux";
        wsl = "x86_64-linux";
        droid = "aarch64-linux";
        default = "x86_64-linux";
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
        workflows = builtins.mapAttrs (
          name: arch:
          mkBuildWorkflow {
            inherit name;
            runsOn = archToRunner."${arch}";
            buildTarget = "nixosConfigurations.${name}.config.system.build.toplevel";
            runName = "Build ${name} by @\${{ github.actor }}";
          }
        ) configs;
      };
    };
}
