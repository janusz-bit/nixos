{ self, inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4/hermes" =
    { config, ... }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      services.hermes-agent = {
        enable = true;
        addToSystemPackages = false;
        settings.model = {
          provider = "ollama-cloud";
          default = "kimi-k2.6:cloud";
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

      services.ollama.enable = true;

      users.users.nixos.extraGroups = [ "hermes" ];
    };
}
