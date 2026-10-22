# Skrypty utrzymania repo (packages.<system>, `nix run .#<nazwa>`):
# flake-update (wejścia flake'a, pakiety lokalne, workflowy, commit),
# repo-sync (commit wszystkiego, rebase, push), flake-release (tag vN, push),
# package-import (kopia pakietu z przypiętego nixpkgs do modules/packages/).
#
# Treść skryptów: _scripts/<nazwa>.sh. package-import kopiuje katalog pakietu
# (meta.position) do modules/packages/_<atrybut>/, dopisuje go do
# localPackages i sprawdza, że daje tę samą derywację co nixpkgs; pliki
# zostają w indeksie bez commita. Od tej chwili overlay podmienia nim pakiet
# z nixpkgs, więc aktualizacje nixpkgs go nie ruszają (`nix-update -F
# <atrybut>` albo ręcznie). flake-update startuje tylko z czystego
# drzewa (commit = sama aktualizacja); repo-sync robi `git add -A` (notatki
# trzymać w $TMPDIR); flake-release wydaje tylko z master, który nie jest za
# origin/master, i pcha gałąź z tagiem atomowo.
#
# Sprawdzenie: `nix build --no-link .#flake-update .#repo-sync .#flake-release
# .#package-import` (flake-update i package-import przechodzą shellcheck).
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        flake-update = pkgs.writeShellApplication {
          name = "flake-update";
          runtimeInputs = [ pkgs.nix-update ];
          text = builtins.readFile ./_scripts/flake-update.sh;
        };

        repo-sync = pkgs.writeShellScriptBin "repo-sync" (builtins.readFile ./_scripts/repo-sync.sh);

        flake-release = pkgs.writeShellScriptBin "flake-release" (
          builtins.readFile ./_scripts/flake-release.sh
        );

        package-import = pkgs.writeShellApplication {
          name = "package-import";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
          ];
          text = builtins.readFile ./_scripts/package-import.sh;
        };
      };
    };
}
