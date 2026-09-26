{ customTop, ... }:
{
  flake.modules.nixos.jupyterlab =
    {
      config,
      pkgs,
      ...
    }:
    let
      python = pkgs.python313.withPackages (
        ps: with ps; [
          jupyterlab
          ipykernel
        ]
      );

      kernels = pkgs.jupyter-kernel.create {
        definitions.python3 = {
          displayName = "Python 3.13";
          argv = [
            python.interpreter
            "-m"
            "ipykernel_launcher"
            "-f"
            "{connection_file}"
          ];
          language = "python";
          logo32 = null;
          logo64 = null;
        };
      };

      serverConfig = pkgs.writeText "jupyter-server-config.py" ''
        import os
        from pathlib import Path
        from jupyter_server.auth import passwd

        password = Path(os.environ["CREDENTIALS_DIRECTORY"], "password").read_text().strip()
        if not password:
            raise RuntimeError("Jupyter password credential is empty")

        c.PasswordIdentityProvider.hashed_password = passwd(password)
        c.PasswordIdentityProvider.password_required = True
        c.PasswordIdentityProvider.allow_password_change = False
        c.IdentityProvider.token = ""
        c.IdentityProvider.cookie_options = {"secure": True, "httponly": True, "samesite": "Lax"}

        c.ServerApp.ip = "127.0.0.1"
        c.ServerApp.port = 8888
        c.ServerApp.port_retries = 0
        c.ServerApp.open_browser = False
        c.ServerApp.root_dir = "/var/lib/jupyterlab/notebooks"
        c.ServerApp.local_hostnames = ["localhost", "jupyter.${customTop.site.full}"]
        c.ServerApp.trust_xheaders = True
      '';
    in
    {
      # The password is decrypted only at runtime. The Nix store contains
      # neither the password nor its hash.
      age.secrets.jupyter-password.file = customTop.secretsDir + "/jupyter-password.age";

      systemd.services.jupyterlab = {
        description = "JupyterLab (Cloudflare Tunnel origin)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          HOME = "/var/lib/jupyterlab";
          JUPYTER_PATH = toString kernels;
          JUPYTER_CONFIG_DIR = "/run/jupyterlab/config";
          JUPYTER_RUNTIME_DIR = "/run/jupyterlab";
        };

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          User = "jupyterlab";
          StateDirectory = "jupyterlab";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "jupyterlab";
          RuntimeDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/jupyterlab";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/jupyterlab/notebooks";
          ExecStart = "${python}/bin/jupyter-lab --config=${serverConfig}";
          LoadCredential = "password:${config.age.secrets.jupyter-password.path}";
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
        };
      };
    };
}
