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

      environment.systemPackages = with pkgs; [
        signal-cli
      ];

      systemd.services.signal-cli = {
        description = "signal-cli HTTP daemon for hermes-agent";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = "signal-cli";
          Group = "signal-cli";
          ExecStart = "${lib.getExe pkgs.signal-cli} -c /var/lib/signal-cli daemon --http 127.0.0.1:8080";
          Restart = "on-failure";
          RestartSec = 5;
          StateDirectory = "signal-cli";
          WorkingDirectory = "/var/lib/signal-cli";
        };
      };

      users.users.signal-cli = {
        isSystemUser = true;
        group = "signal-cli";
        home = "/var/lib/signal-cli";
      };
      users.groups.signal-cli = { };
    };
}
