{
  self,
  inputs,
  ...
}:
{
  flake.modules.nixos.hermes =
    { config, pkgs, ... }:
    let
      # Definiujemy środowisko Pythona w zmiennej, aby móc wyciągnąć absolutną ścieżkę
      hermesPythonEnv = pkgs.python3.withPackages (
        python-pkgs: with python-pkgs; [
          ddgs
          pip
          mcp
        ]
      );
    in
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      age.secrets.hermes-env = {
        file = config.customTop.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

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
        hermesPythonEnv # Używamy zdefiniowanego wyżej środowiska
      ];

      services.hermes-agent.mcpServers = {
        trilium-notes = {
          url = "http://127.0.0.1:8081/mcp";
          enabled = true;
          connect_timeout = 30;
          timeout = 60;
          headers = {
            Authorization = "Bearer \${TRILIUM_ETAPI_TOKEN}";
          };
        };
        ddgs-mcp = {
          # GŁÓWNA ZMIANA: absolutna ścieżka do binarki wygenerowanej przez Nix
          command = "uvx";
          args = [
            "--from"
            "ddgs[mcp]"
            "ddgs"
            "mcp"
          ];
          enabled = true;
          connect_timeout = 30;
          timeout = 60;
        };
        nixos = {
          command = "uvx";
          args = [ "mcp-nixos" ];
          enabled = true;
          connect_timeout = 30;
          timeout = 60;
        };
      };

      services.ollama.enable = true;
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
