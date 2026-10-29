fail() {
  echo "$*" >&2
  exit 1
}

cd "$(git rev-parse --show-toplevel)"
[[ -f flake.nix && -f modules/packages/_waywallen/default.nix ]] || fail "Run flake-update from the NixOS configuration repository."
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash existing changes before running flake-update."

echo "Updating flake inputs..."
nix flake update
echo "Updating bootdev-cli..."
nix-update -F bootdev-cli
# helium i waywallen: dwa pasy — x86_64 (wersja + hash), potem
# aarch64 (hash bez zmiany wersji).
echo "Updating helium..."
nix-update --system x86_64-linux -F helium
nix-update --system aarch64-linux -F helium --version skip
echo "Updating waywallen..."
# OweVersion (plugin open-wallpaper-engine) bumpuje się RĘCZNIE w
# modules/packages/_waywallen/default.nix + `nix hash file`.
nix-update --system x86_64-linux -F waywallen
nix-update --system x86_64-linux -F waywallen-kde-plugin
nix-update --system aarch64-linux -F waywallen --version skip

echo "Updating strata..."
# engineTag/engineVersion i rev llama.cpp podbija się RĘCZNIE
# w modules/packages/_strata/default.nix (SHA256SUMS.txt i setup.py wydania);
# nix-update podbija tylko version i src.
nix-update -F strata
echo "Syncing GitHub Actions workflows and docs from the updated flake..."
nix run .#sync-github-actions
nix run .#sync-docs

git add -A -- flake.lock .github/workflows docs/reference \
  modules/packages/_{bootdev-cli,helium,strata,waywallen,waywallen-kde-plugin}/default.nix
if git diff --cached --quiet; then
  echo "Everything is already up to date."
else
  git commit -m "flake-update: update inputs and packages"
fi
echo "All packages updated!"
