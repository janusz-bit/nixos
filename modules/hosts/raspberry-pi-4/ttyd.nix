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
        # Run as the regular user, not root — the nixos ttyd module
        # defaults to DynamicUser=true (an unprivileged user with no
        # useful home or groups), so every client lands in a stripped
        # session. A named user gets the full profile.
        user = config.customBot.defaultUser;
        # Normal interactive shell — drop the bash wrapper. The NixOS ttyd
        # module runs the service with systemd, which already sources
        # /etc/profile for the session. Spawning fish directly gives the
        # user the same full shell experience (aliases, eza, bat, fastfetch)
        # they get over SSH, instead of a stripped-down wrapper.
        entrypoint = [
          (lib.getExe pkgs.fish)
        ];
      };
    };
}
