{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        flake-update = pkgs.writeShellScriptBin "flake-update" ''
          set -euo pipefail

          cd "$(git rev-parse --show-toplevel)"
          if [[ ! -f flake.nix || ! -f modules/packages/_helium/default.nix ]]; then
            echo "Run flake-update from the NixOS configuration repository." >&2
            exit 1
          fi
          if [[ -n "$(git status --porcelain)" ]]; then
            echo "Commit or stash existing changes before running flake-update." >&2
            exit 1
          fi

          echo "Updating flake inputs..."
          nix flake update
          echo "Updating helium..."
          ${pkgs.lib.getExe pkgs.nix-update} --system x86_64-linux -F helium
          ${pkgs.lib.getExe pkgs.nix-update} --system aarch64-linux -F helium --version skip
          echo "Updating bootdev-cli..."
          ${pkgs.lib.getExe pkgs.nix-update} -F bootdev-cli
          echo "Updating waywallen..."
          # Dwa pasy jak przy helium: x86_64 (wersja + hash), potem
          # aarch64 (hash bez zmiany wersji). OweVersion (plugin
          # open-wallpaper-engine) bumpuje się RĘCZNIE w
          # modules/packages/_waywallen/default.nix + `nix hash file`.
          ${pkgs.lib.getExe pkgs.nix-update} --system x86_64-linux -F waywallen
          ${pkgs.lib.getExe pkgs.nix-update} --system aarch64-linux -F waywallen --version skip

          echo "Syncing GitHub Actions workflows from the updated flake..."
          nix run .#sync-github-actions

          echo "Checking flake outputs for both architectures..."
          nix flake check --all-systems --no-build

          echo "Building updated local packages..."
          nix build --no-link .#helium .#waywallen .#bootdev-cli

          git add -A -- flake.lock .github/workflows \
            modules/packages/_helium/default.nix \
            modules/packages/_bootdev-cli/default.nix \
            modules/packages/_waywallen/default.nix
          if git diff --cached --quiet; then
            echo "Everything is already up to date."
          else
            # The dev shell's workflow hook may still point at the old lock.
            # The fresh generator has already run above.
            SKIP=sync-github-actions git commit -m "flake-update: update inputs and packages"
          fi
          echo "All packages updated!"
        '';

        repo-sync = pkgs.writeShellScriptBin "repo-sync" ''
          set -e
          cd "$(git rev-parse --show-toplevel)"
          echo "Committing local changes..."
          git add -A
          git commit -m "chore: sync repository" || true
          echo "Pulling latest changes..."
          git pull --rebase --autostash
          echo "Pushing to GitHub..."
          git push
          echo "Repository synced!"
        '';

        flake-release = pkgs.writeShellScriptBin "flake-release" ''
          set -e
          latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0")
          latest_num="''${latest_tag#v}"
          if [[ "$latest_num" == *.*.* ]]; then
            IFS='.' read -r major minor patch <<< "$latest_num"
            new_tag="v''${major}.''${minor}.$((patch + 1))"
          elif [[ "$latest_num" == *.* ]]; then
            IFS='.' read -r major minor <<< "$latest_num"
            new_tag="v''${major}.$((minor + 1))"
          else
            new_tag="v$((latest_num + 1))"
          fi
          echo "Releasing $new_tag..."
          git commit -a -m "Release $new_tag" || true
          git tag $new_tag
          git push
          git push --tags
          echo "Release $new_tag pushed successfully!"
        '';
      };
    };
}
