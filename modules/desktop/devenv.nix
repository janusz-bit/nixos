# devenv (https://devenv.sh): deklaratywne środowiska deweloperskie projektów.
#
# Demon nix bierze cache z `cachix.pull` projektu tylko od trusted-users (celowo
# sam root), więc bez devenv.cachix.org w konfiguracji hosta devenv po cichu buduje
# lokalnie całe devenv-nixpkgs. Cache służy projektom devenv, nie temu flake'owi,
# stąd celowo poza nixConfig.
#
# Sprawdzenie: `nix config show extra-substituters` zawiera devenv.cachix.org.
_: {
  flake.modules.nixos.desktop-devenv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.devenv ];

      nix.settings = {
        extra-substituters = [ "https://devenv.cachix.org" ];
        extra-trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };
    };
}
