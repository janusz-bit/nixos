{ self, inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4/hermes" =
    { config, ... }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      # Integracja Ollama + Hermes przez lokalny OpenAI-compatible endpoint.
      # Wymaga ollama signin na serwerze, aby cloud modele były dostępne.
      # Alternatywnie można użyć direct API: base_url = "https://ollama.com/v1" + OLLAMA_API_KEY.
      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;
        extraDependencyGroups = [ "all" ];
        settings.model = {
          provider = "openai";
          base_url = "http://127.0.0.1:11434/v1";
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
