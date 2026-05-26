{ self, inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4/hermes" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;
        settings.model = {
          base_url = "https://api.ollama.cloud/v1";
          default = "gemma4:31b-cloud";
        };
        environmentFiles = [ config.age.secrets.hermes-env.path ];
        restart = "always";
        restartSec = 5;
      };

      services.hermes-agent.environment = {
        API_SERVER_ENABLED = "true";
        API_SERVER_PORT = "8642";
        API_SERVER_HOST = "127.0.0.1";
      };

      systemd.services.hermes-dashboard = {
        description = "Hermes Agent Web Dashboard";
        after = [
          "network-online.target"
          "hermes-agent.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          HERMES_HOME = "/var/lib/hermes/.hermes";
          HERMES_DASHBOARD_TUI = "1";
        };
        serviceConfig = {
          Type = "simple";
          User = "hermes";
          Group = "hermes";
          ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open --insecure";
          Restart = "on-failure";
          RestartSec = 5;
          WorkingDirectory = "/var/lib/hermes";
        };
      };
    };
}
