{
  writeShellScriptBin,
  lib,
  coreutils,
  findutils,
  gnugrep,
  curl,
  jq,
  git,
  nix,
  nix-prefetch-git,
  moreutils,
  yq,
  # Config
  tarballPrefix,
  tarballSuffix,
  releasePrefix,
  releaseSuffix,
  versionFilename,
  owner,
  repo,
}:
let
  path = lib.makeBinPath [
    coreutils
    curl
    findutils
    gnugrep
    jq
    moreutils
    git
    nix-prefetch-git
    nix
    yq
  ];
in
writeShellScriptBin "update-${repo}" ''
  set -euo pipefail
  PATH=${path}

  srcJson=modules/packages/_proton-bin/${versionFilename}
  localBase=$(jq -r .base < $srcJson)
  localRelease=$(jq -r .release < $srcJson)
  localHash=$(jq -r .hash < $srcJson)

  latestVer=$(curl 'https://github.com/${owner}/${repo}/releases.atom' | xq -r '.feed.entry[].link."@href"' | grep -Po '(?<=/)${releasePrefix}[^/]+${releaseSuffix}$' | head -n 1)

  latestBase=$(echo $latestVer | grep -Po '(?<=^${releasePrefix})[^-]+')
  latestRelease=$(echo $latestVer | grep -Po '(?<=-)[^-]+(?=${releaseSuffix}$)')
  latestSha256=$(nix-prefetch-url --type sha256 "https://github.com/${owner}/${repo}/releases/download/''${latestVer}/${tarballPrefix}''${latestVer}${tarballSuffix}")
  latestHash=$(nix-hash --to-sri --type sha256 $latestSha256)

  if [ "${releasePrefix}''${localBase}-''${localRelease}${releaseSuffix}" == "$latestVer" ] && [ "$localHash" == "$latestHash" ]; then
    exit 0
  fi

  if [ "${releasePrefix}''${localBase}-''${localRelease}${releaseSuffix}" == "$latestVer" ]; then
    commitMsg="${repo}: hash update for ''${latestBase}.''${latestRelease}"
  else
    commitMsg="${repo}: ''${localBase}.''${localRelease} -> ''${latestBase}.''${latestRelease}"
  fi

  jq \
    --arg latestBase "$latestBase" --arg latestRelease "$latestRelease" --arg latestHash "$latestHash" \
    '.base = $latestBase | .release = $latestRelease | .hash = $latestHash' \
    "$srcJson" | sponge "$srcJson"

  git add "$srcJson"
  git commit -m "$commitMsg" "$srcJson"
''
