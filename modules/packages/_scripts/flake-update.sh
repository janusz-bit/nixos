fail() {
  echo "$*" >&2
  exit 1
}

version_of() {
  nix eval --raw ".#packages.x86_64-linux.$1.version"
}

# nix-update --commit przy zmianie pliku bez zmiany wersji (drugi pas
# --version skip, sam hash, odświeżony lockfile) robi `git commit --template`
# i otwiera $EDITOR, więc pakiety aktualizuje się bez --commit, a commit
# (jeden na pakiet, ze wszystkimi pasami) robi commit_package.
commit_package() {
  local attr=$1 old=$2 new
  git add -A -- modules/packages
  if git diff --cached --quiet; then
    return
  fi
  new=$(version_of "$attr")
  if [[ $old == "$new" ]]; then
    git commit --quiet -m "$attr: update"
  else
    git commit --quiet -m "$attr: $old -> $new"
  fi
}

cd "$(git rev-parse --show-toplevel)"
[[ -f flake.nix && -f modules/packages/_waywallen/default.nix ]] || fail "Run flake-update from the NixOS configuration repository."
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash existing changes before running flake-update."

echo "Updating flake inputs..."
nix flake update --commit-lock-file
echo "Updating bootdev-cli..."
old=$(version_of bootdev-cli)
nix-update -F bootdev-cli
commit_package bootdev-cli "$old"
# helium i waywallen: dwa pasy — x86_64 (wersja + hash), potem
# aarch64 (hash bez zmiany wersji).
echo "Updating helium..."
old=$(version_of helium)
nix-update --system x86_64-linux -F helium
nix-update --system aarch64-linux -F helium --version skip
commit_package helium "$old"
echo "Updating waywallen..."
# OweVersion (plugin open-wallpaper-engine) bumpuje się RĘCZNIE w
# modules/packages/_waywallen/default.nix + `nix hash file`.
old=$(version_of waywallen)
nix-update --system x86_64-linux -F waywallen
nix-update --system aarch64-linux -F waywallen --version skip
commit_package waywallen "$old"
old=$(version_of waywallen-kde-plugin)
nix-update --system x86_64-linux -F waywallen-kde-plugin
commit_package waywallen-kde-plugin "$old"

echo "Updating strata..."
# engineTag/engineVersion i rev llama.cpp podbija się RĘCZNIE
# w modules/packages/_strata/default.nix (SHA256SUMS.txt i setup.py wydania);
# nix-update podbija tylko version i src.
old=$(version_of strata)
nix-update -F strata
commit_package strata "$old"
echo "Updating rea-agents..."
old=$(version_of rea-agents)
nix-update -F rea-agents
commit_package rea-agents "$old"
echo "Updating unsloth-desktop..."
# Wszystkie wydania maja sufiks -beta, wiec nix-update wymaga --version=unstable.
old=$(version_of unsloth-desktop)
nix-update --system x86_64-linux -F unsloth-desktop --version=unstable
commit_package unsloth-desktop "$old"
echo "Updating opencharts..."
# Upstream nie taguje wydań: wersja 0.3.0-unstable-<data> z gałęzi.
old=$(version_of opencharts)
nix-update -F opencharts --version=branch
commit_package opencharts "$old"
echo "Syncing GitHub Actions workflows and docs from the updated flake..."
nix run .#sync-github-actions
nix run .#sync-docs

git add -A -- .github/workflows docs/reference
if git diff --cached --quiet; then
  echo "Generated files are up to date."
else
  git commit -m "flake-update: sync generated workflows and docs"
fi
echo "All packages updated!"
