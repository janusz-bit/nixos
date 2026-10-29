# Skrypty utrzymania repo (packages.<system>, `nix run .#<nazwa>`):
# flake-update (wejścia flake'a, pakiety lokalne, workflowy, commit),
# repo-sync (commit wszystkiego, rebase, push), flake-release (tag vN, push),
# package-import (kopia pakietu z przypiętego nixpkgs do modules/packages/).
#
# Treść: _scripts/<nazwa>.sh.
# - flake-update startuje tylko z czystego drzewa (commit = sama aktualizacja).
# - repo-sync robi `git add -A` (notatki trzymać w $TMPDIR).
# - flake-release wydaje tylko z master, który nie jest za origin/master,
#   i pcha gałąź z tagiem atomowo.
# - package-import kopiuje katalog pakietu (meta.position) do
#   modules/packages/_<atrybut>/, dopisuje go do localPackages i sprawdza, że
#   daje tę samą derywację co nixpkgs; pliki zostają w indeksie bez commita.
#   Od tej chwili overlay podmienia nim pakiet z nixpkgs, więc aktualizacje
#   nixpkgs go nie ruszają: podbija się go lokalnie (`nix-update -F
#   <atrybut>` albo ręcznie).
#
# Sprawdzenie: `nix build --no-link .#flake-update .#repo-sync .#flake-release
# .#package-import` (każdy przechodzi przy tym shellcheck).
{
  perSystem =
    { pkgs, lib, ... }:
    let
      script =
        name: runtimeInputs:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          text = builtins.readFile ./_scripts/${name}.sh;
        };
    in
    {
      packages = lib.mapAttrs script {
        flake-update = [ pkgs.nix-update ];
        repo-sync = [ ];
        flake-release = [ pkgs.gnugrep ];
        package-import = with pkgs; [
          coreutils
          gawk
        ];
      };
    };
}
