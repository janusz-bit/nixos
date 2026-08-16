_: {
  flake.modules.nixos.ttyd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Web terminal (ttyd) exposed ONLY through the Cloudflare Tunnel
      # (ttyd.janusz-bit.com ingress -> localhost:8082). Firewall leaves
      # 8082 closed, and ttyd additionally binds to loopback only.
      #
      # Auth: HTTP Basic — user "admin", password = the Nextcloud admin
      # password. Reuses the existing nextcloud-adminpass agenix secret;
      # the NixOS ttyd module picks it up via systemd LoadCredential
      # (root reads it before dropping privileges), so no new secret is
      # needed and nothing sensitive ever lands in the nix store.
      services.ttyd = {
        enable = true;
        port = 8082;
        interface = "lo";
        writeable = true;
        username = "admin";
        passwordFile = config.age.secrets.nextcloud-adminpass.path;
        # Direct interactive shell instead of the default `login` prompt —
        # HTTP Basic auth already gates access, a second login: prompt would
        # only add friction. fish matches the shell used on all hosts.
        # Wrapped in bash -l so /etc/profile sets up the full NixOS
        # environment (PATH, profiles), then fish replaces it.
        entrypoint = [
          (lib.getExe pkgs.bashInteractive)
          "-l"
          "-c"
          "exec ${lib.getExe pkgs.fish}"
        ];
      };
    };
}
