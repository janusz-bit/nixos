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

      age.secrets.hermes-env = {
        file = customTop.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

      # Dashboard basic-auth credentials for the web dashboard used by the
      # Hermes desktop app on the main PC (via SSH tunnel, see below).
      # Expected content (KEY=VALUE lines):
      #   HERMES_DASHBOARD_BASIC_AUTH_USERNAME=<login>
      #   HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<haslo>
      #   HERMES_DASHBOARD_BASIC_AUTH_SECRET=<losowy-sekret-sesji>
      age.secrets.hermes-dashboard-auth = {
        file = customTop.secretsDir + "/hermes-dashboard-auth.age";
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
            provider = "opencode-go";
            default = "kimi-k3";
          };
          agent.reasoning_effort = "max";
          web.backend = "ddgs";
          auxiliary.vision = {
            provider = "ollama-cloud";
            model = "gemma4:31b";
          };
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
      users.users.hermes = {
        extraGroups = [
          "users"
          "keys"
          "wheel"
          "systemd-journal"
          "disk"
        ];
        # Allow SSH logins from the main PC (root@nixos key) so the desktop
        # app can open the dashboard tunnel:
        #   ssh -L 9119:127.0.0.1:9119 hermes@<rpi4>
        # Public keys are not secret; inline the root@nixos pubkey directly.
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos"
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

      # Upstream module sets NoNewPrivileges=true, which blocks sudo.
      # We need sudo so the agent can fix file ownership/permissions
      # on files created by the interactive nixos user (e.g. skills,
      # cron scripts) and vice versa.
      systemd.services.hermes-agent.serviceConfig.NoNewPrivileges = lib.mkForce false;

      # New files created by hermes (skills, cron scripts) should be
      # group-readable so the interactive nixos user (in the hermes
      # group) can read them.  UMask=0027 -> files 0640, dirs 0750.
      # Override upstream UMask=0007 (files 0600, dirs 0700) with 0027
      # (files 0640, dirs 0750) so the interactive nixos user (in the
      # hermes group) can read files created by the agent.
      systemd.services.hermes-agent.serviceConfig.UMask = lib.mkForce "0027";

      # Clean stale lock/pid/state files before gateway start.
      # Interactive sessions (run as nixos) can create these files owned
      # by nixos:hermes with 0644 perms, which the hermes systemd service
      # cannot open in append mode (PermissionError). Removing them before
      # start lets the service recreate them with correct ownership.
      systemd.services.hermes-agent.serviceConfig.ExecStartPre = lib.mkBefore [
        "${pkgs.coreutils}/bin/rm -f /var/lib/hermes/.hermes/gateway.lock /var/lib/hermes/.hermes/gateway.pid /var/lib/hermes/.hermes/gateway_state.json"
      ];

      # Web dashboard backend for the Hermes desktop app on the main PC.
      #
      # The desktop app talks to a `hermes dashboard` process (port 9119),
      # NOT to the messaging gateway. We bind it to loopback only — the PC
      # reaches it through an SSH local-forward tunnel, so nothing is
      # exposed on the LAN:
      #
      #   ssh -L 9119:127.0.0.1:9119 hermes@<rpi4>
      #
      # then in the desktop app: Settings -> Gateway -> Remote gateway ->
      # Remote URL http://127.0.0.1:9119 -> Sign in (username/password from
      # the hermes-dashboard-auth secret).
      #
      # The hermes user's authorized_keys (below) include the root@nixos
      # key, so the tunnel can be opened from the main PC without touching
      # the interactive nixos account.
      systemd.services.hermes-dashboard = {
        description = "Hermes Agent Web Dashboard (remote backend for desktop app)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "hermes-agent.service"
        ];
        wants = [ "network-online.target" ];

        environment = {
          HOME = "/var/lib/hermes";
          HERMES_HOME = "/var/lib/hermes/.hermes";
          HERMES_MANAGED = "true";
        };

        serviceConfig = {
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = "/var/lib/hermes/workspace";
          ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --skip-build --no-open --host 127.0.0.1 --port 9119";
          EnvironmentFile = config.age.secrets.hermes-dashboard-auth.path;
          Restart = "always";
          RestartSec = 5;
          UMask = "0027";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = false;
          ReadWritePaths = [
            "/var/lib/hermes"
          ];
          PrivateTmp = true;
        };

        path = [
          config.services.hermes-agent.package
          pkgs.bash
          pkgs.coreutils
          pkgs.git
        ];
      };
    };
}
