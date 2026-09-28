_: {
  flake.modules.nixos.nixos-podman = _: {
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
      };
    };

    # Celowo BEZ grupy `podman`: daje ona dostęp do rootowego
    # /run/podman/podman.sock, czyli roota bez hasła dla każdego procesu
    # użytkownika. Rootless podman (`podman run` jako zwykły użytkownik)
    # działa bez niej; rootful tylko przez sudo.
  };
}
