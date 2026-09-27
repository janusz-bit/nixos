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
          group = "users";
          mode = "0440";
        };
        llmgateway-api-key = {
          file = customTop.secretsDir + "/llmgateway-api-key.age";
          owner = "hermes";
          group = "users";
          mode = "0440";
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
              provider = "openai-codex";
              base_url = "https://chatgpt.com/backend-api/codex";
              default = "gpt-6-sol";
            };
            fallback_providers = [
              {
                provider = "ollama-cloud";
                model = "glm-5.3-flash:cloud";
              }
            ];
            providers.ollama-cloud = {
              base_url = "https://ollama.com/v1";
              key_env = "OLLAMA_API_KEY";
            };
            agent.reasoning_effort = "xhigh";
            web.backend = "ddgs";
            auxiliary.vision = {
              provider = "ollama-cloud";
              base_url = "https://ollama.com/v1";
              model = "glm-5.3-flash:cloud"; # vision: text+image->text (GLM 5.3 Flash)
            };
          };
          environmentFiles = [
            config.age.secrets.hermes-env.path
            config.age.secrets.llmgateway-api-key.path
          ];
          restart = "always";
          restartSec = 5;

          extraPackages = with pkgs; [
            codex
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
              # Hermes keeps OAuth credentials at 0600. If an interactive
              # login creates auth.json as nixos/root, the service cannot read
              # it. Repair ownership without replacing the stored tokens.
              "+${pkgs.writeShellScript "hermes-auth-ownership" ''
                set -eu
                auth_dir=/var/lib/hermes/.hermes
                if [ -d "$auth_dir" ] && [ ! -L "$auth_dir" ]; then
                  ${pkgs.coreutils}/bin/chown hermes:hermes "$auth_dir"
                  ${pkgs.coreutils}/bin/chmod u+rwx "$auth_dir"
                  for auth_file in "$auth_dir/auth.json" "$auth_dir/auth.lock"; do
                    if [ -f "$auth_file" ] && [ ! -L "$auth_file" ]; then
                      ${pkgs.coreutils}/bin/chown hermes:hermes "$auth_file"
                      ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
                    fi
                  done
                fi
              ''}"
              "${pkgs.coreutils}/bin/rm -f /var/lib/hermes/.hermes/gateway.lock /var/lib/hermes/.hermes/gateway.pid /var/lib/hermes/.hermes/gateway_state.json"
            ];
          };
        };
      };
    };
}
