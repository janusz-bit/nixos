fail() {
  echo "$*" >&2
  exit 1
}

# nix-update --commit commituje sam (komunikat `<atrybut>: <stara> -> <nowa>`),
# ale gdy plik zmienia się bez zmiany wersji, robi `git commit --template`
# i otwiera $EDITOR. Tak jest zawsze w drugim pasie (aarch64, --version skip),
# więc ten pas idzie bez --commit, a jego hash dopisuje amend_package do
# commita pierwszego pasa.
amend_package() {
  local attr=$1 dir=$2
  if git diff --quiet -- "$dir"; then
    return
  fi
  [[ $(git log -1 --format=%s) == "$attr: "* ]] ||
    fail "$attr changed in the second pass without a first-pass commit; review $dir and commit it by hand."
  git commit --quiet --amend --no-edit -- "$dir"
}

cd "$(git rev-parse --show-toplevel)"
[[ -f flake.nix && -f modules/packages/_waywallen/default.nix ]] || fail "Run flake-update from the NixOS configuration repository."
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash existing changes before running flake-update."

echo "Updating flake inputs..."
nix flake update --commit-lock-file
echo "Updating bootdev-cli..."
nix-update --commit -F bootdev-cli
# helium i waywallen: dwa pasy — x86_64 (wersja + hash), potem
# aarch64 (hash bez zmiany wersji).
echo "Updating helium..."
nix-update --commit --system x86_64-linux -F helium
nix-update --system aarch64-linux -F helium --version skip
amend_package helium modules/packages/_helium
echo "Updating waywallen..."
# OweVersion (plugin open-wallpaper-engine) bumpuje się RĘCZNIE w
# modules/packages/_waywallen/default.nix + `nix hash file`.
nix-update --commit --system x86_64-linux -F waywallen
nix-update --system aarch64-linux -F waywallen --version skip
amend_package waywallen modules/packages/_waywallen
nix-update --commit --system x86_64-linux -F waywallen-kde-plugin

echo "Updating strata..."
# engineTag/engineVersion i rev llama.cpp podbija się RĘCZNIE
# w modules/packages/_strata/default.nix (SHA256SUMS.txt i setup.py wydania);
# nix-update podbija tylko version i src.
nix-update --commit -F strata
echo "Updating rea-agents..."
nix-update --commit -F rea-agents
echo "Updating unsloth-desktop..."
# Wszystkie wydania maja sufiks -beta, wiec nix-update wymaga --version=unstable.
nix-update --commit --system x86_64-linux -F unsloth-desktop --version=unstable
echo "Updating opencharts..."
# Upstream nie taguje wydań: wersja 0.3.0-unstable-<data> z gałęzi.
nix-update --commit -F opencharts --version=branch
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
