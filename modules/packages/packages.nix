# Pakiety lokalne (modules/packages/_<nazwa>/): jedna lista eksportowana jako
# overlay local-packages (dla hostów, przez base-nix) i jako packages.<system>
# (nix build, nix-update w flake-update).
#
# Wpis nadpisuje pakiet nixpkgs o tej samej nazwie (bootdev-cli: lokalny
# podbija flake-update, więc bywa nowszy). Pakiet podbijany automatycznie
# potrzebuje też wpisu w _scripts/flake-update.sh. package-import dopisuje
# wpisy alfabetycznie, rozpoznając blok localPackages po wcięciach, więc jego
# układ ma zostać taki jak teraz.
#
# Sprawdzenie: `nix eval --raw .#packages.x86_64-linux.helium.version`.
_:
let
  localPackages = pkgs: {
    bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
    helium = pkgs.callPackage ./_helium { };
    llama-cpp-prism = pkgs.callPackage ./_llama-cpp-prism { };
    strata = pkgs.callPackage ./_strata { };
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
