{
  self,
  inputs,
  custom,
  ...
}:
{
  flake.nixosModules."raspberry-pi-4/hermes" =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      age.secrets.hermes-env = {
        file = custom.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

      # Hermes używa providera 'ollama-cloud' z OpenAI-compatible endpointem.
      # https://ollama.com/v1/chat/completions wymaga OLLAMA_API_KEY w environmentFiles.
      # Model 'kimi-k2.6' (bez :cloud) to ID dla direct API.
      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;
        extraDependencyGroups = [ "all" ];
        settings.model = {
          provider = "ollama-cloud";
          base_url = "https://ollama.com/v1";
          default = "kimi-k2.6";
        };
        environmentFiles = [ config.age.secrets.hermes-env.path ];
        restart = "always";
        restartSec = 5;
      };

      services.hermes-agent.environment = {
        API_SERVER_ENABLED = "true";
        API_SERVER_PORT = "8642";
        API_SERVER_HOST = "127.0.0.1";

        # Matrix
        MATRIX_HOMESERVER_URL = "https://matrix.org";
        MATRIX_USER_ID = "@janusz-bit:matrix.org";
        MATRIX_ALLOWED_USERS = "@janusz-bit:matrix.org";
      };

      services.hermes-agent.extraPackages = [
        pkgs.uv
        pkgs.python312
      ];

      services.hermes-agent.mcpServers = {
        web_search_and_fetch = {
          command = "${pkgs.uv}/bin/uv";
          args = [
            "run"
            "--with"
            "mcp>=1.0.0"
            "--with"
            "ollama>=0.6.0"
            "/etc/opencode/web-search-mcp.py"
          ];
          env = { };
        };
      };

      services.ollama.enable = true;

      users.users.nixos.extraGroups = [ "hermes" ];
    };
}
