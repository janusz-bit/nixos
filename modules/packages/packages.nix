# Pakiety lokalne (modules/packages/_<nazwa>/): jedna lista eksportowana jako
# overlay local-packages (dla hostów, przez base-nix) i jako packages.<system>
# (nix build, nix-update w flake-update).
#
# Nowy pakiet: wpis w localPackages (i w flake-update, scripts.nix, jeśli ma
# się podbijać sam). bootdev-cli nadpisuje wersję z nixpkgs: lokalna jest
# aktualizowana przez flake-update i bywa nowsza. Kopię pakietu z nixpkgs
# robi `package-import <atrybut>` (scripts.nix); dopisuje wpis alfabetycznie
# po wcięciach bloku localPackages, więc jego układ ma zostać taki jak teraz.
#
# Sprawdzenie: `nix eval --raw .#packages.x86_64-linux.helium.version`.
_:
let
  localPackages = pkgs: {
    bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
    helium = pkgs.callPackage ./_helium { };
    waywallen = pkgs.callPackage ./_waywallen { };
    waywallen-kde-plugin = pkgs.callPackage ./_waywallen-kde-plugin { };
  };
in
{
  flake.overlays.local-packages = final: _prev: localPackages final;

  perSystem =
    { pkgs, ... }:
    {
      packages = localPackages pkgs;
    };
}
