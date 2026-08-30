_: {
  flake.modules.nixos.nixos-helium =
    { lib, pkgs, ... }:
    {
      # Helium Browser (fork ungoogled-chromium) — pełna implementacja w
      # modules/packages/_helium (przeniesiona z ~/helium-nix); wspólna
      # definicja per-system: /etc/nixos#packages.<system>.helium
      environment.systemPackages = [
        (pkgs.callPackage ../../packages/_helium { })
      ];

      # sandbox Chromium w buildach Helium działa przez user namespaces;
      # security.unprivilegedUsernsClone usunięte w nowym NixOS — na to samo
      # służy sysctl user.max_user_namespaces
      boot.kernel.sysctl."user.max_user_namespaces" = lib.mkDefault 62734;
    };
}
