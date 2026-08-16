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
      #
      # Entrypoint pattern taken from the OCF Berkeley production config
      # (ocf/nix, modules/ttyd.nix): spawn the system `login` program
      # instead of a bare shell. `login` is the SAME binary SSH uses —
      # it sets up the full PAM session, sources /etc/profile and the
      # NixOS environment, then starts the user's login shell (fish via
      # the base bash->fish exec chain). That is what gives the ttyd
      # session aliases, eza/bat/fastfetch and the complete user PATH —
      # a direct fish entrypoint skips all of that.
      services.ttyd = {
        enable = true;
        port = 8082;
        interface = "lo";
        writeable = true;
        username = "admin";
        passwordFile = config.age.secrets.nextcloud-adminpass.path;
        # `login` must run as root to be able to set up user sessions.
        # The service reads passwordFile as root via LoadCredential
        # before executing the entrypoint, so root here is expected.
        user = "root";
        entrypoint = [
          (lib.getExe' pkgs.shadow "login")
        ];
      };
    };
}
