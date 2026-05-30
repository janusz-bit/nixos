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
        environmentFiles = [
          config.age.secrets.hermes-env.path
        ];
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
            # ProtectSystem=strict hides /etc, so use the store path directly.
            "${self + /modules/configs/opencode/web-search-mcp.py}"
          ];
          # Hermes filters env for stdio MCP – must explicitly pass OLLAMA_API_KEY.
          # ${OLLAMA_API_KEY} is resolved by Hermes at connect time from the
          # merged .env file (environmentFiles above) and substituted into the
          # subprocess environment. Escaping \${} produces a literal ${} in
          # the generated YAML that Hermes (not Nix) interprets.
          env = {
            OLLAMA_API_KEY = "\${OLLAMA_API_KEY}";
          };
          # RPi4 needs extra time for uv to resolve/download wheels on first run.
          connect_timeout = 300;
          timeout = 300;
        };

        local_mcp = {
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
              command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
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
