# updateScript dla Helium — wywoływany przez `nix run .#flake-update`
# (modules/packages/scripts.nix) lub ręcznie:
#
#   nix build .#packages.<system>.helium.updateScript
#   ./result/bin/update-helium "$(git rev-parse --show-toplevel)/modules/packages/_helium/default.nix"
#
# Pobiera najnowszy release z GitHuba, prefetchuje .deb dla obu arch i
# podmienia version + hashe w default.nix. Nie commituje — robi to
# flake-update (spójnie z resztą).
{
  lib,
  writeShellScript,
  curl,
  jq,
  gnugrep,
  gnused,
  nix,
}:
writeShellScript "update-helium" ''
  set -euo pipefail
  export PATH="${
    lib.makeBinPath [
      curl
      jq
      gnugrep
      gnused
      nix
    ]
  }:''$PATH"

  if [[ ''$# -ne 1 ]]; then
    echo "Użycie: update-helium <ścieżka-do-default.nix>" >&2
    exit 2
  fi
  pkgfile=''$1

  json=''$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest)
  tag=''$(jq -er .tag_name <<<"''$json")

  current=''$(grep -oP 'version = "\K[^"]+' "''$pkgfile" | head -n1)
  if [[ -z "''$current" ]]; then
    echo "helium: nie znaleziono 'version = ' w ''$pkgfile" >&2
    exit 1
  fi

  if [[ "''$tag" == "''$current" ]]; then
    echo "helium: już najnowszy (''$current)"
    exit 0
  fi

  # URL-e .deb wzięte wprost z assets release'a (odporne na zmianę sufiksu -1/-2)
  url_amd64=''$(jq -er '.assets[] | select(.name | test("helium-bin_.*_amd64\\.deb''$")) | .browser_download_url' <<<"''$json")
  url_arm64=''$(jq -er '.assets[] | select(.name | test("helium-bin_.*_arm64\\.deb''$")) | .browser_download_url' <<<"''$json")
  if [[ -z "''$url_amd64" || -z "''$url_arm64" ]]; then
    echo "helium: brak .deb w release ''$tag" >&2
    exit 1
  fi

  echo "helium: ''$current -> ''$tag"
  echo "helium: prefetchuję .deb (amd64, arm64)..."
  hash_amd64=''$(nix store prefetch-file --json --hash-type sha256 "''$url_amd64" | jq -er .hash)
  hash_arm64=''$(nix store prefetch-file --json --hash-type sha256 "''$url_arm64" | jq -er .hash)

  sed -i \
    -e "s|version = \"''$current\";|version = \"''$tag\";|" \
    -e "s|amd64 = \"sha256-[^\" ]*\";|amd64 = \"''$hash_amd64\";|" \
    -e "s|arm64 = \"sha256-[^\" ]*\";|arm64 = \"''$hash_arm64\";|" \
    "''$pkgfile"

  echo "helium: zaktualizowano ''$pkgfile (''$current -> ''$tag)"
''
