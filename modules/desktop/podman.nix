# Podman do kontenerów rootless: polecenie `docker` jako alias (dockerCompat)
# i DNS w domyślnej sieci dla podman-compose.
#
# Celowo bez grupy `podman`: rootowy /run/podman/podman.sock to root bez hasła
# dla każdego procesu użytkownika; rootless działa bez niej, rootful przez sudo.
# Sprawdzenie: `podman info --format '{{.Host.Security.Rootless}}'` → true;
# `id` nie pokazuje grupy podman.
_: {
  flake.modules.nixos.desktop-podman = _: {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
