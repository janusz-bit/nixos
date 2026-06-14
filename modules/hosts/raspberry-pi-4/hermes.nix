{
  self,
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.hermes =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      age.secrets.hermes-env = {
        file = customTop.secretsDir + "/hermes-env.age";
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
          execution = {
            require_approval = false; # lub lista zaufanych narzędzi
          };
          model = {
            provider = "ollama-cloud";
            default = "kimi-k2.7-code:cloud";
          };
          web.backend = "ddgs";
        };
        environmentFiles = [
          config.age.secrets.hermes-env.path
        ];
        restart = "always";
        restartSec = 5;
      };

      services.hermes-agent.extraPackages = [
        pkgs.uv
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
              command = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
}
