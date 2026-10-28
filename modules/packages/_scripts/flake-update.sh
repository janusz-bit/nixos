cd "$(git rev-parse --show-toplevel)"
if [[ ! -f flake.nix || ! -f modules/packages/_waywallen/default.nix ]]; then
  echo "Run flake-update from the NixOS configuration repository." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash existing changes before running flake-update." >&2
  exit 1
fi

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
nix run .#update-strata
echo "Syncing GitHub Actions workflows and docs from the updated flake..."
nix run .#sync-github-actions
nix run .#sync-docs

git add -A -- flake.lock .github/workflows docs/reference \
  modules/packages/_bootdev-cli/default.nix \
  modules/packages/_helium/default.nix \
  modules/packages/_strata/default.nix \
  modules/packages/_waywallen/default.nix \
  modules/packages/_waywallen-kde-plugin/default.nix
if git diff --cached --quiet; then
  echo "Everything is already up to date."
else
  git commit -m "flake-update: update inputs and packages"
fi
echo "All packages updated!"
