{
  perSystem =
    { config, pkgs, ... }:
    {
      packages = {
        flake-update = pkgs.writeShellScriptBin "flake-update" ''
          set -e
          echo "Updating flake inputs..."
          nix flake update
          echo "Syncing GitHub Actions workflows..."
          ${config.packages.sync-github-actions}/bin/sync-github-actions
          if ! git diff --exit-code flake.lock .github/workflows > /dev/null; then
            echo "Committing flake.lock and synced workflows..."
            git add flake.lock .github/workflows
            git commit -m "flake.lock: update all inputs" flake.lock .github/workflows
          fi
          echo "Updating helium..."
          helium_old=''$(grep -oP 'version = "\K[^"]+' modules/packages/_helium/default.nix | head -n1)
          nix-update --system x86_64-linux -F helium
          nix-update --system aarch64-linux -F helium --version skip
          if ! git diff --exit-code --quiet -- modules/packages/_helium/default.nix; then
            helium_new=''$(grep -oP 'version = "\K[^"]+' modules/packages/_helium/default.nix | head -n1)
            echo "Committing helium update (''$helium_old -> ''$helium_new)..."
            git add modules/packages/_helium/default.nix
            git commit \
              -m "helium: ''$helium_old -> ''$helium_new" \
              -m "Diff: https://github.com/imputnet/helium-linux/compare/''$helium_old...''$helium_new" \
              modules/packages/_helium/default.nix
          fi
          echo "Updating bootdev-cli..."
          ${pkgs.lib.getExe pkgs.nix-update} --commit -F bootdev-cli
          echo "Updating waywallen..."
          # Dwa pasy jak przy helium: x86_64 (wersja + hash), potem
          # aarch64 (hash bez zmiany wersji). OweVersion (plugin
          # open-wallpaper-engine) bumpuje się RĘCZNIE w
          # modules/packages/_waywallen/default.nix + `nix hash file`.
          ww_old=''$(grep -oP 'version = "\K[^"]+' modules/packages/_waywallen/default.nix | head -n1)
          ${pkgs.lib.getExe pkgs.nix-update} --system x86_64-linux -F waywallen
          ${pkgs.lib.getExe pkgs.nix-update} --system aarch64-linux -F waywallen --version skip
          if ! git diff --exit-code --quiet -- modules/packages/_waywallen/default.nix; then
            ww_new=''$(grep -oP 'version = "\K[^"]+' modules/packages/_waywallen/default.nix | head -n1)
            echo "Committing waywallen update (''$ww_old -> ''$ww_new)..."
            git add modules/packages/_waywallen/default.nix
            git commit \
              -m "waywallen: ''$ww_old -> ''$ww_new" \
              -m "Diff: https://github.com/waywallen/waywallen/compare/v''$ww_old...v''$ww_new" \
              modules/packages/_waywallen/default.nix
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
