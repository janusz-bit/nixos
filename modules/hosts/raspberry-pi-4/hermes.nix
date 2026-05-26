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
        settings.model = {
          base_url = "https://api.ollama.cloud/v1";
          default = "gemma4:31b-cloud";
        };
        environmentFiles = [ config.age.secrets.hermes-env.path ];
        restart = "always";
        restartSec = 5;
      };
    };
}
