{ inputs, ... }:
{
  flake.modules.nixos.nixos-helium =
    { lib, pkgs, ... }:
    let
      # Helium Browser (fork ungoogled-chromium) z lokalnego flake'a
      # /home/dinosaur/helium-nix (nixpkgs.follows łączyny z nixpkgs hosta,
      # więc pakiet buduje się na tym samym drzewie nixpkgs co reszta systemu).
      helium-package = inputs.helium-nix.packages.${pkgs.system}.helium-bin;
    in
    {
      environment.systemPackages = [
        helium-package
      ];

      # sandbox Chromium w buildach Helium działa przez user namespaces;
      # security.unprivilegedUsernsClone usunięte w nowym NixOS — na to samo
      # służy sysctl user.max_user_namespaces
      boot.kernel.sysctl."user.max_user_namespaces" = lib.mkDefault 62734;
    };
}
