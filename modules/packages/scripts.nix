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
          echo "Updating bootdev-cli..."
          ${pkgs.lib.getExe pkgs.nix-update} --commit -F bootdev-cli
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
