{
  customTop,
  inputs,
  lib,
  ...
}:
{
  flake.modules.nixos.hermes-webui =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.hermes-webui.nixosModules.default
      ];

      # Wczytujemy hermes-env.age jako sekret współdzielony z hermes-agent
      age.secrets.hermes-webui-env = {
        file = customTop.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

      services.hermes-workspace = {
        enable = true;
        package = inputs.hermes-webui.packages.${pkgs.system}.default.overrideAttrs (old: {
          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (old) pname version src;
            # fetchPnpmDeps requires passing pnpm explicitly if the package did so
            pnpm = pkgs.pnpm;
            fetcherVersion = 3;
            hash = "sha256-1JycO+WwnM6iFol/Zu93uTbkB1Dq8cnntfdbtGTIm/k=";
          };
        });
        host = "127.0.0.1";
        port = 8787;
        hermesApiUrl = "http://127.0.0.1:8642";
        hermesDashboardUrl = "http://127.0.0.1:9119";
        user = "hermes";
        group = "hermes";
        # Keep using the same home directory for state
        dataDir = "/var/lib/hermes";
        environmentFile = config.age.secrets.hermes-webui-env.path;
      };

      systemd.services.hermes-workspace = {
        path = [ pkgs.sqlite ];
        unitConfig.StartLimitIntervalSec = 120;
        serviceConfig = {
          StartLimitBurst = 5;
          # Robust wrapper that sources the env file and maps tokens
          ExecStart = lib.mkForce (
            pkgs.writeShellScript "hermes-workspace-wrapper" ''
              # Source the agenix secret file to get API_SERVER_KEY
              if [ -f "${config.age.secrets.hermes-webui-env.path}" ]; then
                set -a
                source "${config.age.secrets.hermes-webui-env.path}"
                set +a
              fi

              # Map the key to the names expected by the workspace
              export HERMES_API_TOKEN="$API_SERVER_KEY"
              export HERMES_DASHBOARD_TOKEN="$API_SERVER_KEY"

              echo "Starting Hermes Workspace with token mapping..."
              exec ${config.services.hermes-workspace.package}/bin/hermes-workspace
            ''
          );
        };
      };
    };
}
