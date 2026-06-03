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
      # Model 'minimax-m3:cloud' to ID dla Ollama Cloud API.
      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;
        extraDependencyGroups = [
          "all"
          "messaging"
          "matrix"
        ];
        settings = {
          model = {
            provider = "google";
            default = "gemini-3.5-flash";
          };
          # Free web search via DuckDuckGo (no API key required).
          # Hermes lazy-installs the ddgs package on first use.
          # If you need web_extract as well, add an extract_backend:
          web.backend = "ddgs";
        };
        environmentFiles = [
          config.age.secrets.hermes-env.path
        ];
        restart = "always";
        restartSec = 5;
      };

      services.hermes-agent.environment = {
        API_SERVER_ENABLED = "true";
        API_SERVER_PORT = "8642";
        API_SERVER_HOST = "0.0.0.0";
      };

      services.hermes-agent.extraPackages = [
        pkgs.uv
        (pkgs.python3.withPackages (
          python-pkgs: with python-pkgs; [
            ddgs
            pip
          ]
        ))
      ];

      services.hermes-agent.mcpServers = {
        trilium-notes = {
          url = "http://127.0.0.1:8081/mcp";
          enabled = true;
          connect_timeout = 30;
          timeout = 60;
          headers = {
            # Hermes interpolates \${VAR} at MCP connect time from .env.
            Authorization = "Bearer \${TRILIUM_ETAPI_TOKEN}";
          };
        };
      };

      services.ollama.enable = true;
      # Ollama cloud models (e.g. glm-5.1:cloud) require OLLAMA_API_KEY.
      # Reuse hermes-env which already contains OLLAMA_API_KEY=... in KEY=VALUE format.
      systemd.services.ollama.serviceConfig.EnvironmentFile = config.age.secrets.hermes-env.path;

      users.users.nixos.extraGroups = [ "hermes" ];
      users.users.hermes.extraGroups = [
        "users"
        "keys"
      ];

      security.sudo.extraRules = [
        {
          users = [ "hermes" ];
          commands = [
            {
              command = "${pkgs.git}/bin/git";
              options = [ "NOPASSWD" ];
            }
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
}
