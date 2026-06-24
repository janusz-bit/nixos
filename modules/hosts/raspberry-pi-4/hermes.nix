{
  self,
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.hermes =
    { config, pkgs, lib, ... }:
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
        "wheel"
        "systemd-journal"
        "disk"
      ];

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

      # Upstream module sets NoNewPrivileges=true, which blocks sudo.
      # We need sudo so the agent can fix file ownership/permissions
      # on files created by the interactive nixos user (e.g. skills,
      # cron scripts) and vice versa.
      systemd.services.hermes-agent.serviceConfig.NoNewPrivileges = lib.mkForce false;

      # New files created by hermes (skills, cron scripts) should be
      # group-readable so the interactive nixos user AND nextcloud (both
      # in the hermes group) can read them.  UMask=0027 -> files 0640,
      # dirs 0750.
      systemd.services.hermes-agent.serviceConfig.UMask = lib.mkForce "0027";

      # Clean stale lock/pid/state files before gateway start.
      systemd.services.hermes-agent.serviceConfig.ExecStartPre = lib.mkBefore [
        "${pkgs.coreutils}/bin/rm -f /var/lib/hermes/.hermes/gateway.lock /var/lib/hermes/.hermes/gateway.pid /var/lib/hermes/.hermes/gateway_state.json"
      ];

      # Periodically fix permissions on hermes data directories so that
      # files created with restrictive umasks become group-readable.
      # This is essential for Nextcloud external storage access (nextcloud
      # user is in the hermes group and needs g+r/g+x to read files).
      systemd.services.hermes-fix-perms = {
        description = "Fix group-read permissions on hermes data directories";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = [
            # Ensure directories are group-readable+executable with setgid
            "${pkgs.coreutils}/bin/find /var/lib/hermes/.hermes /var/lib/hermes/workspace -type d -exec chmod g+rxs {} +"
            # Ensure files are group-readable
            "${pkgs.coreutils}/bin/find /var/lib/hermes/.hermes /var/lib/hermes/workspace -type f -exec chmod g+r {} +"
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
    };
}
