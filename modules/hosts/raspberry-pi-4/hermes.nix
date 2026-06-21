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
        # The upstream NixOS module defaults its package to
        # inputs.hermes-agent.packages.${system}.default, whose nix/lib.nix
        # carries a stale npmDepsHash on current nixos-unstable. The
        # self.overlays.hermes-agent overlay exposes a patched pkgs.hermes-agent
        # (substituted npmDepsHash) that we pin here so the service builds.
        package = pkgs.hermes-agent;
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
            default = "glm-5.2:cloud";
          };
          web.backend = "ddgs";
        };
        environmentFiles = [
          config.age.secrets.hermes-env.path
        ];
        restart = "always";
        restartSec = 5;
      };

      services.hermes-agent.extraPackages = with pkgs; [
        uv
        nodejs_22
        ripgrep
        ffmpeg
        python311
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
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      # Make hermes-agent create group-writable files so that both the
      # `hermes` service user and the `nixos` login user (member of the
      # `hermes` group) can read/write the same files in ~/.hermes/.
      systemd.services.hermes-agent.serviceConfig.UMask = "0002";

      # Periodically fix permissions on the hermes data directory so that
      # files created by the `nixos` user (e.g. via `hermes` CLI with the
      # default umask 022) become group-writable.  The setgid bit on
      # directories ensures correct group ownership; this service only
      # adjusts the permission bits.
      systemd.services.hermes-fix-perms = {
        description = "Fix group-write permissions on hermes data directory";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = [
            # chmod g+w on all files and dirs under ~/.hermes
            "${pkgs.coreutils}/bin/find /var/lib/hermes/.hermes -type d -exec chmod g+ws {} +"
            "${pkgs.coreutils}/bin/find /var/lib/hermes/.hermes -type f -exec chmod g+w {} +"
          ];
        };
      };

      systemd.timers.hermes-fix-perms = {
        description = "Periodically fix hermes data directory permissions";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
        };
      };

      # Ensure the `nixos` login user also creates group-writable files
      # inside the hermes data directory (umask 002 in interactive shells).
      environment.interactiveShellInit = ''
        if [[ -d /var/lib/hermes/.hermes ]] && [[ "$(id -gn)" == "hermes" || " $(id -Gn) " == *" hermes "* ]]; then
          umask 0002
        fi
      '';
    };
}
