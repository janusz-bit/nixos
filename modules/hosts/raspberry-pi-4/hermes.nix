{
  self,
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.hermes =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      age.secrets = {
        hermes-env = {
          file = customTop.secretsDir + "/hermes-env.age";
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
        llmgateway-api-key = {
          file = customTop.secretsDir + "/llmgateway-api-key.age";
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
      };

      services = {
        hermes-agent = {
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
              provider = "custom";
              base_url = "https://api.llmgateway.io/v1";
              default = "kimi-k3";
            };
            providers.llm-gateway = {
              base_url = "https://api.llmgateway.io/v1";
              key_env = "LLMGATEWAY_API_KEY";
            };
            agent.reasoning_effort = "max";
            web.backend = "ddgs";
            auxiliary.vision = {
              provider = "custom";
              base_url = "https://api.llmgateway.io/v1";
              model = "qwen3.8-max";
            };
          };
          environmentFiles = [
            config.age.secrets.hermes-env.path
            config.age.secrets.llmgateway-api-key.path
          ];
          restart = "always";
          restartSec = 5;

          extraPackages = with pkgs; [
            uv
            nodejs_22
            ripgrep
            ffmpeg
            python311
          ];

          mcpServers = {
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
        };

        ollama.enable = true;
      };

      users.users = {
        nixos.extraGroups = [ "hermes" ];
        hermes.extraGroups = [
          "users"
          "keys"
          "wheel"
          "systemd-journal"
          "disk"
        ];
      };

      security.sudo.extraRules = [
        {
          users = [ "hermes" ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      systemd = {
        services = {
          ollama.serviceConfig.EnvironmentFile = config.age.secrets.hermes-env.path;

          hermes-agent.serviceConfig = {
            # Upstream module sets NoNewPrivileges=true, which blocks sudo.
            # We need sudo so the agent can fix file ownership/permissions
            # on files created by the interactive nixos user (e.g. skills,
            # cron scripts) and vice versa.
            NoNewPrivileges = lib.mkForce false;

            # New files created by hermes (skills, cron scripts) should be
            # group-readable so the interactive nixos user (in the hermes
            # group) can read them.  UMask=0027 -> files 0640, dirs 0750.
            # Override upstream UMask=0007 (files 0600, dirs 0700) with 0027
            # (files 0640, dirs 0750) so the interactive nixos user (in the
            # hermes group) can read files created by the agent.
            UMask = lib.mkForce "0027";

            # Clean stale lock/pid/state files before gateway start.
            # Interactive sessions (run as nixos) can create these files owned
            # by nixos:hermes with 0644 perms, which the hermes systemd service
            # cannot open in append mode (PermissionError). Removing them before
            # start lets the service recreate them with correct ownership.
            ExecStartPre = lib.mkBefore [
              "${pkgs.coreutils}/bin/rm -f /var/lib/hermes/.hermes/gateway.lock /var/lib/hermes/.hermes/gateway.pid /var/lib/hermes/.hermes/gateway_state.json"
            ];
          };
        };
      };
    };
}
