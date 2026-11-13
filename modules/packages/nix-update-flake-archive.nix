# Tymczasowy overlay nix-update-flake-archive: nix-update kopiuje lokalny
# flake do sklepu przez `nix flake archive` zamiast `nix flake metadata`
# (temporary-fixes.md, wpis 16).
#
# nix-update (`get_flake_store_path`) bierze ścieżkę flake'a z pola `path`
# w `nix flake metadata --json` i ewaluuje ją przez `builtins.getFlake`.
# Nix 2.35 zwraca tam ścieżkę sklepu bez kopiowania drzewa, więc po pierwszej
# edycji pliku (podbita wersja) każdy prefetch hasha i --generate-lockfile
# padają z `opening file "/nix/store/…-source": No such file or directory`.
# `nix flake archive --json` kopiuje drzewo i zwraca to samo pole `path`.
# Overlay jest w base-nix (nix-update w pakietach systemowych) i w pkgs
# perSystem (flake-update).
#
# Sprawdzenie: w czystym klonie repo z pakietem, który ma nową wersję,
# `nix run .#nixosConfigurations.nixos.pkgs.nix-update -- -F <pakiet>` podbija
# wersję i hash.
_: {
  flake.overlays.nix-update-flake-archive = _final: prev: {
    nix-update = prev.nix-update.overridePythonAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace nix_update/options.py \
          --replace-fail '["nix", "flake", "metadata", "--json"]' '["nix", "flake", "archive", "--json"]'
      '';
    });
  };
}
